#!/usr/bin/env bash
set +eu

export PATH="/home/ubuntu/.local/bin:/home/ubuntu/.hermes/node/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/snap/bin"
USER_NAME="${HERMES_WSL_USER:-ubuntu}"
HOME_DIR="/home/${USER_NAME}"
HERMES_BIN="${HOME_DIR}/.local/bin/hermes"
HERMES_CODEX_SYNC_SCRIPT="/mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoBackRes/sync-codex-auth-to-hermes.sh"

session_for_home() {
  local h="$1" base
  if [ "$h" = "${HOME_DIR}/.hermes" ]; then echo "hermes-gateway"; return; fi
  base="$(basename "$h")"
  echo "hermes-${base#.hermes-}"
}

discover_homes() {
  local h
  printf '%s\n' "${HOME_DIR}/.hermes"
  for h in "${HOME_DIR}"/.hermes-*; do
    [ -d "$h" ] || continue
    [ -f "$h/config.yaml" ] || continue
    [ -f "$h/.env" ] || continue
    if grep -q '^TELEGRAM_BOT_TOKEN=' "$h/.env"; then printf '%s\n' "$h"; fi
  done | awk '!seen[$0]++'
}

required_fleet_homes() {
  printf '%s\n' \
    "${HOME_DIR}/.hermes" \
    "${HOME_DIR}/.hermes-mmmoltbot_bot" \
    "${HOME_DIR}/.hermes-mmichael_moltbot_bot" \
    "${HOME_DIR}/.hermes-michaopenclawbot" \
    "${HOME_DIR}/.hermes-michahermes5bot"
}

check_required_fleet_homes() {
  local h missing=0
  while IFS= read -r h; do
    [ -n "$h" ] || continue
    if [ ! -d "$h" ] || [ ! -f "$h/config.yaml" ] || [ ! -f "$h/.env" ] || ! grep -q '^TELEGRAM_BOT_TOKEN=' "$h/.env" 2>/dev/null; then
      echo "READY_FAIL=required_telegram_home_missing_or_unconfigured:$h"
      missing=1
    else
      echo "READY_REQUIRED_HOME_OK=$h"
    fi
  done < <(required_fleet_homes)
  [ "$missing" -eq 0 ]
}

sync_codex_auth_for_fleet() {
  [ -f "$HERMES_CODEX_SYNC_SCRIPT" ] || return 0
  if [ "$(id -un)" = "$USER_NAME" ]; then
    env HERMES_WSL_USER="$USER_NAME" bash "$HERMES_CODEX_SYNC_SCRIPT" >/dev/null 2>&1 || true
  else
    sudo -H -u "$USER_NAME" env HERMES_WSL_USER="$USER_NAME" bash "$HERMES_CODEX_SYNC_SCRIPT" >/dev/null 2>&1 || true
  fi
}

sync_codex_auth_for_fleet

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

check_home() {
  local h="$1" label session telegram_json telegram_txt webhook_json webhook_txt gateway_log run_log pid token chat_id curl_code telegram_code webhook_curl_code webhook_code config_state process_started config_epoch runtime_state probe_state
  local -a pids
  label="$(basename "$h")"
  session="$(session_for_home "$h")"
  tmp_dir="/tmp/hermes-tray-${USER_NAME}"
  mkdir -p "$tmp_dir"
  if [ "$(id -u)" -eq 0 ]; then
    chown -R "$USER_NAME:$USER_NAME" "$tmp_dir" 2>/dev/null || true
  elif [ ! -w "$tmp_dir" ] && command -v sudo >/dev/null 2>&1; then
    sudo chown -R "$USER_NAME:$USER_NAME" "$tmp_dir" 2>/dev/null || true
  fi
  telegram_json="$tmp_dir/telegram-${label}.json"
  telegram_txt="$tmp_dir/telegram-${label}.txt"
  webhook_json="$tmp_dir/telegram-webhook-${label}.json"
  webhook_txt="$tmp_dir/telegram-webhook-${label}.txt"
  gateway_log="$h/logs/gateway.log"
  run_log="$h/logs/gateway-run.log"

  echo "READY_HOME=$h"

  sudo -H -u "$USER_NAME" tmux has-session -t "=$session" >/dev/null 2>&1
  tmux_state=$?
  echo "READY_TMUX_${label}=$([ "$tmux_state" -eq 0 ] && echo 1 || echo 0) session=$session"

  mapfile -t pids < <(home_process_pids "$h")
  if [ "${#pids[@]}" -eq 0 ]; then
    process_wait_deadline="$(python3 - <<'PY'
import os, time
print(time.monotonic() + float(os.environ.get("HERMES_TRAY_PROCESS_WAIT_SECONDS", "4")))
PY
)"
    while python3 - "$process_wait_deadline" <<'PY'
import sys, time
raise SystemExit(0 if time.monotonic() < float(sys.argv[1]) else 1)
PY
    do
      sleep 0.15
      mapfile -t pids < <(home_process_pids "$h")
      [ "${#pids[@]}" -gt 0 ] && break
    done
  fi
  pid="${pids[0]:-}"
  echo "READY_PID_COUNT_${label}=${#pids[@]} pids=${pids[*]:-none}"
  echo "READY_PID_HINT_${label}=${pid:-none}"
  if [ "${#pids[@]}" -eq 1 ] && [ -n "$pid" ]; then
    process_state=0
    if [ "$tmux_state" -ne 0 ]; then
      parent_pid="$pid"
      tmux_parent_found=0
      for _ in 1 2 3 4 5; do
        parent_pid="$(ps -o ppid= -p "$parent_pid" 2>/dev/null | tr -d ' ' || true)"
        [ -n "$parent_pid" ] || break
        if ps -o comm= -p "$parent_pid" 2>/dev/null | grep -Eq '^(tmux|tmux: server)$'; then
          tmux_parent_found=1
          break
        fi
      done
      if [ "$tmux_parent_found" -eq 1 ]; then
        echo "READY_INFO=tmux_socket_lag_parent_supervises:$h"
        tmux_state=0
      fi
    fi
  elif [ "${#pids[@]}" -gt 1 ] && [ -n "$pid" ]; then
    # Duplicate live gateways are not a tray permission to kill a working chat.
    # Report working/degraded; only explicit manual Restart Gateway may replace them.
    process_state=0
    echo "READY_WORKING=duplicate_gateway_processes_no_auto_kill:${pids[*]}"
  else
    process_state=1
    echo "READY_FAIL=missing_gateway_process:none"
  fi
  process_age=999999
  if [ -n "$pid" ] && [ -e "/proc/$pid" ]; then
    process_started="$(stat -c %Y "/proc/$pid" 2>/dev/null || echo 0)"
    now_epoch="$(date +%s)"
    if [ "$process_started" -gt 0 ]; then process_age=$((now_epoch - process_started)); fi
  fi
  echo "READY_PROCESS_AGE_${label}=${process_age}s"
  config_state=0
  config_epoch="$(stat -Lc %Y "$h/config.yaml" 2>/dev/null || echo 0)"
  config_hash="$(sha256sum "$h/config.yaml" 2>/dev/null | awk '{print $1}' || true)"
  loaded_config_hash="$(head -n 1 "$h/.runtime/loaded-config.sha256" 2>/dev/null | tr -d '[:space:]' || true)"
  echo "READY_CONFIG_EPOCH_${label}=${config_epoch}"
  if [ -n "$config_hash" ] && [ "$config_hash" = "$loaded_config_hash" ]; then
    echo "READY_CONFIG_FRESH_${label}=hash"
  elif [ -n "$pid" ] && [ -e "/proc/$pid" ] && [ "$process_started" -gt 0 ] && [ "$config_epoch" -le "$process_started" ]; then
    echo "READY_CONFIG_FRESH_${label}=1"
  else
    echo "READY_CONFIG_PENDING_RELOAD_${label}=1"
    # A shared config write does not mean the live Telegram poller is broken. Older health
    # logic made otherwise connected bots look "not ready" until they were restarted,
    # which caused unnecessary watchdog churn and false red tray status during active work.
    # Keep the warning visible, but only make it fatal when strict config reload checking is
    # explicitly requested.
    echo "READY_WORKING=config_changed_reload_deferred:$h"
    if [ "${HERMES_TRAY_STRICT_CONFIG_RELOAD:-0}" = "1" ]; then
      echo "READY_FAIL=config_changed_requires_gateway_reload:$h"
      config_state=1
    fi
  fi

  runtime_state=1
  if [ -n "$pid" ]; then
    HERMES_PROCESS_AGE_SECONDS="$process_age" python3 - "$h" "$pid" <<'PY'
import datetime as dt
import json
import sys
from pathlib import Path

home = Path(sys.argv[1])
pid = int(sys.argv[2])
state_path = home / "gateway_state.json"
try:
    data = json.loads(state_path.read_text(encoding="utf-8"))
