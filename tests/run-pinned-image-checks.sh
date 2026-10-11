#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-pinned-checks.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
bash tests/compile-checks.sh "$task_tmp/checks" \
  LibreShot/Core/PinnedImageWindowController.swift tests/PinnedImageChecks.swift
"$task_tmp/checks"
