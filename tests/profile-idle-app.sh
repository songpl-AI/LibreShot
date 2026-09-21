#!/bin/bash
set -euo pipefail
task_app=${1:?Usage: profile-idle-app.sh /absolute/path/LibreShot.app}
task_binary="$task_app/Contents/MacOS/LibreShot"
[[ -x "$task_binary" ]]
if pgrep -x LibreShot >/dev/null; then
    printf 'LibreShot is already running; quit it before profiling a second copy.\n' >&2
    exit 1
fi
# Launch the full app with its saved settings, without initiating a capture or changing preferences.
"$task_binary" &
task_pid=$!
trap 'kill -TERM "$task_pid" 2>/dev/null || true; wait "$task_pid" 2>/dev/null || true' EXIT
task_previous=0
for task_second in 1 5 15 60; do
    sleep "$((task_second - task_previous))"
    printf 'IDLE APP at %ss\n' "$task_second"
    ps -p "$task_pid" -o pid=,rss=,%cpu=,time=
    vmmap -summary "$task_pid" 2>/dev/null | rg 'Physical footprint' || true
    task_previous=$task_second
done
