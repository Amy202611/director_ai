import argparse
import hashlib
import json
from pathlib import Path, PurePosixPath
import plistlib
import re
import struct
import zipfile

def check_names(info):
    for key in ("CFBundleName", "CFBundleDisplayName"):
        name = info.get(key, "")
        if not isinstance(name, str) or not re.fullmatch(r"[A-Za-z][A-Za-z0-9 ]{0,49}", name):
            raise ValueError(f"{key} must be an ASCII App ID name for SideStore, got {name!r}")
    return {key: info[key] for key in ("CFBundleName", "CFBundleDisplayName")}

def check_macho(data):
    if len(data) < 32 or data[:4] != b"\xcf\xfa\xed\xfe":
        raise ValueError("Expected 64-bit little-endian Mach-O")
    _, cpu, _, kind, count, command_size, _, _ = struct.unpack_from("<IiiIIIII", data)
    if cpu != 0x0100000C or kind != 2:
        raise ValueError("Expected ARM64 executable")
    offset = 32
    platform = None
    signed = encrypted = False
    if offset + command_size > len(data): raise ValueError("Truncated load commands")
    for _ in range(count):
        if offset + 8 > len(data): raise ValueError("Truncated command")
        cmd, size = struct.unpack_from("<II", data, offset)
        if size < 8 or offset + size > 32 + command_size: raise ValueError("Invalid command length")
        if cmd == 0x32:
            if size < 24: raise ValueError("Truncated build version")
            platform = struct.unpack_from("<I", data, offset + 8)[0]
        elif cmd == 0x25:
            platform = 2
        elif cmd == 0x1D:
            signed = True
        elif cmd in (0x21, 0x2C):
            if size < 20: raise ValueError("Truncated encryption command")
            encrypted = struct.unpack_from("<I", data, offset + 16)[0] != 0
        offset += size
    if platform != 2: raise ValueError(f"Expected iPhoneOS platform 2, got {platform}")
    if signed or encrypted: raise ValueError("Expected unsigned, unencrypted executable")
    return {"architecture": "arm64", "platform": "iPhoneOS", "signed": False, "encrypted": False}

def validate(path):
    with zipfile.ZipFile(path) as archive:
        names = archive.namelist()
        if any(PurePosixPath(n).is_absolute() or ".." in PurePosixPath(n).parts for n in names):
            raise ValueError("Unsafe ZIP path")
        apps = {PurePosixPath(n).parts[1] for n in names if len(PurePosixPath(n).parts) >= 2
                and PurePosixPath(n).parts[0] == "Payload" and PurePosixPath(n).parts[1].endswith(".app")}
        if len(apps) != 1: raise ValueError("Expected exactly one Payload/*.app")
        root = "Payload/" + apps.pop() + "/"
        info = plistlib.loads(archive.read(root + "Info.plist"))
        checked_names = check_names(info)
        # A localized display name could make SideStore submit Chinese again.
        if any(n.startswith(root) and n.endswith("/InfoPlist.strings") for n in names):
            raise ValueError("Localized bundle-name overrides need explicit SideStore review")
        if info.get("CFBundleSupportedPlatforms") != ["iPhoneOS"]:
            raise ValueError("Not an iPhoneOS device build")
        if info.get("MinimumOSVersion") != "16.0":
            raise ValueError("Expected minimum iOS 16.0")
        executable = info.get("CFBundleExecutable", "")
        if not executable or "/" in executable or executable in (".", ".."):
            raise ValueError("Invalid CFBundleExecutable")
        if root + "embedded.mobileprovision" in names:
            raise ValueError("Unexpected provisioning profile")
        result = check_macho(archive.read(root + executable))
        result.update(checked_names)
        result.update(bundle_id=info["CFBundleIdentifier"], minimum_ios=info["MinimumOSVersion"],
                      version=info.get("CFBundleShortVersionString"), build=info.get("CFBundleVersion"),
                      sidestore_ascii_name_checked=True)
    result.update(sha256=hashlib.sha256(path.read_bytes()).hexdigest(), size_bytes=path.stat().st_size)
    return result

if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("ipa", type=Path)
    p.add_argument("--report", type=Path, required=True)
    a = p.parse_args()
    report = json.dumps(validate(a.ipa), indent=2, ensure_ascii=False) + "\n"
    a.report.write_text(report, encoding="utf-8")
    print(report)
