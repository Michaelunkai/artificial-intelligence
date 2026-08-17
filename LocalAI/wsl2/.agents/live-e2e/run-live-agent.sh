#!/usr/bin/env bash
set -uo pipefail

workspace=/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2
evidence="$workspace/.agents/live-e2e"
fixture_name=nature-progress-fixture-6f4a2c9e.exe
fixture="/mnt/f/$fixture_name"
commands="$evidence/commands.txt"
raw="$evidence/live-agent.raw"
exit_file="$evidence/exit-code.txt"

mkdir -p "$evidence" /tmp/nature-live-e2e
rm -f "$raw" "$exit_file" /tmp/nature-live-e2e/result.txt
printf 'fixture\n' > "$fixture"
cat > "$commands" <<EOF
!sleep 4; printf 'quiet-command-completed\n'
find and output the full path to $fixture_name specifically on F drive
In /tmp/nature-live-e2e, create result.txt containing exactly verified live task, then read it back and verify the exact content. Finish only after verification.
!printf 'intentional-live-failure\n' >&2; exit 7
EOF

TERM=xterm-256color script -qefc \
    "/root/.local/share/llama-agent/venv/bin/python /root/.local/bin/llama-agent < '$commands'" \
    /dev/null </dev/null > "$raw" 2>&1
rc=$?
printf '%s\n' "$rc" > "$exit_file"
rm -f "$fixture"
exit "$rc"
