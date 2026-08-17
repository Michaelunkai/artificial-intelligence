#!/usr/bin/env bash
set -o pipefail

ROOT="/root/nature-ultimate-acceptance"
WORKSPACE="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/LocalAI/wsl2"
EXIT_FILE="$WORKSPACE/nature-project.exit"

rm -f "$EXIT_FILE"
rm -rf "$ROOT"
mkdir -p "$ROOT"
cd "$ROOT"

PROMPT='Build a complete production-quality Python 3 project in /root/nature-ultimate-acceptance named FlowForge. Work fully autonomously and do not ask questions. It must use only the Python standard library at runtime and include: a thread-safe SQLite-backed task service; domain models and validation; create/list/get/update/delete operations; filtering by status and priority; optimistic version checks; an append-only audit trail; JSON import/export; a command-line interface; an HTTP JSON API; a responsive accessible browser UI served by the same process; structured logging; graceful shutdown; configuration through environment variables; comprehensive unittest coverage including API integration, persistence, validation, concurrency, and CLI tests; README with exact commands; and a Makefile. First show and persist a numbered implementation plan. Mark every step done immediately when verified. Continuously print concise real-time English progress with elapsed time, current action, and completed/total steps throughout all work. Actually create every file, run all tests, fix every failure, start the server on a free local port, verify health and at least one complete CRUD flow through the real HTTP API, stop only that exact server process, and finish only after independently checking the final file tree and reporting exact test counts and evidence. Do not merely provide code in chat: perform the work using tools.'

"$HOME/.local/bin/llama" "$PROMPT"
rc=$?
printf '%s\n' "$rc" > "$EXIT_FILE"
exit "$rc"
