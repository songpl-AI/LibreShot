#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-ocr-sandbox.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
task_app="$task_tmp/LibreShot OCR Probe.app"
mkdir -p "$task_app/Contents/MacOS"
LIBRESHOT_OPTIMIZE=1 bash tests/compile-checks.sh "$task_app/Contents/MacOS/LibreShotOCRProbe" tests/OCRResidencyProfile.swift
cp "$task_app/Contents/MacOS/LibreShotOCRProbe" "$task_app/Contents/MacOS/LibreShotOCRProbeWorker"
python3 - "$task_app/Contents/Info.plist" "$task_tmp" <<'PY'
import plistlib,sys
from pathlib import Path
with open(sys.argv[1],'wb') as f:
    plistlib.dump(dict(CFBundleIdentifier='com.allensong.LibreShot.OCRResidencyProbe.October3',
                      CFBundleName='LibreShot OCR Probe',CFBundleExecutable='LibreShotOCRProbe',
                      CFBundlePackageType='APPL',CFBundleVersion='1',NSHighResolutionCapable=True),f)
for name,extra in [('parent',{}),('worker',{'com.apple.security.inherit':True})]:
    with open(Path(sys.argv[2])/(name+'.plist'),'wb') as f:
        plistlib.dump({'com.apple.security.app-sandbox':True,**extra},f)
PY
codesign --force --sign - --options runtime --entitlements "$task_tmp/worker.plist" "$task_app/Contents/MacOS/LibreShotOCRProbeWorker"
codesign --force --sign - --options runtime --entitlements "$task_tmp/worker.plist" "$task_app/Contents/MacOS/LibreShotOCRWorker"
codesign --force --sign - --options runtime --entitlements "$task_tmp/parent.plist" "$task_app"
codesign --verify --deep --strict "$task_app"
"$task_app/Contents/MacOS/LibreShotOCRProbe" "${1:-worker-parent}"
