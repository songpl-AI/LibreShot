#!/bin/bash
set -euo pipefail

if (( $# < 2 || $# > 3 )); then
    printf 'Usage: %s APP_PID OUTPUT_CSV [SAMPLES]\n' "$0" >&2
    exit 2
fi

app_pid="$1"
output="$2"
samples="${3:-36}"
[[ "$app_pid" =~ ^[0-9]+$ && "$samples" =~ ^[0-9]+$ ]] || exit 2
[[ ! -e "$output" ]] || { printf 'Output already exists: %s\n' "$output" >&2; exit 2; }
printf 'epoch_seconds,process,pid,physical_footprint\n' > "$output"

sample_process() {
    local label="$1" pid="$2" footprint
    footprint=$(vmmap -summary "$pid" 2>/dev/null | awk '$1 == "Physical" && $2 == "footprint:" { print $3; exit }') || true
    [[ -n "$footprint" ]] && printf '%s,%s,%s,%s\n' "$(date +%s)" "$label" "$pid" "$footprint" >> "$output"
}

for ((index=0; index<samples; index++)); do
    kill -0 "$app_pid" 2>/dev/null || break
    sample_process LibreShot "$app_pid"
    translation_pid=$(pgrep -f '^/System/Library/Frameworks/Translation.framework/translationd$' | head -1 || true)
    extension_pid=$(pgrep -f '/TranslationAPISupportExtension.appex/Contents/MacOS/TranslationAPISupportExtension' | head -1 || true)
    [[ -z "$translation_pid" ]] || sample_process translationd "$translation_pid"
    [[ -z "$extension_pid" ]] || sample_process TranslationAPISupportExtension "$extension_pid"
    ((index + 1 == samples)) || sleep 5
done

printf '%s\n' "$output"
