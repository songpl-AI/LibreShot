#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-long-geometry.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
xcrun swiftc -parse-as-library -O \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureTypes.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureImageSampling.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureStreamGeometry.swift \
  tests/LongCaptureStreamGeometryChecks.swift -framework AppKit -o "$task_directory/checks"
"$task_directory/checks"
