param(
  [int]$Port = 9119,
  [string]$Distro = "Ubuntu",
  [string]$WslUser = "ubuntu",
  [string]$HermesHome = "/home/ubuntu/.hermes-mmichael_moltbot_bot",
  [string]$HermesProject = "/home/ubuntu/.hermes/hermes-agent",
  [string]$HermesBin = "/home/ubuntu/.local/bin/hermes",
  [string]$OpenUrlScript = "/home/ubuntu/.hermes/scripts/open_url_on_second_monitor.sh",
  [string]$DashboardPath = "/",
  [switch]$GlobalDashboard
)

$ErrorActionPreference = 'Stop'
$Url = "http://127.0.0.1:$Port"
$Session = "hermes-dashboard-$Port"
$GlobalSession = "hermes-dashboard-global-$Port"
$GlobalLog = "$HermesHome/logs/dashboard-global-url.log"

function Quote-Bash([string]$Value) {
  # Bash-safe single-quote wrapper. Embedded ' becomes: '\''
  return "'" + ($Value -replace "'", "'`"'`"'") + "'"
}

function Invoke-WslBash([string]$Script) {
  $wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
  if (-not (Test-Path -LiteralPath $wsl -PathType Leaf)) { $wsl = 'wsl.exe' }

  # Do not pass a large multi-line Bash program through `bash -lc`: Windows
  # command-line quoting can corrupt embedded quotes. Write a temp .sh and run it.
  $tmp = Join-Path $PSScriptRoot (".open-hermes-dashboard.$PID.sh")
  try {
    $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
    [System.IO.File]::WriteAllText($tmp, $Script, $utf8NoBom)
    if ($tmp -notmatch '^([A-Za-z]):\\(.*)$') {
      throw "Cannot convert temp script path to WSL path: $tmp"
    }
    $drive = $Matches[1].ToLowerInvariant()
    $rest = '/' + ($Matches[2] -replace '\\', '/')
    $wslPath = "/mnt/$drive$rest"
    & $wsl -d $Distro -u $WslUser -- bash $wslPath
    if ($LASTEXITCODE -ne 0) {
      throw "WSL command failed with exit code $LASTEXITCODE"
    }
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

Write-Host "Hermes Dashboard launcher"
Write-Host "URL: $Url"
Write-Host "Mode: $(if ($GlobalDashboard) { 'global tunnel URL' } else { 'local Windows browser URL' })"
Write-Host "Policy: opens the latest Hermes web dashboard with the embedded TUI Chat tab enabled, using real Windows Chrome Profile 2 on monitor 2 via open_url_on_second_monitor.sh; no cloned/sandbox --user-data-dir."

$template = @'
set -Eeuo pipefail
PORT=__PORT__
URL=__URL__
SESSION=__SESSION__
GLOBAL_MODE=__GLOBAL_MODE__
GLOBAL_SESSION=__GLOBAL_SESSION__
GLOBAL_LOG=__GLOBAL_LOG__
USER_HOME=__USER_HOME__
HERMES_HOME_DIR=__HERMES_HOME__
HERMES_PROJECT=__HERMES_PROJECT__
HERMES_BIN=__HERMES_BIN__
OPEN_URL_SCRIPT=__OPEN_URL_SCRIPT__
DASHBOARD_PATH=__DASHBOARD_PATH__
PATH_VALUE="$USER_HOME/.local/bin:$USER_HOME/.hermes/node/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/snap/bin"
LOG_DIR="$HERMES_HOME_DIR/logs"
LOG_FILE="$LOG_DIR/dashboard-run.log"
DASHBOARD_HOST="127.0.0.1"
DASHBOARD_FLAGS="--tui"

log() { printf '[%s] %s\n' "$(date -Iseconds)" "$*"; }
api_ok() { curl -fsS --max-time 2 "$URL/api/status" >/dev/null 2>&1; }
append_dashboard_path() {
  local base="$1" path="${2:-/}"
  if [ -z "$path" ] || [ "$path" = "/" ]; then
    printf '%s\n' "$base"
    return 0
  fi
  case "$path" in
    /*) ;;
    *) path="/$path" ;;
  esac
  printf '%s%s\n' "${base%/}" "$path"
}

[ -x "$HERMES_BIN" ] || { echo "ERROR: Hermes binary not executable: $HERMES_BIN" >&2; exit 11; }
[ -d "$HERMES_PROJECT" ] || { echo "ERROR: Hermes project directory missing: $HERMES_PROJECT" >&2; exit 12; }
[ -d "$HERMES_HOME_DIR" ] || { echo "ERROR: Hermes home missing: $HERMES_HOME_DIR" >&2; exit 13; }
[ -x "$OPEN_URL_SCRIPT" ] || { echo "ERROR: monitor-2 Chrome Profile 2 opener missing/not executable: $OPEN_URL_SCRIPT" >&2; exit 14; }
command -v curl >/dev/null || { echo "ERROR: missing curl" >&2; exit 15; }
command -v tmux >/dev/null || { echo "ERROR: missing tmux" >&2; exit 16; }
ensure_frontend_assets() {
  local dist="$HERMES_PROJECT/hermes_cli/web_dist"
  if [ -s "$dist/index.html" ] && compgen -G "$dist/assets/index-*.js" >/dev/null && compgen -G "$dist/assets/index-*.css" >/dev/null; then
    return 0
  fi
  local node_ver="v22.21.1"
  local node_root="$USER_HOME/.hermes/node"
  local node_bin="$node_root/bin"
  export PATH="$node_bin:$PATH"
  if ! command -v node >/dev/null || ! command -v npm >/dev/null; then
    command -v curl >/dev/null || { echo "ERROR: Dashboard frontend missing and curl unavailable to bootstrap Node." >&2; exit 17; }
    local arch="x64"
    case "$(uname -m)" in
      x86_64|amd64) arch="x64" ;;
      aarch64|arm64) arch="arm64" ;;
      *) echo "ERROR: Unsupported architecture for Node bootstrap: $(uname -m)" >&2; exit 17 ;;
    esac
    local dl="$USER_HOME/.hermes/node-download"
    mkdir -p "$dl"
    local tarball="node-${node_ver}-linux-${arch}.tar.xz"
    if [ ! -s "$dl/$tarball" ]; then
      curl -fsSLo "$dl/$tarball" "https://nodejs.org/dist/${node_ver}/${tarball}"
    fi
    rm -rf "$dl/node-${node_ver}-linux-${arch}" "$node_root.tmp"
    tar -C "$dl" -xf "$dl/$tarball"
    mv "$dl/node-${node_ver}-linux-${arch}" "$node_root.tmp"
    rm -rf "$node_root"
    mv "$node_root.tmp" "$node_root"
    export PATH="$node_bin:$PATH"
  fi
  command -v node >/dev/null || { echo "ERROR: Dashboard frontend missing and node bootstrap failed." >&2; exit 17; }
  command -v npm >/dev/null || { echo "ERROR: Dashboard frontend missing and npm bootstrap failed." >&2; exit 17; }
  command -v git >/dev/null || { echo "ERROR: Dashboard frontend missing and git unavailable for source fetch." >&2; exit 17; }
  local src="$USER_HOME/.cache/hermes-dashboard-web-src"
  rm -rf "$src"
  git clone --depth 1 --filter=blob:none --sparse https://github.com/NousResearch/hermes-agent.git "$src" >/dev/null
  git -C "$src" sparse-checkout set web >/dev/null
  (cd "$src/web" && npm ci >/dev/null && npm run build >/dev/null)
  [ -s "$src/hermes_cli/web_dist/index.html" ] || { echo "ERROR: Dashboard frontend build did not produce web_dist/index.html." >&2; exit 17; }
  rm -rf "$dist"
  mkdir -p "$(dirname "$dist")"
  cp -a "$src/hermes_cli/web_dist" "$dist"
}
ensure_frontend_assets
mkdir -p "$LOG_DIR"

if [ "$GLOBAL_MODE" = "1" ]; then
  DASHBOARD_HOST="0.0.0.0"
  DASHBOARD_FLAGS="--insecure --tui"
  log "Global mode requested; restarting dashboard with public-host support."
  tmux has-session -t "=$SESSION" >/dev/null 2>&1 && tmux kill-session -t "$SESSION" >/dev/null 2>&1 || true
  # A dashboard can be running outside the expected tmux session (for example
  # from an older tray launch). If it keeps port 9119, the public tunnel reaches
  # that host-restricted instance and returns "Invalid Host header". Force-clear
  # the port in global mode so the next block starts the --host 0.0.0.0
  # --insecure dashboard that is meant to sit behind localhost.run.
  if command -v fuser >/dev/null 2>&1; then
    fuser -k "${PORT}/tcp" >/dev/null 2>&1 || true
  else
    python3 - <<'PY' "$PORT" || true
import os, signal, socket, struct, sys
port_hex = f'{int(sys.argv[1]):04X}'
inodes = set()
for table in ('/proc/net/tcp', '/proc/net/tcp6'):
    try:
        lines = open(table).read().splitlines()[1:]
    except OSError:
        continue
    for line in lines:
        parts = line.split()
        if len(parts) > 9 and parts[1].split(':')[-1].upper() == port_hex:
            inodes.add(parts[9])
for pid in filter(str.isdigit, os.listdir('/proc')):
    fd_dir = f'/proc/{pid}/fd'
    try:
        fds = os.listdir(fd_dir)
    except OSError:
        continue
    for fd in fds:
        try:
            target = os.readlink(f'{fd_dir}/{fd}')
        except OSError:
            continue
        if target.startswith('socket:[') and target[8:-1] in inodes:
            try:
                os.kill(int(pid), signal.SIGTERM)
            except OSError:
                pass
            break
PY
  fi
  sleep 1
fi

if api_ok; then
  log "Hermes dashboard is already running at $URL; opening browser."
else
  log "Hermes dashboard is not running at $URL; starting tmux session $SESSION."
  tmux has-session -t "=$SESSION" >/dev/null 2>&1 && tmux kill-session -t "$SESSION" >/dev/null 2>&1 || true
  tmux new-session -d -s "$SESSION" "cd '$HERMES_PROJECT' && export HOME='$USER_HOME' HERMES_HOME='$HERMES_HOME_DIR' PATH='$PATH_VALUE' PYTHONUNBUFFERED=1 && exec '$HERMES_BIN' dashboard --no-open --host '$DASHBOARD_HOST' --port '__PORT__' $DASHBOARD_FLAGS >>'$LOG_FILE' 2>&1"
  deadline=$((SECONDS + 90))
  until api_ok; do
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "ERROR: Hermes dashboard did not become ready at $URL within 90 seconds." >&2
      echo "Last dashboard log lines ($LOG_FILE):" >&2
      tail -120 "$LOG_FILE" >&2 || true
      exit 20
    fi
    sleep 1
  done
  log "Hermes dashboard is ready at $URL."
fi

if [ "$GLOBAL_MODE" = "1" ]; then
  command -v ssh >/dev/null || { echo "ERROR: global dashboard needs ssh for localhost.run, but ssh is missing." >&2; exit 30; }
  log "Starting global dashboard tunnel with localhost.run."
  tmux has-session -t "=$GLOBAL_SESSION" >/dev/null 2>&1 && tmux kill-session -t "$GLOBAL_SESSION" >/dev/null 2>&1 || true
  : > "$GLOBAL_LOG"
  tmux new-session -d -s "$GLOBAL_SESSION" "exec ssh -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ServerAliveInterval=15 -T -R 80:127.0.0.1:'$PORT' nokey@localhost.run >>'$GLOBAL_LOG' 2>&1"
  deadline=$((SECONDS + 120))
  GLOBAL_URL=""
  until [ -n "$GLOBAL_URL" ]; do
    GLOBAL_URL="$( (grep -Eo 'https://[A-Za-z0-9.-]+\.lhr\.life' "$GLOBAL_LOG" 2>/dev/null || true) | tail -1 | tr -d '\r')"
    if [ -n "$GLOBAL_URL" ]; then break; fi
    if ! tmux has-session -t "=$GLOBAL_SESSION" >/dev/null 2>&1; then
      echo "ERROR: global dashboard tunnel exited before producing a URL." >&2
      cat "$GLOBAL_LOG" >&2 || true
      exit 31
    fi
    if [ "$SECONDS" -ge "$deadline" ]; then
      echo "ERROR: global dashboard tunnel did not produce a URL within 120 seconds." >&2
      cat "$GLOBAL_LOG" >&2 || true
      exit 32
    fi
    sleep 1
  done
  printf '%s\n' "$GLOBAL_URL" > "$HERMES_HOME_DIR/logs/dashboard-global-url.txt"
  TARGET_URL="$(append_dashboard_path "$GLOBAL_URL" "$DASHBOARD_PATH")"
  log "Global dashboard URL: $TARGET_URL"
  echo "GLOBAL_DASHBOARD_URL=$TARGET_URL"
  "$OPEN_URL_SCRIPT" "$TARGET_URL"
else
  TARGET_URL="$(append_dashboard_path "$URL" "$DASHBOARD_PATH")"
  "$OPEN_URL_SCRIPT" "$TARGET_URL"
fi

chat_flag="$(curl -fsS --max-time 5 "$URL/chat" | python3 -c 'import re,sys; html=sys.stdin.read(); m=re.search(r"window\.__HERMES_DASHBOARD_EMBEDDED_CHAT__=(true|false)", html); print(m.group(1) if m else "missing")')"
[ "$chat_flag" = "true" ] || { echo "ERROR: Dashboard Chat/TUI tab is not enabled (flag=$chat_flag)." >&2; exit 21; }
curl -fsS --max-time 5 "$URL/api/status" | python3 -c 'import json,sys; d=json.load(sys.stdin); print("Dashboard OK: version=%s hermes_home=%s gateway_state=%s active_sessions=%s chat_tab=enabled" % (d.get("version"), d.get("hermes_home"), d.get("gateway_state"), d.get("active_sessions")))'
'@

$bashScript = $template.Replace('__PORT__', [string]$Port).
  Replace('__URL__', (Quote-Bash $Url)).
  Replace('__SESSION__', (Quote-Bash $Session)).
  Replace('__GLOBAL_MODE__', $(if ($GlobalDashboard) { '1' } else { '0' })).
  Replace('__GLOBAL_SESSION__', (Quote-Bash $GlobalSession)).
  Replace('__GLOBAL_LOG__', (Quote-Bash $GlobalLog)).
  Replace('__USER_HOME__', (Quote-Bash "/home/$WslUser")).
  Replace('__HERMES_HOME__', (Quote-Bash $HermesHome)).
  Replace('__HERMES_PROJECT__', (Quote-Bash $HermesProject)).
  Replace('__HERMES_BIN__', (Quote-Bash $HermesBin)).
  Replace('__OPEN_URL_SCRIPT__', (Quote-Bash $OpenUrlScript)).
  Replace('__DASHBOARD_PATH__', (Quote-Bash $DashboardPath))

Invoke-WslBash $bashScript
