#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-fullscreen.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
# Compile the real delegate without the SwiftUI application entry point.
python3 - "$task_tmp/AppDelegate.swift" <<'PY'
import pathlib, sys
source = pathlib.Path('LibreShot/LibreShot/LibreShotApp.swift').read_text()
pathlib.Path(sys.argv[1]).write_text('import SwiftUI\nimport AppKit\nimport UniformTypeIdentifiers\n' + source[source.index('final class AppDelegate:'):])
PY
bash tests/compile-checks.sh "$task_tmp/checks" "$task_tmp/AppDelegate.swift" \
  LibreShot/Features/Overlay/OverlayWindowController.swift \
  LibreShot/Core/PinnedImageWindowController.swift tests/FullScreenChecks.swift
"$task_tmp/checks"