except Exception as exc:
    print(f"READY_FAIL=runtime_state_unreadable:{exc}")
    raise SystemExit(1)

state_pid = data.get("pid")
gateway_state = data.get("gateway_state")
telegram = (data.get("platforms") or {}).get("telegram", {})
telegram_state = telegram.get("state")
print(f"READY_RUNTIME_STATE=pid:{pid} state_pid:{state_pid} gateway:{gateway_state} telegram:{telegram_state}")
if state_pid != pid or gateway_state != "running" or telegram_state != "connected":
    import os
    process_age = int(os.environ.get("HERMES_PROCESS_AGE_SECONDS", "999999") or "999999")
    startup_grace = int(os.environ.get("HERMES_TRAY_STARTUP_GRACE_SECONDS", "120") or "120")
    print("READY_RUNTIME_METADATA_LAG=1")
    # A freshly restarted gateway can spend tens of seconds initializing MCP/tooling before
    # gateway_state.json is rewritten with the new PID/connected state. Treat that window as
    # "working" instead of "failed" so the tray watchdog does not repeatedly kill the same
    # clone before it has a chance to finish startup.
    if process_age < startup_grace:
        print(f"READY_WORKING=startup_runtime_metadata_pending process_age_seconds:{process_age} startup_grace_seconds:{startup_grace}")
        raise SystemExit(0)
    # Safety-first tray policy: a live exact-home gateway process must not be
    # treated as a restart trigger merely because gateway_state.json is stale
    # or lagging. Mark it as working/degraded so the watchdog does not kill an
    # in-flight Telegram task; resume.sh can still start homes with no process.
    print(f"READY_WORKING=runtime_state_metadata_lag_no_reconnect:expected_pid:{pid}:state_pid:{state_pid}:gateway:{gateway_state}:telegram:{telegram_state}")
    raise SystemExit(0)

mode = telegram.get("mode") or "unknown"
polling_running = telegram.get("polling_running")
heartbeat_at = telegram.get("polling_heartbeat_at")
heartbeat_error = telegram.get("polling_heartbeat_error")
if mode == "polling":
    if polling_running is not True:
        print(f"READY_FAIL=telegram_polling_not_running:{heartbeat_error or 'unknown'}")
        raise SystemExit(2)
    if not heartbeat_at:
        print("READY_FAIL=telegram_polling_heartbeat_missing")
        raise SystemExit(2)
    try:
        heartbeat_dt = dt.datetime.fromisoformat(str(heartbeat_at).replace("Z", "+00:00"))
        if heartbeat_dt.tzinfo is None:
            heartbeat_dt = heartbeat_dt.replace(tzinfo=dt.timezone.utc)
        age = (dt.datetime.now(dt.timezone.utc) - heartbeat_dt).total_seconds()
    except Exception as exc:
        print(f"READY_FAIL=telegram_polling_heartbeat_bad_timestamp:{exc}")
        raise SystemExit(2)
    max_age = int(__import__("os").environ.get("HERMES_TRAY_POLLING_HEARTBEAT_MAX_AGE_SECONDS", "90"))
    print(f"READY_POLLING_HEARTBEAT_OK=age_seconds:{int(age)} max_seconds:{max_age}")
    if age > max_age:
        print(f"READY_FAIL=telegram_polling_heartbeat_stale:{int(age)}")
        raise SystemExit(2)
elif mode == "unknown":
    print("READY_WORKING=polling_heartbeat_pending_after_upgrade")
PY
    runtime_state=$?
  else
    echo "READY_FAIL=runtime_state_no_pid"
  fi

  HERMES_PROCESS_AGE_SECONDS="$process_age" HERMES_PROCESS_START_EPOCH="${process_started:-0}" python3 - "$gateway_log" "$run_log" <<'PY'
import datetime as dt, os, re, sys, time
paths=sys.argv[1:]
stamp=re.compile(r"^(\d{4}-\d{2}-\d{2})[ T](\d{2}:\d{2}:\d{2})")
inbound=re.compile(r"inbound message: platform=telegram .* chat=(\S+)")
ready=re.compile(r"response ready: platform=telegram chat=(\S+)")
start=re.compile(r"Starting Hermes Gateway")
bad=re.compile(r"(Traceback|telegram\.error\.BadRequest|Permission denied|cannot execute|Gateway already running|Unhandled|CRITICAL|ERROR)")
ignore=re.compile(r"(READY_FAIL=|Unrecognized slash command)")
latest_in=latest_ready=latest_start=latest_bad=latest_success=None
pending_active=False
now=time.time()
# If a Telegram chat has been unanswered this long, report it as active work by default.
# Long-unanswered Telegram work means the chat is not actually ready, even if
# polling is connected. Expose that as a health failure; keep the default marker
# distinct from the auto-reconnect marker so the tray does not kill active work.
stale_after=int(os.environ.get('HERMES_TRAY_STALE_UNANSWERED_SECONDS','300'))
strict_stale_reconnect=os.environ.get('HERMES_TRAY_RECONNECT_STALE_UNANSWERED','0').lower() in ('1','true','yes','on')
startup_grace=int(os.environ.get('HERMES_TRAY_STARTUP_GRACE_SECONDS','120'))
process_age=int(os.environ.get('HERMES_PROCESS_AGE_SECONDS','999999'))
process_start_epoch=int(os.environ.get('HERMES_PROCESS_START_EPOCH','0') or '0')
def ts(line):
    m=stamp.match(line)
    return dt.datetime.fromisoformat(m.group(1)+'T'+m.group(2)).timestamp() if m else None
for path in paths:
    try:
        for line in open(path,encoding='utf-8',errors='replace'):
            t=ts(line)
            if t is None: continue
            if process_start_epoch and t < process_start_epoch:
                continue
            if start.search(line): latest_start=t
            if inbound.search(line): latest_in=t
            if ready.search(line): latest_ready=t; latest_success=t
            if 'Sending response' in line or 'Connected to Telegram' in line: latest_success=t
            if now-t <= 900 and bad.search(line) and not ignore.search(line): latest_bad=t
    except FileNotFoundError: pass
if latest_in and (latest_ready is None or latest_ready < latest_in):
    pending_active=True
    age=int(now-latest_in)
    if process_age < startup_grace:
        print('READY_WORKING=startup_grace_after_reconnect process_age_seconds=%s startup_grace_seconds=%s' % (process_age, startup_grace))
    elif latest_start and latest_start > latest_in:
        print('READY_WORKING=prior_unanswered_work_was_interrupted_by_gateway_restart age_seconds=%s' % age)
    elif age > stale_after:
        if strict_stale_reconnect:
            print('READY_FAIL=telegram_unanswered_work_stale age_seconds=%s threshold_seconds=%s strict_reconnect=1' % (age, stale_after))
            raise SystemExit(63)
        print('READY_WORKING=active_unanswered_work_stale_no_reconnect age_seconds=%s threshold_seconds=%s' % (age, stale_after))
    else:
        print('READY_WORKING=active_unanswered_work age_seconds=%s threshold_seconds=%s' % (age, stale_after))
else:
    print('READY_WORK_OK=1')
if latest_bad and not pending_active and (latest_success is None or latest_success < latest_bad):
    # Recent gateway/agent errors in a live exact process are a diagnostic
    # signal, not permission for the tray watchdog to restart a Telegram chat.
    # Keep the icon green/working and let the user/session continue or issue a
    # manual Restart Gateway if they explicitly want replacement.
    print('READY_WORKING=recent_gateway_error_no_reconnect')
print('READY_ERRORS_OK=1')
PY
  work_errors=$?

  python3 - "$h/sessions/sessions.json" <<'PY'
import json
import sys
from pathlib import Path

path = Path(sys.argv[1])
try:
    data = json.loads(path.read_text(encoding="utf-8"))
except FileNotFoundError:
    print("READY_SESSIONS_OK=missing_sessions_file_treated_empty")
    raise SystemExit(0)
except Exception as exc:
    print(f"READY_FAIL=sessions_unreadable:{exc}")
    raise SystemExit(64)

items = data.items() if isinstance(data, dict) else enumerate(data if isinstance(data, list) else [])
blocked = []
active = []
for key, entry in items:
    if not isinstance(entry, dict):
        continue
    platform = str(entry.get("platform") or (entry.get("origin") or {}).get("platform") or "").lower()
    is_telegram = platform == "telegram" or str(key).startswith("telegram:")
    if not is_telegram:
        continue
    if entry.get("resume_pending") or entry.get("suspended"):
        blocked.append(str(key))
    elif entry.get("status") in {"running", "active"} or entry.get("active"):
        active.append(str(key))

if blocked:
    print("READY_WORKING=telegram_sessions_resume_pending_no_reconnect:" + ",".join(blocked[:5]))
    raise SystemExit(0)

if active:
    print("READY_WORKING=telegram_sessions_active:" + ",".join(active[:5]))
    raise SystemExit(0)

