#!/usr/bin/env bash
set -euo pipefail

if [[ $# -ne 2 ]]; then
    printf 'Usage: %s OUTPUT_DIRECTORY PROMPT_FILE\n' "$0" >&2
    exit 64
fi

output_directory=$1
prompt_file=$2
if [[ ! -f "$prompt_file" ]]; then
    printf 'Prompt file not found: %s\n' "$prompt_file" >&2
    exit 66
fi
prompt=$(<"$prompt_file")
if [[ -z "${prompt//[[:space:]]/}" ]]; then
    printf 'Prompt file is empty: %s\n' "$prompt_file" >&2
    exit 65
fi
mkdir -p "$output_directory"
rm -f \
    "$output_directory/terminal.raw" \
    "$output_directory/stdout.log" \
    "$output_directory/stderr.log" \
    "$output_directory/exit-code.txt"

printf -v command '%q ' \
    env \
    TERM=xterm-256color \
    COLUMNS=120 \
    LINES=40 \
    LLAMA_COMPLETION_SOUND=1 \
    /root/.local/bin/llama \
    "$prompt"

set +e
/usr/bin/script -qefc "$command" "$output_directory/terminal.raw"
status=$?
set -e
printf '%s\n' "$status" > "$output_directory/exit-code.txt"
exit "$status"
