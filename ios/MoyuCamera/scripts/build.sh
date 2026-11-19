#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
if [[ "$(uname -s)" != Darwin ]]; then echo "Use GitHub macOS Actions from Windows."; exit 2; fi
mkdir -p Config build/artifacts Resources/Assets.xcassets/AppIcon.appiconset
xcodebuild -version
xcrun --sdk iphoneos --show-sdk-version
if ! command -v xcodegen >/dev/null 2>&1; then brew install xcodegen; fi
xcodegen --version
swift scripts/generate_icon.swift Resources/Assets.xcassets/AppIcon.appiconset/AppIcon-1024.png
xcodegen generate --spec project.yml
number="${GITHUB_RUN_NUMBER:-1}"
if [[ ! "$number" =~ ^[0-9]+$ ]]; then number=1; fi
number=$((number + 100))
for attempt in 1 2; do
  rm -rf build/DerivedData build/MoyuCamera.xcarchive build/Archive.xcresult
  set +e
  xcodebuild archive -project MoyuCamera.xcodeproj -scheme MoyuCamera \
    -configuration Release -sdk iphoneos -destination "generic/platform=iOS" \
    -archivePath "$PWD/build/MoyuCamera.xcarchive" \
    -derivedDataPath "$PWD/build/DerivedData" -resultBundlePath "$PWD/build/Archive.xcresult" \
    ARCHS=arm64 ONLY_ACTIVE_ARCH=NO CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" DEVELOPMENT_TEAM="" CURRENT_PROJECT_VERSION="$number" \
    2>&1 | tee "build/archive-$attempt.log"
  status=${PIPESTATUS[0]}
  set -e
  if [[ "$status" == 0 ]]; then break; fi
  python3 scripts/diagnose.py "build/archive-$attempt.log" > build/diagnostics.md
  if [[ "$attempt" == 1 ]] && grep -Eqi "database is locked|connection reset|timed out|failed to fetch" "build/archive-$attempt.log"; then
    xcodegen generate --spec project.yml
  else
    exit "$status"
  fi
done
app="$PWD/build/MoyuCamera.xcarchive/Products/Applications/MoyuCamera.app"
test -f "$app/MoyuCamera"
test -s "$app/Assets.car"
python3 - "$app/Info.plist" <<'PY'
import plistlib, sys
info = plistlib.load(open(sys.argv[1], "rb"))
icon = info.get("CFBundleIcons", {}).get("CFBundlePrimaryIcon", {})
assert icon.get("CFBundleIconName") == "AppIcon", "App icon missing from compiled bundle"
print("Compiled AppIcon verified")
PY
xcrun lipo -info "$app/MoyuCamera"
if codesign --display "$app" >build/signature.log 2>&1; then
  echo "Unexpected app code signature"; exit 1
fi
rm -rf build/package
mkdir -p build/package/Payload
ditto "$app" build/package/Payload/MoyuCamera.app
ipa="$PWD/build/artifacts/MoyuCamera.ipa"
rm -f "$ipa"
(cd build/package && ditto -c -k --keepParent Payload "$ipa")
python3 scripts/validate_ipa.py "$ipa" --report build/artifacts/IPA-REPORT.json
(cd build/artifacts && shasum -a 256 MoyuCamera.ipa > SHA256SUMS.txt)
if [[ -n "${GITHUB_STEP_SUMMARY:-}" ]]; then
  {
    echo "## MoyuCamera 2.0 原生相机"
    echo "安装名称：MoyuCamera；应用内部：中文；最低 iOS 16.0。"
    echo "已验证真机 ARM64、未签名、未加密、无中文 bundle-name 覆盖。"
    cat build/artifacts/IPA-REPORT.json
  } >> "$GITHUB_STEP_SUMMARY"
fi
