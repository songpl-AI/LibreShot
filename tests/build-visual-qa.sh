#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
output=${1:-/tmp/LibreShot-Visual-QA}
mkdir -p "$output/LibreShotVisualQA.app/Contents/MacOS"
info="$output/LibreShotVisualQA.app/Contents/Info.plist"
if [[ ! -f "$info" ]]; then
    plutil -create xml1 "$info"
    plutil -insert CFBundleIdentifier -string com.libreshot.VisualQA "$info"
    plutil -insert CFBundleName -string LibreShotVisualQA "$info"
    plutil -insert CFBundleExecutable -string LibreShotVisualQA "$info"
    plutil -insert CFBundlePackageType -string APPL "$info"
fi
bash tests/compile-checks.sh "$output/LibreShotVisualQA.app/Contents/MacOS/LibreShotVisualQA" tests/VisualWorkflowUITestApp.swift
codesign --force --sign - "$output/LibreShotVisualQA.app"
printf 'Native UI fixture: %s/LibreShotVisualQA.app\n' "$output"
