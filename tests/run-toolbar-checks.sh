#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-toolbar-checks.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
bash tests/compile-checks.sh "$task_tmp/checks" tests/ToolbarRegressionChecks.swift tests/ImageTranslationChecks.swift
"$task_tmp/checks"
