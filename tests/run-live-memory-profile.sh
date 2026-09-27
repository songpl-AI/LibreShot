#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

if (( $# < 1 || $# > 2 )); then
    printf 'Usage: %s PROFILE_APP [SAMPLES]\n' "$0" >&2
    exit 2
fi

app="$(cd "$1" && pwd)"
samples="${2:-90}"
[[ -d "$app" && "$samples" =~ ^[0-9]+$ ]] || exit 2
output="$(pwd)/dist/memory-run-$(date +%Y%m%d-%H%M%S)"
mkdir "$output"
trace="${TMPDIR:-/tmp}/libreshot-memory-events-$(date +%s)-$$.csv"
trap 'if [[ -f "$trace" ]]; then cp "$trace" "$output/events.csv"; fi' EXIT

open -n -a "$app" --env "LIBRESHOT_MEMORY_TRACE=$trace"
for ((attempt=0; attempt<250; attempt++)); do
    [[ -s "$trace" ]] && break
    sleep 0.2
done
[[ -s "$trace" ]] || { printf 'App did not create trace: %s\n' "$trace" >&2; exit 1; }

pid=$(awk -F, 'NR == 2 { print $2 }' "$trace")
[[ "$pid" =~ ^[0-9]+$ ]] || exit 1
printf 'Profile app PID: %s\nTrace: %s\n' "$pid" "$output/events.csv"
bash tests/sample-live-memory.sh "$pid" "$output/processes.csv" "$samples"
printf 'Profile data: %s\n' "$output"
