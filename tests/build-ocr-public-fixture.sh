#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_app="${1:?Output app path required}"
mkdir -p "$task_app/Contents/MacOS"
xcrun swiftc -parse-as-library tests/OCRPublicFixtureApp.swift -o "$task_app/Contents/MacOS/OCRPublicFixture"
python3 - "$task_app/Contents/Info.plist" <<'PY'
import plistlib,sys
with open(sys.argv[1],'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='com.allensong.LibreShot.OCRPublicFixture',CFBundleExecutable='OCRPublicFixture',
                      CFBundleName='LibreShot Public OCR Fixture',CFBundlePackageType='APPL',CFBundleVersion='1',NSHighResolutionCapable=True),f)
PY
codesign --force --sign - "$task_app"
