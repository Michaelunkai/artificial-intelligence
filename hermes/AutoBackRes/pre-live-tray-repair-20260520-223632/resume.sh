#!/usr/bin/env bash
set -Eeuo pipefail

USER_NAME="${HERMES_WSL_USER:-ubuntu}"
HOME_DIR="/home/${USER_NAME}"
HERMES_BIN="${HOME_DIR}/.local/bin/hermes"
HERMES_VENV_BIN="${HOME_DIR}/.hermes/hermes-agent/venv/bin/hermes"
HERMES_GUARD_SOURCE="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoBackRes/hermes-command-guard.sh"
HERMES_CODEX_SYNC_SCRIPT="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoBackRes/sync-codex-auth-to-hermes.sh"
HERMES_PATH="${HOME_DIR}/.local/bin:${HOME_DIR}/.hermes/node/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/snap/bin"
HERMES_RUNTIME_EXPORTS="HOME='$HOME_DIR' XDG_CACHE_HOME='$HOME_DIR/.cache' UV_CACHE_DIR='$HOME_DIR/.cache/uv'"
# Allows the local tmux wrapper to distinguish the tray/root supervisor from
# ordinary Hermes agent tool calls. The root intent checker still rejects any
# process ancestry that comes from a live Hermes gateway/agent.
export HERMES_TRAY_GATEWAY_ADMIN=1
FLEET_LOG_DIR="${HOME_DIR}/.hermes/logs"
RESUME_LOG="${FLEET_LOG_DIR}/resume.log"
CODEX_AUTH="${HOME_DIR}/.codex/auth.json"
RESUME_TMP_DIR="/tmp/hermes-resume-${USER_NAME}-$$"
RESUME_LOCK="/tmp/hermes-tray-${USER_NAME}/resume.lock"

# Future-proof discovery: every Hermes home with config.yaml + .env + TELEGRAM_BOT_TOKEN
# is supervised by the same Windows tray app. Runtime/session/log files remain per-home.
discover_homes() {
  local h
  printf '%s\n' "${HOME_DIR}/.hermes"
  for h in "${HOME_DIR}"/.hermes-*; do
    [ -d "$h" ] || continue
    [ -f "$h/config.yaml" ] || continue
    [ -f "$h/.env" ] || continue
    if grep -q '^TELEGRAM_BOT_TOKEN=' "$h/.env"; then
      printf '%s\n' "$h"
    fi
  done | awk '!seen[$0]++'
}

ensure_required_telegram_fleet_homes() {
  python3 - "$USER_NAME" <<'PY'
import os
import pwd
import re
import sys
from pathlib import Path

user = sys.argv[1]
main_home = Path("/home") / user / ".hermes"
pw = pwd.getpwnam(user)
user_uid = pw.pw_uid
user_gid = pw.pw_gid
required = [
    {"id": "8527881897", "username": "Michaopenclawbot", "home": Path("/home") / user / ".hermes-michaopenclawbot"},
    {"id": "8575060895", "username": "MichaHermes5bot", "home": Path("/home") / user / ".hermes-michahermes5bot"},
]
shared = ["config.yaml", "skills", "scripts", "hooks", "memories", "memory_store.db", "memory_store.db-shm", "memory_store.db-wal", "auth.json", "plugins"]
private_dirs = ["sessions", "logs", "cache", "audio_cache", "cron", "state-snapshots", "tmp", ".runtime"]
token_re = re.compile(r"(8527881897|8575060895):[A-Za-z0-9_-]{20,}")

def env_value(path, key):
    try:
        lines = path.read_text(encoding="utf-8", errors="ignore").splitlines()
    except FileNotFoundError:
        return None
    for raw in lines:
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        if line.startswith("export "):
            line = line[7:].lstrip()
        name, value = line.split("=", 1)
        if name.strip() == key:
            return value.strip().strip('"').strip("'")
    return None

def token_from_env(home):
    token = env_value(home / ".env", "TELEGRAM_BOT_TOKEN")
    if token and token_re.fullmatch(token):
        return token
    return None

def recover_tokens():
    tokens = {}
    for item in required:
        token = token_from_env(item["home"])
        if token:
            tokens[item["id"]] = token
    if len(tokens) == len(required):
        return tokens
    roots = [
        Path("/mnt/c/Users/micha/.codex/sessions/2026/05/13"),
        Path("/mnt/f/backup/obsidion/agents/sessions"),
        Path("/mnt/f/backup/obsidion/errors/tgtray"),
        main_home,
    ]
    allowed_suffixes = {".jsonl", ".json", ".md", ".txt", ".log", ".env", ""}
    for root in roots:
        if not root.exists():
            continue
        try:
            scanned = 0
            for path in root.rglob("*"):
                if len(tokens) == len(required):
                    return tokens
                try:
                    if not path.is_file() or path.suffix.lower() not in allowed_suffixes or path.stat().st_size > 10_000_000:
                        continue
                    scanned += 1
                    if scanned > 5000:
                        break
                    text = path.read_text(encoding="utf-8", errors="ignore")
                except (OSError, UnicodeError):
                    continue
                for match in token_re.finditer(text):
                    tokens.setdefault(match.group(1), match.group(0))
        except OSError:
            continue
    return tokens

def resolved_home(home):
    if home.is_symlink():
        target = os.readlink(home)
        target_path = Path(target)
        if not target_path.is_absolute():
            target_path = home.parent / target_path
        return target_path
    return home

def prepare_required_home(home):
    target = resolved_home(home)
    try:
        target.mkdir(parents=True, exist_ok=True)
        return target
    except OSError as exc:
        if not home.is_symlink():
            raise
        preserved_dir = main_home / "restore-preserved-symlinks"
        preserved_dir.mkdir(parents=True, exist_ok=True)
        preserved = preserved_dir / f"{home.name}.broken-target.symlink"
        index = 1
        while preserved.exists() or preserved.is_symlink():
            preserved = preserved_dir / f"{home.name}.broken-target.{index}.symlink"
            index += 1
        home.rename(preserved)
        (preserved_dir / f"{preserved.name}.target.txt").write_text(f"{target}\n{type(exc).__name__}: {exc}\n", encoding="utf-8")
        home.mkdir(parents=True, exist_ok=True)
        (home / ".runtime").mkdir(parents=True, exist_ok=True)
        (home / ".runtime" / "required-home-repaired-needs-restart").write_text("1\n", encoding="utf-8")
        print(f"REQUIRED_HOME_BROKEN_SYMLINK_PRESERVED={home}:{preserved}")
        return home

def safe_symlink(dst, src):
    if dst.exists() or dst.is_symlink():
        return
    if src.exists() or src.is_symlink():
        dst.symlink_to(src, target_is_directory=src.is_dir())

def write_env(home, token):
    allowed = env_value(main_home / ".env", "TELEGRAM_ALLOWED_USERS") or "716239770"
    test_chat = env_value(main_home / ".env", "TELEGRAM_TEST_CHAT_ID")
    lines = [f"TELEGRAM_BOT_TOKEN={token}", f"TELEGRAM_ALLOWED_USERS={allowed}"]
    if test_chat:
        lines.append(f"TELEGRAM_TEST_CHAT_ID={test_chat}")
    env_path = home / ".env"
    env_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    env_path.chmod(0o600)
    os.chown(env_path, user_uid, user_gid)

def chown_private_home(path):
    os.chown(path, user_uid, user_gid)
    for name in private_dirs:
        item = path / name
        if item.exists() and not item.is_symlink():
            os.chown(item, user_uid, user_gid)

tokens = recover_tokens()
failed = False
for item in required:
    home = item["home"]
    target = prepare_required_home(home)
    token = tokens.get(item["id"])
    if not token:
        print(f"REQUIRED_HOME_TOKEN_MISSING={item['username']}:{item['id']}:{home}")
        failed = True
        continue
    for name in private_dirs:
        (target / name).mkdir(parents=True, exist_ok=True)
    write_env(target, token)
    chown_private_home(target)
    for name in shared:
        safe_symlink(target / name, main_home / name)
    print(f"REQUIRED_HOME_READY={item['username']}:{home}")
if failed:
    raise SystemExit(73)
PY
}

ts() { date -Iseconds; }
log() {
  local line="[$(ts)] $*"
  echo "$line"
  mkdir -p "$FLEET_LOG_DIR"
  printf '%s\n' "$line" >> "$RESUME_LOG"
}

as_ubuntu() {
  if [ "$(id -un)" = "$USER_NAME" ]; then
    env PATH="$HERMES_PATH" HOME="$HOME_DIR" "$@"
  else
    sudo -H -u "$USER_NAME" env PATH="$HERMES_PATH" HOME="$HOME_DIR" "$@"
  fi
}

env_value_home() {
  local h="$1" key="$2"
  python3 - "$h/.env" "$key" <<'PY'
from pathlib import Path
import sys
path = Path(sys.argv[1])
key = sys.argv[2]
prefix = key + "="
try:
    lines = path.read_text(encoding="utf-8", errors="replace").splitlines()
except FileNotFoundError:
    raise SystemExit(0)
for raw in lines:
    line = raw.strip()
    if not line or line.startswith("#") or "=" not in line:
        continue
    if line.startswith("export "):
        line = line[7:].lstrip()
    if not line.startswith(prefix):
        continue
    value = line.split("=", 1)[1].strip()
    if (value.startswith('"') and value.endswith('"')) or (value.startswith("'") and value.endswith("'")):
        value = value[1:-1]
    print(value)
    break
PY
}

