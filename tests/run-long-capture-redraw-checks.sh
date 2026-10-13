#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-long-redraw.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
bash tests/compile-checks.sh "$task_directory/checks" tests/LongCaptureRedrawChecks.swift
"$task_directory/checks"
