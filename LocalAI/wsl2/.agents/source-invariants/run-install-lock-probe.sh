#!/usr/bin/env bash
set -euo pipefail

source_file="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/a.sh"
output_file="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2/.agents/source-invariants/install-lock-probe.raw"
fake_home=$(mktemp -d /tmp/nature-install-lock.XXXXXX)
holder_pid=""

cleanup() {
    if [[ -n "$holder_pid" ]]; then
        kill "$holder_pid" 2>/dev/null || true
        wait "$holder_pid" 2>/dev/null || true
    fi
    rm -rf "$fake_home"
}
trap cleanup EXIT

mkdir -p "$fake_home/.local/bin" "$fake_home/.local/share/llama-agent"
cp /root/.local/bin/llama-agent "$fake_home/.local/bin/llama-agent"
source_hash=$(sha256sum "$source_file" | awk '{print $1}')
agent_hash=$(sha256sum "$fake_home/.local/bin/llama-agent" | awk '{print $1}')
printf '%s|%s\n' "$source_hash" "$agent_hash" \
    > "$fake_home/.local/share/llama-agent/installed-source.sha256"

(
    exec 7>"$fake_home/.local/share/llama-agent/install.lock"
    flock 7
    : > "$fake_home/lock-ready"
    sleep 5
) &
holder_pid=$!
for _ in $(seq 1 100); do
    [[ -e "$fake_home/lock-ready" ]] && break
    sleep 0.05
done
[[ -e "$fake_home/lock-ready" ]]

rm -f "$output_file"
command_text=$(printf 'env HOME=%q TERM=xterm-256color bash %q' \
    "$fake_home" "$source_file")
/usr/bin/script -qefc "$command_text" "$output_file"

python3 - "$output_file" <<'PY'
import collections
import re
import sys
from pathlib import Path

raw = Path(sys.argv[1]).read_text(errors="replace")
ansi = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")
lines = [
    " ".join(ansi.sub("", line).split())
    for line in re.split(r"[\r\n]+", raw)
]
working = [line for line in lines if line.startswith("[WORKING]")]
counts = collections.Counter(working)
assert working, raw
assert len(working) == len(counts), counts
assert any("waited 2 seconds" in line for line in working), working
assert any("waited 4 seconds" in line for line in working), working
assert all("has not started duplicate package or build work" in line for line in working)
assert "already deployed this exact source and agent" in raw
assert "Step 1/11" not in raw
print(f"INSTALL_LOCK_PROBE_OK frames={len(working)} unique={len(counts)}")
PY