ensure_tmp_writable() {
  # The Windows tray or earlier root-run probes can leave root-owned /tmp files
  # that break later normal-user resume checks. Self-heal before any redirects.
  mkdir -p "/tmp/hermes-tray-${USER_NAME}" 2>/dev/null || true
  local patterns=(
    "/tmp/hermes-resume-${USER_NAME}-"*
    "/tmp/hermes-resume-${USER_NAME}.lock"
    "/tmp/hermes-tray-${USER_NAME}"
  )
  if [ "$(id -u)" -eq 0 ]; then
    chown -R "$USER_NAME:$USER_NAME" "${patterns[@]}" 2>/dev/null || true
  elif command -v sudo >/dev/null 2>&1; then
    sudo chown -R "$USER_NAME:$USER_NAME" "${patterns[@]}" 2>/dev/null || true
  fi
}

prepare_resume_tmp() {
  rm -rf "$RESUME_TMP_DIR" 2>/dev/null || true
  mkdir -p "$RESUME_TMP_DIR"
  if [ "$(id -u)" -eq 0 ]; then
    chown "$USER_NAME:$USER_NAME" "$RESUME_TMP_DIR" 2>/dev/null || true
  fi
  chmod 700 "$RESUME_TMP_DIR" 2>/dev/null || true
}

sync_codex_auth_for_fleet() {
  [ -f "$HERMES_CODEX_SYNC_SCRIPT" ] || { log "Codex auth sync script missing: $HERMES_CODEX_SYNC_SCRIPT"; return 0; }
  if as_ubuntu env HERMES_WSL_USER="$USER_NAME" bash "$HERMES_CODEX_SYNC_SCRIPT" >>"$RESUME_LOG" 2>&1; then
    log "Codex auth synced into shared Hermes fleet store"
  else
    log "WARNING: Codex auth sync failed; keeping existing Hermes auth store"
  fi
}

ensure_fleet_auth_permissions() {
  local root_auth="${HOME_DIR}/.hermes/auth.json"
  local root_lock="${HOME_DIR}/.hermes/auth.lock"
  local h

  if [ -e "$root_auth" ]; then
    chown "$USER_NAME:$USER_NAME" "$root_auth" 2>/dev/null || true
    chmod 600 "$root_auth" 2>/dev/null || true
  fi
  if [ -e "$root_lock" ]; then
    chown "$USER_NAME:$USER_NAME" "$root_lock" 2>/dev/null || true
    chmod 600 "$root_lock" 2>/dev/null || true
  fi

  while IFS= read -r h; do
    [ -n "$h" ] || continue
    chown -h "$USER_NAME:$USER_NAME" "$h/auth.json" 2>/dev/null || true
    if [ -e "$h/auth.json" ]; then
      chown "$USER_NAME:$USER_NAME" "$h/auth.json" 2>/dev/null || true
      chmod 600 "$h/auth.json" 2>/dev/null || true
    fi
    if [ -e "$h/auth.lock" ]; then
      chown "$USER_NAME:$USER_NAME" "$h/auth.lock" 2>/dev/null || true
      chmod 600 "$h/auth.lock" 2>/dev/null || true
    fi
    if ! as_ubuntu test -r "$h/auth.json"; then
      log "ERROR: [$h] auth.json is not readable by $USER_NAME after permission repair"
      return 31
    fi
  done < <(discover_homes)
  log "Hermes fleet auth permissions verified for $USER_NAME"
}

ensure_companion_watchdogs() {
  local script="${HOME_DIR}/.hermes/scripts/ensure_telegram_companion_watchdogs.sh"
  local progress_script="${HOME_DIR}/.hermes/scripts/ensure_telegram_progress_watchdog.sh"
  if [ ! -x "$script" ]; then
    log "WARNING: companion watchdog guard missing or not executable: $script"
  else
    ( exec 9>&-; "$script" ) | while IFS= read -r line; do log "$line"; done
  fi
  if [ ! -x "$progress_script" ]; then
    log "WARNING: progress watchdog guard missing or not executable: $progress_script"
  else
    ( exec 9>&-; "$progress_script" ) | while IFS= read -r line; do log "$line"; done
  fi
}

ensure_hermes_agent_runtime() {
  local root="${HOME_DIR}/.hermes/hermes-agent"
  local tag="${HERMES_AGENT_RESTORE_TAG:-v2026.5.7}"
  if [ -x "$root/venv/bin/hermes" ] && [ -f "$root/gateway/run.py" ] && [ -f "$root/hermes_cli/main.py" ]; then
    return 0
  fi
  log "Hermes agent runtime missing or incomplete; recreating $root from official tag $tag"
  rm -rf "$root.tmp-restore"
  mkdir -p "${HOME_DIR}/.hermes"
  chown "$USER_NAME:$USER_NAME" "${HOME_DIR}/.hermes" 2>/dev/null || true
  as_ubuntu git clone --branch "$tag" --depth 1 https://github.com/NousResearch/hermes-agent.git "$root.tmp-restore"
  as_ubuntu python3 -m venv "$root.tmp-restore/venv"
  as_ubuntu "$root.tmp-restore/venv/bin/python" -m pip install --upgrade pip setuptools wheel
  as_ubuntu "$root.tmp-restore/venv/bin/pip" install -e "$root.tmp-restore[messaging,cli,pty,mcp,web,google]"
  rm -rf "$root"
  mv "$root.tmp-restore" "$root"
  chown -R "$USER_NAME:$USER_NAME" "$root" 2>/dev/null || true
  if [ ! -x "$root/venv/bin/hermes" ]; then
    log "ERROR: restored Hermes binary is still missing or not executable: $root/venv/bin/hermes"
    exit 18
  fi
  log "Hermes agent runtime recreated successfully"
}

