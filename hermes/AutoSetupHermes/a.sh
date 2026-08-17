#!/usr/bin/env bash
set -Eeuo pipefail
set +x

SCRIPT_VERSION="2026-05-05-hermes-wsl-reinstall-safe"
INSTALLER_URL="https://raw.githubusercontent.com/NousResearch/hermes-agent/main/scripts/install.sh"
TARGET_USER="${HERMES_WSL_USER:-}"
TARGET_USER_FALLBACK="${HERMES_WSL_USER_FALLBACK:-ubuntu}"
TMUX_SESSION="${HERMES_TMUX_SESSION:-hermes-gateway}"
DEFAULT_CODEX_MODEL="gpt-5.5"
WIN_CODEX_HOME="/mnt/c/Users/micha/.codex"
WIN_HERMES_SECRET="${WIN_HERMES_SECRET:-/mnt/c/Users/micha/.codex/secrets/hermes-telegram.env}"
OPENCLAW_ROUTE_REGISTRY="/mnt/c/Users/micha/.openclaw/telegram/route-registry.json"
WINDOWS_STARTUP_TASK_NAME="${WINDOWS_STARTUP_TASK_NAME:-Hermes WSL2 Gateway}"

die() {
  printf 'ERROR: %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[%s] %s\n' "$(date -Iseconds)" "$*"
}

user_home_for() {
  local name="$1"
  getent passwd "$name" | awk -F: '{print $6}'
}

