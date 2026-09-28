#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_binary=$(mktemp /tmp/LibreShot-OverlayPermissionChecks.XXXXXX)
trap 'rm -f "$task_binary"' EXIT
bash tests/compile-checks.sh "$task_binary" \
  LibreShot/Features/Overlay/OverlayWindowController.swift \
  tests/OverlayPermissionRegressionChecks.swift
"$task_binary"