apply_hermes_agent_local_hardening() {
  local root="${HOME_DIR}/.hermes/hermes-agent"
  [ -d "$root" ] || { log "ERROR: Hermes agent root missing before hardening: $root"; exit 19; }
  as_ubuntu "$root/venv/bin/python" - "$root" <<'PY'
from pathlib import Path
import sys

root = Path(sys.argv[1])

def replace_once(path: Path, old: str, new: str, marker: str) -> None:
    text = path.read_text(encoding="utf-8")
    if marker in text:
        return
    if old not in text:
        raise SystemExit(f"hardening marker and source block missing: {path}:{marker}")
    path.write_text(text.replace(old, new, 1), encoding="utf-8")

run_py = root / "gateway" / "run.py"
replace_once(
    run_py,
    """                if qcmd.get(\"type\") == \"exec\":\n                    exec_cmd = qcmd.get(\"command\", \"\")\n                    if exec_cmd:\n                        try:\n                            proc = await asyncio.create_subprocess_shell(\n                                exec_cmd,\n                                stdout=asyncio.subprocess.PIPE,\n                                stderr=asyncio.subprocess.PIPE,\n                            )\n                            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=30)\n                            output = (stdout or stderr).decode().strip()\n                            return output if output else \"Command returned no output.\"\n                        except asyncio.TimeoutError:\n                            return \"Quick command timed out (30s).\"\n                        except Exception as e:\n                            return f\"Quick command error: {e}\"\n                    else:\n                        return f\"Quick command '/{command}' has no command defined.\"\n                elif qcmd.get(\"type\") == \"alias\":\n""",
    """                if qcmd.get(\"type\") == \"exec\":\n                    exec_cmd = qcmd.get(\"command\", \"\")\n                    if exec_cmd:\n                        if qcmd.get(\"append_args\"):\n                            user_args = event.get_command_args().strip()\n                            if user_args:\n                                exec_cmd = f\"{exec_cmd} {shlex.quote(user_args)}\"\n                        timeout = qcmd.get(\"timeout\", 30)\n                        try:\n                            timeout = max(1, int(timeout))\n                        except (TypeError, ValueError):\n                            timeout = 30\n                        try:\n                            proc = await asyncio.create_subprocess_shell(\n                                exec_cmd,\n                                stdout=asyncio.subprocess.PIPE,\n                                stderr=asyncio.subprocess.PIPE,\n                            )\n                            stdout, stderr = await asyncio.wait_for(proc.communicate(), timeout=timeout)\n                            output = (stdout or stderr).decode().strip()\n                            return output if output else \"Command returned no output.\"\n                        except asyncio.TimeoutError:\n                            return f\"Quick command timed out ({timeout}s).\"\n                        except Exception as e:\n                            return f\"Quick command error: {e}\"\n                    else:\n                        return f\"Quick command '/{command}' has no command defined.\"\n                elif qcmd.get(\"type\") == \"prompt\":\n                    prompt = str(qcmd.get(\"prompt\", \"\")).strip()\n                    if not prompt:\n                        return f\"Quick command '/{command}' has no prompt defined.\"\n                    user_args = event.get_command_args().strip()\n                    if user_args:\n                        event.text = f\"{prompt}\\n\\nUser arguments:\\n{user_args}\"\n                    else:\n                        event.text = prompt\n                    command = None\n                    canonical = None\n                    # Fall through to normal agent handling with the saved\n                    # command contract plus the user's arguments.\n                elif qcmd.get(\"type\") == \"alias\":\n""",
    "elif qcmd.get(\"type\") == \"prompt\":",
)
text = run_py.read_text(encoding="utf-8")
if "Startup auto-resume is disabled; resume-pending sessions will continue on the next real user message." not in text:
    text = text.replace(
        "        window = _auto_continue_freshness_window()\n",
        "        if os.environ.get(\"HERMES_STARTUP_AUTO_RESUME\", \"0\").strip().lower() not in {\n"
        "            \"1\",\n"
        "            \"true\",\n"
        "            \"yes\",\n"
        "            \"on\",\n"
        "        }:\n"
        "            logger.info(\n"
        "                \"Startup auto-resume is disabled; resume-pending sessions will continue on the next real user message.\"\n"
        "            )\n"
        "            return 0\n\n"
        "        window = _auto_continue_freshness_window()\n",
        1,
    )
    run_py.write_text(text, encoding="utf-8")
    text = run_py.read_text(encoding="utf-8")
if "Dropped empty internal gateway event" not in text:
    text = text.replace(
        "        if source.user_id is None:\n",
        "        if is_internal:\n"
        "            if not (event.text or \"\").strip():\n"
        "                logger.info(\n"
        "                    \"Dropped empty internal gateway event: platform=%s chat=%s\",\n"
        "                    source.platform.value if source.platform else \"unknown\",\n"
        "                    source.chat_id or \"unknown\",\n"
        "                )\n"
        "                return None\n"
        "        elif source.user_id is None:\n",
        1,
    )
    run_py.write_text(text, encoding="utf-8")
    text = run_py.read_text(encoding="utf-8")
if "checkpoint_resume_is_fresh" not in text:
    text = text.replace(
        "        checkpoint = self._read_session_checkpoint(session_key)\n"
        "        should_add_checkpoint = (\n"
        "            checkpoint is not None\n"
        "            and (\n"
        "                self._is_continue_request_text(message_text)\n"
        "                or bool(getattr(session_entry, \"resume_pending\", False))\n"
        "            )\n"
        "        )\n",
        "        checkpoint = self._read_session_checkpoint(session_key)\n"
        "        checkpoint_resume_is_fresh = _is_fresh_gateway_interruption(\n"
        "            _last_transcript_timestamp(history),\n"
        "            window_secs=_auto_continue_freshness_window(),\n"
        "        )\n"
        "        should_add_checkpoint = (\n"
        "            checkpoint is not None\n"
        "            and (\n"
        "                self._is_continue_request_text(message_text)\n"
        "                or (\n"
        "                    bool(getattr(session_entry, \"resume_pending\", False))\n"
        "                    and checkpoint_resume_is_fresh\n"
        "                )\n"
        "            )\n"
        "        )\n",
        1,
    )
    run_py.write_text(text, encoding="utf-8")
    text = run_py.read_text(encoding="utf-8")
if 'queued this message and will answer it next' not in text:
    text = text.replace(
        '            if self._busy_input_mode == "queue":\n                logger.debug("PRIORITY queue follow-up for session %s", _quick_key)\n                self._queue_or_replace_pending_event(_quick_key, event)\n                return None\n',
        '            if self._busy_input_mode == "queue":\n                logger.debug("PRIORITY queue follow-up for session %s", _quick_key)\n                self._queue_or_replace_pending_event(_quick_key, event)\n                return "⏳ I’m still working on the previous request — I queued this message and will answer it next. Send /stop only if you want to manually stop the running task."\n',
        1,
    )
    run_py.write_text(text, encoding="utf-8")
    text = run_py.read_text(encoding="utf-8")
if "qcmd.get(\"append_args\")" not in text:
    text = text.replace(
        "                    if exec_cmd:\n                        timeout = qcmd.get(\"timeout\", 30)\n",
        "                    if exec_cmd:\n                        if qcmd.get(\"append_args\"):\n                            user_args = event.get_command_args().strip()\n                            if user_args:\n                                exec_cmd = f\"{exec_cmd} {shlex.quote(user_args)}\"\n                        timeout = qcmd.get(\"timeout\", 30)\n",
        1,
    )
    run_py.write_text(text, encoding="utf-8")
    text = run_py.read_text(encoding="utf-8")
if "supported: 'exec', 'alias', 'prompt'" not in text:
    text = text.replace(
        "supported: 'exec', 'alias').",
        "supported: 'exec', 'alias', 'prompt').",
        1,
    )
    run_py.write_text(text, encoding="utf-8")

status_py = root / "gateway" / "status.py"
text = status_py.read_text(encoding="utf-8")
if "platform_extra: Any = _UNSET" not in text:
    text = text.replace(
        "    error_message: Any = _UNSET,\n) -> None:\n",
        "    error_message: Any = _UNSET,\n    platform_extra: Any = _UNSET,\n) -> None:\n",
        1,
    )
    text = text.replace(
        "        if error_message is not _UNSET:\n            platform_payload[\"error_message\"] = error_message\n        platform_payload[\"updated_at\"] = _utc_now_iso()\n",
        "        if error_message is not _UNSET:\n            platform_payload[\"error_message\"] = error_message\n        if isinstance(platform_extra, dict):\n            platform_payload.update(platform_extra)\n        platform_payload[\"updated_at\"] = _utc_now_iso()\n",
        1,
    )
if "path.chmod(0o600)" not in text:
    text = text.replace(
        "def _write_json_file(path: Path, payload: dict[str, Any]) -> None:\n    atomic_json_write(path, payload, indent=None, separators=(\",\", \":\"))\n",
        "def _write_json_file(path: Path, payload: dict[str, Any]) -> None:\n    atomic_json_write(path, payload, indent=None, separators=(\",\", \":\"))\n    try:\n        path.chmod(0o600)\n    except OSError:\n        pass\n",
        1,
    )
status_py.write_text(text, encoding="utf-8")

commands_py = root / "hermes_cli" / "commands.py"
text = commands_py.read_text(encoding="utf-8")
if "User quick commands are the commands this installation relies on most" not in text:
    text = text.replace(
        "    core_commands = list(telegram_bot_commands())\n    reserved_names = {n for n, _ in core_commands}\n    all_commands = list(core_commands)\n",
        "    quick_commands: list[tuple[str, str]] = []\n    try:\n        from hermes_cli.config import read_raw_config\n        cfg = read_raw_config()\n        raw_quick = cfg.get(\"quick_commands\", {}) if isinstance(cfg, dict) else {}\n        if isinstance(raw_quick, Mapping):\n            for raw_name, meta in raw_quick.items():\n                if not isinstance(raw_name, str) or not isinstance(meta, Mapping):\n                    continue\n                tg_name = _sanitize_telegram_name(raw_name)\n                if not tg_name:\n                    continue\n                desc = str(meta.get(\"description\") or f\"Run /{raw_name}\")\n                if len(desc) > 40:\n                    desc = desc[:37] + \"...\"\n                quick_commands.append((tg_name, desc))\n    except Exception:\n        quick_commands = []\n\n    # User quick commands are the commands this installation relies on most\n    # in Telegram, so keep them ahead of generic core/skill overflow.\n    quick_commands = _clamp_command_names(quick_commands, set())\n    core_commands = list(telegram_bot_commands())\n    reserved_for_quick = {n for n, _ in quick_commands}\n    core_commands = [(n, d) for n, d in core_commands if n not in reserved_for_quick]\n    all_commands = list(quick_commands)\n    reserved_names = {n for n, _ in core_commands}\n    reserved_names.update(n for n, _ in quick_commands)\n    all_commands.extend(core_commands)\n",
        1,
    )
    commands_py.write_text(text, encoding="utf-8")

telegram_py = root / "gateway" / "platforms" / "telegram.py"
text = telegram_py.read_text(encoding="utf-8")
if "from datetime import datetime, timezone" not in text:
    text = text.replace("import re\nfrom typing", "import re\nfrom datetime import datetime, timezone\nfrom typing", 1)
if "self._polling_heartbeat_task" not in text:
    text = text.replace(
        "        self._polling_error_task: Optional[asyncio.Task] = None\n",
        "        self._polling_error_task: Optional[asyncio.Task] = None\n        self._polling_heartbeat_task: Optional[asyncio.Task] = None\n",
        1,
    )
if "def _write_polling_heartbeat" not in text:
    text = text.replace(
        "    def _coerce_bool_extra(self, key: str, default: bool = False) -> bool:\n",
        "    def _write_polling_heartbeat(self, *, running: bool, error: Optional[str] = None) -> None:\n        try:\n            from gateway.status import write_runtime_status\n            write_runtime_status(\n                platform=self.platform.value,\n                platform_state=\"connected\" if running else \"disconnected\",\n                error_message=error,\n                platform_extra={\n                    \"mode\": \"webhook\" if self._webhook_mode else \"polling\",\n                    \"polling_running\": bool(running),\n                    \"polling_heartbeat_at\": datetime.now(timezone.utc).isoformat(),\n                    \"polling_heartbeat_error\": error,\n                },\n            )\n        except Exception as exc:\n            logger.debug(\"[%s] polling heartbeat status write failed: %s\", self.name, exc)\n\n    async def _polling_heartbeat_loop(self) -> None:\n        while True:\n            try:\n                running = bool(\n                    self._app\n                    and self._app.updater\n                    and getattr(self._app.updater, \"running\", False)\n                )\n                self._write_polling_heartbeat(running=running)\n            except asyncio.CancelledError:\n                raise\n            except Exception as exc:\n                self._write_polling_heartbeat(running=False, error=str(exc))\n            await asyncio.sleep(float(os.getenv(\"HERMES_TELEGRAM_POLLING_HEARTBEAT_SECONDS\", \"30\")))\n\n    def _coerce_bool_extra(self, key: str, default: bool = False) -> bool:\n",
        1,
    )
if "BotCommandScopeAllPrivateChats" not in text:
    text = text.replace(
        "                from telegram import BotCommand\n",
        "                from telegram import (\n                    BotCommand,\n                    BotCommandScopeAllGroupChats,\n                    BotCommandScopeAllPrivateChats,\n                    BotCommandScopeDefault,\n                )\n",
        1,
    )
    text = text.replace(
        "                await self._bot.set_my_commands([\n                    BotCommand(name, desc) for name, desc in menu_commands\n                ])\n",
        "                bot_commands = [BotCommand(name, desc) for name, desc in menu_commands]\n                scopes = (\n                    BotCommandScopeDefault(),\n                    BotCommandScopeAllPrivateChats(),\n                    BotCommandScopeAllGroupChats(),\n                )\n                for scope in scopes:\n                    await self._bot.set_my_commands(bot_commands, scope=scope)\n",
        1,
    )
if "self._write_polling_heartbeat(running=True)" not in text:
    text = text.replace(
        "                await self._app.updater.start_polling(\n                    allowed_updates=Update.ALL_TYPES,\n                    drop_pending_updates=True,\n                    error_callback=_polling_error_callback,\n                )\n",
        "                await self._app.updater.start_polling(\n                    allowed_updates=Update.ALL_TYPES,\n                    drop_pending_updates=True,\n                    error_callback=_polling_error_callback,\n                )\n                self._write_polling_heartbeat(running=True)\n                if self._polling_heartbeat_task and not self._polling_heartbeat_task.done():\n                    self._polling_heartbeat_task.cancel()\n                self._polling_heartbeat_task = asyncio.create_task(self._polling_heartbeat_loop())\n",
        1,
    )
if "self._polling_heartbeat_task = None" not in text:
    text = text.replace(
        "    async def disconnect(self) -> None:\n        \"\"\"Stop polling/webhook, cancel pending album flushes, and disconnect.\"\"\"\n",
        "    async def disconnect(self) -> None:\n        \"\"\"Stop polling/webhook, cancel pending album flushes, and disconnect.\"\"\"\n        if self._polling_heartbeat_task and not self._polling_heartbeat_task.done():\n            self._polling_heartbeat_task.cancel()\n            try:\n                await self._polling_heartbeat_task\n            except asyncio.CancelledError:\n                pass\n        self._polling_heartbeat_task = None\n",
        1,
    )
telegram_py.write_text(text, encoding="utf-8")

print("HERMES_AGENT_LOCAL_HARDENING_OK=1")
PY
}

