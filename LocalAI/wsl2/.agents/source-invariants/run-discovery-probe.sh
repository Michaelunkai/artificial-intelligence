#!/usr/bin/env bash
set -euo pipefail

source_file="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/a.sh"
work_file=$(mktemp /tmp/nature-discovery.XXXXXX.py)
trap 'rm -f "$work_file"' EXIT

start=$(grep -n '^python3 - .*DISCOVERYEOF' "$source_file" | head -1 | cut -d: -f1)
end=$(grep -n '^DISCOVERYEOF$' "$source_file" | head -1 | cut -d: -f1)
sed -n "$((start + 1)),$((end - 1))p" "$source_file" >"$work_file"

python3 -m py_compile "$work_file"
python3 "$work_file" 28 10 /root/models
