#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-long-settlement.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
xcrun swiftc -parse-as-library -O \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureFrameSettlement.swift \
  tests/LongCaptureFrameSettlementChecks.swift -o "$task_directory/checks"
"$task_directory/checks"