install_hermes_command_guard() {
  if [ ! -x "$HERMES_VENV_BIN" ]; then log "ERROR: real Hermes binary missing: $HERMES_VENV_BIN"; exit 16; fi
  if [ ! -f "$HERMES_GUARD_SOURCE" ]; then log "ERROR: Hermes command guard source missing: $HERMES_GUARD_SOURCE"; exit 17; fi
  mkdir -p "${HOME_DIR}/.local/bin"
  rm -f "$HERMES_BIN"
  install -o "$USER_NAME" -g "$USER_NAME" -m 0755 "$HERMES_GUARD_SOURCE" "$HERMES_BIN"
}

session_for_home() {
  local h="$1" base
  if [ "$h" = "${HOME_DIR}/.hermes" ]; then echo "hermes-gateway"; return; fi
  base="$(basename "$h")"
  echo "hermes-${base#.hermes-}"
}

home_process_pids() {
  local h="$1"
  python3 - "$USER_NAME" "$HOME_DIR" "$h" <<'PY'
import os, pwd, sys
user, home_dir, target_home = sys.argv[1:4]
try:
    target_uid = pwd.getpwnam(user).pw_uid
except KeyError:
    raise SystemExit(0)

def is_gateway_argv(argv):
    # Match the actual gateway process argv only, not shell/tool commands that merely contain the text.
    for i in range(len(argv) - 2):
        exe = argv[i]
        if exe.endswith('/hermes') and argv[i + 1:i + 3] == ['gateway', 'run']:
            return True
    for i in range(len(argv) - 3):
        if argv[i].endswith('/python') or argv[i].endswith('/python3'):
            if argv[i + 1:i + 4] == ['-m', 'hermes_cli.main', 'gateway'] and len(argv) > i + 4 and argv[i + 4] == 'run':
                return True
    for i in range(len(argv) - 2):
        if argv[i].endswith('/hermes_cli/main.py') and argv[i + 1:i + 3] == ['gateway', 'run']:
            return True
    return False

for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    pid = int(name)
    proc = f'/proc/{name}'
    try:
        st = os.stat(proc)
        if st.st_uid != target_uid:
            continue
        raw_cmd = open(f'{proc}/cmdline','rb').read().split(b'\0')
        argv = [x.decode('utf-8','ignore') for x in raw_cmd if x]
        if not is_gateway_argv(argv):
            continue
        env_items = open(f'{proc}/environ','rb').read().split(b'\0')
        env = {}
        for item in env_items:
            if b'=' in item:
                k, v = item.split(b'=', 1)
                env[k.decode('utf-8','ignore')] = v.decode('utf-8','ignore')
    except Exception:
        continue
    env_home = env.get('HERMES_HOME')
    if env_home == target_home or (target_home == f'{home_dir}/.hermes' and not env_home):
        print(pid)
PY
}

tmux_running() {
  local session="$1"
  as_ubuntu tmux has-session -t "=$session" >/dev/null 2>&1
}

home_process_running() {
  local h="$1"
  local -a pids
  mapfile -t pids < <(home_process_pids "$h")
  [ "${#pids[@]}" -eq 1 ]
}

home_process_age_seconds() {
  local h="$1" pid process_started now_epoch
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    process_started="$(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    if [ "$process_started" -gt 0 ]; then echo $((now_epoch - process_started)); return 0; fi
  done < <(home_process_pids "$h")
  echo 999999
}

home_process_start_epoch() {
  local h="$1" pid process_started
  while IFS= read -r pid; do
    [ -n "$pid" ] || continue
    process_started="$(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)"
    if [ "$process_started" -gt 0 ]; then echo "$process_started"; return 0; fi
  done < <(home_process_pids "$h")
  echo 0
}

home_config_epoch() {
  local h="$1" cfg="$h/config.yaml"
  if [ -e "$cfg" ]; then stat -Lc %Y "$cfg" 2>/dev/null || echo 0; else echo 0; fi
}

home_config_hash() {
  local h="$1" cfg="$h/config.yaml"
  if [ -e "$cfg" ]; then sha256sum "$cfg" 2>/dev/null | awk '{print $1}' || true; fi
}

home_config_loaded_ok() {
  local h="$1" current loaded_file loaded
  current="$(home_config_hash "$h")"
  loaded_file="$h/.runtime/loaded-config.sha256"
  [ -n "$current" ] || return 1
  [ -s "$loaded_file" ] || return 1
  loaded="$(head -n 1 "$loaded_file" 2>/dev/null | tr -d '[:space:]')"
  [ "$current" = "$loaded" ]
}

mark_loaded_config_home() {
  local h="$1" hash runtime_dir
  hash="$(home_config_hash "$h")"
  [ -n "$hash" ] || return 1
  runtime_dir="$h/.runtime"
  mkdir -p "$runtime_dir"
  printf '%s\n' "$hash" >"$runtime_dir/loaded-config.sha256"
  chown -R "$USER_NAME:$USER_NAME" "$runtime_dir" 2>/dev/null || true
}

resume_markers_present_home() {
  local h="$1"
  python3 - "$h/sessions/sessions.json" <<'PY'
import json, sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    raise SystemExit(1)
items = data.values() if isinstance(data, dict) else data
for entry in items:
    if isinstance(entry, dict) and entry.get("resume_pending") and entry.get("resume_reason") in {
        "restart_timeout",
        "shutdown_timeout",
        "restart_interrupted",
    }:
        raise SystemExit(0)
raise SystemExit(1)
PY
}

clear_resume_markers_home() {
  local h="$1" reason="$2"
  python3 - "$h/sessions/sessions.json" "$reason" <<'PY'
import datetime as dt
import json
import os
import shutil
import sys

path, reason = sys.argv[1], sys.argv[2]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except FileNotFoundError:
    raise SystemExit(0)

restart_reasons = {"restart_timeout", "shutdown_timeout", "restart_interrupted"}
items = data.values() if isinstance(data, dict) else data
changed = 0
stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
for entry in items:
    if not isinstance(entry, dict):
        continue
    if entry.get("resume_pending") and entry.get("resume_reason") in restart_reasons:
        entry["resume_pending"] = False
        entry["suspended"] = False
        entry["resume_reason"] = f"cleared_by_tray_resume_{reason}_{stamp}"
        entry["last_resume_cleared_at"] = dt.datetime.now().isoformat()
        changed += 1

if changed:
    backup = f"{path}.bak-clear-resume-{stamp}"
    shutil.copy2(path, backup)
    tmp = f"{path}.tmp-clear-resume-{os.getpid()}"
    with open(tmp, "w", encoding="utf-8") as f:
        json.dump(data, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, path)
print(f"RESUME_MARKERS_CLEARED={changed}")
PY
  chown -R "$USER_NAME:$USER_NAME" "$h/sessions" "$h/.runtime" 2>/dev/null || true
  chmod 600 "$h/gateway.pid" "$h/gateway.lock" 2>/dev/null || true
}

