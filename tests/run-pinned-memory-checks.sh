#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-pinned-memory.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
LIBRESHOT_OPTIMIZE=1 bash tests/compile-checks.sh "$task_tmp/checks" \
  LibreShot/Core/PinnedImageWindowController.swift tests/PinnedImageMemoryChecks.swift
if (($# == 0)); then "$task_tmp/checks"; else
  for scenario in "$@"; do "$task_tmp/checks" "$scenario"; done
fi
