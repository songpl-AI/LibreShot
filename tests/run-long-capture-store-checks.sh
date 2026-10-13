#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-long-store.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
xcrun swiftc -parse-as-library -O \
  LibreShot/LibreShot/Core/LongCapture/LongCaptureDocumentStore.swift \
  tests/LongCaptureStoreChecks.swift -framework AppKit -o "$task_directory/checks"
if [[ "${1:-checks}" != "checks" ]]; then
  "$task_directory/checks" "$@"
  exit
fi
mkdir "$task_directory/spool"
export TMPDIR="$task_directory/spool"
ulimit -c 0
failed=0
"$task_directory/checks" || failed=1
for mode in overflow-append overflow-image-window overflow-document-window; do
  "$task_directory/checks" "$mode" || failed=1
done
exit "$failed"