gateway_work_ok() {
  local h="$1" out="$2" gateway_log="$h/logs/gateway.log" run_log="$h/logs/gateway-run.log"
  HERMES_PROCESS_AGE_SECONDS="$(home_process_age_seconds "$h")" python3 - "$gateway_log" "$run_log" >>"$out" <<'PY'
import datetime as dt, os, re, sys, time
paths=sys.argv[1:]
stamp=re.compile(r"^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})")
inbound=re.compile(r"inbound message: platform=telegram .* chat=(\S+)")
ready=re.compile(r"response ready: platform=telegram chat=(\S+)")
start=re.compile(r"Starting Hermes Gateway")
latest_in=latest_ready=latest_start=None
now=time.time()
stale_after=int(os.environ.get('HERMES_TRAY_STALE_UNANSWERED_SECONDS','300'))
strict_stale_reconnect=os.environ.get('HERMES_TRAY_RECONNECT_STALE_UNANSWERED','0').lower() in ('1','true','yes','on')
startup_grace=int(os.environ.get('HERMES_TRAY_STARTUP_GRACE_SECONDS','120'))
process_age=int(os.environ.get('HERMES_PROCESS_AGE_SECONDS','999999'))
def ts(line):
    m=stamp.match(line)
    return dt.datetime.fromisoformat(m.group(1)+'T'+m.group(2)).timestamp() if m else None
for path in paths:
    try:
        for line in open(path, encoding='utf-8', errors='replace'):
            t=ts(line)
            if t is None: continue
            if start.search(line): latest_start=t
            if inbound.search(line): latest_in=t
            if ready.search(line): latest_ready=t
    except FileNotFoundError:
        pass
if latest_in and (latest_ready is None or latest_ready < latest_in):
    age=int(now-latest_in)
    if process_age < startup_grace:
        print('WORK_ACTIVE=startup_grace_after_reconnect process_age_seconds=%s startup_grace_seconds=%s' % (process_age, startup_grace))
        raise SystemExit(0)
    if latest_start and latest_start > latest_in:
        print('WORK_INTERRUPTED_BY_PRIOR_RESTART=1 age_seconds=%s' % age)
        raise SystemExit(0)
    if age > stale_after:
        if strict_stale_reconnect:
            print('WORK_STALE=long_running_unanswered_work_reconnect_required age_seconds=%s threshold_seconds=%s strict_reconnect=1' % (age, stale_after))
            raise SystemExit(63)
        print('WORK_ACTIVE=long_running_unanswered_work_no_reconnect age_seconds=%s threshold_seconds=%s' % (age, stale_after))
        raise SystemExit(0)
    print('WORK_ACTIVE=active_unanswered_work age_seconds=%s threshold_seconds=%s' % (age, stale_after))
else:
    print('WORK_OK=1')
PY
  local rc=$?
  echo "WORK_CHECK_RC=$rc" >>"$out"
  return "$rc"
}

repair_duplicate_processes_home() {
  local h="$1" pid keep state_pid session tmux_pid
  local -a pids
  mapfile -t pids < <(home_process_pids "$h")
  [ "${#pids[@]}" -gt 1 ] || return 1
  if [ "${HERMES_FORCE_GATEWAY_RESTART_DURING_WORK:-}" != "manual-root-danger" ]; then
    log "[$h] Duplicate exact-home gateways found (${pids[*]}), but automatic duplicate termination is disabled to avoid interrupting Telegram work"
    return 1
  fi
  session="$(session_for_home "$h")"
  state_pid="$(python3 - "$h/gateway_state.json" <<'PY'
import json, sys
try:
    print(json.load(open(sys.argv[1], encoding="utf-8")).get("pid") or "")
except Exception:
    print("")
PY
)"
  tmux_pid="$(as_ubuntu tmux list-panes -t "=$session" -F '#{pane_pid}' 2>/dev/null | head -1 || true)"
  keep=""
  # Prefer the exact tmux-supervised pane over stale runtime metadata.  A manual
  # `python -m hermes_cli.main gateway run --replace` can keep updating
  # gateway_state.json while the tray has already recreated the authoritative
  # tmux gateway; keeping the state PID would kill the tray-controlled process
  # and leave future sessions outside HermesTray supervision.
  if [ -n "$tmux_pid" ] && printf '%s\n' "${pids[@]}" | grep -Fxq "$tmux_pid"; then
    keep="$tmux_pid"
  elif [ -n "$state_pid" ] && printf '%s\n' "${pids[@]}" | grep -Fxq "$state_pid"; then
    keep="$state_pid"
  else
    log "[$h] Duplicate exact-home gateways found (${pids[*]}), but no state/tmux-supervised healthy gateway could be identified; refusing automatic duplicate termination"
    return 1
  fi
  log "[$h] Duplicate exact-home gateways found (${pids[*]}); keeping pid=$keep and terminating only extras"
  for pid in "${pids[@]}"; do
    [ "$pid" != "$keep" ] || continue
    kill "$pid" 2>/dev/null || true
    log "[$h] Terminated duplicate gateway pid=$pid; kept live pid=$keep"
  done
  sleep 2
  mapfile -t pids < <(home_process_pids "$h")
  for pid in "${pids[@]}"; do
    [ "$pid" != "$keep" ] || continue
    kill -9 "$pid" 2>/dev/null || true
    log "[$h] Killed stubborn duplicate gateway pid=$pid; kept live pid=$keep"
  done
  return 0
}

manual_gateway_stop_requested() {
  [ "${HERMES_ALLOW_GATEWAY_STOP:-}" = "manual-intent" ] && /usr/local/sbin/hermes-check-manual-gateway-intent >/dev/null 2>&1
}

gateway_has_active_work_home() {
  local h="$1" out="$RESUME_TMP_DIR/active-work-$(basename "$h").txt"
  : >"$out"
  gateway_work_ok "$h" "$out" || true
  grep -Eq '^(WORK_ACTIVE=|WORK_INTERRUPTED_BY_PRIOR_RESTART=)' "$out"
}

status_ok() {
  local h="$1" session out tmux_ok=1 process_ok=1 work_ok=0 config_ok=1 runtime_ok=1 process_epoch config_epoch
  local -a pids
  session="$(session_for_home "$h")"
  out="$RESUME_TMP_DIR/status-$(basename "$h").txt"
  {
    echo "HERMES_HOME=$h"
    if tmux_running "$session"; then echo "TMUX_OK=$session"; tmux_ok=0; else echo "TMUX_BAD=$session"; fi
    mapfile -t pids < <(home_process_pids "$h")
    echo "PROCESS_COUNT=${#pids[@]} pids=${pids[*]:-none}"
    if [ "${#pids[@]}" -eq 1 ]; then echo "PROCESS_OK=exact_home"; process_ok=0; else echo "PROCESS_BAD=duplicate_or_missing_exact_home"; fi
    process_epoch="$(home_process_start_epoch "$h")"
    config_epoch="$(home_config_epoch "$h")"
    echo "PROCESS_START_EPOCH=$process_epoch"
    echo "CONFIG_EPOCH=$config_epoch"
    if home_config_loaded_ok "$h" || { [ "$process_epoch" -gt 0 ] && [ "$config_epoch" -le "$process_epoch" ]; }; then
      echo "CONFIG_FRESH_OK=1"
      config_ok=0
    else
      echo "CONFIG_PENDING_RELOAD=1"
      # A shared config write does not mean the live Telegram poller is unhealthy.
      # Treat it as a deferred reload by default so the tray/watchdog never kills
      # active or otherwise healthy sessions just to pick up config changes.
      echo "CONFIG_RELOAD_DEFERRED=active_gateway_not_restarted"
      if [ "${HERMES_TRAY_STRICT_CONFIG_RELOAD:-0}" = "1" ]; then
        echo "CONFIG_RELOAD_REQUIRED=1"
      else
        config_ok=0
      fi
    fi
  } >"$out"
  if [ "${#pids[@]}" -eq 1 ]; then
    if python3 - "$h/gateway_state.json" "${pids[0]}" >>"$out" <<'PY'
import datetime as dt
import json
import os
import sys
from pathlib import Path

path = Path(sys.argv[1])
pid = int(sys.argv[2])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"RUNTIME_BAD=state_unreadable:{exc}")
    raise SystemExit(1)

state_pid = data.get("pid")
gateway_state = data.get("gateway_state")
telegram = (data.get("platforms") or {}).get("telegram", {})
telegram_state = telegram.get("state")
heartbeat_at = telegram.get("polling_heartbeat_at")
print(f"RUNTIME_STATE=pid:{pid} state_pid:{state_pid} gateway:{gateway_state} telegram:{telegram_state}")
if state_pid != pid or gateway_state != "running" or telegram_state != "connected":
    print("RUNTIME_BAD=metadata_mismatch")
    raise SystemExit(1)
if heartbeat_at:
    try:
        heartbeat = dt.datetime.fromisoformat(str(heartbeat_at).replace("Z", "+00:00"))
        if heartbeat.tzinfo is None:
            heartbeat = heartbeat.replace(tzinfo=dt.timezone.utc)
        age = (dt.datetime.now(dt.timezone.utc) - heartbeat).total_seconds()
        max_age = int(os.environ.get("HERMES_TRAY_POLLING_HEARTBEAT_MAX_AGE_SECONDS", "90"))
        print(f"RUNTIME_HEARTBEAT_OK=age_seconds:{int(age)} max_seconds:{max_age}")
        if age > max_age:
            print("RUNTIME_BAD=heartbeat_stale")
            raise SystemExit(1)
    except Exception as exc:
        print(f"RUNTIME_BAD=heartbeat_invalid:{exc}")
        raise SystemExit(1)
