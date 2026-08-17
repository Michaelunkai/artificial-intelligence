#!/usr/bin/env bash
set -euo pipefail

base="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/.agents/source-invariants"
python3 "$base/tty-progress-probe.py" >"$base/redirected-stdout.txt"
