#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_tmp=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-roadmap-ui.XXXXXX")
trap 'rm -rf "$task_tmp"' EXIT
mkdir -p "$task_tmp/LibreShotRoadmapQA.app/Contents/MacOS"
cp tests/RoadmapQA-Info.plist "$task_tmp/LibreShotRoadmapQA.app/Contents/Info.plist"
bash tests/compile-checks.sh "$task_tmp/LibreShotRoadmapQA.app/Contents/MacOS/LibreShotRoadmapQA" tests/RoadmapUITestApp.swift
codesign --force --sign - "$task_tmp/LibreShotRoadmapQA.app"
open -W -n "$task_tmp/LibreShotRoadmapQA.app"
