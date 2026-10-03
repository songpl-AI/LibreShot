#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

if [[ -n "$(git status --porcelain)" ]]; then
    printf 'Commit or stash local changes before making a reproducible preview.\n' >&2
    exit 1
fi
output=${1:-"$(pwd)/dist/LibreShot-Preview-$(date +%Y%m%d-%H%M%S)"}
mkdir -p "$(dirname "$output")"
mkdir "$output"
output=$(cd "$output" && pwd)
work=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-preview-build.XXXXXX")
trap 'rm -rf "$work"' EXIT
revision=$(git rev-parse HEAD)
preview_bundle_id=${LIBRESHOT_PREVIEW_BUNDLE_ID:-com.allensong.LibreShot.Preview}
preview_display_name=${LIBRESHOT_PREVIEW_DISPLAY_NAME:-LibreShot Preview}

xcodebuild -project LibreShot/LibreShot.xcodeproj -scheme LibreShot \
    -configuration Release -destination 'generic/platform=macOS' \
    -derivedDataPath "$work" \
    CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= \
    PRODUCT_NAME=LibreShotPreview \
    PRODUCT_BUNDLE_IDENTIFIER="$preview_bundle_id" \
    INFOPLIST_KEY_CFBundleDisplayName="$preview_display_name" \
    'ARCHS=arm64 x86_64' ONLY_ACTIVE_ARCH=NO build > "$output/build.log" 2>&1

app="$output/LibreShot Preview.app"
ditto "$work/Build/Products/Release/LibreShotPreview.app" "$app"
info="$app/Contents/Info.plist"
plutil -insert LibreShotBuildChannel -string local-preview "$info"
plutil -insert LibreShotSourceRevision -string "$revision" "$info"
codesign --force --sign - --options runtime --entitlements LibreShot/LibreShot/LibreShot.entitlements "$app"
if [[ "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$info")" != "$preview_bundle_id" ]] ||
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :LibreShotBuildChannel' "$info")" != "local-preview" ]] ||
   [[ "$(/usr/libexec/PlistBuddy -c 'Print :LibreShotSourceRevision' "$info")" != "$revision" ]]; then
    printf 'Preview identity verification failed.\n' >&2
    exit 1
fi
bash scripts/verify_release_signing.sh --allow-ad-hoc "$app"
codesign -d --entitlements :- "$app" > "$output/entitlements.plist" 2> "$output/signature.log"
[[ "$(/usr/libexec/PlistBuddy -c 'Print :com.apple.security.app-sandbox' "$output/entitlements.plist")" == true ]]
lipo "$app/Contents/MacOS/LibreShotPreview" -verify_arch arm64 x86_64
cp docs/qa/preview-trial.md "$output/READ-ME.md"
ditto -c -k --sequesterRsrc --keepParent "$app" "$output/LibreShot-Preview.zip"
(cd "$output" && shasum -a 256 LibreShot-Preview.zip > SHA256SUMS)
metadata="$output/BUILD-INFO.plist"
plutil -create xml1 "$metadata"
plutil -insert sourceRevision -string "$revision" "$metadata"
plutil -insert bundleIdentifier -string "$preview_bundle_id" "$metadata"
plutil -insert version -string "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$info")" "$metadata"
plutil -insert build -string "$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$info")" "$metadata"
plutil -insert signing -string ad-hoc "$metadata"
plutil -insert architectures -json '["arm64","x86_64"]' "$metadata"
plutil -convert json -o "$output/BUILD-INFO.json" "$metadata"
printf 'Local preview: %s\nNot a signed/notarized public release.\n' "$app"
