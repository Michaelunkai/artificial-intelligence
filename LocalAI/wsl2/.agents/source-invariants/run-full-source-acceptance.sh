#!/usr/bin/env bash
set -euo pipefail

source_file="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/a.sh"
work_dir=$(mktemp -d /tmp/nature-source-acceptance.XXXXXX)
trap 'rm -rf "$work_dir"' EXIT
host_site="/mnt/c/Users/micha/AppData/Local/Programs/Python/Python312/Lib/site-packages"

sed -n \
    '/^cat > "$HOME\/.local\/bin\/llama-agent" <<'\''AGENTEOF'\''$/,/^AGENTEOF$/p' \
    "$source_file" |
    sed '1d;$d' >"$work_dir/llama-agent"

sed -n \
    '/<<'\''PYTESTEOF'\''$/,/^PYTESTEOF$/p' \
    "$source_file" |
    sed '1d;$d' >"$work_dir/acceptance.py"

PYTHONPATH="$host_site${PYTHONPATH:+:$PYTHONPATH}" \
    python3 -m py_compile "$work_dir/llama-agent"
PYTHONPATH="$host_site${PYTHONPATH:+:$PYTHONPATH}" \
    python3 "$work_dir/acceptance.py" "$work_dir/llama-agent"
