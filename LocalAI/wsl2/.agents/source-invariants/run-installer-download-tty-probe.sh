#!/usr/bin/env bash
set -euo pipefail

base="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/.agents/source-invariants"
source_file="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/a.sh"
fixture="$base/fake-model.part"
trap 'rm -f "$fixture"' EXIT

source <(
    sed -n '/^PROGRESS_FILE=$(mktemp)/,/^set_activity "Starting the Local AI installation/p' "$source_file" |
        sed '$d'
)

stty cols 42
truncate -s 1073741824 "$fixture"
set_activity "Downloading a deliberately long local model name"
set_download_progress "$fixture" 4294967296
progress_clock &
PROGRESS_PID=$!
sleep 1.2
truncate -s 2147483648 "$fixture"
sleep 1.2
stop_progress_clock