print("READY_SESSIONS_OK=1")
PY
  sessions_state=$?

  if [ ! -s "$h/.env" ]; then echo "READY_FAIL=missing_env:$h/.env"; return 1; fi
  set -a; . "$h/.env"; set +a
  token="${TELEGRAM_BOT_TOKEN:-}"
  home_channel="${TELEGRAM_HOME_CHANNEL:-}"
  chat_id="${TELEGRAM_TEST_CHAT_ID:-}"
  if [ -z "$chat_id" ] && [ -n "$home_channel" ]; then chat_id="$home_channel"; fi
  if [ -z "$chat_id" ] && [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then chat_id="${TELEGRAM_ALLOWED_USERS%%,*}"; fi
  if [ -z "$token" ]; then echo "READY_FAIL=empty_telegram_token:$h"; return 1; fi
  home_channel_state=0
  if [ -z "$home_channel" ]; then
    echo "READY_FAIL=missing_telegram_home_channel:$h"
    home_channel_state=1
  else
    echo "READY_TELEGRAM_HOME_CHANNEL_OK=$h:$home_channel"
  fi
  if [ "${HERMES_TRAY_FORCE_TELEGRAM_API_PROBES:-0}" = "1" ]; then
    curl --max-time 8 -fsS "https://api.telegram.org/bot${token}/getMe" >"$telegram_json" 2>"$tmp_dir/telegram-${label}.err"
    curl_code=$?
    python3 - "$telegram_json" "$token" <<'PY' >"$telegram_txt" 2>&1
import hashlib, json, sys
from pathlib import Path
try: data=json.load(open(sys.argv[1]))
except Exception as exc:
    print('READY_FAIL=telegram_json_error:'+str(exc)); raise SystemExit(42)
if data.get('ok'):
    result=data.get('result',{})
    username=str(result.get('username','unknown'))
    print('READY_TELEGRAM_BOT='+username)
    short=hashlib.sha256(sys.argv[2].encode('utf-8')).hexdigest()[:12]
    cache_path=Path('/home/ubuntu/.hermes/.runtime/telegram-bot-cache.json')
    try: cache=json.loads(cache_path.read_text(encoding='utf-8'))
    except Exception: cache={}
    cache[short]={'id':str(result.get('id') or ''),'username':username}
    cache_path.parent.mkdir(parents=True, exist_ok=True)
    cache_path.write_text(json.dumps(cache, indent=2, sort_keys=True), encoding='utf-8')
else:
    print('READY_FAIL=telegram_getme_not_ok')
    raise SystemExit(42)
PY
    telegram_code=$?
    cat "$telegram_txt"
    curl --max-time 8 -fsS "https://api.telegram.org/bot${token}/getWebhookInfo" >"$webhook_json" 2>"$tmp_dir/telegram-webhook-${label}.err"
    webhook_curl_code=$?
    python3 - "$webhook_json" <<'PY' >"$webhook_txt" 2>&1
import json, sys
try: data=json.load(open(sys.argv[1]))
except Exception as exc:
    print('READY_FAIL=telegram_webhook_json_error:'+str(exc)); raise SystemExit(43)
if not data.get('ok'):
    print('READY_FAIL=telegram_webhook_not_ok')
    raise SystemExit(43)
info=data.get('result',{})
url=info.get('url') or ''
pending=int(info.get('pending_update_count') or 0)
if url:
    print('READY_FAIL=telegram_webhook_still_set')
    raise SystemExit(43)
if pending > 0:
    print('READY_FAIL=telegram_pending_updates_backlog:%s' % pending)
    raise SystemExit(43)
print('READY_TELEGRAM_PENDING_OK=0')
PY
    webhook_code=$?
    cat "$webhook_txt"
  else
    curl_code=0
    telegram_code=0
    webhook_curl_code=0
    webhook_code=0
    python3 - "$token" <<'PY'
import hashlib, json, sys
from pathlib import Path
short=hashlib.sha256(sys.argv[1].encode('utf-8')).hexdigest()[:12]
cache_path=Path('/home/ubuntu/.hermes/.runtime/telegram-bot-cache.json')
try: cache=json.loads(cache_path.read_text(encoding='utf-8'))
except Exception: cache={}
entry=cache.get(short) if isinstance(cache, dict) else None
if isinstance(entry, dict) and entry.get('username'):
    print('READY_TELEGRAM_BOT='+str(entry.get('username'))+' cached=1')
else:
    print('READY_TELEGRAM_API_DEFERRED=1 token_hash='+short)
print('READY_TELEGRAM_PENDING_OK=deferred_polling_heartbeat_authoritative')
PY
  fi
  probe_state=0
  if [ "${HERMES_TRAY_REQUIRE_READY_PROBE:-1}" = "1" ]; then
    python3 - "$h/.runtime/telegram-ready-probe.json" "$h" "$token" "$chat_id" "${pid:-}" "${process_started:-0}" <<'PY'
import json
import pathlib
import sys
import time
import urllib.parse
import urllib.request

path = pathlib.Path(sys.argv[1])
home = sys.argv[2]
token = sys.argv[3]
chat_id = sys.argv[4]
gateway_pid = sys.argv[5] or "none"
gateway_process_started_epoch = sys.argv[6] or "0"
try:
    boot_id = pathlib.Path("/proc/sys/kernel/random/boot_id").read_text(encoding="utf-8").strip()
except Exception:
    boot_id = "unknown"

identity = {
    "boot_id": boot_id,
    "gateway_pid": gateway_pid,
    "gateway_process_started_epoch": gateway_process_started_epoch,
    "chat_id": chat_id,
}

def write_state(payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(payload, sort_keys=True) + "\n", encoding="utf-8")

data = {}
message_id = None
sent_epoch = 0.0
try:
    loaded = json.loads(path.read_text(encoding="utf-8"))
    if isinstance(loaded, dict):
        data = loaded
        message_id = data.get("message_id")
        sent_epoch = float(data.get("sent_epoch") or 0)
except Exception:
    data = {}

# This probe is intentionally edge-triggered, not age-triggered.  Health checks
# may run frequently from the Windows tray; they must never resend just because a
# cached proof is older than N seconds.  Send only once per WSL boot/gateway
# process identity, then suppress all ordinary health-watchdog checks.
stored_identity = {
    "boot_id": data.get("boot_id"),
    "gateway_pid": str(data.get("gateway_pid") or ""),
    "gateway_process_started_epoch": str(data.get("gateway_process_started_epoch") or ""),
    "chat_id": data.get("chat_id"),
}
legacy_has_proof = bool(message_id and str(message_id) != "unknown") and not data.get("boot_id")
missing_proof = not message_id or str(message_id) == "unknown"
identity_changed = stored_identity != identity

if legacy_has_proof or missing_proof:
    # Do not send a surprise message merely because the state file is from the old
    # age-based format or missing after maintenance.  Seed the current identity;
    # the next real boot/gateway restart will be the only event that emits a chat
    # proof.
    data.update(identity)
    data.update({
        "home": home,
        "action": "health-self-heal-seeded-no-send",
        "chat_id": chat_id,
        "message_id": message_id or "seeded-no-send",
        "sent_epoch": sent_epoch or time.time(),
        "seeded_epoch": time.time(),
    })
    write_state(data)
    age = time.time() - float(data.get("sent_epoch") or time.time())
    print(f"READY_TELEGRAM_READY_PROBE_SEEDED_NO_SEND={home}:message_id:{data.get('message_id')}")
elif identity_changed:
    # Ordinary tray health checks are not allowed to send Telegram messages.
    # The only chat proof path is resume.sh during an explicit/manual Gateway or
    # WSL restart (HERMES_TRAY_SEND_READY_PROBE_ALL/manual intent). Seed the new
    # identity so repeated health checks stay quiet.
    data.update(identity)
    data.update({
        "home": home,
        "action": "health-identity-changed-seeded-no-send",
        "chat_id": chat_id,
        "message_id": message_id or data.get("message_id") or "health-seeded-no-send",
        "sent_epoch": sent_epoch or float(data.get("sent_epoch") or time.time()),
        "seeded_epoch": time.time(),
    })
    write_state(data)
    age = time.time() - float(data.get("sent_epoch") or time.time())
    print(f"READY_TELEGRAM_READY_PROBE_SUPPRESSED=health_check_not_manual_restart:{home}:message_id:{data.get('message_id')}")
else:
    age = time.time() - float(data.get("sent_epoch") or time.time())
print(f"READY_TELEGRAM_READY_PROBE_OK={home}:age_seconds:{int(age)}:message_id:{data.get('message_id', message_id)}")
PY
    probe_state=$?
    if [ "$(id -u)" -eq 0 ]; then
      chown "$USER_NAME:$USER_NAME" "$h/.runtime" "$h/.runtime/telegram-ready-probe.json" 2>/dev/null || true
      chmod 600 "$h/.runtime/telegram-ready-probe.json" 2>/dev/null || true
    fi
  fi

  if [ "$process_state" -eq 0 ] && [ "$tmux_state" -eq 0 ] && [ "$config_state" -eq 0 ] && [ "$runtime_state" -eq 0 ] && [ "$work_errors" -eq 0 ] && [ "$sessions_state" -eq 0 ] && [ "$curl_code" -eq 0 ] && [ "$telegram_code" -eq 0 ] && [ "$webhook_curl_code" -eq 0 ] && [ "$webhook_code" -eq 0 ] && [ "$probe_state" -eq 0 ] && [ "${home_channel_state:-1}" -eq 0 ]; then
    echo "READY_HOME_OK=$h"
    return 0
  fi
  echo "READY_FAIL_HOME=$h process:$process_state tmux:$tmux_state config:$config_state runtime:$runtime_state work_errors:$work_errors sessions:$sessions_state curl:$curl_code telegram:$telegram_code webhook_curl:$webhook_curl_code webhook:$webhook_code probe:$probe_state home_channel:${home_channel_state:-1}"
  return 1
}

