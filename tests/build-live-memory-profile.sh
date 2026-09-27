#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

output="${1:-$(pwd)/dist/memory-profile-$(date +%Y%m%d-%H%M%S)}"
mkdir "$output"
output="$(cd "$output" && pwd)"

xcodebuild -project LibreShot/LibreShot.xcodeproj -scheme LibreShot \
  -configuration Debug -derivedDataPath "$output/DerivedData" \
  PRODUCT_BUNDLE_IDENTIFIER=com.allensong.LibreShot.MemoryProfile \
  INFOPLIST_KEY_CFBundleDisplayName='LibreShot Memory Profile' \
  ENABLE_HARDENED_RUNTIME=NO CODE_SIGNING_ALLOWED=NO build -quiet

app="$output/LibreShot Memory Profile.app"
ditto "$output/DerivedData/Build/Products/Debug/LibreShot.app" "$app"
# The isolated profiling app is not sandboxed so it can write its opt-in trace
# beside the profiler output. The production app and its entitlements are unchanged.
codesign --force --sign - --timestamp=none "$app"
codesign --verify --deep --strict "$app"
printf '%s\n' "$app"