print("RUNTIME_OK=1")
PY
    then
      runtime_ok=0
    fi
  else
    echo "RUNTIME_BAD=no_exact_process" >>"$out"
  fi
  gateway_work_ok "$h" "$out" || work_ok=$?
  echo "STATUS_CODES tmux=$tmux_ok process=$process_ok runtime=$runtime_ok work=$work_ok config=$config_ok" >>"$out"
  [ "$tmux_ok" -eq 0 ] && [ "$process_ok" -eq 0 ] && [ "$runtime_ok" -eq 0 ] && [ "$work_ok" -eq 0 ] && [ "$config_ok" -eq 0 ]
}

log_status_failure_home() {
  local h="$1" out="$RESUME_TMP_DIR/status-$(basename "$h").txt"
  if [ -s "$out" ]; then
    while IFS= read -r line; do log "[$h] HEALTH_MISMATCH=$line"; done <"$out"
  else
    log "[$h] HEALTH_MISMATCH=no_status_output"
  fi
}

print_home_status() {
  local h="$1" session out process_epoch config_epoch
  local -a pids
  session="$(session_for_home "$h")"
  out="$RESUME_TMP_DIR/print-status-$(basename "$h").txt"
  echo "HERMES_HOME=$h"
  if tmux_running "$session"; then echo "TMUX_OK=$session"; else echo "TMUX_BAD=$session"; fi
  mapfile -t pids < <(home_process_pids "$h")
  echo "PROCESS_COUNT=${#pids[@]} pids=${pids[*]:-none}"
  if [ "${#pids[@]}" -eq 1 ]; then echo "PROCESS_OK=exact_home"; else echo "PROCESS_BAD=duplicate_or_missing_exact_home"; fi
  process_epoch="$(home_process_start_epoch "$h")"
  config_epoch="$(home_config_epoch "$h")"
  echo "PROCESS_START_EPOCH=$process_epoch"
  echo "CONFIG_EPOCH=$config_epoch"
  if home_config_loaded_ok "$h" || { [ "$process_epoch" -gt 0 ] && [ "$config_epoch" -le "$process_epoch" ]; }; then
    echo "CONFIG_FRESH_OK=1"
  else
    echo "CONFIG_PENDING_RELOAD=1"
    echo "CONFIG_RELOAD_DEFERRED=active_gateway_not_restarted"
  fi
  : >"$out"
  gateway_work_ok "$h" "$out" || true
  cat "$out"
}

telegram_api_probe_home() {
  local h="$1" token
  if [ "${HERMES_TRAY_DEFER_TELEGRAM_API_PROBES:-1}" = "1" ]; then
    log "[$h] Telegram API getMe probe deferred for sub-10s startup hot path"
    return 0
  fi
  token="$(env_value_home "$h" TELEGRAM_BOT_TOKEN)"
  if [ -z "$token" ]; then log "ERROR: $h has no TELEGRAM_BOT_TOKEN"; return 13; fi
  timeout 12s curl --max-time 8 -fsS "https://api.telegram.org/bot${token}/getMe" >"$RESUME_TMP_DIR/getme-$(basename "$h").json"
  python3 - "$h" "$RESUME_TMP_DIR/getme-$(basename "$h").json" <<'PY'
import json, sys
data=json.load(open(sys.argv[2]))
if not data.get('ok'):
    raise SystemExit('Telegram getMe returned not ok for '+sys.argv[1])
user=data.get('result', {})
print('Telegram bot OK for %s: id=%s username=@%s' % (sys.argv[1], user.get('id'), user.get('username')))
PY
}

telegram_send_probe_home() {
  local h="$1" action="$2" chat_id token probe_dir probe_file
  token="$(env_value_home "$h" TELEGRAM_BOT_TOKEN)"
  chat_id="$(env_value_home "$h" TELEGRAM_TEST_CHAT_ID)"
  if [ -z "$chat_id" ]; then
    chat_id="$(env_value_home "$h" TELEGRAM_ALLOWED_USERS)"
    chat_id="${chat_id%%,*}"
  fi
  if [ -z "$chat_id" ] || [ -z "$token" ]; then return 1; fi
  # Telegram ready proofs are deliberately explicit opt-in edge notifications.
  # Do not send chat messages from ordinary tray health/resume/self-heal passes;
  # those run often and would look like random spam. Even a manual gateway
  # restart stays quiet unless HERMES_TRAY_SEND_READY_PROBE_ALL=1 is explicitly set.
  if [ "${HERMES_TRAY_SEND_READY_PROBE_ALL:-0}" != "1" ]; then
    log "[$h] TELEGRAM_READY_PROBE_SUPPRESSED=not_manual_gateway_restart action=$action"
    return 0
  fi
  local text
  text="Hermes tray verified ${h} is back online after gateway restart and ready: $(ts)"
  local send_json send_err
  send_json="$RESUME_TMP_DIR/send-$(basename "$h").json"
  send_err="$RESUME_TMP_DIR/send-$(basename "$h").err"
  if timeout 12s curl --max-time 8 -fsS -X POST "https://api.telegram.org/bot${token}/sendMessage" \
    -d chat_id="$chat_id" \
    --data-urlencode text="$text" >"$send_json" 2>"$send_err" \
    && python3 - "$send_json" <<'PY'
import json, sys
with open(sys.argv[1], encoding='utf-8') as f:
    data = json.load(f)
if data.get('ok') is not True:
    raise SystemExit(1)
result = data.get('result') or {}
print('message_id=' + str(result.get('message_id', 'unknown')))
PY
  then
    msg_id="$(python3 - "$send_json" <<'PY'
import json, sys
print((json.load(open(sys.argv[1], encoding='utf-8')).get('result') or {}).get('message_id', 'unknown'))
PY
)"
    probe_dir="$h/.runtime"
    probe_file="$probe_dir/telegram-ready-probe.json"
    mkdir -p "$probe_dir"
    python3 - "$probe_file" "$h" "$action" "$chat_id" "$msg_id" <<'PY'
import json, pathlib, sys, time
path = pathlib.Path(sys.argv[1])
payload = {
    "home": sys.argv[2],
    "action": sys.argv[3],
    "chat_id": sys.argv[4],
    "message_id": sys.argv[5],
    "sent_epoch": time.time(),
}
path.write_text(json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8")
PY
    chown "$USER_NAME:$USER_NAME" "$probe_dir" "$probe_file" 2>/dev/null || true
    chmod 600 "$probe_file" 2>/dev/null || true
    log "[$h] TELEGRAM_READY_PROBE_SENT=1 action=$action chat=$chat_id message_id=$msg_id"
  else
    log "[$h] TELEGRAM_READY_PROBE_FAILED=1 action=$action chat=$chat_id"
    cat "$send_err" 2>/dev/null | while IFS= read -r line; do log "[$h] TELEGRAM_READY_PROBE_ERR=$line"; done
    cat "$send_json" 2>/dev/null | head -c 500 | while IFS= read -r line; do log "[$h] TELEGRAM_READY_PROBE_BODY=$line"; done
    return 1
  fi
}

repair_shared_config_if_truncated() {
  python3 <<'PY'
import datetime as dt
import shutil
from pathlib import Path

import yaml

home = Path("/home/ubuntu/.hermes")
config = home / "config.yaml"
required_quick = {"nnew", "sstop", "all", "todoist", "image", "ps5", "ahk", "clean", "ccc"}

def load(path: Path) -> dict:
    try:
        data = yaml.safe_load(path.read_text(encoding="utf-8", errors="replace"))
    except Exception:
        return {}
    return data if isinstance(data, dict) else {}

current = load(config)
quick = current.get("quick_commands") if isinstance(current.get("quick_commands"), dict) else {}
broken = (
    len(current) < 20
    or len(quick) < 40
    or any(name not in quick for name in required_quick)
)

if not broken:
    print(f"CONFIG_GUARD_OK=quick:{len(quick)} keys:{len(current)}")
    raise SystemExit(0)

candidates = []
for path in home.glob("config.yaml*"):
    if path.name == "config.yaml":
        continue
    data = load(path)
    q = data.get("quick_commands") if isinstance(data.get("quick_commands"), dict) else {}
    if len(data) >= 20 and len(q) >= 40 and all(name in q for name in required_quick):
        candidates.append((path.stat().st_mtime, path, len(q), len(data)))

if not candidates:
    print("CONFIG_GUARD_FAIL=no_complete_config_backup")
    raise SystemExit(23)

_mtime, source, qcount, key_count = sorted(candidates, reverse=True)[0]
stamp = dt.datetime.now().strftime("%Y%m%d-%H%M%S")
backup = home / f"config.yaml.bak-truncated-autoguard-{stamp}"
if config.exists():
    shutil.copy2(config, backup)
shutil.copy2(source, config)
print(f"CONFIG_GUARD_RESTORED={source} quick:{qcount} keys:{key_count} backup:{backup}")
PY
}