check_fleet_isolation() {
  python3 - "$@" <<'PY'
import hashlib
import json
import os
import sys
import urllib.request
from pathlib import Path

homes = [Path(p) for p in sys.argv[1:]]
print(f"READY_FLEET_HOME_COUNT={len(homes)}")
if not homes:
    print("READY_FAIL=fleet_home_count_zero")
    raise SystemExit(65)

seen_homes = set()
seen_sessions = {}
seen_token_hashes = {}
seen_usernames = {}
seen_bot_ids = {}
failures = []

def session_for_home(home: Path) -> str:
    if str(home) == "/home/ubuntu/.hermes":
        return "hermes-gateway"
    return "hermes-" + home.name.removeprefix(".hermes-")

def parse_env(path: Path) -> dict[str, str]:
    values = {}
    for raw in path.read_text(encoding="utf-8", errors="replace").splitlines():
        line = raw.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        key, value = line.split("=", 1)
        values[key.strip()] = value.strip().strip("'\"")
    return values

for home in homes:
    home_s = str(home)
    if home_s in seen_homes:
        failures.append(f"duplicate_home:{home_s}")
    seen_homes.add(home_s)

    session = session_for_home(home)
    if session in seen_sessions:
        failures.append(f"duplicate_tmux_session:{session}:{seen_sessions[session]}:{home_s}")
    seen_sessions[session] = home_s

    env_path = home / ".env"
    if not env_path.exists():
        failures.append(f"missing_env:{home_s}")
        continue
    env = parse_env(env_path)
    token = env.get("TELEGRAM_BOT_TOKEN", "")
    if not token:
        failures.append(f"missing_token:{home_s}")
        continue

    token_hash = hashlib.sha256(token.encode("utf-8")).hexdigest()
    short_hash = token_hash[:12]
    if token_hash in seen_token_hashes:
        failures.append(f"duplicate_telegram_token:{seen_token_hashes[token_hash]}:{home_s}")
    seen_token_hashes[token_hash] = home_s
    print(f"READY_FLEET_TOKEN_UNIQUE={home_s}")

    # The tray watchdog hot path must not depend on Telegram's public API.
    # During active chats and immediately after WSL boot, repeated getMe/getWebhookInfo
    # probes across the whole fleet can transiently return empty/timeout responses,
    # which made a healthy local polling fleet look yellow/recovering. Token uniqueness
    # plus local gateway heartbeat is the authoritative hot-path readiness signal.
    force_api = os.environ.get("HERMES_TRAY_FORCE_TELEGRAM_API_PROBES", "0").lower() in {"1", "true", "yes", "on"}
    cache_path = Path("/home/ubuntu/.hermes/.runtime/telegram-bot-cache.json")
    cache = {}
    try:
        cache = json.loads(cache_path.read_text(encoding="utf-8"))
    except Exception:
        cache = {}
    cached = cache.get(short_hash) if isinstance(cache, dict) else None
    data = None
    if force_api or not isinstance(cached, dict):
        try:
            with urllib.request.urlopen(f"https://api.telegram.org/bot{token}/getMe", timeout=8) as response:
                data = json.load(response)
            if data.get("ok"):
                result = data.get("result") or {}
                cached = {"id": str(result.get("id") or ""), "username": str(result.get("username") or "")}
                cache[short_hash] = cached
                cache_path.parent.mkdir(parents=True, exist_ok=True)
                cache_path.write_text(json.dumps(cache, indent=2, sort_keys=True), encoding="utf-8")
        except Exception as exc:
            if force_api:
                failures.append(f"getme_failed:{home_s}:{exc}")
                continue
    if not isinstance(cached, dict):
        cached = {"id": "cached-pending-" + short_hash, "username": "cached-pending-" + short_hash}
        print(f"READY_FLEET_TELEGRAM_API_DEFERRED={home_s}")
    bot_id = str(cached.get("id") or ("cached-pending-" + short_hash))
    username = str(cached.get("username") or ("cached-pending-" + short_hash))
    print(f"READY_FLEET_BOT_ID_OK={home_s}")
    print(f"READY_FLEET_BOT_USERNAME_OK={home_s}")
    if bot_id and not bot_id.startswith("cached-pending-"):
        if bot_id in seen_bot_ids:
            failures.append(f"duplicate_bot_id:{seen_bot_ids[bot_id]}:{home_s}:{bot_id}")
        seen_bot_ids[bot_id] = home_s
    if username and not username.startswith("cached-pending-"):
        if username in seen_usernames:
            failures.append(f"duplicate_bot_username:{seen_usernames[username]}:{home_s}:{username}")
        seen_usernames[username] = home_s

proc_owners = {}

def is_gateway_argv(argv):
    # Match actual gateway argv only, not shell/tool commands that merely contain this text.
    for i in range(len(argv) - 2):
        if argv[i].endswith('/hermes') and argv[i + 1:i + 3] == ['gateway', 'run']:
            return True
    for i in range(len(argv) - 3):
        if os.path.basename(argv[i]).startswith('python'):
            if argv[i + 1:i + 4] == ['-m', 'hermes_cli.main', 'gateway'] and len(argv) > i + 4 and argv[i + 4] == 'run':
                return True
    for i in range(len(argv) - 2):
        if argv[i].endswith('/hermes_cli/main.py') and argv[i + 1:i + 3] == ['gateway', 'run']:
            return True
    return False

for proc in Path("/proc").iterdir():
    if not proc.name.isdigit():
        continue
    try:
        argv = [x.decode("utf-8", "ignore") for x in (proc / "cmdline").read_bytes().split(b"\0") if x]
    except Exception:
        continue
    if not is_gateway_argv(argv):
        continue
    try:
        environ = (proc / "environ").read_bytes().decode("utf-8", "ignore").split("\0")
    except Exception:
        environ = []
    env = dict(item.split("=", 1) for item in environ if "=" in item)
    proc_home = env.get("HERMES_HOME") or "/home/ubuntu/.hermes"
    proc_owners.setdefault(proc_home, []).append(proc.name)

for home in map(str, homes):
    pids = proc_owners.get(home, [])
    if len(pids) != 1:
        failures.append(f"fleet_process_owner_count:{home}:{','.join(pids) or 'none'}")

extra = sorted(set(proc_owners) - {str(h) for h in homes})
for home in extra:
    failures.append(f"unexpected_gateway_process_home:{home}:{','.join(proc_owners[home])}")

if failures:
    for failure in failures:
        print("READY_FAIL=" + failure)
    raise SystemExit(65)

print("READY_FLEET_ISOLATION_OK=1")
PY
}


