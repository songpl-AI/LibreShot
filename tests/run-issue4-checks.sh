#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-issue4-checks.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
bash tests/compile-checks.sh "$task_tmp/checks" tests/Issue4RegressionChecks.swift
"$task_tmp/checks"
task_clipboard="LibreShot.ClipboardCheck.$(uuidgen)"
"$task_tmp/checks" --clipboard-write "$task_clipboard"
"$task_tmp/checks" --clipboard-read "$task_clipboard"
