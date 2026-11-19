#!/usr/bin/env bash
set -euo pipefail
# Publish a raw IPA asset: users download and share it without unzipping an Actions artifact.
: "${GH_REPO:?Set GH_REPO to owner/repository}"
: "${GITHUB_SHA:?Set GITHUB_SHA to the verified build commit}"
ipa="${1:?Pass the verified IPA file}"
test -s "$ipa"
tag="ios-${GITHUB_RUN_NUMBER:-manual}-${GITHUB_SHA:0:7}"
notes=$(mktemp)
trap 'rm -f "$notes"' EXIT
cat >"$notes" <<'NOTES'
直接下载 .ipa 文件即可转发，无需解压。
这是供真实 iPhone 使用的未签名 ARM64 安装包，需要通过 SideStore 等工具签名安装。
免费 Apple ID 签名通常需要每 7 天刷新；此下载不是免签或企业签名安装。
NOTES
gh release create "$tag" "$ipa" --repo "$GH_REPO" --target "$GITHUB_SHA" \
  --title "MoyuCamera $tag" --notes-file "$notes"