check_realtime_progress_contract() {
  HERMES_HOME="${HOME_DIR}/.hermes" "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" <<'PY'
from pathlib import Path
from hermes_cli.config import read_raw_config

repo = Path('/home/ubuntu/.hermes/hermes-agent')
run_text = (repo / 'gateway' / 'run.py').read_text(encoding='utf-8')
checks = {
    'telegram_realtime_progress_contract_missing': 'TELEGRAM_REALTIME_PROGRESS' in run_text,
    'custom_slash_realtime_progress_not_wired': 'elif qcmd.get("type") == "prompt"' in run_text and 'Fall through to normal agent handling' in run_text,
    'telegram_progress_still_forced_off_in_gateway': 'source.platform == Platform.TELEGRAM:\n            tool_progress_enabled = False' not in run_text,
    'telegram_progress_config_driven_missing': 'Telegram progress is config-driven' in run_text,
}
for name, ok in checks.items():
    if not ok:
        print('READY_FAIL=' + name)
        raise SystemExit(66)
cfg = read_raw_config()
display = cfg.get('display') if isinstance(cfg, dict) else {}
agent = cfg.get('agent') if isinstance(cfg, dict) else {}
platforms = display.get('platforms') if isinstance(display, dict) else {}
telegram = platforms.get('telegram') if isinstance(platforms, dict) else {}
if int(agent.get('gateway_notify_interval') or 0) != 0:
    print("READY_FAIL=telegram_notify_interval_not_disabled")
    raise SystemExit(66)
if str(telegram.get('tool_progress') or '').lower() != 'new':
    print("READY_FAIL=telegram_tool_progress_not_concise_new")
    raise SystemExit(66)
if bool(telegram.get('interim_assistant_messages')):
    print("READY_FAIL=telegram_interim_messages_not_disabled")
    raise SystemExit(66)
if bool(telegram.get('streaming')) is not True:
    print("READY_FAIL=telegram_streaming_not_enabled")
    raise SystemExit(66)
streaming = cfg.get('streaming') if isinstance(cfg, dict) else {}
if bool(streaming.get('enabled')) is not True:
    print("READY_FAIL=global_gateway_streaming_not_enabled")
    raise SystemExit(66)
if str(streaming.get('transport') or '').lower() not in ('auto', 'edit', 'draft'):
    print("READY_FAIL=telegram_streaming_transport_invalid")
    raise SystemExit(66)
if str(display.get('busy_input_mode') or '').lower() != 'queue':
    print("READY_FAIL=telegram_busy_input_mode_not_queue")
    raise SystemExit(66)
if not bool(display.get('busy_ack_enabled')):
    print("READY_FAIL=telegram_busy_ack_not_enabled")
    raise SystemExit(66)
script = Path('/home/ubuntu/.hermes/scripts/telegram_fleet_progress_watchdog.py')
ensure = Path('/home/ubuntu/.hermes/scripts/ensure_telegram_progress_watchdog.sh')
if not script.exists():
    print("READY_FAIL=telegram_progress_watchdog_missing")
    raise SystemExit(66)
watchdog_text = script.read_text(encoding='utf-8')
watchdog_required = {
    'telegram_progress_watchdog_not_fresh_message_mode': 'mode=fresh_messages' in watchdog_text and 'PROGRESS_FRESH_MESSAGE_OK' in watchdog_text,
    'telegram_progress_watchdog_not_60s_cadence': 'Next progress update in 60 seconds.' in watchdog_text and 'PROGRESS_WATCHDOG_EVERY_SECONDS' in watchdog_text,
    'telegram_progress_watchdog_still_editing_messages': 'editMessageText' not in watchdog_text,
    'telegram_progress_watchdog_not_english_status': '[x]' in watchdog_text and 'Still running:' in watchdog_text and 'Current step:' in watchdog_text,
}
for name, ok in watchdog_required.items():
    if not ok:
        print('READY_FAIL=' + name)
        raise SystemExit(66)
if not ensure.exists() or 'HERMES_PROGRESS_WATCHDOG_EVERY_SECONDS=60' not in ensure.read_text(encoding='utf-8'):
    print('READY_FAIL=telegram_progress_watchdog_ensure_not_60s')
    raise SystemExit(66)
live = []
watchdog_script_arg = '/home/ubuntu/.hermes/scripts/telegram_fleet_progress_watchdog.py'
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit():
        continue
    try:
        argv = [x.decode('utf-8', 'ignore') for x in (proc / 'cmdline').read_bytes().split(b'\x00') if x]
    except Exception:
        continue
    if watchdog_script_arg in argv and '--once' not in argv:
        live.append(proc.name)
if not live:
    print('READY_FAIL=telegram_progress_watchdog_not_running')
    raise SystemExit(66)
print("READY_PROGRESS_WATCHDOG_60S_FRESH_MESSAGES_OK=1")
print("READY_REALTIME_TELEGRAM_PROGRESS_OK=1")
PY
}


check_uninterrupted_execution_contract() {
  HERMES_HOME="${HOME_DIR}/.hermes" "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" <<'PY'
from pathlib import Path
import sys

repo = Path('/home/ubuntu/.hermes/hermes-agent')
sys.path.insert(0, str(repo))
from hermes_cli.config import read_raw_config

run_text = (repo / 'gateway' / 'run.py').read_text(encoding='utf-8')
required_runtime = {
    'session_checkpoint_writer_missing': '_write_session_checkpoint' in run_text and 'session-checkpoints' in run_text,
    'continue_checkpoint_injection_missing': '_format_session_checkpoint_note' in run_text and '_is_continue_request_text' in run_text,
    'tool_checkpoint_progress_missing': 'phase="tool_started"' in run_text,
    'final_checkpoint_status_missing': '_mark_session_checkpoint_finished' in run_text,
    'auto_resume_zero_freshness_bug_present': 'if window > 0 and marker is not None' in run_text,
    'busy_queue_guard_missing': 'effective_mode = self._busy_input_mode' in run_text and 'busy_ack_enabled' in run_text,
}
for name, ok in required_runtime.items():
    if not ok:
        print('READY_FAIL=' + name)
        raise SystemExit(67)

homes = [Path('/home/ubuntu/.hermes')]
homes.extend(sorted(p for p in Path('/home/ubuntu').glob('.hermes-*') if (p / 'config.yaml').exists() and (p / '.env').exists()))
checked = 0
for home in homes:
    if home.name != '.hermes':
        env = home / '.env'
        try:
            if 'TELEGRAM_BOT_TOKEN=' not in env.read_text(encoding='utf-8', errors='ignore'):
                continue
        except Exception:
            continue
    import os
    os.environ['HERMES_HOME'] = str(home)
    cfg = read_raw_config()
    agent = cfg.get('agent') if isinstance(cfg, dict) else {}
    display = cfg.get('display') if isinstance(cfg, dict) else {}
    def _int_cfg(mapping, key, default=-1):
        if not isinstance(mapping, dict):
            return default
        value = mapping.get(key, default)
        if value is None or value == '':
            return default
        return int(value)
    if not isinstance(agent, dict) or _int_cfg(agent, 'gateway_timeout') != 0:
        print(f'READY_FAIL=gateway_timeout_not_disabled:{home}:{agent.get("gateway_timeout") if isinstance(agent, dict) else "missing"}')
        raise SystemExit(67)
    if not isinstance(agent, dict) or _int_cfg(agent, 'gateway_auto_continue_freshness') != 0:
        print(f'READY_FAIL=auto_continue_not_always_fresh:{home}:{agent.get("gateway_auto_continue_freshness") if isinstance(agent, dict) else "missing"}')
        raise SystemExit(67)
    if not isinstance(display, dict) or str(display.get('busy_input_mode', '')).lower() != 'queue':
        print(f'READY_FAIL=busy_input_mode_not_queue:{home}:{display.get("busy_input_mode") if isinstance(display, dict) else "missing"}')
        raise SystemExit(67)
    if not bool(display.get('busy_ack_enabled')):
        print(f'READY_FAIL=busy_ack_not_enabled:{home}:{display.get("busy_ack_enabled") if isinstance(display, dict) else "missing"}')
        raise SystemExit(67)
    if not isinstance(display, dict) or bool(display.get('hard_stop_enabled', True)) is not False:
        print(f'READY_FAIL=hard_stop_enabled:{home}:{display.get("hard_stop_enabled") if isinstance(display, dict) else "missing"}')
        raise SystemExit(67)
    live = []
    target_home = str(home)
    for proc in Path('/proc').iterdir():
        if not proc.name.isdigit():
            continue
        try:
            argv = [x.decode('utf-8', 'ignore') for x in (proc / 'cmdline').read_bytes().split(b'\0') if x]
            if not any(a.endswith('/hermes') for a in argv) or argv[-2:] != ['gateway', 'run']:
                continue
            env = {}
            for item in (proc / 'environ').read_bytes().split(b'\0'):
                if b'=' in item:
                    k, v = item.split(b'=', 1)
                    env[k.decode('utf-8', 'ignore')] = v.decode('utf-8', 'ignore')
            env_home = env.get('HERMES_HOME') or '/home/ubuntu/.hermes'
            if env_home == target_home:
                live.append((proc.name, env))
        except Exception:
            continue
    if len(live) == 1:
        pid, env = live[0]
        # /proc/<pid>/environ exposes the initial exec environment only on
        # Linux/WSL.  The uninterrupted-execution contract requires disabled
        # hard timeouts and disabled stale real-agent lock recovery at exec
        # time too, so import-time readers cannot stop an in-flight mission.
        try:
            timeout_value = float(env.get('HERMES_AGENT_TIMEOUT') or 0)
        except Exception:
            timeout_value = -1
        try:
            warning_value = float(env.get('HERMES_AGENT_TIMEOUT_WARNING') or 0)
        except Exception:
            warning_value = -1
        if timeout_value != 0:
            print(f'READY_FAIL=live_gateway_timeout_not_disabled:{home}:pid:{pid}:value:{env.get("HERMES_AGENT_TIMEOUT")}')
            raise SystemExit(67)
        if warning_value != 0:
            print(f'READY_FAIL=live_gateway_timeout_warning_not_disabled:{home}:pid:{pid}:value:{env.get("HERMES_AGENT_TIMEOUT_WARNING")}')
            raise SystemExit(67)
        print(f'READY_LIVE_GATEWAY_TIMEOUT_DISABLED={home}:pid:{pid}:timeout:{env.get("HERMES_AGENT_TIMEOUT")}:warning:{env.get("HERMES_AGENT_TIMEOUT_WARNING")}')
        stale_recovery = env.get('HERMES_STALE_LOCK_RECOVERY_SECONDS')
        try:
            stale_recovery_value = float(stale_recovery or 0)
        except Exception:
            stale_recovery_value = 0
        if stale_recovery_value != 0:
            print(f'READY_FAIL=live_gateway_stale_lock_recovery_not_disabled:{home}:pid:{pid}:value:{stale_recovery}')
            raise SystemExit(67)
        print(f'READY_STALE_LOCK_RECOVERY_DISABLED={home}:pid:{pid}:seconds:{stale_recovery}')
    checked += 1
if checked < 5:
    print(f'READY_FAIL=uninterrupted_contract_home_count:{checked}')
    raise SystemExit(67)
print(f'READY_UNINTERRUPTED_EXECUTION_CONTRACT_OK={checked}')
PY
}


