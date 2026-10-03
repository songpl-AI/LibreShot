#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-ocr-residency.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
LIBRESHOT_OPTIMIZE=1 bash tests/compile-checks.sh "$task_tmp/profile" tests/OCRResidencyProfile.swift
"$task_tmp/profile" "${1:-in-process}"
