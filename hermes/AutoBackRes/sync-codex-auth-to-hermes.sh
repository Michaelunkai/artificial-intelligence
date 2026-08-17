#!/usr/bin/env bash
set -Eeuo pipefail

USER_NAME="${HERMES_WSL_USER:-ubuntu}"
HOME_DIR="/home/${USER_NAME}"
WIN_CODEX_HOME="${WIN_CODEX_HOME:-/mnt/c/Users/micha/.codex}"
CODEX_HOME="${CODEX_HOME:-${HOME_DIR}/.codex}"
HERMES_HOME_MAIN="${HERMES_HOME_MAIN:-${HOME_DIR}/.hermes}"
HERMES_PYTHON="${HERMES_PYTHON:-${HERMES_HOME_MAIN}/hermes-agent/venv/bin/python}"
LOG_FILE="${HERMES_CODEX_SYNC_LOG:-${HERMES_HOME_MAIN}/logs/codex-auth-sync.log}"
LOCK_DIR="/tmp/hermes-tray-${USER_NAME}"
LOCK_FILE="${LOCK_DIR}/codex-auth-sync.lock"

ts() { date -Iseconds; }

log() {
  mkdir -p "$(dirname "$LOG_FILE")" "$LOCK_DIR"
  printf '[%s] %s\n' "$(ts)" "$*" | tee -a "$LOG_FILE"
}

run_as_user() {
  if [ "$(id -un)" = "$USER_NAME" ]; then
    "$@"
  else
    sudo -H -u "$USER_NAME" "$@"
  fi
}

ensure_owner() {
  if [ "$(id -u)" -eq 0 ]; then
    chown -R "$USER_NAME:$USER_NAME" "$CODEX_HOME" "$HERMES_HOME_MAIN" "$LOCK_DIR" 2>/dev/null || true
  fi
}

sync_codex_file() {
  local source_auth="${WIN_CODEX_HOME}/auth.json"
  local target_auth="${CODEX_HOME}/auth.json"

  [ -s "$source_auth" ] || { log "ERROR: Windows Codex auth missing: $source_auth"; return 20; }
  [ -x "$HERMES_PYTHON" ] || { log "ERROR: Hermes python missing: $HERMES_PYTHON"; return 21; }

  run_as_user mkdir -p "$CODEX_HOME" "${HERMES_HOME_MAIN}/logs"
  run_as_user "$HERMES_PYTHON" - "$source_auth" "$target_auth" <<'PY'
import base64
import json
import os
import shutil
import sys
import time
from pathlib import Path

source = Path(sys.argv[1])
target = Path(sys.argv[2])

payload = json.loads(source.read_text(encoding="utf-8"))
tokens = payload.get("tokens")
if not isinstance(tokens, dict):
    raise SystemExit("Windows Codex auth has no tokens object")
access = tokens.get("access_token")
refresh = tokens.get("refresh_token")
if not isinstance(access, str) or not access:
    raise SystemExit("Windows Codex auth missing access_token")
if not isinstance(refresh, str) or not refresh:
    raise SystemExit("Windows Codex auth missing refresh_token")

def jwt_exp(token: str) -> int:
    try:
        part = token.split(".")[1]
        part += "=" * ((4 - len(part) % 4) % 4)
        decoded = json.loads(base64.urlsafe_b64decode(part.encode("ascii")))
        return int(decoded.get("exp") or 0)
    except Exception as exc:
        raise SystemExit(f"Cannot decode Codex access token expiry: {exc}")

remaining = jwt_exp(access) - int(time.time())
if remaining < 300:
    raise SystemExit(f"Windows Codex access token is too close to expiry: {remaining}s")

target.parent.mkdir(parents=True, exist_ok=True)
tmp = target.with_name(f"{target.name}.tmp-{os.getpid()}")
tmp.write_text(json.dumps(payload, separators=(",", ":")) + "\n", encoding="utf-8")
os.chmod(tmp, 0o600)
if target.exists():
    old = target.read_text(encoding="utf-8", errors="replace")
    new = tmp.read_text(encoding="utf-8")
    if old == new:
        tmp.unlink()
        print(f"CODEX_AUTH_ALREADY_CURRENT remaining_seconds={remaining}")
        raise SystemExit(0)
    backup = target.with_name(f"{target.name}.bak-hermes-sync-{time.strftime('%Y%m%d-%H%M%S')}")
    shutil.copy2(target, backup)
    os.chmod(backup, 0o600)
tmp.replace(target)
os.chmod(target, 0o600)
print(f"CODEX_AUTH_SYNCED remaining_seconds={remaining}")
PY
}

import_into_hermes() {
  run_as_user env CODEX_HOME="$CODEX_HOME" HERMES_HOME="$HERMES_HOME_MAIN" "$HERMES_PYTHON" - <<'PY'
from hermes_cli.auth import _import_codex_cli_tokens, _save_codex_tokens, resolve_codex_runtime_credentials

tokens = _import_codex_cli_tokens()
if not tokens:
    raise SystemExit("Could not import valid non-expired Codex CLI tokens into Hermes")
_save_codex_tokens(tokens)
creds = resolve_codex_runtime_credentials(refresh_if_expiring=False)
if not creds.get("api_key"):
    raise SystemExit("Hermes Codex auth import did not yield an access token")
print(f"HERMES_CODEX_AUTH_SYNCED source={creds.get('source')}")
PY
}

ensure_fleet_symlinks() {
  local h
  for h in "${HOME_DIR}"/.hermes-*; do
    [ -d "$h" ] || continue
    [ -f "$h/config.yaml" ] || continue
    [ -f "$h/.env" ] || continue
    if [ -L "$h/auth.json" ] && [ "$(readlink "$h/auth.json")" = "${HERMES_HOME_MAIN}/auth.json" ]; then
      continue
    fi
    if [ -e "$h/auth.json" ] && [ ! -L "$h/auth.json" ]; then
      mv "$h/auth.json" "$h/auth.json.bak-hermes-sync-$(date +%Y%m%d-%H%M%S)"
    else
      rm -f "$h/auth.json"
    fi
    ln -s "${HERMES_HOME_MAIN}/auth.json" "$h/auth.json"
    log "Linked $h/auth.json to shared Hermes auth store"
  done
}

main() {
  mkdir -p "$LOCK_DIR"
  ensure_owner
  exec 8>"$LOCK_FILE"
  if ! flock -n 8; then
    log "Codex auth sync already running; skipped overlap"
    exit 0
  fi
  local stamp_file="${LOCK_DIR}/codex-auth-sync.last"
  local now last ttl
  now="$(date +%s)"
  ttl="${HERMES_CODEX_SYNC_MIN_INTERVAL_SECONDS:-21600}"
  last="$(cat "$stamp_file" 2>/dev/null || echo 0)"
  if [ "$ttl" -gt 0 ] && [ $((now - ${last:-0})) -lt "$ttl" ]; then
    # Keep sync functionality enabled, but avoid repeated tray/resume polling when the auth is already fresh.
    exit 0
  fi
  sync_codex_file | while IFS= read -r line; do log "$line"; done
  import_into_hermes | while IFS= read -r line; do log "$line"; done
  ensure_fleet_symlinks
  ensure_owner
  printf '%s\n' "$now" >"$stamp_file"
  log "Codex auth sync complete for Hermes fleet"
}

main "$@"
