#!/usr/bin/env bash
set -euo pipefail

base="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/.agents/source-invariants"
source_file="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/a.sh"

# Load the installer progress implementation without starting the installer.
source <(
    {
        sed -n \
            '/^PROGRESS_FILE=$(mktemp)/,/^set_activity "Starting the Local AI installation/p' \
            "$source_file" |
            sed '$d'
        sed -n '/^# ─── Colours & helpers/,/^fail()/p' "$source_file"
    }
)

set_activity "Checking the first verified installer fact"
progress_clock &
PROGRESS_PID=$!
sleep 1.2
ok "The first verified installer fact completed"
sleep 1.2
set_activity "Checking the second verified installer fact"
sleep 1.2
stop_progress_clock
printf 'INSTALLER_REDIRECTED_STDOUT_RESULT\n' >"$base/installer-redirected-stdout.txt"
