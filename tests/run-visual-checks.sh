#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-visual-checks.XXXXXX")
trap 'rm -rf "$work"' EXIT
bash tests/compile-checks.sh "$work/visual-checks" tests/VisualWorkflowChecks.swift
"$work/visual-checks"
