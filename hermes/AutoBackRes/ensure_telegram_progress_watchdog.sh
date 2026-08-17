#!/usr/bin/env bash
set -u

USER_NAME="${HERMES_WSL_USER:-ubuntu}"
HOME_DIR="/home/${USER_NAME}"
SESSION="hermes-telegram-progress-watchdog"
SCRIPT="${HOME_DIR}/.hermes/scripts/telegram_fleet_progress_watchdog.py"
LOG_DIR="${HOME_DIR}/.hermes/logs"
LOG_FILE="${LOG_DIR}/telegram-progress-watchdog.log"
MODE="low_noise_edit_zero_token_v1"
mkdir -p "$LOG_DIR"

if [ ! -f "$SCRIPT" ]; then
  echo "READY_PROGRESS_WATCHDOG_FAIL=script_missing path=${SCRIPT}"
  exit 1
fi
chmod 0755 "$SCRIPT" 2>/dev/null || true

if ! python3 -m py_compile "$SCRIPT" >/dev/null 2>&1; then
  echo "READY_PROGRESS_WATCHDOG_FAIL=script_py_compile path=${SCRIPT}"
  python3 -m py_compile "$SCRIPT" 2>&1 | tail -20
  exit 1
fi

if ! python3 "$SCRIPT" --self-test >/dev/null 2>&1; then
  echo "READY_PROGRESS_WATCHDOG_FAIL=self_test path=${SCRIPT}"
  python3 "$SCRIPT" --self-test 2>&1 | tail -20
  exit 1
fi

dry_json="$(python3 "$SCRIPT" --once --dry-run 2>&1)"
dry_code=$?
if [ "$dry_code" -ne 0 ]; then
  echo "READY_PROGRESS_WATCHDOG_FAIL=dry_run_exit code=${dry_code}"
  printf '%s\n' "$dry_json" | tail -20
  exit 1
fi
if ! DRY_JSON="$dry_json" python3 - <<'PY'
import json, os, sys
data = json.loads(os.environ["DRY_JSON"])
if data.get("mode") != "low_noise_edit_zero_token_v1":
    raise SystemExit("wrong_mode")
if data.get("homes") != 5 or data.get("required_homes") != 5:
    raise SystemExit("homes_not_five")
if data.get("telegram_calls") != 0 or data.get("sent") != 0 or data.get("edited") != 0:
    raise SystemExit("dry_run_touched_telegram")
print("dry_run_ok active=%s would_edit=%s would_send=%s" % (data.get("active"), data.get("would_edit"), data.get("would_send")))
PY
then
  echo "READY_PROGRESS_WATCHDOG_FAIL=dry_run_validation"
  printf '%s\n' "$dry_json" | tail -20
  exit 1
fi

state_mode="$(python3 - <<'PY'
import json
from pathlib import Path
p=Path('/home/ubuntu/.hermes/.runtime/telegram-progress-watchdog-state.json')
try:
    data=json.loads(p.read_text())
except Exception:
    data={}
print((data.get('_watchdog_runtime') or {}).get('mode') or '')
PY
)"
if tmux has-session -t "=${SESSION}" >/dev/null 2>&1; then
  current_cmd="$(tmux display-message -p -t "=${SESSION}" '#{pane_current_command} #{pane_start_command}' 2>/dev/null || true)"
  if printf '%s' "$current_cmd" | grep -q "telegram_fleet_progress_watchdog.py" && [ "$state_mode" = "$MODE" ]; then
    echo "READY_PROGRESS_WATCHDOG_OK=already_running session=${SESSION} script=${SCRIPT} log=${LOG_FILE} mode=${MODE}"
    exit 0
  fi
  echo "READY_PROGRESS_WATCHDOG_REPLACE=sidecar_only session=${SESSION} previous_mode=${state_mode:-unknown}"
  tmux kill-session -t "=${SESSION}" >/dev/null 2>&1 || true
fi

tmux new-session -d -s "$SESSION" "HERMES_WSL_USER='$USER_NAME' HERMES_PROGRESS_WATCHDOG_EVERY_SECONDS=60 HERMES_PROGRESS_WATCHDOG_POLL_SECONDS=2 python3 '$SCRIPT' >>'$LOG_FILE' 2>&1"
sleep 1
if ! tmux has-session -t "=${SESSION}" >/dev/null 2>&1; then
  echo "READY_PROGRESS_WATCHDOG_FAIL=start_failed session=${SESSION}"
  exit 1
fi
echo "READY_PROGRESS_WATCHDOG_OK=started session=${SESSION} script=${SCRIPT} log=${LOG_FILE} mode=${MODE} sidecar_only=1"