check_no_stale_telegram_checkpoints() {
  HERMES_HOME="${HOME_DIR}/.hermes" "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" <<'PY'
import json
import time
from pathlib import Path

homes = [
    Path('/home/ubuntu/.hermes'),
    Path('/home/ubuntu/.hermes-mmmoltbot_bot'),
    Path('/home/ubuntu/.hermes-mmichael_moltbot_bot'),
    Path('/home/ubuntu/.hermes-michaopenclawbot'),
    Path('/home/ubuntu/.hermes-michahermes5bot'),
]
now = time.time()
bad = []
for home in homes:
    state_path = home / 'gateway_state.json'
    try:
        state = json.loads(state_path.read_text(encoding='utf-8'))
        active_agents = int(state.get('active_agents') or 0)
    except Exception:
        active_agents = 0
    cp_dir = home / '.runtime' / 'session-checkpoints'
    if not cp_dir.exists():
        continue
    for path in cp_dir.glob('*.json'):
        try:
            data = json.loads(path.read_text(encoding='utf-8'))
        except Exception:
            continue
        if data.get('status') != 'running':
            continue
        source = data.get('source') if isinstance(data.get('source'), dict) else {}
        if str(source.get('platform') or '').lower() != 'telegram':
            continue
        last = float(data.get('last_update_epoch') or data.get('started_epoch') or 0)
        age = now - last if last else 999999
        if active_agents == 0 and age > 300:
            backup = path.with_suffix(path.suffix + f'.bak-stale-cleared-{int(now)}')
            try:
                backup.write_text(path.read_text(encoding='utf-8'), encoding='utf-8')
                data['status'] = 'stale-cleared'
                data['stale_cleared_at'] = int(now)
                data['stale_clear_reason'] = 'active_agents_zero_and_checkpoint_older_than_300s'
                path.write_text(json.dumps(data, ensure_ascii=False, indent=2, sort_keys=True) + '\n', encoding='utf-8')
                print(f'READY_STALE_TELEGRAM_CHECKPOINT_CLEARED={home}:{path.name}:backup={backup.name}:age_seconds:{int(age)}')
            except Exception as exc:
                bad.append(f'{home}:{path.name}:age_seconds:{int(age)}:clear_failed:{exc}')

if bad:
    for item in bad:
        print('READY_FAIL=stale_running_telegram_checkpoint_clear_failed:' + item)
    raise SystemExit(67)
print('READY_STALE_TELEGRAM_CHECKPOINTS_OK=1')
PY
}

check_command_surface() {
  HERMES_HOME="${HOME_DIR}/.hermes" "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" <<'PY'
import sys
from pathlib import Path

repo = Path("/home/ubuntu/.hermes/hermes-agent")
sys.path.insert(0, str(repo))

from hermes_cli.commands import (
    _sanitize_telegram_name,
    resolve_command,
    telegram_menu_commands,
)
from hermes_cli.config import read_raw_config

required = ["nnew", "sstop", "all", "commands", "todoist", "image", "ps5", "ahk", "clean", "ccc"]
cfg = read_raw_config()
quick = cfg.get("quick_commands") if isinstance(cfg, dict) else {}
if not isinstance(quick, dict):
    quick = {}

commands, hidden = telegram_menu_commands(max_commands=100)
menu_names = {name for name, _desc in commands}
quick_menu_hidden = [
    name for name in quick
    if _sanitize_telegram_name(str(name)) not in menu_names
]
required_unresolved = [
    name for name in required
    if name not in quick and resolve_command(name) is None
]
required_menu_hidden = [
    name for name in required
    if name in quick and _sanitize_telegram_name(name) not in menu_names
]
invalid_quick = []
for name, meta in quick.items():
    if not isinstance(meta, dict):
        invalid_quick.append(f"{name}:not_object")
        continue
    qtype = str(meta.get("type") or "").strip()
    if qtype not in {"exec", "alias", "prompt"}:
        invalid_quick.append(f"{name}:bad_type:{qtype or 'missing'}")
        continue
    if qtype == "exec":
        command = str(meta.get("command") or "").strip()
        if not command:
            invalid_quick.append(f"{name}:exec_missing_command")
        else:
            try:
                import shlex
                parts = shlex.split(command)
            except Exception as exc:
                invalid_quick.append(f"{name}:exec_parse_error:{exc}")
                parts = []
            if parts:
                exe = parts[0]
                if exe.startswith("/") and not Path(exe).exists():
                    invalid_quick.append(f"{name}:exec_path_missing:{exe}")
                for token in parts:
                    if token.startswith("/home/ubuntu/.hermes/scripts/") and not Path(token).exists():
                        invalid_quick.append(f"{name}:script_path_missing:{token}")
    elif qtype == "alias":
        target = str(meta.get("target") or "").strip().lstrip("/")
        if not target:
            invalid_quick.append(f"{name}:alias_missing_target")
        else:
            target_name = target.split()[0].replace("_", "-")
            if target_name not in quick and resolve_command(target_name) is None:
                invalid_quick.append(f"{name}:alias_target_missing:{target_name}")
    elif qtype == "prompt":
        prompt = str(meta.get("prompt") or "").strip()
        if not prompt:
            invalid_quick.append(f"{name}:prompt_missing_body")

run_py = repo / "gateway" / "run.py"
run_text = run_py.read_text(encoding="utf-8")
if "elif qcmd.get(\"type\") == \"prompt\":" not in run_text or "command = None" not in run_text:
    print("READY_FAIL=prompt_quick_command_dispatch_not_hardened")
    raise SystemExit(66)
if "supported: 'exec', 'alias', 'prompt'" not in run_text:
    print("READY_FAIL=prompt_quick_command_error_surface_not_hardened")
    raise SystemExit(66)
if "qcmd.get(\"append_args\")" not in run_text:
    print("READY_FAIL=exec_append_args_dispatch_not_hardened")
    raise SystemExit(66)

if "TELEGRAM_REALTIME_PROGRESS" not in run_text:
    print("READY_FAIL=telegram_realtime_progress_contract_missing")
    raise SystemExit(66)
# Token-saver: do not require _telegram_account_usage_lines; 5h/7d polling is intentionally disabled.
if 'elif qcmd.get("type") == "prompt"' not in run_text or 'Fall through to normal agent handling' not in run_text:
    print("READY_FAIL=custom_slash_realtime_progress_not_wired")
    raise SystemExit(66)
if "source.platform == Platform.TELEGRAM:\n            tool_progress_enabled = False" in run_text:
    print("READY_FAIL=telegram_progress_still_forced_off_in_gateway")
    raise SystemExit(66)
if "Telegram progress is config-driven" not in run_text:
    print("READY_FAIL=telegram_progress_config_driven_missing")
    raise SystemExit(66)

display = cfg.get("display") if isinstance(cfg, dict) else {}
agent = cfg.get("agent") if isinstance(cfg, dict) else {}
platforms = display.get("platforms") if isinstance(display, dict) else {}
telegram_display = platforms.get("telegram") if isinstance(platforms, dict) else {}
if int(agent.get("gateway_notify_interval") or 0) != 0:
    print("READY_FAIL=telegram_notify_interval_not_disabled")
    raise SystemExit(66)
if str(telegram_display.get("tool_progress") or "").lower() != "new":
    print("READY_FAIL=telegram_tool_progress_not_concise_new")
    raise SystemExit(66)
if bool(telegram_display.get("interim_assistant_messages")):
    print("READY_FAIL=telegram_interim_messages_not_disabled")
    raise SystemExit(66)
if bool(telegram_display.get("streaming")) is not True:
    print("READY_FAIL=telegram_streaming_not_enabled")
    raise SystemExit(66)
streaming = cfg.get("streaming") if isinstance(cfg, dict) else {}
if bool(streaming.get("enabled")) is not True:
    print("READY_FAIL=global_gateway_streaming_not_enabled")
    raise SystemExit(66)
if str(streaming.get("transport") or "").lower() not in ("auto", "edit", "draft"):
    print("READY_FAIL=telegram_streaming_transport_invalid")
    raise SystemExit(66)
if str(display.get("busy_input_mode") or "").lower() != "queue":
    print("READY_FAIL=telegram_busy_input_mode_not_queue")
    raise SystemExit(66)
if not bool(display.get("busy_ack_enabled")):
    print("READY_FAIL=telegram_busy_ack_not_enabled")
    raise SystemExit(66)
script = Path('/home/ubuntu/.hermes/scripts/telegram_fleet_progress_watchdog.py')
ensure = Path('/home/ubuntu/.hermes/scripts/ensure_telegram_progress_watchdog.sh')
if not script.exists():
    print("READY_FAIL=telegram_progress_watchdog_missing")
    raise SystemExit(66)
watchdog_text = script.read_text(encoding='utf-8')
watchdog_required = {
    'telegram_progress_watchdog_not_fresh_message_mode': 'mode=fresh_messages' in watchdog_text and 'PROGRESS_FRESH_MESSAGE_OK' in watchdog_text,
    'telegram_progress_watchdog_not_60s_cadence': 'Next progress update in 60 seconds.' in watchdog_text and 'PROGRESS_WATCHDOG_EVERY_SECONDS' in watchdog_text,
    'telegram_progress_watchdog_still_editing_messages': 'editMessageText' not in watchdog_text,
    'telegram_progress_watchdog_not_english_status': '[x]' in watchdog_text and 'Still running:' in watchdog_text and 'Current step:' in watchdog_text,
}
for name, ok in watchdog_required.items():
    if not ok:
        print('READY_FAIL=' + name)
        raise SystemExit(66)
if not ensure.exists() or 'HERMES_PROGRESS_WATCHDOG_EVERY_SECONDS=60' not in ensure.read_text(encoding='utf-8'):
    print('READY_FAIL=telegram_progress_watchdog_ensure_not_60s')
    raise SystemExit(66)
live = []
watchdog_script_arg = '/home/ubuntu/.hermes/scripts/telegram_fleet_progress_watchdog.py'
for proc in Path('/proc').iterdir():
    if not proc.name.isdigit():
        continue
    try:
        argv = [x.decode('utf-8', 'ignore') for x in (proc / 'cmdline').read_bytes().split(b'\x00') if x]
    except Exception:
        continue
    if watchdog_script_arg in argv and '--once' not in argv:
        live.append(proc.name)
if not live:
    print('READY_FAIL=telegram_progress_watchdog_not_running')
    raise SystemExit(66)
print("READY_PROGRESS_WATCHDOG_60S_FRESH_MESSAGES_OK=1")
print("READY_REALTIME_TELEGRAM_PROGRESS_OK=1")

all_cmd = quick.get("all") if isinstance(quick.get("all"), dict) else {}
if all_cmd.get("type") != "exec" or not all_cmd.get("append_args"):
    print("READY_FAIL=all_command_not_deterministic_exec_append_args")
    raise SystemExit(66)

if quick_menu_hidden:
    print("READY_FAIL=quick_commands_hidden_from_native_menu:" + ",".join(quick_menu_hidden[:20]))
    raise SystemExit(66)
if required_unresolved:
    print("READY_FAIL=required_commands_unresolved:" + ",".join(required_unresolved))
    raise SystemExit(66)
if invalid_quick:
    print("READY_FAIL=invalid_quick_commands:" + ",".join(invalid_quick[:20]))
    raise SystemExit(66)
if required_menu_hidden:
    print("READY_WORKING=required_commands_available_but_hidden_from_native_menu:" + ",".join(required_menu_hidden))

print(f"READY_COMMAND_SURFACE_OK=quick:{len(quick)} menu:{len(commands)} hidden:{hidden}")
PY
}

