#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

# Use a fresh destination. Never erase tracked build/ artifacts or previous packages.
release_output="${1:-$(pwd)/dist/LibreShot-$(date +%Y%m%d-%H%M%S)}"
mkdir -p "$(dirname "$release_output")"
mkdir "$release_output"
release_output="$(cd "$release_output" && pwd)"
archive_path="$release_output/LibreShot.xcarchive"

echo "Building signed Release archive..."
xcodebuild archive \
  -project LibreShot/LibreShot.xcodeproj \
  -scheme LibreShot \
  -configuration Release \
  -archivePath "$archive_path" \
  -destination 'generic/platform=macOS' \
  -quiet

app_path="$release_output/LibreShot.app"
ditto "$archive_path/Products/Applications/LibreShot.app" "$app_path"
codesign --verify --deep --strict "$app_path"
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
echo "Signed with this Mac's configured identity; notarization is a separate distribution step."
