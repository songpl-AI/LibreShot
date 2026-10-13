#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-long-baseline.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
task_flags=(-parse-as-library)
if [[ "${LIBRESHOT_OPTIMIZE:-0}" == 1 ]]; then task_flags+=(-O); fi
xcrun swiftc "${task_flags[@]}" \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureEngine.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureTypes.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureDocumentStore.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureOverlapMatcher.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureImageSampling.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureSeamVerifier.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureFrameSettlement.swift \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureInitialFrameSource.swift \
  tests/LongCaptureInitialBaselineChecks.swift -o "$task_directory/checks"
"$task_directory/checks"
