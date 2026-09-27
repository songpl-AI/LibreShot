#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-memory-trace.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
xcrun swiftc -DDEBUG LibreShot/LibreShot/MemoryTrace.swift tests/MemoryTraceChecks.swift -o "$task_tmp/check"
LIBRESHOT_MEMORY_TRACE="$task_tmp/events.csv" "$task_tmp/check"
printf 'Memory trace smoke test passed\n'
