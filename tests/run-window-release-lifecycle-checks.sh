#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d /tmp/LibreShot-WindowReleaseChecks.XXXXXX)
trap 'rm -rf "$task_directory"' EXIT
bash tests/compile-checks.sh "$task_directory/checks" \
  LibreShot/Features/Overlay/OverlayWindowController.swift \
  tests/WindowReleaseLifecycleChecks.swift
"$task_directory/checks"
