#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
task_directory=$(mktemp -d "${TMPDIR:-/tmp}/libreshot-activation-policy.XXXXXX")
trap 'rm -rf "$task_directory"' EXIT
bash tests/compile-checks.sh "$task_directory/checks" tests/ActivationPolicyChecks.swift
"$task_directory/checks"
