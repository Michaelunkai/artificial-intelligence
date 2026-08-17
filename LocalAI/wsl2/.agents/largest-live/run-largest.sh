#!/usr/bin/env bash
set -uo pipefail

workspace=/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2
evidence="$workspace/.agents/largest-live"
raw="$evidence/largest.raw"
exit_file="$evidence/exit-code.txt"

mkdir -p "$evidence"
rm -f "$raw" "$exit_file"
TERM=xterm-256color script -qefc \
    "/root/.local/share/llama-agent/venv/bin/python '$evidence/run-largest.py'" \
    /dev/null </dev/null > "$raw" 2>&1
rc=$?
printf '%s\n' "$rc" > "$exit_file"
exit "$rc"