sync_telegram_menus() {
  local sync_script="${HOME_DIR}/.hermes/scripts/sync_telegram_clone_menus.py"
  local cache_file="${HOME_DIR}/.hermes/.runtime/telegram-menu-sync.ok"
  local current_hash cached_hash cached_epoch now max_age
  if [ ! -f "$sync_script" ]; then
    log "ERROR: Telegram menu sync script missing: $sync_script"
    return 22
  fi
  if [ "${HERMES_TRAY_DEFER_MENU_SYNC:-1}" = "1" ] && [ "${HERMES_TRAY_FORCE_MENU_SYNC:-0}" != "1" ]; then
    log "Telegram BotCommand menu sync deferred for sub-10s startup hot path"
    return 0
  fi
  mkdir -p "${HOME_DIR}/.hermes/.runtime" 2>/dev/null || true
  chown -R "$USER_NAME:$USER_NAME" "${HOME_DIR}/.hermes/.runtime" 2>/dev/null || true
  current_hash="$(sha256sum "${HOME_DIR}/.hermes/config.yaml" 2>/dev/null | awk '{print $1}' || true)"
  cached_hash="$(sed -n '1p' "$cache_file" 2>/dev/null | tr -d '[:space:]' || true)"
  cached_epoch="$(sed -n '2p' "$cache_file" 2>/dev/null | tr -d '[:space:]' || echo 0)"
  now="$(date +%s)"
  max_age="${HERMES_TRAY_MENU_CACHE_SECONDS:-86400}"
  if [ "${HERMES_TRAY_FORCE_MENU_SYNC:-0}" != "1" ] && [ -n "$current_hash" ] && [ "$current_hash" = "$cached_hash" ] && [ $((now - ${cached_epoch:-0})) -le "$max_age" ]; then
    log "Telegram BotCommand menus recently synchronized and verified (cache hit)"
    return 0
  fi
  log "Synchronizing Telegram BotCommand menus for the full Hermes fleet"
  if as_ubuntu env HERMES_HOME="${HOME_DIR}/.hermes" TELEGRAM_MENU_API_TIMEOUT=8 \
      "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" "$sync_script" --verbose \
      >"$RESUME_TMP_DIR/telegram-menu-sync.out" 2>"$RESUME_TMP_DIR/telegram-menu-sync.err"; then
    while IFS= read -r line; do log "[telegram-menu] $line"; done <"$RESUME_TMP_DIR/telegram-menu-sync.out"
    log "Telegram BotCommand menus synchronized and verified"
    as_ubuntu bash -lc "mkdir -p '${HOME_DIR}/.hermes/.runtime' && { printf '%s\n' '$current_hash'; date +%s; } > '${cache_file}'" 2>/dev/null || true
    chown -R "$USER_NAME:$USER_NAME" "${HOME_DIR}/.hermes/.runtime" 2>/dev/null || true
    return 0
  fi
  local rc=$?
  log "ERROR: Telegram menu sync failed with exit $rc"
  while IFS= read -r line; do log "[telegram-menu] $line"; done <"$RESUME_TMP_DIR/telegram-menu-sync.out" 2>/dev/null || true
  while IFS= read -r line; do log "[telegram-menu-err] $line"; done <"$RESUME_TMP_DIR/telegram-menu-sync.err" 2>/dev/null || true
  return "$rc"
}

start_gateway_home() {
  local h="$1" session log_dir run_log deadline pid active_work_file repair_restart_marker
  local -a existing_pids
  session="$(session_for_home "$h")"
  log_dir="$h/logs"
  run_log="$log_dir/gateway-run.log"
  repair_restart_marker="$h/.runtime/required-home-repaired-needs-restart"
  mkdir -p "$log_dir"
  mapfile -t existing_pids < <(home_process_pids "$h")
  if [ -f "$repair_restart_marker" ] && [ "${#existing_pids[@]}" -gt 0 ] && [ "${HERMES_FORCE_GATEWAY_RESTART_DURING_WORK:-}" != "manual-root-danger" ]; then
    log "[$h] repaired required home restart marker is pending, but automatic resume will not kill a live gateway; explicit manual Restart Gateway is required. pids=${existing_pids[*]}"
    mark_loaded_config_home "$h" || true
    return 21
  fi
  if [ -f "$repair_restart_marker" ] && [ "${#existing_pids[@]}" -gt 0 ]; then
    log "[$h] repaired required home replaced a broken restore symlink; restarting exact stale gateway process(es): ${existing_pids[*]}"
    as_ubuntu tmux kill-session -t "$session" 2>/dev/null || true
    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      kill "$pid" 2>/dev/null || true
      log "[$h] Terminated stale repaired-home gateway pid=$pid before reconnect"
    done < <(home_process_pids "$h")
    sleep 2
    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      kill -9 "$pid" 2>/dev/null || true
      log "[$h] Killed stubborn stale repaired-home gateway pid=$pid before reconnect"
    done < <(home_process_pids "$h")
    existing_pids=()
  fi
  if [ "${#existing_pids[@]}" -gt 0 ] && [ "${HERMES_FORCE_GATEWAY_RESTART_DURING_WORK:-}" != "manual-root-danger" ]; then
    log "[$h] exact gateway process already exists (${existing_pids[*]}); automatic tray resume will not kill/reconnect a live Telegram gateway"
    mark_loaded_config_home "$h" || true
    return 0
  fi
  # Active-work guards protect a currently running gateway from being killed mid-turn.
  # After WSL/host restart there may be no gateway process at all, while old logs still
  # show an unanswered message. In that case blocking reconnect leaves the bot dead and
  # the tray yellow forever. Reconnect missing gateways immediately; the gateway's
  # resume-pending/tool-tail recovery preserves the session and continues when the user
  # asks it to continue.
  if home_process_running "$h" && gateway_has_active_work_home "$h" && [ "${HERMES_FORCE_GATEWAY_RESTART_DURING_WORK:-}" != "manual-root-danger" ]; then
    active_work_file="$RESUME_TMP_DIR/active-work-$(basename "$h").txt"
    while IFS= read -r line; do log "[$h] ACTIVE_WORK_GUARD=$line"; done <"$active_work_file"
    log "[$h] reconnect blocked: Telegram work is active/interrupted on a live gateway; keeping the existing gateway to avoid mid-work disconnect"
    return 21
  fi
  mapfile -t existing_pids < <(home_process_pids "$h")
  if [ "${#existing_pids[@]}" -gt 0 ]; then
    if ! manual_gateway_stop_requested; then
      log "[$h] gateway is not healthy, but automatic reconnect is deferred because live exact gateway process(es) exist (${existing_pids[*]}); only an explicit manual Restart Gateway may replace them"
      return 21
    fi
    log "[$h] manual-intent confirmed; reconnecting only this Hermes home via tmux session $session."
    local reconnect_token
    reconnect_token="$(env_value_home "$h" TELEGRAM_BOT_TOKEN)"
    if [ -n "$reconnect_token" ]; then
      timeout 12s curl --max-time 8 -fsS "https://api.telegram.org/bot${reconnect_token}/deleteWebhook" >"$RESUME_TMP_DIR/deletewebhook-$(basename "$h").json" || true
    fi
    as_ubuntu tmux kill-session -t "$session" 2>/dev/null || true
    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      kill "$pid" 2>/dev/null || true
      log "[$h] Terminated old/duplicate gateway pid=$pid before reconnect"
    done < <(home_process_pids "$h")
    sleep 2
    while IFS= read -r pid; do
      [ -n "$pid" ] || continue
      kill -9 "$pid" 2>/dev/null || true
      log "[$h] Killed stubborn duplicate gateway pid=$pid before reconnect"
    done < <(home_process_pids "$h")
  else
    log "[$h] no exact gateway process exists; automatic cold-start is allowed after WSL/Windows restart"
    as_ubuntu tmux kill-session -t "$session" 2>/dev/null || true
  fi
  rm -f "$h/gateway.lock" "$h/gateway.pid" 2>/dev/null || true
  chown "$USER_NAME:$USER_NAME" "$h" "$h/gateway_state.json" "$h/processes.json" "$h/gateway.pid" "$h/gateway.lock" 2>/dev/null || true
  chmod 600 "$h/gateway.pid" "$h/gateway.lock" 2>/dev/null || true
  clear_resume_markers_home "$h" "cold_start" | while IFS= read -r line; do log "[$h] $line"; done
  mark_loaded_config_home "$h" || true
  as_ubuntu tmux new-session -d -s "$session" \
    "cd '$HOME_DIR' && export $HERMES_RUNTIME_EXPORTS HERMES_HOME='$h' HERMES_AGENT_TIMEOUT=0 HERMES_AGENT_TIMEOUT_WARNING=0 HERMES_STALE_LOCK_RECOVERY_SECONDS=0 HERMES_MAX_ITERATIONS=1000 HERMES_AUTO_CONTINUE_FRESHNESS=0 HERMES_NO_INTERACTIVE_DEP_PROMPTS=1 HERMES_DISABLE_DEP_AUTOINSTALL=1 PYTHONUNBUFFERED=1 PATH='$HERMES_PATH' && exec '$HERMES_BIN' gateway run >>'$run_log' 2>&1" 9>&-
  rm -f "$repair_restart_marker" 2>/dev/null || true
  local max_wait poll_sleep
  max_wait="${HERMES_TRAY_GATEWAY_READY_TIMEOUT_SECONDS:-4}"
  poll_sleep="${HERMES_TRAY_GATEWAY_READY_POLL_SECONDS:-0.2}"
  deadline=$(python3 - <<PY
import time
print(time.monotonic() + float(${max_wait@Q}))
PY
)
  while python3 - "$deadline" <<'PY'
import sys, time
raise SystemExit(0 if time.monotonic() < float(sys.argv[1]) else 1)
PY
  do
    if tmux_running "$session" && home_process_running "$h" && status_ok "$h"; then
      log "[$h] Hermes gateway process is supervised and runtime-ready after cold start/reconnect"
      clear_resume_markers_home "$h" "post_ready" | while IFS= read -r line; do log "[$h] $line"; done
      return 0
    fi
    sleep "$poll_sleep"
  done
  log "ERROR: [$h] Hermes gateway process did not become runtime-ready within ${max_wait}s cold-start budget"
  cat "$RESUME_TMP_DIR/status-$(basename "$h").txt" 2>/dev/null || true
  tail -120 "$run_log" 2>/dev/null || true
  return 20
}

