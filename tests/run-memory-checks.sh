#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-memory-checks.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
LIBRESHOT_OPTIMIZE=1 bash tests/compile-checks.sh "$task_tmp/checks" tests/MemoryLifecycleChecks.swift
"$task_tmp/checks"
