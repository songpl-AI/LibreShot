#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_stamp=$(date -u +%Y%m%dT%H%M%SZ)
task_directory=${LIBRESHOT_STATIONARY_CHECK_OUTPUT:-dist/long-capture-stationary-safety-checks-$task_stamp}
mkdir -p "$task_directory"
task_directory=$(cd "$task_directory" && pwd)
python3 - "$task_directory" <<'PY'
import datetime
import hashlib
import json
import os
import pathlib
import platform
import subprocess
import sys

output = pathlib.Path(sys.argv[1])
paths = [pathlib.Path("tests/LongCaptureStationaryQuantizationChecks.swift"),
         pathlib.Path("tests/run-long-capture-stationary-quantization-checks.sh")]
sources = sorted(pathlib.Path("LibreShot").rglob("*.swift"))
manifest = {
    "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
    "scope": "synthetic stationary safety boundaries and known unsupported redraws; no capture or installed-app changes",
    "git_head": subprocess.check_output(["git", "rev-parse", "HEAD"], text=True).strip(),
    "macos_version": platform.mac_ver()[0],
    "optimized": os.environ.get("LIBRESHOT_OPTIMIZE", "0") == "1",
    "test_sha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in paths},
    "source_sha256": {str(path): hashlib.sha256(path.read_bytes()).hexdigest() for path in sources},
    "limits": "cols0 does not imply identical input pixels; synthetic repaint is not a proven live-capture root cause",
}
(output / "RUN.json").write_text(json.dumps(manifest, indent=2) + "\n")
PY
bash tests/compile-checks.sh "$task_directory/checks" \
  tests/LongCaptureStationaryQuantizationChecks.swift 2>&1 | tee "$task_directory/compile.log"
"$task_directory/checks" 2>"$task_directory/runtime.stderr.log" | tee "$task_directory/results.log"
printf 'Evidence: %s\n' "$task_directory"