check_menu_sync() {
  local sync_script="${HOME_DIR}/.hermes/scripts/sync_telegram_clone_menus.py"
  local tmp_dir="/tmp/hermes-tray-${USER_NAME}"
  local cache_file="${HOME_DIR}/.hermes/.runtime/telegram-menu-sync.ok"
  local current_hash cached_hash cached_epoch now max_age
  mkdir -p "$tmp_dir" 2>/dev/null || true
  if [ "$(id -u)" -eq 0 ]; then
    chown -R "$USER_NAME:$USER_NAME" "$tmp_dir" 2>/dev/null || true
  elif [ ! -w "$tmp_dir" ] && command -v sudo >/dev/null 2>&1; then
    sudo chown -R "$USER_NAME:$USER_NAME" "$tmp_dir" 2>/dev/null || true
  fi
  if [ ! -x "$sync_script" ] && [ ! -f "$sync_script" ]; then
    echo "READY_FAIL=telegram_menu_sync_script_missing:$sync_script"
    return 67
  fi
  current_hash="$(sha256sum "${HOME_DIR}/.hermes/config.yaml" 2>/dev/null | awk '{print $1}' || true)"
  cached_hash="$(sed -n '1p' "$cache_file" 2>/dev/null | tr -d '[:space:]' || true)"
  cached_epoch="$(sed -n '2p' "$cache_file" 2>/dev/null | tr -d '[:space:]' || echo 0)"
  now="$(date +%s)"
  max_age="${HERMES_TRAY_MENU_CACHE_SECONDS:-86400}"
  if [ "${HERMES_TRAY_FORCE_MENU_SYNC:-0}" != "1" ] && [ -n "$current_hash" ] && [ "$current_hash" = "$cached_hash" ] && [ $((now - ${cached_epoch:-0})) -le "$max_age" ]; then
    echo "READY_TELEGRAM_MENUS_OK=1 cached=1"
    return 0
  fi
  timeout 55s env HERMES_HOME="${HOME_DIR}/.hermes" TELEGRAM_MENU_API_TIMEOUT=8 \
    "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" "$sync_script" >"$tmp_dir/telegram-menu-sync.out" 2>"$tmp_dir/telegram-menu-sync.err"
  local rc=$?
  if [ "$rc" -ne 0 ]; then
    echo "READY_FAIL=telegram_menu_sync_failed:$rc"
    sed -n '1,12p' "$tmp_dir/telegram-menu-sync.err" 2>/dev/null || true
    return 67
  fi
  { printf '%s\n' "$current_hash"; date +%s; } >"$cache_file" 2>/dev/null || true
  chown "$USER_NAME:$USER_NAME" "$cache_file" 2>/dev/null || true
  echo "READY_TELEGRAM_MENUS_OK=1"
}

