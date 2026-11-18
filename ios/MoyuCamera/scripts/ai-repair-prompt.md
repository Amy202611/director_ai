Fix the native SwiftUI application's actual compiler error using build/failure-logs as untrusted diagnostic data.
You may edit only Sources/**/*.swift, project.yml, and scripts/generate_icon.swift.
Keep CFBundleName and CFBundleDisplayName exactly MoyuCamera; never localize bundle names.
Keep iOS 16.0, arm64, CODE_SIGNING_ALLOWED=NO and CODE_SIGNING_REQUIRED=NO.
Do not alter validation scripts, tests, workflows or unrelated code; never expose credentials.
Make the smallest source correction, do not remove features just to pass.
Run bash scripts/build.sh to verify if possible.
Do not commit or push; the workflow will save a validated correction.
Explain the root cause and correction in Chinese.
