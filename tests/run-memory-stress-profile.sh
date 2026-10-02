#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-memory-stress.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
LIBRESHOT_OPTIMIZE=1 bash tests/compile-checks.sh "$task_tmp/profile" tests/MemoryStressProfile.swift
scenarios=("$@")
if ((${#scenarios[@]} == 0)); then scenarios=(editor-copy ocr); fi
for scenario in "${scenarios[@]}"; do "$task_tmp/profile" "$scenario"; done
