#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-ocr-worker-checks.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
LIBRESHOT_OPTIMIZE=1 bash tests/compile-checks.sh "$task_tmp/checks" tests/OCRWorkerChecks.swift
xcrun swiftc -parse-as-library LibreShot/LibreShot/Core/OCR/OCREngine.swift \
    LibreShot/LibreShot/Core/OCR/OCRWire.swift tests/OCRFakeWorker.swift -o "$task_tmp/fake"
for mode in crash json version oversize timeout success; do cp "$task_tmp/fake" "$task_tmp/$mode"; done
"$task_tmp/checks" "$task_tmp"
if pgrep -f "^$task_tmp/(crash|json|version|oversize|timeout|success)"; then
    echo 'FAIL: orphaned OCR test worker'; exit 1
fi
