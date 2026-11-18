import importlib.util
from pathlib import Path
import plistlib
import struct
import tempfile
import unittest
import zipfile

spec = importlib.util.spec_from_file_location("validate_ipa", Path(__file__).resolve().parents[1] / "scripts/validate_ipa.py")
validator = importlib.util.module_from_spec(spec)
spec.loader.exec_module(validator)

def macho(platform=2, cpu=0x0100000C, signed=False, encrypted=False):
    commands = struct.pack("<IIIIII", 0x32, 24, platform, 0x100000, 0x120000, 0)
    count = 1
    if signed:
        commands += struct.pack("<IIII", 0x1D, 16, 0, 0)
        count += 1
    if encrypted:
        commands += struct.pack("<IIIIII", 0x2C, 24, 0, 0, 1, 0)
        count += 1
    return struct.pack("<IiiIIIII", 0xFEEDFACF, cpu, 0, 2, count, len(commands), 0, 0) + commands

class PackageTests(unittest.TestCase):
    def test_ascii_names(self):
        result = validator.check_names({"CFBundleName": "MoyuCamera", "CFBundleDisplayName": "MoyuCamera"})
        self.assertEqual(result["CFBundleDisplayName"], "MoyuCamera")
    def test_reported_chinese_app_id_name_regression(self):
        for field in ("CFBundleName", "CFBundleDisplayName"):
            info = {"CFBundleName": "MoyuCamera", "CFBundleDisplayName": "MoyuCamera"}
            info[field] = "摸鱼相机"
            with self.assertRaisesRegex(ValueError, "ASCII"):
                validator.check_names(info)
    def test_missing_name(self):
        with self.assertRaises(ValueError):
            validator.check_names({"CFBundleName": "MoyuCamera"})
    def test_real_arm64(self):
        self.assertEqual(validator.check_macho(macho())["architecture"], "arm64")
    def test_arm64_simulator_rejected(self):
        with self.assertRaises(ValueError): validator.check_macho(macho(platform=7))
    def test_x86_rejected(self):
        with self.assertRaises(ValueError): validator.check_macho(macho(cpu=0x01000007))
    def test_signed_or_encrypted_rejected(self):
        for data in (macho(signed=True), macho(encrypted=True)):
            with self.assertRaises(ValueError): validator.check_macho(data)
    def test_truncation_rejected(self):
        with self.assertRaises(ValueError): validator.check_macho(macho()[:-1])
    def test_actual_ipa_structure_and_names(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "MoyuCamera.ipa"
            with zipfile.ZipFile(path, "w") as z:
                z.writestr("Payload/MoyuCamera.app/Info.plist", plistlib.dumps({
                    "CFBundleName": "MoyuCamera", "CFBundleDisplayName": "MoyuCamera",
                    "CFBundleIdentifier": "com.moyu.native.camera",
                    "CFBundleExecutable": "MoyuCamera", "MinimumOSVersion": "16.0",
                    "CFBundleSupportedPlatforms": ["iPhoneOS"]
                }))
                z.writestr("Payload/MoyuCamera.app/MoyuCamera", macho())
            self.assertTrue(validator.validate(path)["sidestore_ascii_name_checked"])

if __name__ == "__main__": unittest.main()
