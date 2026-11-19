#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
xcrun simctl list devices available -j > build/simulators.json
device=$(python3 - <<'PY'
import json, subprocess, sys
data=json.load(open("build/simulators.json"))
sdk=subprocess.check_output(["xcrun","--sdk","iphonesimulator","--show-sdk-version"],text=True).strip()
wanted="com.apple.CoreSimulator.SimRuntime.iOS-"+sdk.replace(".","-")
print("Using simulator runtime: "+wanted,file=sys.stderr)
for runtime, devices in sorted(data["devices"].items(),reverse=True):
    if runtime != wanted: continue
    for device in devices:
        if device.get("isAvailable") and "iPhone" in device["name"]:
            print(device["udid"]); raise SystemExit
raise SystemExit("No iPhone simulator for selected Xcode SDK "+sdk)
PY
)
xcodebuild -showdestinations -project MoyuCamera.xcodeproj -scheme MoyuCamera \
  -sdk iphonesimulator ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES 2>&1 | tee build/destinations.log
if ! grep -q "$device" build/destinations.log; then
  echo "Selected simulator is not visible to Xcode; inspect destinations.log"
  exit 70
fi
xcrun simctl boot "$device" || true
xcrun simctl bootstatus "$device" -b
xcodebuild test -project MoyuCamera.xcodeproj -scheme MoyuCamera \
  -configuration Debug -sdk iphonesimulator -parallel-testing-enabled NO -destination "platform=iOS Simulator,id=$device" \
  -derivedDataPath "$PWD/build/SimulatorData" -resultBundlePath "$PWD/build/NativeTests.xcresult" \
  ARCHS=x86_64 ONLY_ACTIVE_ARCH=YES CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
  CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" 2>&1 | tee build/native-tests.log
