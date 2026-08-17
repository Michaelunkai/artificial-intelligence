#!/usr/bin/env bash
set -uo pipefail

root="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2"
evidence="$root/.agents/install-final-vram"
raw="$evidence/terminal-final-gate.raw"
exit_file="$evidence/terminal-final-gate.exit"

rm -f "$exit_file"
script -qefc "env TERM=xterm-256color bash '$root/a.sh'" "$raw"
status=$?
printf '%s\n' "$status" >"$exit_file"
exit "$status"
