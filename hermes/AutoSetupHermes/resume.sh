#!/usr/bin/env bash
set -Eeuo pipefail

USER_NAME="${HERMES_WSL_USER:-ubuntu}"
HOME_DIR="/home/${USER_NAME}"
SESSION_NAME="${HERMES_TMUX_SESSION:-hermes-gateway}"
HERMES_BIN="${HOME_DIR}/.local/bin/hermes"
HERMES_VENV_BIN="${HOME_DIR}/.hermes/hermes-agent/venv/bin/hermes"
HERMES_PATH="${HOME_DIR}/.local/bin:${HOME_DIR}/.hermes/node/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/snap/bin"
LOG_DIR="${HOME_DIR}/.hermes/logs"
GATEWAY_LOG="${LOG_DIR}/gateway.log"
RUN_LOG="${LOG_DIR}/gateway-run.log"
RESUME_LOG="${LOG_DIR}/resume.log"
SECRET_FILE="${HOME_DIR}/.config/hermes-setup/telegram.env"
CODEX_AUTH="${HOME_DIR}/.codex/auth.json"
HERMES_ENV="${HOME_DIR}/.hermes/.env"

ts() {
  date -Iseconds
}

log() {
  local line
  line="[$(ts)] $*"
  echo "$line"
  if [ -d "$LOG_DIR" ]; then
    printf '%s\n' "$line" >> "$RESUME_LOG"
  fi
}

as_ubuntu() {
  if [ "$(id -un)" = "$USER_NAME" ]; then
    env PATH="$HERMES_PATH" HOME="$HOME_DIR" "$@"
  else
    sudo -H -u "$USER_NAME" env PATH="$HERMES_PATH" HOME="$HOME_DIR" "$@"
  fi
}

require_file() {
  local path="$1"
  local label="$2"
  if [ ! -e "$path" ]; then
    log "ERROR: missing ${label}: ${path}"
    exit 10
  fi
}

require_cmd() {
  local cmd="$1"
  if ! command -v "$cmd" >/dev/null 2>&1; then
    log "ERROR: missing command: $cmd"
    exit 11
  fi
}

gateway_status_ok() {
  as_ubuntu "$HERMES_BIN" gateway status >/tmp/hermes-resume-status.txt 2>&1
}

gateway_process_ok() {
  pgrep -u "$USER_NAME" -f "hermes gateway run" >/dev/null 2>&1
}

gateway_has_connected_before() {
  grep -Eq "Connected to Telegram|Gateway running with 1 platform" "$GATEWAY_LOG" 2>/dev/null
}

telegram_api_probe() {
  curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" >/tmp/hermes-resume-getme.json
  python3 - <<'PY'
import json
data=json.load(open('/tmp/hermes-resume-getme.json'))
if not data.get('ok'):
    raise SystemExit('Telegram getMe returned not ok')
user=data.get('result', {})
print('Telegram bot OK: id=%s username=@%s' % (user.get('id'), user.get('username')))
PY
}

telegram_send_probe() {
  local chat_id="${TELEGRAM_TEST_CHAT_ID:-}"
  if [ -z "$chat_id" ] && [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then
    chat_id="${TELEGRAM_ALLOWED_USERS%%,*}"
  fi
  if [ -z "$chat_id" ]; then
    log "ERROR: no Telegram chat id in TELEGRAM_TEST_CHAT_ID or TELEGRAM_ALLOWED_USERS"
    exit 12
  fi
  curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
    -d chat_id="$chat_id" \
    --data-urlencode text="Hermes WSL2 resume verified and ready: $(ts)" >/tmp/hermes-resume-send.json
  python3 - <<'PY'
import json
data=json.load(open('/tmp/hermes-resume-send.json'))
if not data.get('ok'):
    raise SystemExit('Telegram sendMessage returned not ok')
print('Telegram resume probe sent')
PY
}

start_gateway_without_data_loss() {
  log "Gateway is not healthy; reconnecting Hermes gateway only. No data files will be removed."
  curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/deleteWebhook" >/tmp/hermes-resume-deletewebhook.json || true
  as_ubuntu tmux kill-session -t "$SESSION_NAME" 2>/dev/null || true
  as_ubuntu tmux new-session -d -s "$SESSION_NAME" \
    "cd '$HOME_DIR' && export PATH='$HERMES_PATH' && exec '$HERMES_BIN' gateway run >>'$RUN_LOG' 2>&1"

  local deadline
  deadline=$((SECONDS + 75))
  while [ "$SECONDS" -lt "$deadline" ]; do
    if gateway_status_ok && gateway_process_ok; then
      log "Hermes gateway status OK after reconnect"
      return 0
    fi
    sleep 3
  done

  log "ERROR: Hermes gateway did not become healthy in time"
  cat /tmp/hermes-resume-status.txt 2>/dev/null || true
  tail -120 "$RUN_LOG" 2>/dev/null || true
  exit 20
}

mkdir -p "$LOG_DIR"
touch "$RESUME_LOG"
log "Starting Hermes WSL2 resume check"

require_cmd curl
require_cmd python3
require_cmd tmux
require_file "$SECRET_FILE" "Telegram secret"
require_file "$CODEX_AUTH" "Codex auth"
require_file "$HERMES_ENV" "Hermes env"

if [ ! -x "$HERMES_BIN" ] && [ -x "$HERMES_VENV_BIN" ]; then
  mkdir -p "${HOME_DIR}/.local/bin"
  ln -sfn "$HERMES_VENV_BIN" "$HERMES_BIN"
fi
require_file "$HERMES_BIN" "Hermes command"

chown "$USER_NAME:$USER_NAME" "$SECRET_FILE" "$CODEX_AUTH" "$HERMES_ENV" "$RESUME_LOG" 2>/dev/null || true
chmod 600 "$SECRET_FILE" "$CODEX_AUTH" "$HERMES_ENV" 2>/dev/null || true

set -a
. "$SECRET_FILE"
set +a
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
  log "ERROR: TELEGRAM_BOT_TOKEN is missing in ${SECRET_FILE}"
  exit 13
fi

telegram_api_probe

action="kept-existing"
if gateway_status_ok && gateway_process_ok && gateway_has_connected_before; then
  log "Existing Hermes gateway is healthy; keeping it running without restart"
else
  action="reconnected"
  start_gateway_without_data_loss
fi

telegram_send_probe

log "Final Hermes gateway status:"
cat /tmp/hermes-resume-status.txt 2>/dev/null || as_ubuntu "$HERMES_BIN" gateway status
log "Recent Telegram gateway log:"
grep -E "Connected to Telegram|Gateway running with 1 platform" "$GATEWAY_LOG" 2>/dev/null | tail -10 || true

echo "RESUME_ACTION=$action"
echo "RESUME_LOG=$RESUME_LOG"
echo "RUN_LOG=$RUN_LOG"
log "Hermes WSL2 resume complete"
