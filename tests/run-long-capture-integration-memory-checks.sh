#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-long-integration-memory.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
xcrun swiftc -parse-as-library -O \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureTypes.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureImageSampling.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureOverlapMatcher.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureDocumentStore.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureSeamVerifier.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureEngine.swift \
  tests/LongCaptureIntegrationMemoryChecks.swift -framework AppKit -o "$task_directory/checks"
mkdir "$task_directory/spool"
export TMPDIR="$task_directory/spool"
ulimit -c 0
"$task_directory/checks"
