#!/bin/zsh

# 构建本地测试 DMG，并为每个版本写入相同的 designated requirement。
# 普通 ad-hoc 签名默认使用 cdhash 作为应用身份，二进制一变化就会让旧的 TCC
# 辅助功能授权失效；固定 identifier 要求可让后续本地测试版本保持同一身份。
set -euo pipefail

project_root="$(cd "$(dirname "$0")/.." && pwd)"
derived_data="$(mktemp -d /tmp/MacWindowButtons-StableBuild.XXXXXX)"
staging="$(mktemp -d /tmp/MacWindowButtons-StableDMG.XXXXXX)"

cleanup() {
    rm -rf "$derived_data" "$staging"
}
trap cleanup EXIT

cd "$project_root"
xcodebuild -quiet \
    -project MacWindowButtons.xcodeproj \
    -scheme MacWindowButtons \
    -configuration Release \
    -derivedDataPath "$derived_data" \
    CODE_SIGNING_ALLOWED=NO \
    build

app_path="$derived_data/Build/Products/Release/MacWindowButtons.app"
version="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")"
requirement='=designated => identifier "com.lwb.MacWindowButtons"'

codesign --force --deep --sign - --requirements "$requirement" "$app_path"
codesign --verify --deep --strict --verbose=2 "$app_path"

cp -R "$app_path" "$staging/MacWindowButtons.app"
ln -s /Applications "$staging/Applications"
mkdir -p dist
hdiutil create \
    -volname MacWindowButtons \
    -srcfolder "$staging" \
    -ov \
    -format UDZO \
    "dist/MacWindowButtons-$version.dmg"

hdiutil verify "dist/MacWindowButtons-$version.dmg"
codesign -dr - "$staging/MacWindowButtons.app"
shasum -a 256 "dist/MacWindowButtons-$version.dmg"
