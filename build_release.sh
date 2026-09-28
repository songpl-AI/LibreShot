#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

signing_mode=ad-hoc
if [[ ${1:-} == --developer-id ]]; then
  signing_mode=developer-id
  shift
elif [[ ${1:-} == --ad-hoc ]]; then
  shift
fi

# Use a fresh destination. Never erase tracked build/ artifacts or previous packages.
release_output="${1:-$(pwd)/dist/LibreShot-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$(dirname "$release_output")"
mkdir "$release_output"
release_output="$(cd "$release_output" && pwd)"
archive_path="$release_output/LibreShot.xcarchive"

signing_args=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM=)
if [[ "$signing_mode" == developer-id ]]; then
  signing_args=("CODE_SIGN_IDENTITY=Developer ID Application" CODE_SIGN_STYLE=Manual)
fi
echo "Building $signing_mode Release archive..."
xcodebuild archive \
  -project LibreShot/LibreShot.xcodeproj \
  -scheme LibreShot \
  -configuration Release \
  -archivePath "$archive_path" \
  -destination 'generic/platform=macOS' \
  "${signing_args[@]}" \
  -quiet

app_path="$release_output/LibreShot.app"
ditto "$archive_path/Products/Applications/LibreShot.app" "$app_path"
if [[ "$signing_mode" == ad-hoc ]]; then
  bash scripts/verify_release_signing.sh --allow-ad-hoc "$app_path"
else
  bash scripts/verify_release_signing.sh "$app_path"
fi
version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$app_path/Contents/Info.plist")
build_number=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleVersion' "$app_path/Contents/Info.plist")
dmg_name="LibreShot-${version}-${build_number}.dmg"
dmg_source=$(mktemp -d "$release_output/dmg-source.XXXXXX")
trap 'rm -rf "$dmg_source"' EXIT
ditto "$app_path" "$dmg_source/LibreShot.app"
ln -s /Applications "$dmg_source/Applications"
hdiutil create -volname "LibreShot $version" -srcfolder "$dmg_source" \
  -format UDZO "$release_output/$dmg_name" -quiet
hdiutil verify "$release_output/$dmg_name" -quiet
(cd "$release_output" && shasum -a 256 "$dmg_name" > SHA256SUMS)
echo "Package: $release_output/$dmg_name"
if [[ "$signing_mode" == ad-hoc ]]; then
  echo "Signing mode: ad-hoc. This package cannot be notarized; macOS permissions may need to be granted again after an update."
else
  echo "Signing mode: developer-id. Notarization is a separate distribution step."
fi