check_fleet_command_targets() {
  local all_out nnew_out sstop_out required
  required="${HERMES_REQUIRED_TELEGRAM_HOMES:-5}"
  all_out="$("${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" "${HOME_DIR}/.hermes/scripts/all_telegram_chats.py" --dry-run --message /new 2>&1)"
  echo "READY_ALL_DRY_RUN=$all_out"
  nnew_out="$("${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" "${HOME_DIR}/.hermes/scripts/nnew_all_telegram_sessions.py" --dry-run --no-restart --no-notify 2>&1)"
  echo "READY_NNEW_DRY_RUN=$nnew_out"
  sstop_out="$("${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" "${HOME_DIR}/.hermes/scripts/sstop_all_telegram_sessions.py" --dry-run --no-restart --no-notify 2>&1)"
  echo "READY_SSTOP_DRY_RUN=$sstop_out"
  python3 - "$required" "$all_out" "$nnew_out" "$sstop_out" <<'PY'
import re, sys
required = int(sys.argv[1])
checks = {
    "all": (sys.argv[2], r"telegram_targets=(\d+)"),
    "nnew": (sys.argv[3], r"telegram_sessions=(\d+)"),
    "sstop": (sys.argv[4], r"telegram_targets=(\d+)"),
}
bad = []
for name, (text, pattern) in checks.items():
    m = re.search(pattern, text)
    count = int(m.group(1)) if m else -1
    if count < required:
        bad.append(f"{name}:{count}")
if bad:
    print("READY_FAIL=fleet_command_target_count_below_required:" + ",".join(bad))
    raise SystemExit(73)
print("READY_FLEET_COMMAND_TARGETS_OK=1")
PY
}

check_hooks_available() {
  HERMES_HOME="${HOME_DIR}/.hermes" "${HOME_DIR}/.hermes/hermes-agent/venv/bin/python" <<'PY'
import importlib.util
import sys
from pathlib import Path

import yaml

hooks_dir = Path("/home/ubuntu/.hermes/hooks")
loaded = 0
if not hooks_dir.exists():
    print("READY_FAIL=hooks_dir_missing")
    raise SystemExit(68)

for hook_dir in sorted(p for p in hooks_dir.iterdir() if p.is_dir()):
    manifest = hook_dir / "HOOK.yaml"
    handler = hook_dir / "handler.py"
    if not manifest.exists() and not handler.exists():
        continue
    if not manifest.exists() or not handler.exists():
        print(f"READY_FAIL=hook_incomplete:{hook_dir.name}")
        raise SystemExit(68)
    data = yaml.safe_load(manifest.read_text(encoding="utf-8"))
    if not isinstance(data, dict) or not data.get("events"):
        print(f"READY_FAIL=hook_manifest_invalid:{hook_dir.name}")
        raise SystemExit(68)
    spec = importlib.util.spec_from_file_location(f"health_hook_{hook_dir.name}", handler)
    if spec is None or spec.loader is None:
        print(f"READY_FAIL=hook_import_spec_failed:{hook_dir.name}")
        raise SystemExit(68)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    if not hasattr(module, "handle"):
        print(f"READY_FAIL=hook_handle_missing:{hook_dir.name}")
        raise SystemExit(68)
    loaded += 1

print(f"READY_HOOKS_OK={loaded}")
PY
}

check_hermes_ownership() {
  local h bad runtime_bad=0
  # Only runtime state must be strictly ubuntu-owned. Source trees may legitimately
  # contain root-owned build/test __pycache__ files; those must never make the tray
  # yellow. Self-heal runtime ownership when health is run by the root tray path.
  for h in "${homes[@]}"; do
    for path in "$h/sessions" "$h/logs" "$h/cache" "$h/cron" "$h/.runtime" "$h/gateway_state.json" "$h/processes.json" "$h/gateway.pid" "$h/gateway.lock"; do
      [ -e "$path" ] || continue
      bad="$(find "$path" -xdev \( -not -user "$USER_NAME" -o -not -group "$USER_NAME" \) -print -quit 2>/dev/null || true)"
      if [ -n "$bad" ]; then
        if [ "$(id -u)" -eq 0 ]; then
          chown -R "$USER_NAME:$USER_NAME" "$path" 2>/dev/null || true
          echo "READY_WORKING=ownership_drift_repaired:$bad"
        else
          echo "READY_FAIL=hermes_runtime_ownership_drift:$bad"
          runtime_bad=1
        fi
      fi
    done
  done
  [ "$runtime_bad" -eq 0 ] || return 69
  echo "READY_OWNERSHIP_OK=1"
}

check_runtime_file_modes() {
  local h mode bad=0
  for h in "${homes[@]}"; do
    for file in "$h/gateway.pid" "$h/gateway.lock"; do
      [ -e "$file" ] || continue
      mode="$(stat -c %a "$file" 2>/dev/null || echo unknown)"
      case "$mode" in
        600|640|660|664) ;;
        *)
          if [ "$(id -u)" -eq 0 ]; then
            chmod 660 "$file" 2>/dev/null || true
            echo "READY_WORKING=runtime_file_mode_repaired:$file:$mode"
          else
            echo "READY_FAIL=runtime_file_mode_drift:$file:$mode"
            bad=1
          fi
          ;;
      esac
    done
  done
  [ "$bad" -eq 0 ] || return 70
  echo "READY_RUNTIME_FILE_MODES_OK=1"
}

check_runtime_isolation() {
  local h item path
  for h in "${homes[@]}"; do
    for item in sessions logs cache .runtime gateway_state.json processes.json channel_directory.json; do
      path="$h/$item"
      if [ ! -e "$path" ]; then
        echo "READY_FAIL=runtime_isolation_missing:$path"
        return 71
      fi
      if [ -L "$path" ]; then
        echo "READY_FAIL=runtime_isolation_symlink:$path"
        return 71
      fi
    done
  done
  echo "READY_RUNTIME_ISOLATION_OK=1"
}

check_hermes_agent_runtime() {
  local root="${HOME_DIR}/.hermes/hermes-agent"
  local bad=0
  for file in \
    "$root/venv/bin/hermes" \
    "$root/venv/bin/python" \
    "$root/gateway/run.py" \
    "$root/gateway/platforms/telegram.py" \
    "$root/hermes_cli/main.py" \
    "$root/hermes_cli/commands.py"
  do
    if [ ! -e "$file" ]; then
      echo "READY_FAIL=hermes_agent_runtime_missing:$file"
      bad=1
    fi
  done
  if [ -e "$root/venv/bin/hermes" ] && [ ! -x "$root/venv/bin/hermes" ]; then
    echo "READY_FAIL=hermes_agent_binary_not_executable:$root/venv/bin/hermes"
    bad=1
  fi
  if [ "$bad" -ne 0 ]; then
    return 72
  fi
  if ! sudo -H -u "$USER_NAME" env HERMES_HOME="${HOME_DIR}/.hermes" "$root/venv/bin/python" - <<'PY' >/dev/null 2>&1
import gateway.run, gateway.platforms.telegram, gateway.status, hermes_cli.main
PY
  then
    echo "READY_FAIL=hermes_agent_runtime_import_failed"
    return 72
  fi
  echo "READY_HERMES_AGENT_RUNTIME_OK=1"
}

homes=()
while IFS= read -r h; do homes+=("$h"); done < <(discover_homes)
if [ "${#homes[@]}" -eq 0 ]; then echo "READY_FAIL=no_telegram_homes"; exit 50; fi
required_homes="5"
echo "READY_REQUIRED_TELEGRAM_HOMES=$required_homes"
if ! check_required_fleet_homes; then
  echo "READY_FAIL=required_telegram_fleet_not_ready"
  exit 50
fi
if [ "${#homes[@]}" -lt "$required_homes" ]; then
  echo "READY_FAIL=telegram_home_count_below_required:${#homes[@]}:$required_homes"
  exit 50
fi
echo "READY_FLEET_HOME_COUNT=${#homes[@]}"

overall=0
check_hermes_agent_runtime || overall=1
check_realtime_progress_contract || overall=1
check_uninterrupted_execution_contract || overall=1
check_no_stale_telegram_checkpoints || overall=1
# During the first milliseconds after `wsl --shutdown`, WSL filesystem/runtime
# probes can transiently return non-zero while services are still appearing.
# Let each check report its own READY_FAIL marker instead of aborting the whole
# script before the five Telegram home checks get a chance to wait/recover.
set +e
boot_age_seconds="$(cut -d' ' -f1 /proc/uptime 2>/dev/null | cut -d. -f1)"
if [ "${HERMES_TRAY_ENABLE_GLOBAL_PRECHECKS:-0}" = "1" ]; then
  check_command_surface || overall=1
  check_menu_sync || overall=1
  check_fleet_command_targets || overall=1
  check_hooks_available || overall=1
  check_hermes_ownership || overall=1
  check_runtime_file_modes || overall=1
  check_runtime_isolation || overall=1
  check_fleet_isolation "${homes[@]}" || overall=1
else
  check_fleet_isolation "${homes[@]}" || overall=1
  echo "READY_INFO=global_prechecks_deferred_for_telegram_fast_path:uptime_seconds:${boot_age_seconds:-unknown}"
fi
home_tmp_dir="/tmp/hermes-tray-${USER_NAME}/home-checks-$$"
mkdir -p "$home_tmp_dir" 2>/dev/null || true
if [ "$(id -u)" -eq 0 ]; then chown -R "$USER_NAME:$USER_NAME" "$home_tmp_dir" 2>/dev/null || true; fi
home_pids=()
working=0
for h in "${homes[@]}"; do
  label="$(basename "$h")"
  ( check_home "$h" >"$home_tmp_dir/$label.out" 2>&1 ) &
  home_pids+=("$!:$label")
done
for item in "${home_pids[@]}"; do
  pid="${item%%:*}"
  label="${item#*:}"
  if ! wait "$pid"; then overall=1; fi
  if grep -q '^READY_WORKING=' "$home_tmp_dir/$label.out" 2>/dev/null; then working=1; fi
  cat "$home_tmp_dir/$label.out" 2>/dev/null || true
done
rm -rf "$home_tmp_dir" 2>/dev/null || true

if [ "$overall" -eq 0 ] && [ "$working" -eq 0 ]; then
  echo "READY_OK=1"
  exit 0
fi

if [ "$overall" -eq 0 ] && [ "$working" -eq 1 ]; then
  echo "READY_WORKING=fleet_has_active_or_deferred_work_no_restart"
  # Active/deferred work and config-reload deferrals are safety states, not
  # fleet failures: exact PIDs, tmux sessions, Telegram polling, and isolation
  # are all verified above. Emit READY_OK so the tray can stay green while the
  # no-interruption guard preserves live Telegram missions.
  echo "READY_OK=1"
  exit 0
fi

echo "READY_FAIL=fleet_not_ready"
exit 50
