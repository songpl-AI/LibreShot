#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-fullscreen.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
bash tests/compile-checks.sh "$task_tmp/checks" \
  LibreShot/Features/Overlay/OverlayWindowController.swift tests/FullscreenOverlayChecks.swift
"$task_tmp/checks"
