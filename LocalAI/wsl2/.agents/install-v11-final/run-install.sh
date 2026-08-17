#!/usr/bin/env bash
set +e

base="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/.agents/install-v11-final"
script="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/a.sh"

rm -f "$base/exit-code.txt"
bash "$script" >"$base/install.log" 2>&1
rc=$?
printf '%s\n' "$rc" >"$base/exit-code.txt"
exit "$rc"