is_windows_mount_path() {
  case "$1" in
    /mnt/[a-zA-Z]/*) return 0 ;;
    *) return 1 ;;
  esac
}

first_wsl_human_user() {
  awk -F: '$3 >= 1000 && $3 < 60000 && $1 != "nobody" {print $1; exit}' /etc/passwd
}

resolve_target_user() {
  local requested="${TARGET_USER:-}"
  local detected=""
  if [ -n "$requested" ]; then
    printf '%s\n' "$requested"
    return 0
  fi
  if id "$TARGET_USER_FALLBACK" >/dev/null 2>&1; then
    printf '%s\n' "$TARGET_USER_FALLBACK"
    return 0
  fi
  detected="$(first_wsl_human_user || true)"
  if [ -n "$detected" ]; then
    printf '%s\n' "$detected"
  else
    printf '%s\n' "$TARGET_USER_FALLBACK"
  fi
}

ensure_root_prereqs() {
  [ "$(id -u)" -eq 0 ] || return 0
  if command -v sudo >/dev/null 2>&1 && command -v adduser >/dev/null 2>&1; then
    return 0
  fi
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  info "Installing root bootstrap prerequisites for fresh WSL"
  apt-get update -y
  apt-get install -y sudo adduser passwd ca-certificates
}

ensure_target_user_exists() {
  local target_user="$1"
  id "$target_user" >/dev/null 2>&1 && return 0
  [ "$(id -u)" -eq 0 ] || die "Target WSL user $target_user does not exist and current user is not root"
  ensure_root_prereqs
  info "Creating WSL user $target_user for Hermes"
  adduser --disabled-password --gecos "" "$target_user"
  usermod -aG sudo "$target_user" || true
}

ensure_passwordless_sudo_for_setup() {
  local target_user="$1"
  [ "$(id -u)" -eq 0 ] || return 0
  ensure_root_prereqs
  install -d -m 755 /etc/sudoers.d
  printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$target_user" > /etc/sudoers.d/99-hermes-wsl-setup
  chmod 440 /etc/sudoers.d/99-hermes-wsl-setup
}

ensure_target_user_home_writable() {
  local target_home="$1"
  local target_user="$2"
  [ "$(id -u)" -eq 0 ] || return 0
  [ -n "$target_home" ] || die "Cannot repair empty target home path"
  case "$target_home" in
    /home/*|/root) ;;
    *) die "Refusing to repair unexpected home path: $target_home" ;;
  esac

  install -d -m 750 -o "$target_user" -g "$target_user" "$target_home"
  chown "$target_user:$target_user" "$target_home"
  chmod u+rwx "$target_home"

  # WSL imports can preserve root-owned parent dirs. uv and Hermes both need
  # normal user-writable XDG dirs before the installer runs as the target user.
  install -d -m 700 -o "$target_user" -g "$target_user" \
    "$target_home/.config" \
    "$target_home/.local" \
    "$target_home/.local/bin" \
    "$target_home/.cache"
  chown "$target_user:$target_user" \
    "$target_home/.config" \
    "$target_home/.local" \
    "$target_home/.local/bin" \
    "$target_home/.cache"
  chmod u+rwx "$target_home/.config" "$target_home/.local" "$target_home/.local/bin" "$target_home/.cache"
}

write_secret_file() {
  local secret_file="$1"
  local target_user="${2:-}"
  local token="$3"
  local allowed="${4:-}"
  local setup_dir
  setup_dir="$(dirname "$secret_file")"

  [ -n "$token" ] || return 0
  if [ "$(id -u)" -eq 0 ] && [ -n "$target_user" ] && ! is_windows_mount_path "$secret_file"; then
    install -d -m 700 -o "$target_user" -g "$target_user" "$setup_dir"
  else
    install -d -m 700 "$setup_dir" 2>/dev/null || mkdir -p "$setup_dir"
  fi
  umask 077
  {
    printf 'TELEGRAM_BOT_TOKEN=%q\n' "$token"
    if [ -n "$allowed" ]; then
      printf 'TELEGRAM_ALLOWED_USERS=%q\n' "$allowed"
    fi
  } > "$secret_file.tmp"
  if [ "$(id -u)" -eq 0 ] && [ -n "$target_user" ] && ! is_windows_mount_path "$secret_file"; then
    chown "$target_user:$target_user" "$secret_file.tmp"
  fi
  chmod 600 "$secret_file.tmp" 2>/dev/null || true
  mv "$secret_file.tmp" "$secret_file"
}

write_secret_for_home() {
  local target_home="$1"
  local target_user="$2"
  local secret_file="$target_home/.config/hermes-setup/telegram.env"

  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || return 0
  write_secret_file "$secret_file" "$target_user" "$TELEGRAM_BOT_TOKEN" "${TELEGRAM_ALLOWED_USERS:-}"
  info "Stored Telegram token in Linux-side secret file for $target_user"
}

write_windows_secret_from_env() {
  [ -n "${TELEGRAM_BOT_TOKEN:-}" ] || return 0
  [ -n "$WIN_HERMES_SECRET" ] || return 0
  if is_windows_mount_path "$WIN_HERMES_SECRET"; then
    write_secret_file "$WIN_HERMES_SECRET" "" "$TELEGRAM_BOT_TOKEN" "${TELEGRAM_ALLOWED_USERS:-}"
    info "Stored Telegram token in Windows-side secret fallback for WSL reinstalls"
  fi
}

seed_secret_for_home() {
  local target_home="$1"
  local target_user="$2"
  local secret_file="$target_home/.config/hermes-setup/telegram.env"
  local setup_dir
  setup_dir="$(dirname "$secret_file")"

  [ -s "$secret_file" ] && return 0
  if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
    write_secret_for_home "$target_home" "$target_user"
    write_windows_secret_from_env
    return 0
  fi
  if [ -s "$WIN_HERMES_SECRET" ]; then
    if [ "$(id -u)" -eq 0 ] && ! is_windows_mount_path "$secret_file"; then
      install -d -m 700 -o "$target_user" -g "$target_user" "$setup_dir"
    else
      install -d -m 700 "$setup_dir"
    fi
    cp "$WIN_HERMES_SECRET" "$secret_file.tmp"
    if [ "$(id -u)" -eq 0 ] && ! is_windows_mount_path "$secret_file"; then
      chown "$target_user:$target_user" "$secret_file.tmp"
    fi
    chmod 600 "$secret_file.tmp"
    mv "$secret_file.tmp" "$secret_file"
    info "Seeded Linux-side Telegram secret from Windows-side fallback"
  fi
}

if [ "${HERMES_SETUP_AS_USER:-0}" != "1" ] && [ "$(id -u)" -eq 0 ]; then
  TARGET_USER="$(resolve_target_user)"
  ensure_target_user_exists "$TARGET_USER"
  ensure_passwordless_sudo_for_setup "$TARGET_USER"
  TARGET_HOME="$(user_home_for "$TARGET_USER")"
  [ -n "$TARGET_HOME" ] || die "Could not resolve home for $TARGET_USER"
  ensure_target_user_home_writable "$TARGET_HOME" "$TARGET_USER"
  seed_secret_for_home "$TARGET_HOME" "$TARGET_USER"
  unset TELEGRAM_BOT_TOKEN TELEGRAM_ALLOWED_USERS
  exec sudo -H -u "$TARGET_USER" env HERMES_SETUP_AS_USER=1 HERMES_WSL_USER="$TARGET_USER" bash "$0" "$@"
fi

HOME_DIR="$HOME"
HERMES_HOME="${HERMES_HOME:-$HOME_DIR/.hermes}"
SETUP_DIR="$HOME_DIR/.config/hermes-setup"
SECRET_FILE="$SETUP_DIR/telegram.env"
CODEX_HOME="$HOME_DIR/.codex"
CODEX_AUTH="$CODEX_HOME/auth.json"
HERMES_ENV="$HERMES_HOME/.env"
HERMES_CONFIG="$HERMES_HOME/config.yaml"
BACKUP_DIR="$HERMES_HOME/backups"
SETUP_LOG="$HERMES_HOME/logs/setup-a.log"
GATEWAY_LOG="$HERMES_HOME/logs/gateway-run.log"
GATEWAY_INTERNAL_LOG="$HERMES_HOME/logs/gateway.log"
ERROR_LOG="$HERMES_HOME/logs/errors.log"
SMOKE_LOG="$HERMES_HOME/logs/provider-smoke.log"
UPDATE_CHECK_LOG="$HERMES_HOME/logs/update-check.log"

umask 077
install -d -m 700 "$SETUP_DIR" "$CODEX_HOME" "$HERMES_HOME" "$HERMES_HOME/logs" "$BACKUP_DIR"
touch "$SETUP_LOG"
chmod 600 "$SETUP_LOG"

if [ -n "${TELEGRAM_BOT_TOKEN:-}" ]; then
  write_secret_for_home "$HOME_DIR" "$(id -un)"
  write_windows_secret_from_env
  unset TELEGRAM_BOT_TOKEN
fi

seed_secret_for_home "$HOME_DIR" "$(id -un)"
[ -f "$SECRET_FILE" ] || die "Missing Telegram secret file: $SECRET_FILE and Windows fallback $WIN_HERMES_SECRET. Run once with TELEGRAM_BOT_TOKEN set."
# shellcheck disable=SC1090
source "$SECRET_FILE"
[ -n "${TELEGRAM_BOT_TOKEN:-}" ] || die "TELEGRAM_BOT_TOKEN is empty in $SECRET_FILE"
if [[ ! "$TELEGRAM_BOT_TOKEN" =~ ^[0-9]{6,12}:[A-Za-z0-9_-]{20,}$ ]]; then
  die "TELEGRAM_BOT_TOKEN exists but does not match Telegram bot token shape"
fi
if [ ! -s "$WIN_HERMES_SECRET" ]; then
  write_windows_secret_from_env
fi

export PATH="$HOME_DIR/.local/bin:$HERMES_HOME/node/bin:/usr/local/bin:$PATH"

run() {
  info "+ $*"
  "$@"
}

retry() {
  local attempts="$1"
  shift
  local n=1
  until "$@"; do
    if [ "$n" -ge "$attempts" ]; then
      return 1
    fi
    info "Retry $n/$attempts failed for: $*"
    sleep $((n * 3))
    n=$((n + 1))
  done
}

backup_file() {
  local file="$1"
  [ -f "$file" ] || return 0
  local base stamp dest
  base="$(basename "$file")"
  stamp="$(date +%Y%m%d-%H%M%S)"
  dest="$BACKUP_DIR/$base.$stamp.bak"
  cp "$file" "$dest"
  chmod 600 "$dest"
}

prune_hermes_env_backups() {
  [ -d "$BACKUP_DIR" ] || return 0
  case "$BACKUP_DIR" in
    "$HERMES_HOME"/backups) ;;
    *) die "Refusing to prune unexpected backup dir: $BACKUP_DIR" ;;
  esac
  find "$BACKUP_DIR" -maxdepth 1 -type f -name '.env.*.bak' -exec rm -f -- {} +
}

apt_install() {
  export DEBIAN_FRONTEND=noninteractive
  export NEEDRESTART_MODE=a
  run sudo -n true
  run retry 3 sudo apt-get update -y
  run retry 3 sudo apt-get install -y \
    ca-certificates curl git python3 python3-venv python3-pip \
    build-essential python3-dev libffi-dev pkg-config \
    ripgrep ffmpeg tmux jq
}

copy_codex_auth() {
  local source_auth="$WIN_CODEX_HOME/auth.json"
  [ -s "$source_auth" ] || die "Windows Codex auth not found at $source_auth"
  python3 -m json.tool "$source_auth" >/dev/null || die "Windows Codex auth JSON is invalid"
  backup_file "$CODEX_AUTH"
  cp "$source_auth" "$CODEX_AUTH.tmp"
  chmod 600 "$CODEX_AUTH.tmp"
  mv "$CODEX_AUTH.tmp" "$CODEX_AUTH"
  info "Imported Codex auth into $CODEX_AUTH"
}

detect_codex_model() {
  python3 - "$WIN_CODEX_HOME/config.toml" "$DEFAULT_CODEX_MODEL" <<'PY'
import re, sys
path, default = sys.argv[1], sys.argv[2]
try:
    text = open(path, "r", encoding="utf-8").read()
except OSError:
    print(default)
    raise SystemExit
match = re.search(r'(?m)^\s*model\s*=\s*"([^"]+)"', text)
print(match.group(1) if match else default)
PY
}

telegram_api_check() {
  TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" python3 - <<'PY'
import json, os, sys, urllib.request
token = os.environ["TELEGRAM_BOT_TOKEN"]
with urllib.request.urlopen(f"https://api.telegram.org/bot{token}/getMe", timeout=25) as r:
    data = json.load(r)
if not data.get("ok"):
    raise SystemExit("Telegram getMe returned ok=false")
result = data["result"]
print(f"Telegram bot OK: id={result.get('id')} username=@{result.get('username')} can_join_groups={result.get('can_join_groups')}")
PY
}

delete_webhook_for_polling() {
  TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" python3 - <<'PY'
import json, os, urllib.parse, urllib.request
token = os.environ["TELEGRAM_BOT_TOKEN"]
base = f"https://api.telegram.org/bot{token}"
info = json.load(urllib.request.urlopen(base + "/getWebhookInfo", timeout=25))
url = (info.get("result") or {}).get("url") or ""
if url:
    req = urllib.request.Request(base + "/deleteWebhook", data=urllib.parse.urlencode({"drop_pending_updates": "false"}).encode())
    deleted = json.load(urllib.request.urlopen(req, timeout=25))
    if not deleted.get("ok"):
        raise SystemExit("deleteWebhook returned ok=false")
    print("Telegram webhook cleared for long polling gateway")
else:
    print("Telegram webhook already empty")
PY
}

detect_telegram_allowed_users() {
  if [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then
    printf '%s\n' "$TELEGRAM_ALLOWED_USERS"
    return 0
  fi
  if [ -f "$OPENCLAW_ROUTE_REGISTRY" ]; then
    python3 - "$OPENCLAW_ROUTE_REGISTRY" <<'PY'
import json, sys
path = sys.argv[1]
try:
    data = json.load(open(path, encoding="utf-8"))
except Exception:
    raise SystemExit
ids = []
def walk(x):
    if isinstance(x, dict):
        if str(x.get("accountId", "")).lower() == "openclaw4" and x.get("userId"):
            ids.append(str(x["userId"]))
        for v in x.values():
            walk(v)
    elif isinstance(x, list):
        for v in x:
            walk(v)
walk(data)
print(",".join(dict.fromkeys(ids)))
PY
  fi
}

install_or_update_hermes() {
  if command -v hermes >/dev/null 2>&1 && [ -x "$HERMES_HOME/hermes-agent/venv/bin/python" ]; then
    info "Hermes already installed; checking for updates"
    : > "$UPDATE_CHECK_LOG"
    chmod 600 "$UPDATE_CHECK_LOG"
    if timeout 180 hermes update --check >"$UPDATE_CHECK_LOG" 2>&1; then
      if grep -qi "Already up to date" "$UPDATE_CHECK_LOG"; then
        hermes --version || true
        return 0
      fi
      info "Hermes update appears available; running hermes update --yes"
      timeout 1200 hermes update --yes
      hermes --version || true
      return 0
    fi
    info "Hermes update check failed; falling back to official installer"
  fi
  if ! command -v uv >/dev/null 2>&1; then
    if [ -x "$HOME_DIR/.local/bin/uv" ]; then
      export PATH="$HOME_DIR/.local/bin:$PATH"
    else
      info "Pre-installing uv so the Hermes installer can detect it reliably"
      local uv_install_log="$HERMES_HOME/logs/uv-install.log"
      if ! bash -c "curl -LsSf https://astral.sh/uv/install.sh | sh" >"$uv_install_log" 2>&1; then
        sed -E 's/[0-9]{6,12}:[A-Za-z0-9_-]{20,}/[TELEGRAM_TOKEN_MASKED]/g; s/sk-[A-Za-z0-9_-]{20,}/[OPENAI_KEY_MASKED]/g' "$uv_install_log" | tail -80 >&2 || true
        die "uv bootstrap did not complete"
      fi
      export PATH="$HOME_DIR/.local/bin:$PATH"
    fi
  fi
  command -v uv >/dev/null 2>&1 || die "uv is unavailable after bootstrap"
  info "Installing/updating Hermes Agent via official installer"
  local installer_log="$HERMES_HOME/logs/hermes-installer.log"
  : > "$installer_log"
  chmod 600 "$installer_log"
  if ! retry 3 bash -c "curl -fsSL '$INSTALLER_URL' | bash -s -- --skip-setup" >"$installer_log" 2>&1; then
    sed -E 's/[0-9]{6,12}:[A-Za-z0-9_-]{20,}/[TELEGRAM_TOKEN_MASKED]/g; s/sk-[A-Za-z0-9_-]{20,}/[OPENAI_KEY_MASKED]/g' "$installer_log" | tail -160 >&2 || true
    die "Hermes installer did not complete"
  fi
  info "Hermes installer completed"
  hash -r || true
  if ! command -v hermes >/dev/null 2>&1; then
    if [ -x "$HOME_DIR/.local/bin/hermes" ]; then
      export PATH="$HOME_DIR/.local/bin:$PATH"
    elif [ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ]; then
      ln -sf "$HERMES_HOME/hermes-agent/venv/bin/hermes" "$HOME_DIR/.local/bin/hermes"
      export PATH="$HOME_DIR/.local/bin:$PATH"
    fi
  fi
  command -v hermes >/dev/null 2>&1 || die "Hermes command is still unavailable after installer"
  info "Running Hermes post-install update"
  timeout 1200 hermes update --yes || die "Hermes post-install update failed"
  install_hermes_command_guard
  hermes --version || true
}

install_hermes_command_guard() {
  local guard_source=""
  local candidate
  for candidate in \
    /mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoSetupHermes/hermes-command-guard.sh \
    /mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoBackRes/hermes-command-guard.sh; do
    if [ -f "$candidate" ]; then
      guard_source="$candidate"
      break
    fi
  done
  [ -n "$guard_source" ] || die "Hermes command guard source was not found"
  [ -x "$HERMES_HOME/hermes-agent/venv/bin/hermes" ] || die "Real Hermes binary missing before installing command guard"
  mkdir -p "$HOME_DIR/.local/bin"
  rm -f "$HOME_DIR/.local/bin/hermes"
  install -m 0755 "$guard_source" "$HOME_DIR/.local/bin/hermes"
}

write_hermes_config() {
  local codex_model="$1"
  if [ -f "$HERMES_CONFIG" ]; then
    backup_file "$HERMES_CONFIG"
  fi
  cat > "$HERMES_CONFIG" <<YAML
model:
  provider: "openai-codex"
  default: "$codex_model"

terminal:
  backend: "local"
  cwd: "$HOME_DIR"
  timeout: 180
  docker_mount_cwd_to_workspace: false
  lifetime_seconds: 300

unauthorized_dm_behavior: "ignore"
YAML
  chmod 600 "$HERMES_CONFIG"
  info "Wrote Hermes config with provider=openai-codex model=$codex_model"
}

upsert_hermes_env() {
  # Do not back up .env: it contains the Telegram bot token.
  prune_hermes_env_backups
  local allowed_users
  allowed_users="$(detect_telegram_allowed_users || true)"
  TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" \
  TELEGRAM_ALLOWED_USERS_VALUE="$allowed_users" \
  HERMES_ENV="$HERMES_ENV" \
  HOME_DIR="$HOME_DIR" \
  python3 - <<'PY'
import os
from pathlib import Path

env_path = Path(os.environ["HERMES_ENV"])
env_path.parent.mkdir(parents=True, exist_ok=True)
updates = {
    "TELEGRAM_BOT_TOKEN": os.environ["TELEGRAM_BOT_TOKEN"],
}
allowed = os.environ.get("TELEGRAM_ALLOWED_USERS_VALUE", "").strip()
if allowed:
    updates["TELEGRAM_ALLOWED_USERS"] = allowed
remove = {"GATEWAY_ALLOW_ALL_USERS", "TELEGRAM_ALLOW_ALL_USERS", "MESSAGING_CWD"}
existing = []
if env_path.exists():
    existing = env_path.read_text(encoding="utf-8", errors="replace").splitlines()
kept = []
for line in existing:
    key = line.split("=", 1)[0].strip() if "=" in line else ""
    if key in updates or key in remove:
        continue
    kept.append(line)
for key, value in updates.items():
    kept.append(f"{key}={value}")
env_path.write_text("\n".join(kept).rstrip() + "\n", encoding="utf-8")
os.chmod(env_path, 0o600)
PY
  info "Updated Hermes .env without enabling allow-all access"
  if [ -n "$allowed_users" ]; then
    info "Configured TELEGRAM_ALLOWED_USERS from existing OpenClaw route registry"
  else
    info "No Telegram allowlist found; Hermes DM pairing remains enabled"
  fi
}

import_codex_to_hermes_auth() {
  local hermes_python="$HERMES_HOME/hermes-agent/venv/bin/python"
  [ -x "$hermes_python" ] || die "Hermes venv python not found at $hermes_python"
  backup_file "$HERMES_HOME/auth.json"
  CODEX_HOME="$CODEX_HOME" "$hermes_python" - <<'PY'
from hermes_cli.auth import _import_codex_cli_tokens, _save_codex_tokens

tokens = _import_codex_cli_tokens()
if not tokens:
    raise SystemExit("Could not import non-expired Codex CLI tokens from ~/.codex/auth.json")
_save_codex_tokens(tokens)
print("Imported Codex CLI tokens into Hermes auth store")
PY
  chmod 600 "$HERMES_HOME/auth.json"
  "$hermes_python" - <<'PY'
from hermes_cli.auth import resolve_codex_runtime_credentials
creds = resolve_codex_runtime_credentials(refresh_if_expiring=False)
if not creds.get("api_key"):
    raise SystemExit("Hermes Codex auth import did not yield a runtime token")
print(f"Hermes Codex auth ready: provider={creds.get('provider')} source={creds.get('source')}")
PY
}

provider_smoke() {
  local codex_model="$1"
  : > "$SMOKE_LOG"
  chmod 600 "$SMOKE_LOG"
  info "Running OpenAI Codex provider smoke test"
  if timeout 180 hermes -z "Reply with exactly HERMES_OK and no other words." --provider openai-codex --model "$codex_model" >"$SMOKE_LOG" 2>&1; then
    if grep -q "HERMES_OK" "$SMOKE_LOG"; then
      info "OpenAI Codex provider smoke test passed"
      return 0
    fi
  fi
  info "Primary model smoke failed; trying gpt-5.4 fallback"
  if timeout 180 hermes -z "Reply with exactly HERMES_OK and no other words." --provider openai-codex --model "gpt-5.4" >"$SMOKE_LOG" 2>&1; then
    if grep -q "HERMES_OK" "$SMOKE_LOG"; then
      info "OpenAI Codex provider smoke passed with gpt-5.4 fallback"
      return 0
    fi
  fi
  sed -E 's/[0-9]{6,12}:[A-Za-z0-9_-]{20,}/[TELEGRAM_TOKEN_MASKED]/g; s/sk-[A-Za-z0-9_-]{20,}/[OPENAI_KEY_MASKED]/g' "$SMOKE_LOG" | tail -80 >&2 || true
  die "OpenAI Codex provider smoke test failed"
}

start_gateway() {
  : > "$GATEWAY_LOG"
  : > "$GATEWAY_INTERNAL_LOG"
  : > "$ERROR_LOG"
  chmod 600 "$GATEWAY_LOG"
  chmod 600 "$GATEWAY_INTERNAL_LOG" "$ERROR_LOG"
  tmux has-session -t "$TMUX_SESSION" 2>/dev/null && tmux kill-session -t "$TMUX_SESSION" || true
  HERMES_ALLOW_GATEWAY_STOP=1 hermes gateway stop >/dev/null 2>&1 || true
  tmux new-session -d -s "$TMUX_SESSION" "cd '$HOME_DIR' && export PATH='$PATH' && exec hermes gateway run >>'$GATEWAY_LOG' 2>&1"
  info "Started Hermes gateway in tmux session $TMUX_SESSION"
  sleep 5
  if tmux has-session -t "$TMUX_SESSION" 2>/dev/null || gateway_process_running || gateway_status_running; then
    return 0
  fi
  info "tmux gateway launch exited early; retrying with nohup fallback"
  start_gateway_nohup
}

start_gateway_nohup() {
  env PATH="$PATH" nohup bash -lc "cd '$HOME_DIR' && exec hermes gateway run" >>"$GATEWAY_LOG" 2>&1 &
  info "Started Hermes gateway with nohup fallback"
}

gateway_status_running() {
  hermes gateway status >/tmp/hermes-gateway-status-check.txt 2>&1 && grep -q "Gateway is running" /tmp/hermes-gateway-status-check.txt
}

gateway_process_running() {
  pgrep -u "$(id -u)" -f '[h]ermes gateway run' >/dev/null 2>&1
}

tail_gateway_logs() {
  for log in "$GATEWAY_LOG" "$GATEWAY_INTERNAL_LOG" "$ERROR_LOG"; do
    [ -f "$log" ] || continue
    printf '\n--- %s ---\n' "$log" >&2
    sed -E 's/[0-9]{6,12}:[A-Za-z0-9_-]{20,}/[TELEGRAM_TOKEN_MASKED]/g; s/sk-[A-Za-z0-9_-]{20,}/[OPENAI_KEY_MASKED]/g' "$log" | tail -120 >&2 || true
  done
}

gateway_ready_log_seen() {
  grep -Eiq 'telegram.*(connected|polling|started)|gateway.*(running|started|ready)|No user allowlists configured' "$GATEWAY_LOG" "$GATEWAY_INTERNAL_LOG" 2>/dev/null
}

wait_gateway_ready() {
  local i
  local restarted=0
  for i in $(seq 1 90); do
    if gateway_status_running; then
      info "Hermes gateway status reports running"
      return 0
    fi
    if gateway_ready_log_seen && { tmux has-session -t "$TMUX_SESSION" 2>/dev/null || gateway_process_running; }; then
      info "Hermes gateway readiness signal found in log"
      return 0
    fi
    if [ "$i" -ge 6 ] && ! tmux has-session -t "$TMUX_SESSION" 2>/dev/null && ! gateway_process_running; then
      if [ "$restarted" -eq 0 ]; then
        info "Gateway process exited before readiness; retrying once with nohup fallback"
        start_gateway_nohup
        restarted=1
      else
        tail_gateway_logs
        die "Hermes gateway exited before readiness after retry"
      fi
    fi
    sleep 2
  done
  tail_gateway_logs
  die "Hermes gateway did not report readiness within timeout"
}

telegram_chat_probe() {
  local allowed_users
  allowed_users="$(detect_telegram_allowed_users || true)"
  TELEGRAM_BOT_TOKEN="$TELEGRAM_BOT_TOKEN" TELEGRAM_ALLOWED_USERS_VALUE="$allowed_users" python3 - <<'PY'
import json, os, sys, urllib.parse, urllib.request
token = os.environ["TELEGRAM_BOT_TOKEN"]
allowed = [x.strip() for x in os.environ.get("TELEGRAM_ALLOWED_USERS_VALUE", "").split(",") if x.strip()]
base = f"https://api.telegram.org/bot{token}"
if not allowed:
    print("Telegram chat probe: no allowlisted chat_id found; DM the bot once to complete end-to-end reply proof.")
    raise SystemExit(20)
chat_id = allowed[0]
payload = urllib.parse.urlencode({"chat_id": str(chat_id), "text": "Hermes is ready to work. Gateway is online in WSL2 and connected to Telegram."}).encode()
sent = json.load(urllib.request.urlopen(urllib.request.Request(base + "/sendMessage", data=payload), timeout=20))
if not sent.get("ok"):
    raise SystemExit("sendMessage returned ok=false")
print(f"Telegram chat probe: sent setup check to chat_id={chat_id}")
PY
}

final_checks() {
  bash -n "$0"
  command -v hermes >/dev/null 2>&1
  stat -c 'secret_file_mode=%a owner=%U path=%n' "$SECRET_FILE"
  stat -c 'codex_auth_mode=%a owner=%U path=%n' "$CODEX_AUTH"
  stat -c 'hermes_env_mode=%a owner=%U path=%n' "$HERMES_ENV"
  local doctor_log="$HERMES_HOME/logs/doctor.log"
  if hermes doctor --fix >"$doctor_log" 2>&1 || hermes doctor >"$doctor_log" 2>&1; then
    info "Hermes diagnostics completed"
  else
    sed -E 's/[0-9]{6,12}:[A-Za-z0-9_-]{20,}/[TELEGRAM_TOKEN_MASKED]/g; s/sk-[A-Za-z0-9_-]{20,}/[OPENAI_KEY_MASKED]/g' "$doctor_log" | tail -120 >&2 || true
    die "Hermes diagnostics did not complete"
  fi
  hermes gateway status || true
}

print_run_command() {
  cat <<'EOF'

Run this setup now, after Windows reboot, or after reinstalling Ubuntu WSL from PowerShell:
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -ExecutionPolicy Bypass -Command "rws; wsl -d ubuntu -- bash /mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoSetupHermes/a.sh"

Enable it at Windows logon and run it immediately:
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoSetupHermes\enable-windows-startup.ps1" -RunNow
EOF
}

main() {
  info "Starting Hermes WSL setup script version $SCRIPT_VERSION as $(id -un) in $HOME_DIR"
  apt_install
  copy_codex_auth
  local codex_model
  codex_model="$(detect_codex_model)"
  telegram_api_check
  delete_webhook_for_polling
  install_or_update_hermes
  write_hermes_config "$codex_model"
  upsert_hermes_env
  import_codex_to_hermes_auth
  provider_smoke "$codex_model"
  start_gateway
  wait_gateway_ready
  final_checks
  if telegram_chat_probe; then
    info "Telegram outbound chat probe completed"
  else
    info "Telegram end-to-end user reply proof still needs an incoming DM/chat_id"
  fi
  info "Hermes WSL setup completed"
  print_run_command
}

main "$@" 2>&1 | sed -E 's/[0-9]{6,12}:[A-Za-z0-9_-]{20,}/[TELEGRAM_TOKEN_MASKED]/g; s/sk-[A-Za-z0-9_-]{20,}/[OPENAI_KEY_MASKED]/g'
exit "${PIPESTATUS[0]}"
