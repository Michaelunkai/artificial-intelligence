#!/usr/bin/env bash
set -euo pipefail

output_directory=/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/.agents/live-final/resume-final-gated
mkdir -p "$output_directory"
rm -f \
    "$output_directory/terminal.raw" \
    "$output_directory/exit-code.txt"

set +e
TERM=xterm-256color COLUMNS=140 LINES=45 LLAMA_COMPLETION_SOUND=1 \
    /usr/bin/script -qefc \
    "/root/.local/bin/llama --resume" \
    "$output_directory/terminal.raw"
status=$?
set -e
printf '%s\n' "$status" >"$output_directory/exit-code.txt"
exit "$status"
