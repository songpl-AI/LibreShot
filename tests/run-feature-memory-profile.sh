#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-feature-memory.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
LIBRESHOT_OPTIMIZE=1 bash tests/compile-checks.sh "$task_tmp/profile" tests/FeatureMemoryProfile.swift
scenarios=("$@")
if ((${#scenarios[@]} == 0)); then scenarios=(ocr translation image-translation translation-window translation-window-loop image-render long); fi
for scenario in "${scenarios[@]}"; do
    printf '\n=== %s ===\n' "$scenario"
    "$task_tmp/profile" "$scenario"
done
