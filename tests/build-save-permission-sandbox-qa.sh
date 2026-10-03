#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_output=${1:?Usage: tests/build-save-permission-sandbox-qa.sh OUTPUT_DIRECTORY}
mkdir -p "$task_output/LibreShot Save QA.app/Contents/MacOS"
task_output=$(cd "$task_output" && pwd)
task_app="$task_output/LibreShot Save QA.app"
bash tests/compile-checks.sh "$task_app/Contents/MacOS/LibreShotSaveQA" tests/SavePermissionSandboxChecks.swift
python3 - "$task_app/Contents/Info.plist" <<'PY'
import plistlib, sys
with open(sys.argv[1], 'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='com.allensong.LibreShot.SavePermissionQA.October3',
                      CFBundleName='LibreShot Save QA', CFBundleExecutable='LibreShotSaveQA',
                      CFBundlePackageType='APPL', CFBundleVersion='1', CFBundleShortVersionString='1.0',
                      NSHighResolutionCapable=True), f)
PY
cat > "$task_output/entitlements.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>com.apple.security.app-sandbox</key><true/>
<key>com.apple.security.files.user-selected.read-write</key><true/>
</dict></plist>
PLIST
codesign --force --sign - --options runtime --entitlements "$task_output/entitlements.plist" "$task_app"
codesign --verify --deep --strict "$task_app"
printf 'Sandbox QA app: %s\nLaunch the same signed bundle twice; inspect its container result.json.\n' "$task_app"
