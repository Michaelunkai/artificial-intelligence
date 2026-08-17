#!/usr/bin/env bash
set +e

base="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/.agents/install-final-idempotent"
installer="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/a.sh"

rm -f "$base/exit-code.txt"
/usr/bin/script -qefc "/bin/bash '$installer'" "$base/terminal.raw"
rc=$?
printf '%s\n' "$rc" >"$base/exit-code.txt"
exit "$rc"
