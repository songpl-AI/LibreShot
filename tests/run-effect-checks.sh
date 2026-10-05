#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-effect-checks.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
bash tests/compile-checks.sh "$task_tmp/checks" tests/EffectRenderingChecks.swift
"$task_tmp/checks"
