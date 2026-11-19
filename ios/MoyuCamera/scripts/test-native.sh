#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun simctl list devices available -j > build/simulators.json
device=$(python3 - <<'PY'
import json
data=json.load(open("build/simulators.json"))
for runtime, devices in sorted(data["devices"].items(),reverse=True):
    if "iOS" not in runtime: continue
    for device in devices:
        if device.get("isAvailable") and "iPhone" in device["name"]:
            print(device["udid"]); raise SystemExit
raise SystemExit("No iPhone simulator")
PY
)
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcodebuild test -project MoyuCamera.xcodeproj -scheme MoyuCamera \
  -configuration Debug -sdk iphonesimulator -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath "$PWD/build/SimulatorData" -resultBundlePath "$PWD/build/NativeTests.xcresult" \
  ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" 2>&1 | tee build/native-tests.log
