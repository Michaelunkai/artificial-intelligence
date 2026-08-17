#!/usr/bin/env bash
set +e

base="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/.agents/install-exact-evidence"
installer="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/a.sh"

rm -f \
    "$base/terminal.raw" \
    "$base/exit-code.txt"
/usr/bin/script -qefc "/bin/bash '$installer'" "$base/terminal.raw"
status=$?
printf '%s\n' "$status" > "$base/exit-code.txt"
exit "$status"