mkdir -p "$FLEET_LOG_DIR"
touch "$RESUME_LOG"
ensure_tmp_writable
exec 9>"$RESUME_LOCK"
if ! flock -n 9; then
  log "Another Hermes WSL2 fleet resume is already running; refusing overlap."
  exit 75
fi
prepare_resume_tmp
trap 'rm -rf "$RESUME_TMP_DIR" 2>/dev/null || true' EXIT
log "Starting Hermes WSL2 fleet resume check — 🟢 UNINTERRUPTED MODE (no auto timeout/stale-stop; manual /stop or /sstop only)"
command -v curl >/dev/null || { log "ERROR: missing curl"; exit 11; }
command -v python3 >/dev/null || { log "ERROR: missing python3"; exit 11; }
command -v tmux >/dev/null || { log "ERROR: missing tmux"; exit 11; }
[ -e "$CODEX_AUTH" ] || { log "ERROR: missing Codex auth: $CODEX_AUTH"; exit 10; }
sync_codex_auth_for_fleet
if ensure_required_telegram_fleet_homes; then
  log "Required Telegram fleet homes verified: Michaopenclawbot + MichaHermes5bot are not replaceable by NvidiaMax"
else
  log "ERROR: required Telegram fleet home repair failed; refusing to let optional bots satisfy the five-bot contract"
  exit 73
fi
ensure_fleet_auth_permissions
ensure_hermes_agent_runtime
apply_hermes_agent_local_hardening | while IFS= read -r line; do log "$line"; done
if [ -f "${HOME_DIR}/.hermes/scripts/ensure_realtime_progress_contract.py" ]; then
  if as_ubuntu "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" "${HOME_DIR}/.hermes/scripts/ensure_realtime_progress_contract.py" >"$RESUME_TMP_DIR/realtime-progress-contract.out" 2>&1; then
    while IFS= read -r line; do log "$line"; done <"$RESUME_TMP_DIR/realtime-progress-contract.out"
    log "HERMES_REALTIME_PROGRESS_CONTRACT_OK=1"
  else
    while IFS= read -r line; do log "$line"; done <"$RESUME_TMP_DIR/realtime-progress-contract.out"
    log "WARNING: realtime progress contract validation failed; continuing restore resume so Telegram gateways still start"
  fi
fi
if [ -f "${HOME_DIR}/.hermes/scripts/ensure_uninterrupted_execution_contract.py" ]; then
  as_ubuntu "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" "${HOME_DIR}/.hermes/scripts/ensure_uninterrupted_execution_contract.py" | while IFS= read -r line; do log "$line"; done
  log "HERMES_UNINTERRUPTED_EXECUTION_CONTRACT_OK=1"
fi
install_hermes_command_guard

if repair_shared_config_if_truncated >"$RESUME_TMP_DIR/config-guard.out" 2>&1; then
  guard_rc=0
else
  guard_rc=$?
fi
while IFS= read -r line; do log "$line"; done <"$RESUME_TMP_DIR/config-guard.out"
if [ "$guard_rc" -ne 0 ]; then
  log "ERROR: shared config guard failed with exit $guard_rc"
  exit "$guard_rc"
fi

homes=()
while IFS= read -r h; do homes+=("$h"); done < <(discover_homes)
if [ "${#homes[@]}" -eq 0 ]; then log "ERROR: no Telegram Hermes homes discovered"; exit 14; fi
log "Discovered ${#homes[@]} Telegram Hermes home(s): ${homes[*]}"

overall=0
if [ "${HERMES_TRAY_FAST_BOOT:-0}" = "1" ]; then
  log "FAST_BOOT=1 prestarting only homes with no exact gateway process; live working gateways are never killed by fast boot"
  fast_items=()
  for h in "${homes[@]}"; do
    session="$(session_for_home "$h")"
    # Critical safety rule: fast boot may start a bot after WSL/host restart,
    # but must not "repair" a live process by killing it. A missing tmux session
    # with an exact live gateway is reported later as working/degraded rather
    # than interrupted. Only a manual Restart Gateway path may replace live work.
    if ! home_process_running "$h"; then
      label="$(basename "$h")"
      ( start_gateway_home "$h" >"$RESUME_TMP_DIR/fast-boot-$label.out" 2>&1 ) &
      fast_items+=("$!:$label:$h")
    fi
  done
  for item in "${fast_items[@]}"; do
    pid="${item%%:*}"
    rest="${item#*:}"
    label="${rest%%:*}"
    h="${rest#*:}"
    if wait "$pid"; then
      log "[$h] FAST_BOOT_START_OK=1"
    else
      log "[$h] FAST_BOOT_START_FAILED=1"
      overall=1
    fi
    while IFS= read -r line; do log "[$h] [fast-boot] $line"; done <"$RESUME_TMP_DIR/fast-boot-$label.out" 2>/dev/null || true
  done
fi

overall=${overall:-0}
for h in "${homes[@]}"; do
  action="kept-existing"
  chown -R "$USER_NAME:$USER_NAME" "$h/logs" 2>/dev/null || true
  ensure_fleet_auth_permissions
  chmod 600 "$h/.env" 2>/dev/null || true
  if ! telegram_api_probe_home "$h"; then overall=1; continue; fi
  session="$(session_for_home "$h")"
  if resume_markers_present_home "$h"; then
    log "[$h] Restart-recovery marker found"
    if status_ok "$h"; then
      clear_resume_markers_home "$h" "healthy_keep" | while IFS= read -r line; do log "[$h] $line"; done
      log "[$h] Existing Hermes gateway is healthy; cleared restart marker without reconnect"
    else
      log_status_failure_home "$h"
      if repair_duplicate_processes_home "$h" && status_ok "$h"; then
        clear_resume_markers_home "$h" "dedupe_keep" | while IFS= read -r line; do log "[$h] $line"; done
        log "[$h] Restart marker plus duplicate poller repaired without restarting the kept gateway"
      else
        if home_process_running "$h" && gateway_has_active_work_home "$h" && [ "${HERMES_FORCE_GATEWAY_RESTART_DURING_WORK:-}" != "manual-root-danger" ]; then
          active_work_file="$RESUME_TMP_DIR/active-work-$(basename "$h").txt"
          while IFS= read -r line; do log "[$h] ACTIVE_WORK_GUARD=$line"; done <"$active_work_file"
          log "[$h] Restart marker plus active live work; preserving the running gateway and not reconnecting"
        else
          log "[$h] Restart marker plus unhealthy runtime; reconnecting this Hermes home"
          action="reconnected"
          if ! start_gateway_home "$h"; then overall=1; continue; fi
        fi
      fi
    fi
	  elif status_ok "$h"; then
		    clear_resume_markers_home "$h" "healthy_keep" | while IFS= read -r line; do log "[$h] $line"; done
		    log "[$h] Existing Hermes gateway is healthy; keeping it running without restart"
  else
    log_status_failure_home "$h"
    if repair_duplicate_processes_home "$h" && status_ok "$h"; then
      log "[$h] Duplicate poller repaired without restarting the kept gateway"
      action="kept-existing"
    else
      if home_process_running "$h" && gateway_has_active_work_home "$h" && [ "${HERMES_FORCE_GATEWAY_RESTART_DURING_WORK:-}" != "manual-root-danger" ]; then
        active_work_file="$RESUME_TMP_DIR/active-work-$(basename "$h").txt"
        while IFS= read -r line; do log "[$h] ACTIVE_WORK_GUARD=$line"; done <"$active_work_file"
        log "[$h] Unhealthy metadata but active live work is present; preserving the running gateway and not reconnecting"
        action="kept-existing"
      else
        action="reconnected"
        if ! start_gateway_home "$h"; then overall=1; continue; fi
      fi
    fi
	  fi
	  clear_resume_markers_home "$h" "post_ready" | while IFS= read -r line; do log "[$h] $line"; done
	  if ! telegram_send_probe_home "$h" "$action"; then overall=1; fi
  log "[$h] Final Hermes gateway status:"
  print_home_status "$h" || true
  grep -E "Connected to Telegram|Gateway running with 1 platform" "$h/logs/gateway.log" 2>/dev/null | tail -5 || true
done

if ! sync_telegram_menus; then
  overall=1
fi

ensure_companion_watchdogs

if [ "$overall" -ne 0 ]; then
  log "Hermes WSL2 fleet resume completed with failures"
  exit "$overall"
fi

echo "RESUME_ACTION=fleet-ok"
echo "RESUME_LOG=$RESUME_LOG"
log "Hermes WSL2 fleet resume complete"
