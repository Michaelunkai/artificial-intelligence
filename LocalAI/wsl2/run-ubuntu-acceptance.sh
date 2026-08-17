#!/usr/bin/env bash
set -o pipefail

SCRIPT_DIR="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2"
EXIT_FILE="$SCRIPT_DIR/ubuntu-install.exit"

rm -f "$EXIT_FILE"
bash "$SCRIPT_DIR/a.sh"
rc=$?
printf '%s\n' "$rc" > "$EXIT_FILE"
exit "$rc"
