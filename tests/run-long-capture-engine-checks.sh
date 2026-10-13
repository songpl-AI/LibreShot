#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-long-engine.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
bash tests/compile-checks.sh "$task_directory/checks" tests/LongCaptureEngineChecks.swift
"$task_directory/checks"

