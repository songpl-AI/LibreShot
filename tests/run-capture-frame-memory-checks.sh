#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-frame-memory.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
LIBRESHOT_OPTIMIZE=1 bash tests/compile-checks.sh "$task_tmp/checks" tests/CaptureFrameMemoryChecks.swift
"$task_tmp/checks"
# Optional isolated conversion profiles. These use public generated pixel buffers,
# not screen capture, application preferences, translation models or the clipboard.
for task_mode in "$@"; do "$task_tmp/checks" "$task_mode"; done
