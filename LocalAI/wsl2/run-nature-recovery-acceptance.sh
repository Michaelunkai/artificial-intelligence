#!/usr/bin/env bash
set -euo pipefail

cd /root/nature-ultimate-acceptance

PROMPT=$(cat <<'EOF'
Recover and finish the existing FlowForge project in /root/nature-ultimate-acceptance/FlowForge without asking me for help.

Start by writing a detailed numbered recovery plan. Keep its steps updated immediately as each one is proven complete.

Fresh independent acceptance on August 13, 2026 reports 67 discovered tests with
3 failures and 8 errors. Fix these exact current defects first:
- FlowForge/api/server.py is syntactically invalid because `import socket` is
  before `from __future__ import annotations`. The future import must immediately
  follow the module docstring.
- All API tests are blocked by that syntax error. Preserve object JSON responses
  and make server shutdown/rebinding reliable without manually pre-binding a
  second socket.
- FlowForge/cli.py still imports `service`, `database`, and related modules as
  top-level modules. Make package imports work for `python3 -m FlowForge.cli`.
- Import/export still fails valid import, duplicate-ID skipping, JSON-string
  tags, and export/import round trips.
- A stale optimistic version still succeeds instead of raising ValueError.

Requirements:
1. Inspect the current code and full tracebacks before editing. Do not use tail/head to hide test failures.
2. Use focused apply_patch edits for existing files. Do not use write_file for
   existing Python modules and never rewrite a file with identical content.
3. Fix implementation root causes and only correct tests when the test itself is objectively malformed.
4. Run exactly `cd /root/nature-ultimate-acceptance && python3 -m unittest
   discover -s FlowForge/tests -v` after every repair group until all tests pass.
5. Run compileall and the CLI tests from a clean package-aware working directory.
6. Ensure README.md and Makefile document exact setup, tests, CLI, server, import/export, and environment configuration.
7. Start the HTTP server on a free port, prove /health, then perform real create, read, update with optimistic version, filtered list, audit, export/import, and delete requests.
8. Shut the proof server down cleanly and verify the port is released.
9. Do not claim completion from file creation or partial tests. Finish only after fresh full-suite and live HTTP evidence, and end with [TASK_COMPLETE].
EOF
)

exec /root/.local/bin/llama-agent "$PROMPT"
