#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-long-finish-retry.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
bash tests/compile-checks.sh "$task_directory/checks" tests/LongCaptureFinishRetryChecks.swift
ulimit -c 0
"$task_directory/checks"
