#!/usr/bin/env bash
###############################################################################
# a.sh - THE ULTIMATE ONE-SCRIPT LOCAL AI AGENT INSTALLER (v11)
#
# What this script does (on a fresh WSL2 Ubuntu):
#   1.  Installs ALL system dependencies (with real-time progress)
#   2.  Installs CUDA toolkit if NVIDIA GPU detected (with progress)
#   3.  Builds llama.cpp from source with GPU support (with progress)
#   4.  Downloads the best model your hardware can run (with progress)
#   5.  Configures passwordless sudo for the agent
#   6.  Installs win-tools (Windows operations via PowerShell)
#   7.  Installs verified Chrome Profile 2 URL opening and capability checks
#   8.  Installs Playwright for advanced browser automation
#   9.  Installs the resilient autonomous AI agent (llama-agent v11)
#  10.  Configures PATH, LD_LIBRARY_PATH, and .wslconfig
#  11.  Runs end-to-end tests
#
# Usage from WSL2:
#   bash /path/to/a.sh
#   bash /path/to/a.sh --launch
#
# Usage from Windows PowerShell (Admin):
#   wsl -d Ubuntu -- bash /mnt/f/path/to/a.sh
#
# PowerShell launcher note:
#   A wrapper must forward ValueFromRemainingArguments positionally. Passing a
#   named -RemainingArguments token through to Bash is interpreted as invalid
#   Bash option -R before this script can start.
#
# After install:
#   source ~/.bashrc && llama
###############################################################################

# Launchers such as systemd-run may omit HOME or set it to "/". Resolve the
# effective account's real home before staging or creating any installer state.
EFFECTIVE_HOME=$(awk -F: -v uid="$(id -u)" '$3 == uid { print $6; exit }' \
    /etc/passwd 2>/dev/null || true)
if [ -n "$EFFECTIVE_HOME" ]; then
    export HOME="$EFFECTIVE_HOME"
fi

# Long installers must not keep reading executable source through WSL's
# Windows-drive bridge. Stage the exact bytes atomically on Linux ext4 and
# execute that immutable copy. The content hash keeps concurrent versions
# separate and also preserves the install provenance contract below.
if [[ "${BASH_SOURCE[0]}" == /mnt/* ]] && [ -f "${BASH_SOURCE[0]}" ]; then
    STAGE_DIR="$HOME/.local/share/llama-agent/installer-sources"
    mkdir -p "$STAGE_DIR" || {
        printf 'Cannot create the Linux installer staging directory: %s\n' "$STAGE_DIR" >&2
        exit 2
    }
    STAGE_SOURCE_HASH=$(sha256sum "${BASH_SOURCE[0]}" 2>/dev/null | {
        read -r hash _ || true
        printf '%s' "$hash"
    })
    if [ -z "$STAGE_SOURCE_HASH" ]; then
        printf 'Cannot hash the installer before staging it from the Windows drive.\n' >&2
        exit 2
    fi
    STAGED_INSTALLER="$STAGE_DIR/a-${STAGE_SOURCE_HASH}.sh"
    STAGED_SOURCE_HASH=$(sha256sum "$STAGED_INSTALLER" 2>/dev/null | {
        read -r hash _ || true
        printf '%s' "$hash"
    })
    if [ "$STAGED_SOURCE_HASH" != "$STAGE_SOURCE_HASH" ]; then
        STAGED_INSTALLER_NEXT="${STAGED_INSTALLER}.next.$$"
        if ! cp "${BASH_SOURCE[0]}" "$STAGED_INSTALLER_NEXT"; then
            rm -f "$STAGED_INSTALLER_NEXT"
            printf 'Cannot create a verified Linux copy of the installer.\n' >&2
            exit 2
        fi
        STAGED_NEXT_HASH=$(sha256sum "$STAGED_INSTALLER_NEXT" 2>/dev/null | {
            read -r hash _ || true
            printf '%s' "$hash"
        })
        if [ "$STAGED_NEXT_HASH" != "$STAGE_SOURCE_HASH" ]; then
            rm -f "$STAGED_INSTALLER_NEXT"
            printf 'The Linux installer copy failed its byte-integrity check.\n' >&2
            exit 2
        fi
        chmod 700 "$STAGED_INSTALLER_NEXT"
        mv -f "$STAGED_INSTALLER_NEXT" "$STAGED_INSTALLER"
    fi
    exec bash "$STAGED_INSTALLER" "$@"
fi

set -Eeo pipefail

# Keep the PowerShell launcher argument-only. Complex shell source passed
# through PowerShell -> wsl.exe -> bash loses quoting and can become empty.
launch_local_ai() {
    local installer stamp record record_source record_agent
    local current_source current_agent model

    installer=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
    stamp="$HOME/.local/share/llama-agent/installed-source.sha256"
    record=$(cat "$stamp" 2>/dev/null || true)
    record_source=${record%%|*}
    record_agent=${record#*|}
    current_source=$(sha256sum "$installer" 2>/dev/null || true)
    current_source=${current_source%% *}
    current_agent=$(sha256sum "$HOME/.local/bin/llama-agent" 2>/dev/null || true)
    current_agent=${current_agent%% *}
    model=$(find "$HOME/models" -maxdepth 1 -name '*.gguf' -type f -print -quit 2>/dev/null || true)

    if [ ! -x "$HOME/.local/bin/llama-agent" ] ||
       [ ! -x "$HOME/.local/bin/llama" ] ||
       [ -z "$model" ] ||
       [ -z "$record_source" ] ||
       [ "$record_source" != "$current_source" ] ||
       [ "$record_agent" != "$current_agent" ]; then
        printf 'The Local AI installation is missing or outdated; checking the serialized installer now.\n'
        if ! bash "$installer"; then
            printf 'The Local AI installer stopped without committing a verified installation.\n' >&2
            return 1
        fi
    fi

    record=$(cat "$stamp" 2>/dev/null || true)
    record_source=${record%%|*}
    record_agent=${record#*|}
    current_source=$(sha256sum "$installer" 2>/dev/null || true)
    current_source=${current_source%% *}
    current_agent=$(sha256sum "$HOME/.local/bin/llama-agent" 2>/dev/null || true)
    current_agent=${current_agent%% *}
    if [ -z "$record_source" ] ||
       [ "$record_source" != "$current_source" ] ||
       [ "$record_agent" != "$current_agent" ]; then
        printf 'The Local AI installer returned without committing the exact current source and agent hashes.\n' >&2
        return 1
    fi
    if [ ! -x "$HOME/.local/bin/llama" ]; then
        printf 'Local AI installation finished without creating %s.\n' \
            "$HOME/.local/bin/llama" >&2
        return 1
    fi
    if ! find "$HOME/models" -maxdepth 1 -name '*.gguf' -type f -print -quit |
         grep -q .; then
        printf 'Local AI installation finished without an installed model.\n' >&2
        return 1
    fi

    exec "$HOME/.local/bin/llama" "$@"
}

if [ "${1:-}" = "--launch" ]; then
    shift
    launch_local_ai "$@"
fi

# Serialize full installs so concurrent `llm` launches cannot race apt, builds,
# agent replacement, or acceptance tests. A waiter reports changing facts and
# reuses an exact completed deployment instead of doing the same work twice.
INSTALL_SOURCE_PATH=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
INSTALL_START_SOURCE_HASH=$(sha256sum "$INSTALL_SOURCE_PATH" 2>/dev/null | {
    read -r hash _ || true
    printf '%s' "$hash"
})
INSTALL_STATE_DIR="$HOME/.local/share/llama-agent"
INSTALL_LOCK_FILE="$INSTALL_STATE_DIR/install.lock"
INSTALL_STAMP="$INSTALL_STATE_DIR/installed-source.sha256"
mkdir -p "$INSTALL_STATE_DIR"
if ! command -v flock >/dev/null 2>&1; then
    printf 'Cannot safely start the Local AI installation because the system lock tool is unavailable.\n' >&2
    exit 1
fi
exec 8>"$INSTALL_LOCK_FILE"
INSTALL_LOCK_WAITED=0
INSTALL_LOCK_WAIT_SECONDS=0
if ! flock -n 8; then
    INSTALL_LOCK_WAITED=1
    while ! flock -n 8; do
        sleep 2
        INSTALL_LOCK_WAIT_SECONDS=$((INSTALL_LOCK_WAIT_SECONDS + 2))
        if [ -t 1 ]; then
            printf '\r\033[2K[WORKING] Another Local AI installation owns the update lock; waited %d seconds. This process has not started duplicate package or build work.' \
                "$INSTALL_LOCK_WAIT_SECONDS"
        elif [ "$INSTALL_LOCK_WAIT_SECONDS" -eq 2 ] ||
             [ $((INSTALL_LOCK_WAIT_SECONDS % 30)) -eq 0 ]; then
            printf '[WORKING] Another Local AI installation owns the update lock; waited %d seconds. This process has not started duplicate package or build work.\n' \
                "$INSTALL_LOCK_WAIT_SECONDS"
        fi
    done
    if [ -t 1 ]; then
        printf '\r\033[2K'
    fi
    printf '[DONE] The existing Local AI installation released the update lock after %d seconds.\n' \
        "$INSTALL_LOCK_WAIT_SECONDS"
fi
if [ "$INSTALL_LOCK_WAITED" -eq 1 ]; then
    INSTALL_LOCKED_SOURCE_HASH=$(sha256sum "$INSTALL_SOURCE_PATH" 2>/dev/null | {
        read -r hash _ || true
        printf '%s' "$hash"
    })
    if [ "$INSTALL_LOCKED_SOURCE_HASH" != "$INSTALL_START_SOURCE_HASH" ]; then
        printf 'The installer source changed while this process waited. No installation was started; launch it again to use one consistent source version.\n' >&2
        exit 1
    fi
    INSTALLED_AGENT_HASH=$(sha256sum "$HOME/.local/bin/llama-agent" 2>/dev/null | {
        read -r hash _ || true
        printf '%s' "$hash"
    })
    INSTALL_RECORD=$(cat "$INSTALL_STAMP" 2>/dev/null || true)
    if [ -n "$INSTALL_START_SOURCE_HASH" ] &&
       [ "$INSTALL_RECORD" = "$INSTALL_START_SOURCE_HASH|$INSTALLED_AGENT_HASH" ]; then
        printf '[DONE] The completed installation already deployed this exact source and agent; no duplicate installation is needed.\n'
        exit 0
    fi
    printf '[WORKING] The earlier installer did not commit this exact source, so this process is starting one recovery installation now.\n'
fi

# Keep output immediate even when this script is piped through another process.
export PYTHONUNBUFFERED=1
export FORCE_COLOR=1

PROGRESS_FILE=$(mktemp)
PROGRESS_DETAIL_FILE=$(mktemp)
PROGRESS_PAUSE_FILE=$(mktemp)
PROGRESS_OUTPUT_LOCK="${PROGRESS_FILE}.output-lock"
PROGRESS_PID=""
PROGRESS_LOG_HEARTBEAT_SECONDS="${LOCAL_AI_PROGRESS_LOG_HEARTBEAT_SECONDS:-8}"
if ! [[ "$PROGRESS_LOG_HEARTBEAT_SECONDS" =~ ^[0-9]+$ ]] ||
   [ "$PROGRESS_LOG_HEARTBEAT_SECONDS" -lt 1 ] ||
   [ "$PROGRESS_LOG_HEARTBEAT_SECONDS" -gt 8 ]; then
    PROGRESS_LOG_HEARTBEAT_SECONDS=8
fi
read -r INSTALL_STARTED_UPTIME _ < /proc/uptime
INSTALL_STARTED_S=${INSTALL_STARTED_UPTIME%.*}
MAIN_INSTALL_PID=$$
PROGRESS_TTY_FD=""
if [ -t 1 ]; then
    if { exec 9>/dev/tty; } 2>/dev/null; then
        PROGRESS_TTY_FD=9
    fi
fi

acquire_progress_output() {
    while ! mkdir "$PROGRESS_OUTPUT_LOCK" 2>/dev/null; do
        sleep 0.01
    done
}

release_progress_output() {
    rmdir "$PROGRESS_OUTPUT_LOCK" 2>/dev/null || true
}

set_activity() {
    printf '%s\n' "$*" > "${PROGRESS_FILE}.next"
    mv -f "${PROGRESS_FILE}.next" "$PROGRESS_FILE"
    : > "${PROGRESS_DETAIL_FILE}.next"
    mv -f "${PROGRESS_DETAIL_FILE}.next" "$PROGRESS_DETAIL_FILE"
    rm -f "$PROGRESS_PAUSE_FILE"
}

set_download_progress() {
    printf '%s|%s\n' "$1" "$2" > "${PROGRESS_DETAIL_FILE}.next"
    mv -f "${PROGRESS_DETAIL_FILE}.next" "$PROGRESS_DETAIL_FILE"
}

clear_download_progress() {
    : > "${PROGRESS_DETAIL_FILE}.next"
    mv -f "${PROGRESS_DETAIL_FILE}.next" "$PROGRESS_DETAIL_FILE"
}

progress_clock() {
    local now_s now_ms elapsed_s activity uptime_now
    local detail download_file download_expected download_bytes
    local previous_download_file="" previous_download_bytes=0 previous_sample_ms=0
    local download_status="" download_line="" semantic="" line="" columns=160
    local max_chars clipped word_boundary
    local last_activity="" last_semantic="" last_logged_ms=0 should_emit=0
    local observation_bucket=0 observation_from=0 observation_to=0
    local last_visible_line=""
    declare -A logged_lines=()
    while true; do
        activity=$(cat "$PROGRESS_FILE" 2>/dev/null || echo "Installer process is alive; its first named operation has not started")
        read -r uptime_now _ < /proc/uptime
        now_s=${uptime_now%.*}
        now_ms=$(( now_s * 1000 ))
        elapsed_s=$(( now_s - INSTALL_STARTED_S ))
        download_status=""
        detail=$(cat "$PROGRESS_DETAIL_FILE" 2>/dev/null || true)
        if [ -n "$detail" ]; then
            download_file=${detail%%|*}
            download_expected=${detail#*|}
            download_bytes=$(stat -c %s "$download_file" 2>/dev/null || echo 0)
            if [ "$download_file" != "$previous_download_file" ]; then
                previous_download_file="$download_file"
                previous_download_bytes="$download_bytes"
                previous_sample_ms="$now_ms"
            fi
            download_status=$(awk \
                -v done="${download_bytes:-0}" \
                -v total="${download_expected:-0}" \
                -v before="${previous_download_bytes:-0}" \
                -v elapsed_ms="$(( now_ms - previous_sample_ms ))" '
                BEGIN {
                    percent = total > 0 ? int(done * 100 / total) : 0
                    rate = elapsed_ms > 0 ? (done - before) * 1000 / elapsed_ms / 1048576 : 0
                    printf "Downloaded %.2f of %.2f GiB (%d%%), %.1f MiB/s", \
                        done/1073741824, total/1073741824, percent, rate
                }')
            previous_download_bytes="$download_bytes"
            previous_sample_ms="$now_ms"
        else
            previous_download_file=""
            previous_download_bytes=0
            previous_sample_ms="$now_ms"
        fi
        if [ -n "$download_status" ]; then
            download_line="[WORKING] $download_status"
            line="$download_line | $activity"
            semantic="$download_status|$activity"
        else
            download_line=""
            line="[WORKING] $activity"
            semantic="$activity"
        fi
        observation_bucket=$(( elapsed_s / PROGRESS_LOG_HEARTBEAT_SECONDS ))
        if [ "$observation_bucket" -gt 0 ] && [ -n "$download_status" ]; then
            observation_from=$(( (observation_bucket - 1) * PROGRESS_LOG_HEARTBEAT_SECONDS ))
            observation_to=$(( observation_bucket * PROGRESS_LOG_HEARTBEAT_SECONDS ))
            line="[WORKING] Seconds ${observation_from}-${observation_to}: ${download_status}. Current installer operation: ${activity}"
            semantic="${semantic}|observation:${observation_bucket}"
        fi
        acquire_progress_output
        if [ ! -e "$PROGRESS_PAUSE_FILE" ]; then
            if [ -n "$PROGRESS_TTY_FD" ]; then
                columns=$(stty size </dev/tty 2>/dev/null | awk '{print $2}')
                [ -n "$columns" ] || columns=$(tput cols 2>/dev/null || echo 160)
                if ! [[ "${columns:-}" =~ ^[0-9]+$ ]] || [ "$columns" -lt 24 ]; then
                    columns=80
                fi
                if [ "${#line}" -ge "$columns" ]; then
                    if [ -n "$download_line" ] && [ "${#download_line}" -lt "$columns" ]; then
                        line="$download_line"
                    else
                        max_chars=$(( columns - 4 ))
                        clipped="${line:0:$max_chars}"
                        word_boundary="${clipped% *}"
                        if [ "${#word_boundary}" -ge $(( max_chars / 2 )) ]; then
                            clipped="$word_boundary"
                        fi
                        line="${clipped}..."
                    fi
                fi
                if [ "$line" != "$last_visible_line" ]; then
                    printf '\r\033[2K\033[2m%s\033[0m' "$line" >&9
                    last_visible_line="$line"
                fi
            else
                should_emit=0
                if [ "$activity" != "$last_activity" ]; then
                    should_emit=1
                elif [ "$semantic" != "$last_semantic" ] &&
                     [ $(( now_ms - last_logged_ms )) -ge $(( PROGRESS_LOG_HEARTBEAT_SECONDS * 1000 )) ]; then
                    should_emit=1
                fi
                if [ "$should_emit" -eq 1 ]; then
                    if [ -z "${logged_lines[$line]+x}" ]; then
                        printf '\033[2m%s\033[0m\n' "$line"
                        logged_lines["$line"]=1
                        last_logged_ms="$now_ms"
                    fi
                fi
            fi
        fi
        release_progress_output
        last_activity="$activity"
        last_semantic="$semantic"
        sleep 1
    done
}

stop_progress_clock() {
    if [ -n "${PROGRESS_PID:-}" ]; then
        kill "$PROGRESS_PID" 2>/dev/null || true
        wait "$PROGRESS_PID" 2>/dev/null || true
        PROGRESS_PID=""
    fi
    if [ -n "$PROGRESS_TTY_FD" ]; then
        printf '\r\033[2K' >&9
    fi
    rm -rf "$PROGRESS_OUTPUT_LOCK"
    rm -f "$PROGRESS_FILE" "$PROGRESS_DETAIL_FILE" "$PROGRESS_PAUSE_FILE" \
        "${PROGRESS_FILE}.next" "${PROGRESS_DETAIL_FILE}.next"
}

set_activity "Starting the Local AI installation and checking the machine"
progress_clock &
PROGRESS_PID=$!

# ─── Graceful Ctrl+C handling ───────────────────────────────────────────────
cleanup_on_exit() {
    stop_progress_clock
    echo ""
    echo -e "\033[0;33m[INTERRUPTED]\033[0m Install interrupted. Partial install may exist."
    echo -e "\033[0;37m  You can re-run this script — it will pick up where it left off.\033[0m"
    exit 130
}
trap cleanup_on_exit INT TERM
trap stop_progress_clock EXIT

# ─── Colours & helpers ──────────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; DIM='\033[2m'; NC='\033[0m'
INSTALLER_ERROR_REPORTED=0

clear_progress_line() {
    if [ -n "$PROGRESS_TTY_FD" ]; then
        printf '\r\033[2K' >&9
    fi
    return 0
}
event_time() { date '+%H:%M:%S.%3N' 2>/dev/null || date '+%H:%M:%S.000'; }

write_installer_event() {
    local keep_paused="$1" color="$2" label="$3"
    shift 3
    : > "$PROGRESS_PAUSE_FILE"
    acquire_progress_output
    clear_progress_line
    echo -e "${color}[${label} $(event_time)]${NC}  $*"
    release_progress_output
    [ "$keep_paused" -eq 1 ] || rm -f "$PROGRESS_PAUSE_FILE"
}

info()  { set_activity "$*"; write_installer_event 0 "$CYAN" INFO "$*"; }
ok()    { clear_download_progress; write_installer_event 1 "$GREEN" DONE "$*"; }
warn()  { clear_download_progress; write_installer_event 0 "$YELLOW" WARN "$*"; }
fail()  {
    INSTALLER_ERROR_REPORTED=1
    clear_download_progress
    write_installer_event 1 "$RED" FAIL "$*"
    exit 1
}

report_unhandled_installer_error() {
    local status="$1" line="$2" command="$3"
    [ "$status" -ne 0 ] || return 0
    if [ "$INSTALLER_ERROR_REPORTED" -eq 0 ]; then
        INSTALLER_ERROR_REPORTED=1
        set +e
        clear_download_progress
        stop_progress_clock
        printf '\n\033[0;31m[FAIL]\033[0m Installer command failed with exit code %s at line %s.\n' \
            "$status" "$line" >&2
        printf '       Command: %s\n' "$command" >&2
        printf '       Re-run the same a.sh; completed idempotent steps will be reused.\n' >&2
    fi
    exit "$status"
}
trap 'report_unhandled_installer_error "$?" "$LINENO" "$BASH_COMMAND"' ERR

# Windows executables launched from WSL depend on the kernel's WSLInterop
# binfmt handler. systemd lifecycle transitions can remove that handler while
# leaving /mnt/c and the executable files intact, so path checks and retries
# alone cannot recover. Probe the real boundary and reconstruct it when needed.
WINDOWS_POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
WINDOWS_CMD="/mnt/c/Windows/System32/cmd.exe"
WSL_INTEROP_ROOT="/proc/sys/fs/binfmt_misc"
WSL_INTEROP_RECORD="$WSL_INTEROP_ROOT/WSLInterop"
WSL_INTEROP_REGISTER="$WSL_INTEROP_ROOT/register"
WSL_INTEROP_RULE=":WSLInterop:M::MZ::/init:P"
WSL_INTEROP_GUARD="/usr/local/libexec/local-ai-wsl-interop-guard"

refresh_wsl_interop_environment() {
    if { [ -z "${WSL_INTEROP:-}" ] || [ ! -S "$WSL_INTEROP" ]; } &&
       [ -S /run/WSL/1_interop ]; then
        export WSL_INTEROP=/run/WSL/1_interop
    fi
}

windows_interop_probe() {
    local output
    refresh_wsl_interop_environment
    wsl_interop_record_ready || return 1
    [ -x "$WINDOWS_CMD" ] || return 1
    output=$(timeout 8s "$WINDOWS_CMD" /d /c \
        "echo LOCAL_AI_WINDOWS_INTEROP_OK" 2>/dev/null |
        tr -d '\r' | tail -1) || return 1
    [ "$output" = "LOCAL_AI_WINDOWS_INTEROP_OK" ]
}

wsl_interop_record_ready() {
    [ -r "$WSL_INTEROP_RECORD" ] &&
        grep -qx 'enabled' "$WSL_INTEROP_RECORD" &&
        grep -qx 'interpreter /init' "$WSL_INTEROP_RECORD" &&
        grep -qx 'flags: P' "$WSL_INTEROP_RECORD"
}

write_wsl_interop_control() {
    local path="$1" value="$2"
    sudo -n /usr/bin/python3 - "$path" "$value" <<'PYEOF'
import sys
with open(sys.argv[1], "w", encoding="ascii") as handle:
    handle.write(sys.argv[2] + "\n")
PYEOF
}

repair_wsl_interop_runtime() {
    windows_interop_probe && return 0
    [ -x /init ] || return 1

    if [ ! -e "$WSL_INTEROP_REGISTER" ]; then
        sudo -n /usr/bin/mkdir -p "$WSL_INTEROP_ROOT" || return 1
        sudo -n /usr/bin/mount -t binfmt_misc binfmt_misc "$WSL_INTEROP_ROOT" \
            >/dev/null 2>&1 || return 1
    fi
    [ -w "$WSL_INTEROP_REGISTER" ] || [ -e "$WSL_INTEROP_REGISTER" ] || return 1

    if [ -e "$WSL_INTEROP_RECORD" ]; then
        write_wsl_interop_control "$WSL_INTEROP_RECORD" -1 || return 1
    fi
    if [ ! -e "$WSL_INTEROP_RECORD" ]; then
        write_wsl_interop_control "$WSL_INTEROP_REGISTER" "$WSL_INTEROP_RULE" \
            || return 1
    elif grep -qx 'disabled' "$WSL_INTEROP_RECORD" 2>/dev/null; then
        write_wsl_interop_control "$WSL_INTEROP_RECORD" 1 || return 1
    fi

    wsl_interop_record_ready && windows_interop_probe
}

ensure_wsl_interop() {
    local attempt
    windows_interop_probe && return 0
    for attempt in 1 2 3; do
        set_activity "Repairing the WSL-to-Windows executable bridge; attempt $attempt of 3"
        if repair_wsl_interop_runtime; then
            return 0
        fi
        [ "$attempt" -eq 3 ] || sleep "$attempt"
    done
    return 1
}

install_wsl_interop_guard() {
    local guard_next service_next
    guard_next=$(mktemp)
    service_next=$(mktemp)
    cat > "$guard_next" <<'GUARDEOF'
#!/usr/bin/env bash
set -uo pipefail

root="${LOCAL_AI_BINFMT_ROOT:-/proc/sys/fs/binfmt_misc}"
record="$root/WSLInterop"
register="$root/register"
rule=":WSLInterop:M::MZ::/init:P"
windows_cmd="${LOCAL_AI_WINDOWS_CMD:-/mnt/c/Windows/System32/cmd.exe}"

if { [ -z "${WSL_INTEROP:-}" ] || [ ! -S "$WSL_INTEROP" ]; } &&
   [ -S /run/WSL/1_interop ]; then
    export WSL_INTEROP=/run/WSL/1_interop
fi

as_root() {
    if [ "${EUID:-$(id -u)}" -eq 0 ]; then
        "$@"
    else
        sudo -n "$@"
    fi
}

write_control() {
    local path="$1" value="$2"
    as_root /usr/bin/python3 - "$path" "$value" <<'PYEOF'
import sys
with open(sys.argv[1], "w", encoding="ascii") as handle:
    handle.write(sys.argv[2] + "\n")
PYEOF
}

probe() {
    local output
    record_ready || return 1
    [ -x "$windows_cmd" ] || return 1
    output=$(timeout 8s "$windows_cmd" /d /c \
        "echo LOCAL_AI_WINDOWS_INTEROP_OK" 2>/dev/null |
        tr -d '\r' | tail -1) || return 1
    [ "$output" = "LOCAL_AI_WINDOWS_INTEROP_OK" ]
}

record_ready() {
    [ -r "$record" ] &&
        grep -qx 'enabled' "$record" &&
        grep -qx 'interpreter /init' "$record" &&
        grep -qx 'flags: P' "$record"
}

probe && exit 0
[ -x /init ] || {
    printf 'WSL interop repair failed: /init is unavailable.\n' >&2
    exit 1
}
if [ ! -e "$register" ]; then
    as_root /usr/bin/mkdir -p "$root" || exit 1
    as_root /usr/bin/mount -t binfmt_misc binfmt_misc "$root" \
        >/dev/null 2>&1 || exit 1
fi
# A record can say "enabled" while WSL's run-detectors path has lost the
# corresponding live handler. The executable probe above is authoritative, so
# replace every existing record after a failed probe instead of trusting text.
if [ -e "$record" ]; then
    write_control "$record" -1 || exit 1
fi
if [ ! -e "$record" ]; then
    write_control "$register" "$rule" || exit 1
fi
if ! record_ready || ! probe; then
    printf 'WSL interop repair did not restore Windows executable launch support.\n' >&2
    exit 1
fi
GUARDEOF
    cat > "$service_next" <<'SERVICEEOF'
[Unit]
Description=Restore WSL Windows executable interoperability
After=systemd-binfmt.service
Wants=systemd-binfmt.service
Before=multi-user.target
ConditionPathExists=/init

[Service]
Type=oneshot
ExecStart=/usr/local/libexec/local-ai-wsl-interop-guard
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
SERVICEEOF
    sudo -n /usr/bin/mkdir -p /usr/local/libexec || return 1
    sudo -n /usr/bin/cp "$guard_next" "$WSL_INTEROP_GUARD" || return 1
    sudo -n /usr/bin/chmod 0755 "$WSL_INTEROP_GUARD" || return 1
    sudo -n /usr/bin/cp "$service_next" \
        /etc/systemd/system/local-ai-wsl-interop-guard.service || return 1
    rm -f "$guard_next" "$service_next"

    sudo -n /usr/bin/python3 - <<'PYEOF'
from pathlib import Path

path = Path("/etc/wsl.conf")
lines = path.read_text(encoding="utf-8").splitlines() if path.exists() else []
section_start = None
section_end = len(lines)
for index, line in enumerate(lines):
    stripped = line.strip().lower()
    if stripped == "[interop]":
        section_start = index
        continue
    if section_start is not None and index > section_start and stripped.startswith("["):
        section_end = index
        break

required = {"enabled": "enabled=true", "appendwindowspath": "appendWindowsPath=true"}
if section_start is None:
    if lines and lines[-1].strip():
        lines.append("")
    lines.extend(["[interop]", *required.values()])
else:
    seen = set()
    for index in range(section_start + 1, section_end):
        stripped = lines[index].strip()
        if "=" not in stripped or stripped.startswith(("#", ";")):
            continue
        key = stripped.split("=", 1)[0].strip().lower()
        if key in required:
            lines[index] = required[key]
            seen.add(key)
    insert_at = section_end
    for key, value in required.items():
        if key not in seen:
            lines.insert(insert_at, value)
            insert_at += 1

temporary = path.with_name(path.name + ".local-ai-next")
temporary.write_text("\n".join(lines).rstrip() + "\n", encoding="utf-8")
temporary.replace(path)
PYEOF

    if [ "$(ps -p 1 -o comm= 2>/dev/null | xargs)" = "systemd" ] &&
       command -v systemctl >/dev/null 2>&1; then
        sudo -n /usr/bin/systemctl daemon-reload || return 1
        sudo -n /usr/bin/systemctl enable --now \
            local-ai-wsl-interop-guard.service >/dev/null || return 1
    fi
    "$WSL_INTEROP_GUARD"
}

# ─── Detect hardware ────────────────────────────────────────────────────────
info "Detecting hardware..."
CORES=$(nproc 2>/dev/null || echo 4)
MEM_KB=$(awk '/MemTotal/{print $2}' /proc/meminfo 2>/dev/null || echo 4194304)
MEM_GB=$(( MEM_KB / 1024 / 1024 ))
HAS_NVIDIA=0; GPU_VRAM_GB=0; GPU_NAME="None"; GPU_VRAM_MB=0
NVIDIA_SMI=$(command -v nvidia-smi 2>/dev/null || true)
if [ -z "$NVIDIA_SMI" ] && [ -x /usr/lib/wsl/lib/nvidia-smi ]; then
    NVIDIA_SMI=/usr/lib/wsl/lib/nvidia-smi
fi
if [ -n "$NVIDIA_SMI" ]; then
    for gpu_probe_attempt in $(seq 1 10); do
        GPU_PROBE=$("$NVIDIA_SMI" \
            --query-gpu=name,memory.total \
            --format=csv,noheader,nounits 2>/dev/null |
            head -1 || true)
        GPU_NAME=${GPU_PROBE%,*}
        GPU_VRAM_MB=${GPU_PROBE##*,}
        GPU_NAME=$(printf '%s' "$GPU_NAME" | xargs)
        GPU_VRAM_MB=$(printf '%s' "$GPU_VRAM_MB" | tr -dc '0-9')
        if [ -n "$GPU_NAME" ] && [ "${GPU_VRAM_MB:-0}" -gt 0 ]; then
            HAS_NVIDIA=1
            GPU_VRAM_GB=$(( GPU_VRAM_MB / 1024 ))
            break
        fi
        [ "$gpu_probe_attempt" -lt 10 ] && sleep 1
    done
fi
info "CPU: $CORES cores | RAM: ${MEM_GB}GB | GPU: $GPU_NAME (${GPU_VRAM_GB} GB VRAM)"

# ─── Upgrade WSL memory (so the best model has room to run) ───
# .wslconfig is only read at WSL startup, so a restart is needed to take effect.
# We detect the ACTUAL physical RAM on Windows and give WSL a generous share
# (capped at 64GB) instead of a hardcoded 16GB, so big models always fit.
if ! windows_interop_probe && sudo -n true 2>/dev/null; then
    ensure_wsl_interop ||
        warn "Windows interop is unavailable before setup; it will be repaired after passwordless sudo is configured."
fi
WIN_PROFILE_WIN=$(timeout 5s "$WINDOWS_POWERSHELL" -NoProfile -NonInteractive -Command \
    '[Environment]::GetFolderPath("UserProfile")' 2>/dev/null | tr -d '\r' | tail -1 || true)
if [ -z "$WIN_PROFILE_WIN" ] || [ "$WIN_PROFILE_WIN" = "%USERPROFILE%" ]; then
    WIN_PROFILE_WIN=$(timeout 5s cmd.exe /C "echo %USERPROFILE%" 2>/dev/null | tr -d '\r' | tail -1 || echo "")
fi
WIN_PROFILE=""
if [ -n "$WIN_PROFILE_WIN" ] && command -v wslpath &>/dev/null; then
    WIN_PROFILE=$(wslpath -u "$WIN_PROFILE_WIN" 2>/dev/null || echo "")
fi
WIN_USER=$(basename "$WIN_PROFILE" 2>/dev/null || echo "")
WSL_MEM_GB=16
if [ -n "$WIN_PROFILE" ] && [ -d "$WIN_PROFILE" ]; then
    WSLCONFIG="${WIN_PROFILE}/.wslconfig"
    EXISTING_WSL_MEM_GB=0
    if [ -f "$WSLCONFIG" ]; then
        CFG_MEM_LINE=$(grep -iE '^[[:space:]]*memory[[:space:]]*=[[:space:]]*[0-9]+(GB|MB)' "$WSLCONFIG" 2>/dev/null | head -1 || true)
        CFG_MEM_NUMBER=$(printf '%s' "$CFG_MEM_LINE" | sed -nE 's/.*=[[:space:]]*([0-9]+)(GB|MB).*/\1/Ip')
        CFG_MEM_UNIT=$(printf '%s' "$CFG_MEM_LINE" | sed -nE 's/.*=[[:space:]]*[0-9]+(GB|MB).*/\1/Ip' | tr '[:lower:]' '[:upper:]')
        if [ -n "$CFG_MEM_NUMBER" ] && [ "$CFG_MEM_NUMBER" -gt 0 ] 2>/dev/null; then
            EXISTING_WSL_MEM_GB=$CFG_MEM_NUMBER
            [ "$CFG_MEM_UNIT" = "MB" ] && EXISTING_WSL_MEM_GB=$(( (CFG_MEM_NUMBER + 1023) / 1024 ))
            [ "$EXISTING_WSL_MEM_GB" -gt 0 ] && WSL_MEM_GB=$EXISTING_WSL_MEM_GB
        fi
    fi

    # This host query has hung on real systems. Bound it, and preserve a valid
    # existing setting if Windows does not answer instead of blocking install.
    PHYS_BYTES=$(timeout 8s "$WINDOWS_POWERSHELL" -NoProfile -NonInteractive -Command \
        "(Get-CimInstance Win32_ComputerSystem).TotalPhysicalMemory" 2>/dev/null \
        | tr -dc '0-9' | head -c 15 || true)
    if [ -n "$PHYS_BYTES" ] && [ "$PHYS_BYTES" -gt 0 ]; then
        PHYS_GB=$(( PHYS_BYTES / 1024 / 1024 / 1024 ))
        [ "$PHYS_GB" -lt 1 ] && PHYS_GB=16
        # Give WSL ~70% of physical RAM, capped at 64GB, min 16GB. Large
        # sparse/MoE models can spill cold weights to RAM while keeping their
        # active layers and KV cache on the GPU.
        WSL_MEM_GB=$(( PHYS_GB * 7 / 10 ))
        [ "$WSL_MEM_GB" -lt 16 ] && WSL_MEM_GB=16
        [ "$WSL_MEM_GB" -gt 64 ] && WSL_MEM_GB=64
    elif [ "$EXISTING_WSL_MEM_GB" -gt 0 ]; then
        info "  Windows RAM query did not finish in 8 seconds; keeping the existing ${EXISTING_WSL_MEM_GB}GB WSL memory limit."
    fi
    if [ -f "$WSLCONFIG" ]; then
        if grep -qiE '^[[:space:]]*memory[[:space:]]*=' "$WSLCONFIG"; then
            if [ "$EXISTING_WSL_MEM_GB" -ne "$WSL_MEM_GB" ]; then
                sed -i -E "s/^([[:space:]]*)memory[[:space:]]*=[[:space:]]*[0-9]+(GB|MB)/\1memory=${WSL_MEM_GB}GB/I" "$WSLCONFIG" 2>/dev/null \
                    && info "  Updated .wslconfig memory from ${EXISTING_WSL_MEM_GB}GB to ${WSL_MEM_GB}GB (restart WSL to apply)."
            else
                info "  Kept the existing .wslconfig memory limit at ${WSL_MEM_GB}GB."
            fi
        else
            sed -i "/^\[wsl2\]/a memory=${WSL_MEM_GB}GB" "$WSLCONFIG"
        fi
        grep -qiE '^[[:space:]]*processors[[:space:]]*=' "$WSLCONFIG" \
            && sed -i -E "s/^([[:space:]]*)processors[[:space:]]*=.*/\1processors=${CORES}/I" "$WSLCONFIG" \
            || sed -i "/^\[wsl2\]/a processors=${CORES}" "$WSLCONFIG"
        grep -qiE '^[[:space:]]*swap[[:space:]]*=' "$WSLCONFIG" \
            && sed -i -E "s/^([[:space:]]*)swap[[:space:]]*=.*/\1swap=16GB/I" "$WSLCONFIG" \
            || sed -i "/^\[wsl2\]/a swap=16GB" "$WSLCONFIG"
    else
        cat > "$WSLCONFIG" <<WSLCFG
[wsl2]
memory=${WSL_MEM_GB}GB
processors=${CORES}
swap=16GB
localhostForwarding=true

[experimental]
autoMemoryReclaim=gradual
WSLCFG
        info "  Created .wslconfig with ${WSL_MEM_GB}GB memory (restart WSL to apply)"
    fi
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 1 — System packages (REAL-TIME PROGRESS)
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 1/11: Installing system packages..."
export DEBIAN_FRONTEND=noninteractive

package_manager_busy() {
    local lock
    if command -v fuser >/dev/null 2>&1; then
        for lock in \
            /var/lib/dpkg/lock-frontend \
            /var/lib/dpkg/lock \
            /var/cache/apt/archives/lock \
            /var/lib/apt/lists/lock; do
            if sudo fuser "$lock" >/dev/null 2>&1; then
                return 0
            fi
        done
        return 1
    fi
    pgrep -x apt-get >/dev/null 2>&1 ||
        pgrep -x apt >/dev/null 2>&1 ||
        pgrep -x dpkg >/dev/null 2>&1 ||
        pgrep -f 'unattended-upgrade( |$)' >/dev/null 2>&1
}

wait_for_package_manager() {
    local operation="${1:-the next package operation}"
    local waited=0
    local maximum="${LOCAL_AI_APT_LOCK_WAIT_SECONDS:-600}"
    if ! [[ "$maximum" =~ ^[0-9]+$ ]] || [ "$maximum" -lt 30 ]; then
        maximum=600
    fi
    while package_manager_busy; do
        if [ "$waited" -ge "$maximum" ]; then
            fail "The package manager remained busy for ${waited} seconds before $operation"
        fi
        set_activity "Waiting for the existing apt/dpkg owner before $operation; ${waited} seconds observed"
        sleep 4
        waited=$((waited + 4))
    done
    if [ "$waited" -gt 0 ]; then
        ok "The existing package operation released its locks after ${waited} seconds"
    fi
}

apt_get() {
    local operation="$1"
    shift
    set_activity "$operation"
    wait_for_package_manager "$operation"
    set_activity "$operation"
    sudo apt-get -o DPkg::Lock::Timeout=600 "$@"
}

download_verified_file() {
    local label="$1" url="$2" destination="$3"
    local temporary="${destination}.next.$$"
    rm -f "$temporary"
    set_activity "$label"
    if ! curl --fail --location --retry 5 --retry-all-errors \
        --connect-timeout 20 --progress-bar "$url" -o "$temporary"; then
        rm -f "$temporary"
        return 1
    fi
    if [ ! -s "$temporary" ]; then
        rm -f "$temporary"
        return 1
    fi
    mv -f "$temporary" "$destination"
}

info "  Updating package lists..."
apt_get "Updating Ubuntu package lists" update

install_available_packages() {
    local label="$1"
    shift
    local package
    local -a available=()
    local -a unavailable=()
    local -a failed=()

    for package in "$@"; do
        if apt-cache show "$package" >/dev/null 2>&1; then
            available+=("$package")
        else
            unavailable+=("$package")
        fi
    done

    if [ "${#unavailable[@]}" -gt 0 ]; then
        warn "$label: this Ubuntu release has no apt candidate for: ${unavailable[*]}"
    fi
    if [ "${#available[@]}" -eq 0 ]; then
        warn "$label: no requested package has an apt candidate"
        return 0
    fi

    set_activity "$label: installing ${#available[@]} available packages"
    if apt_get "installing $label" install -y "${available[@]}"; then
        ok "$label installed"
        return 0
    fi

    warn "$label did not install as one transaction; retrying each package independently"
    for package in "${available[@]}"; do
        set_activity "$label: checking $package independently"
        if ! apt_get "installing $package" install -y "$package"; then
            failed+=("$package")
        fi
    done
    if [ "${#failed[@]}" -gt 0 ]; then
        warn "$label could not install: ${failed[*]}"
        return 1
    fi
    ok "$label installed after isolated package recovery"
}

info "  Installing core packages (build tools, Python, Git, and diagnostics)..."
install_available_packages "Core development tools" \
    build-essential cmake git curl wget unzip \
    python3 python3-pip python3-venv python3-dev python3-tk pipx \
    jq file bc net-tools openssh-client rsync \
    htop tmux screen tree pkg-config ca-certificates \
    gnupg lsb-release software-properties-common apt-transport-https \
    libopenblas-dev libcurl4-openssl-dev libssl-dev \
    shellcheck bats

info "  Installing CLI tools (ripgrep, fd, bat, fzf, etc)..."
install_available_packages "Fast command-line tools" \
    ripgrep fd-find bat fzf trash-cli xclip xsel \
    parallel moreutils strace lsof netcat-openbsd dnsutils \
    entr watchman hyperfine \
    || fail "Required command-line tools could not all be installed"

info "  Installing universal media, document, database, network, and OCR tools..."
install_available_packages "Universal data and automation tools" \
    ffmpeg imagemagick pandoc sqlite3 \
    poppler-utils ghostscript tesseract-ocr \
    nmap tree zip gzip bzip2 xz-utils zstd \
    nodejs npm bc expect sshpass \
    postgresql-client default-mysql-client redis-tools \
    adb scrcpy graphviz \
    || fail "Required universal data and automation tools could not all be installed"

info "  Installing broad compiler, language, debugger, and build-system coverage..."
install_available_packages "Native compilers and build systems" \
    clang lldb gdb valgrind ninja-build meson ccache mold \
    nasm yasm autoconf automake libtool bison flex gfortran \
    || fail "Required native compiler coverage could not be installed"
install_available_packages "Major language SDKs and package managers" \
    dotnet-sdk-10.0 default-jdk maven gradle golang-go \
    ruby-full php-cli php-dev composer \
    lua5.4 liblua5.4-dev luarocks \
    r-base r-base-dev ghc cabal-install \
    nim crystal erlang elixir mono-devel fpc \
    ocaml opam clojure kotlin scala \
    || fail "One or more available major language SDKs could not be installed"

info "  Installing the official Rust toolchain with Cargo, Clippy, and rustfmt..."
if [ ! -x "$HOME/.cargo/bin/rustup" ]; then
    RUSTUP_INSTALLER=$(mktemp)
    download_verified_file \
        "Downloading the official Rust installer" \
        "https://sh.rustup.rs" "$RUSTUP_INSTALLER" \
        || fail "The official Rust installer could not be downloaded"
    sh "$RUSTUP_INSTALLER" -y --profile default \
        || fail "The official Rust toolchain installer failed"
    rm -f "$RUSTUP_INSTALLER"
fi
export PATH="$HOME/.cargo/bin:$PATH"
"$HOME/.cargo/bin/rustup" toolchain install stable --profile default \
    || fail "Rust stable toolchain installation failed"
"$HOME/.cargo/bin/rustup" default stable \
    || fail "Rust stable toolchain activation failed"
"$HOME/.cargo/bin/rustup" component add clippy rustfmt \
    || fail "Rust verification components failed to install"
ok "Official Rust toolchain installed"

info "  Installing mise for verified on-demand coverage of hundreds of additional toolchains..."
if [ ! -x "$HOME/.local/bin/mise" ]; then
    MISE_INSTALLER=$(mktemp)
    download_verified_file \
        "Downloading the official mise installer" \
        "https://mise.run" "$MISE_INSTALLER" \
        || fail "The official mise installer could not be downloaded"
    sh "$MISE_INSTALLER" \
        || fail "The official mise runtime-manager installer failed"
    rm -f "$MISE_INSTALLER"
fi
export PATH="$HOME/.local/share/mise/shims:$HOME/.local/bin:$PATH"
"$HOME/.local/bin/mise" --version \
    || fail "mise installed but did not pass its version check"
ok "mise runtime manager installed for uncommon and project-pinned toolchains"

info "  Installing the current Node.js 24 LTS line from signed official release checksums..."
NODE_ARCH=$(dpkg --print-architecture)
case "$NODE_ARCH" in
    amd64) NODE_ARCH=x64 ;;
    arm64) NODE_ARCH=arm64 ;;
    *) NODE_ARCH="" ;;
esac
if [ -n "$NODE_ARCH" ]; then
    NODE_RELEASE_ROOT="https://nodejs.org/dist/latest-v24.x"
    NODE_CHECKSUMS=$(mktemp)
    if download_verified_file \
        "Downloading signed Node.js release checksums" \
        "$NODE_RELEASE_ROOT/SHASUMS256.txt" "$NODE_CHECKSUMS"; then
        NODE_ARCHIVE=$(awk -v arch="$NODE_ARCH" \
            '$2 ~ ("node-v[0-9.]+-linux-" arch "\\.tar\\.xz$") { print $2; exit }' \
            "$NODE_CHECKSUMS")
        if [ -n "$NODE_ARCHIVE" ]; then
            NODE_VERSION=${NODE_ARCHIVE#node-}
            NODE_VERSION=${NODE_VERSION%-linux-*}
            NODE_DEST="/usr/local/lib/nodejs/node-$NODE_VERSION-linux-$NODE_ARCH"
            if [ ! -x "$NODE_DEST/bin/node" ]; then
                NODE_DOWNLOAD=$(mktemp)
                download_verified_file \
                    "Downloading the official Node.js $NODE_VERSION archive" \
                    "$NODE_RELEASE_ROOT/$NODE_ARCHIVE" "$NODE_DOWNLOAD" \
                    || fail "Official Node.js archive download failed"
                (
                    cd "$(dirname "$NODE_DOWNLOAD")"
                    grep "  $NODE_ARCHIVE\$" "$NODE_CHECKSUMS" |
                        sed "s#  $NODE_ARCHIVE#  $(basename "$NODE_DOWNLOAD")#" |
                        sha256sum -c -
                ) || fail "Official Node.js checksum verification failed"
                sudo mkdir -p /usr/local/lib/nodejs
                sudo tar -xJf "$NODE_DOWNLOAD" -C /usr/local/lib/nodejs
                rm -f "$NODE_DOWNLOAD"
            fi
            for executable in node npm npx corepack; do
                if [ -x "$NODE_DEST/bin/$executable" ]; then
                    sudo ln -sfn "$NODE_DEST/bin/$executable" "/usr/local/bin/$executable"
                fi
            done
            ok "Official Node.js $NODE_VERSION installed"
        else
            warn "The official Node.js release list had no Linux $NODE_ARCH archive"
        fi
    else
        warn "The official Node.js checksum list could not be downloaded"
    fi
    rm -f "$NODE_CHECKSUMS"
else
    warn "No official Node.js binary mapping is configured for architecture $(dpkg --print-architecture)"
fi

if command -v corepack >/dev/null 2>&1; then
    sudo corepack enable || warn "Corepack could not enable pnpm and Yarn shims"
fi
npm install -g --allow-scripts=yarn typescript eslint prettier pyright pnpm yarn \
    || fail "Global JavaScript verification tools failed to install"
NODE_GLOBAL_BIN="$(npm prefix -g)/bin"
for executable in tsc tsserver eslint prettier pyright pyright-langserver pnpm yarn; do
    if [ -x "$NODE_GLOBAL_BIN/$executable" ]; then
        sudo ln -sfn "$NODE_GLOBAL_BIN/$executable" "/usr/local/bin/$executable"
    fi
done
for executable in tsc eslint prettier pyright pnpm yarn; do
    command -v "$executable" >/dev/null 2>&1 \
        || fail "Global JavaScript tool $executable installed but is not executable from PATH"
done
ok "Global JavaScript and TypeScript verification tools installed and exposed on PATH"

info "  Installing PowerShell 7 for cross-platform scripting..."
if ! command -v pwsh >/dev/null 2>&1; then
    MICROSOFT_REPO_DEB=$(mktemp)
    if download_verified_file \
        "Downloading the Microsoft package repository configuration" \
        "https://packages.microsoft.com/config/ubuntu/24.04/packages-microsoft-prod.deb" \
        "$MICROSOFT_REPO_DEB" &&
       sudo dpkg -i "$MICROSOFT_REPO_DEB" &&
       apt_get "refreshing Microsoft package metadata" update &&
       apt_get "installing PowerShell 7" install -y powershell; then
        ok "PowerShell 7 installed"
    else
        warn "PowerShell 7 installation failed; Windows PowerShell remains available through WSL interop"
    fi
    rm -f "$MICROSOFT_REPO_DEB"
else
    ok "PowerShell 7 already installed"
fi

info "  Installing optional power tools (GitHub CLI, Docker, yt-dlp)..."
# Install each tool SEPARATELY so one failure never kills the others.
# Known landmine: Ubuntu's docker.io pulls 'containerd', which CONFLICTS with
# the 'containerd.io' package from Docker's official repo if that is present.
# We detect and remove the conflicting package first, then install docker.io.
apt_get "Installing GitHub CLI" install -y gh \
    || fail "GitHub CLI could not be installed"
apt_get "Installing yt-dlp" install -y yt-dlp \
    || fail "yt-dlp could not be installed"
if command -v docker >/dev/null 2>&1; then
    ok "  docker already installed"
else
    # Is Docker CE (the official repo package) already installed? If so, docker
    # is effectively available via a different path - leave its containerd.io alone.
    DOCKER_CE=$(dpkg -l 2>/dev/null | grep -c '^ii  docker-ce' || true)
    if apt_get "Installing Docker tools" install -y docker.io docker-compose; then
        ok "  docker.io installed"
    elif [ "$DOCKER_CE" -gt 0 ]; then
        warn "docker-ce already installed - keeping it (docker available via docker-ce)"
    else
        fail "Docker tools could not be installed without damaging the existing container runtime"
    fi
fi
command -v docker >/dev/null 2>&1 \
    || fail "Docker installation completed without an executable docker command"

AGENT_VENV="$HOME/.local/share/llama-agent/venv"
info "  Creating an isolated Python environment for agent capabilities..."
python3 -m venv "$AGENT_VENV" \
    || fail "Could not create the isolated agent Python environment"
"$AGENT_VENV/bin/python" -m pip install --upgrade pip wheel \
    || warn "pip upgrade failed; continuing with the bundled venv pip"
"$AGENT_VENV/bin/python" -m pip install \
    requests beautifulsoup4 lxml rich prompt_toolkit \
    pytest pytest-cov ruff mypy pylint black isort pip-tools \
    httpx pydantic fastapi uvicorn \
    || fail "Required agent Python libraries failed to install"
"$AGENT_VENV/bin/python" -m pip install playwright \
    || fail "The isolated browser-automation library could not be installed"

# Symlink fd / bat under their short names
if command -v fdfind >/dev/null 2>&1 && ! command -v fd >/dev/null 2>&1; then
    sudo ln -sfn "$(command -v fdfind)" /usr/local/bin/fd \
        || fail "The fd compatibility command could not be exposed"
fi
if command -v batcat >/dev/null 2>&1 && ! command -v bat >/dev/null 2>&1; then
    sudo ln -sfn "$(command -v batcat)" /usr/local/bin/bat \
        || fail "The bat compatibility command could not be exposed"
fi
command -v fd >/dev/null 2>&1 \
    || fail "fd installed but is not executable from PATH"
command -v bat >/dev/null 2>&1 \
    || fail "bat installed but is not executable from PATH"

ok "System packages installed"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 2 — CUDA toolkit (REAL-TIME PROGRESS with fallbacks)
# ═══════════════════════════════════════════════════════════════════════════════
if [ "$HAS_NVIDIA" -eq 1 ]; then
    info "Step 2/11: Ensuring CUDA toolkit..."

    cuda_nvcc_exists() {
        command -v nvcc >/dev/null 2>&1 ||
            [ -x /usr/local/cuda/bin/nvcc ] ||
            find /usr/local -maxdepth 3 -type f -path '*/cuda-*/bin/nvcc' \
                -executable -print -quit 2>/dev/null | grep -q .
    }

    activate_cuda_path() {
        local nvcc_path cuda_root
        nvcc_path=$(command -v nvcc 2>/dev/null || true)
        if [ -z "$nvcc_path" ]; then
            nvcc_path=$(find /usr/local -maxdepth 3 -type f \
                -path '*/cuda-*/bin/nvcc' -executable -print -quit 2>/dev/null || true)
        fi
        [ -n "$nvcc_path" ] || return 1
        cuda_root=$(dirname "$(dirname "$nvcc_path")")
        export CUDA_PATH="$cuda_root"
        export PATH="$cuda_root/bin:$PATH"
        export LD_LIBRARY_PATH="$cuda_root/lib64:${LD_LIBRARY_PATH:-}"
        return 0
    }

    retry_cuda_step() {
        local label="$1"
        shift
        local attempt
        for attempt in 1 2 3; do
            set_activity "$label; attempt $attempt of 3"
            if "$@"; then
                ok "$label completed on attempt $attempt"
                return 0
            fi
            if [ "$attempt" -lt 3 ]; then
                warn "$label failed on attempt $attempt; retrying after $((attempt * 3)) seconds"
                sleep $((attempt * 3))
            fi
        done
        return 1
    }

    install_cuda_repository() {
        local distro package_url package_file
        distro="ubuntu$(lsb_release -rs | tr -d '.')"
        package_url="https://developer.download.nvidia.com/compute/cuda/repos/${distro}/x86_64/cuda-keyring_1.1-1_all.deb"
        package_file="/tmp/cuda-keyring-${distro}.deb"

        set_activity "Downloading the NVIDIA CUDA repository keyring for $distro"
        curl --fail --location --retry 3 --retry-all-errors \
            --connect-timeout 20 --progress-bar \
            "$package_url" -o "${package_file}.next" \
            || return 1
        dpkg-deb --info "${package_file}.next" >/dev/null 2>&1 \
            || return 1
        mv -f "${package_file}.next" "$package_file"
        retry_cuda_step "Installing the NVIDIA CUDA repository keyring" \
            sudo dpkg -i "$package_file" \
            || return 1
        apt_get "Refreshing NVIDIA CUDA package metadata" update
    }

    install_cuda_toolkit() {
        local candidate version branch package
        candidate=$(apt-cache policy cuda-toolkit 2>/dev/null |
            awk '/Candidate:/{print $2; exit}')
        [ -n "$candidate" ] && [ "$candidate" != "(none)" ] || return 1
        version=${candidate%%-*}
        branch=$(printf '%s' "$version" | awk -F. '{print $1 "-" $2}')
        package="cuda-toolkit-${branch}"
        apt-cache show "$package" >/dev/null 2>&1 || package="cuda-toolkit"
        set_activity "Installing NVIDIA $package version $candidate with live apt output"
        apt_get "Installing NVIDIA $package version $candidate" \
            install -y "$package"
    }

    verify_cuda_toolchain() {
        local probe_dir
        activate_cuda_path || return 1
        probe_dir=$(mktemp -d)
        cat > "$probe_dir/cuda_probe.cu" <<'CUDAEOF'
#include <cstdio>
#include <cuda_runtime.h>
__global__ void mark_ready(int *value) { *value = 73; }
int main() {
    int *device = nullptr;
    int host = 0;
    if (cudaMalloc(&device, sizeof(int)) != cudaSuccess) return 2;
    mark_ready<<<1, 1>>>(device);
    if (cudaDeviceSynchronize() != cudaSuccess) return 3;
    if (cudaMemcpy(&host, device, sizeof(int), cudaMemcpyDeviceToHost) != cudaSuccess) return 4;
    cudaFree(device);
    if (host != 73) return 5;
    std::puts("CUDA_TOOLCHAIN_AND_GPU_OK");
    return 0;
}
CUDAEOF
        set_activity "Compiling a CUDA verification program with nvcc"
        nvcc -O2 "$probe_dir/cuda_probe.cu" -o "$probe_dir/cuda_probe" \
            || {
                rm -rf "$probe_dir"
                return 1
            }
        set_activity "Running the CUDA verification program on the NVIDIA GPU"
        "$probe_dir/cuda_probe"
        local result=$?
        rm -rf "$probe_dir"
        return "$result"
    }

    if cuda_nvcc_exists; then
        activate_cuda_path \
            || fail "nvcc exists but its CUDA installation root could not be activated"
    else
        info "  Installing the complete NVIDIA CUDA toolkit with live download and package output..."
        install_cuda_repository \
            || fail "The verified NVIDIA CUDA repository could not be configured"
        retry_cuda_step "Installing the complete NVIDIA CUDA toolkit" \
            install_cuda_toolkit \
            || fail "The NVIDIA CUDA toolkit could not be installed after three attempts"
        activate_cuda_path \
            || fail "CUDA packages installed but nvcc could not be located"
    fi
    verify_cuda_toolchain \
        || fail "CUDA installed, but compiling and running a real GPU verification program failed"
    ok "CUDA toolkit and live NVIDIA GPU execution verified: $(nvcc --version 2>/dev/null | grep release || echo 'nvcc detected')"
else
    info "Step 2/11: No NVIDIA GPU — skipping CUDA"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 3 — Build llama.cpp (REAL-TIME PROGRESS)
# ═══════════════════════════════════════════════════════════════════════════════
LLAMA_DIR="$HOME/llama.cpp"
info "Step 3/11: Building llama.cpp..."

if [ -d "$LLAMA_DIR/.git" ]; then
    info "  Updating existing llama.cpp source..."
    if ! git -C "$LLAMA_DIR" pull --ff-only; then
        warn "The llama.cpp update failed; preserving and validating the existing source checkout"
        git -C "$LLAMA_DIR" rev-parse --verify HEAD >/dev/null \
            || fail "The existing llama.cpp checkout is not usable"
    fi
else
    LLAMA_CLONE_TMP="${LLAMA_DIR}.new.$$"
    rm -rf "$LLAMA_CLONE_TMP"
    LLAMA_CLONED=0
    for attempt in 1 2 3; do
        info "  Cloning llama.cpp into a temporary directory (attempt $attempt/3)..."
        if git clone --depth 1 https://github.com/ggml-org/llama.cpp.git \
            "$LLAMA_CLONE_TMP"; then
            LLAMA_CLONED=1
            break
        fi
        rm -rf "$LLAMA_CLONE_TMP"
        if [ "$attempt" -lt 3 ]; then
            set_activity "llama.cpp clone attempt $attempt failed; waiting before retry $((attempt + 1))"
            sleep $((attempt * 2))
        fi
    done
    if [ "$LLAMA_CLONED" -ne 1 ] || [ ! -d "$LLAMA_CLONE_TMP/.git" ]; then
        rm -rf "$LLAMA_CLONE_TMP"
        fail "llama.cpp could not be cloned after three verified attempts"
    fi
    rm -rf "$LLAMA_DIR"
    mv "$LLAMA_CLONE_TMP" "$LLAMA_DIR"
fi

cd "$LLAMA_DIR"

CMAKE_ARGS="-DCMAKE_BUILD_TYPE=Release"
if [ "$HAS_NVIDIA" -eq 1 ]; then
    export PATH="/usr/local/cuda/bin:$PATH"
    export CUDA_PATH="/usr/local/cuda"
    # Make cmake find CUDA even if not in default paths
    CMAKE_ARGS="$CMAKE_ARGS -DGGML_CUDA=ON -DCUDAToolkit_ROOT=/usr/local/cuda -DCMAKE_CUDA_COMPILER=/usr/local/cuda/bin/nvcc"
    info "  Configuring with CUDA support..."
else
    info "  Configuring CPU-only build..."
fi

set_activity "Configuring the llama.cpp build with CMake"
cmake -B build $CMAKE_ARGS \
    || fail "CMake could not configure llama.cpp"

BUILD_JOBS="$CORES"
if [ "$HAS_NVIDIA" -eq 1 ]; then
    CUDA_MEMORY_JOBS=$(( MEM_GB / 6 ))
    [ "$CUDA_MEMORY_JOBS" -lt 2 ] && CUDA_MEMORY_JOBS=2
    [ "$CUDA_MEMORY_JOBS" -gt 8 ] && CUDA_MEMORY_JOBS=8
    [ "$BUILD_JOBS" -gt "$CUDA_MEMORY_JOBS" ] && BUILD_JOBS="$CUDA_MEMORY_JOBS"
fi
if [[ "${LOCAL_AI_BUILD_JOBS:-}" =~ ^[0-9]+$ ]] &&
   [ "$LOCAL_AI_BUILD_JOBS" -ge 1 ]; then
    BUILD_JOBS="$LOCAL_AI_BUILD_JOBS"
    [ "$BUILD_JOBS" -gt "$CORES" ] && BUILD_JOBS="$CORES"
fi
info "  Compiling with $BUILD_JOBS memory-safe parallel jobs (this may take a few minutes)..."
cmake --build build --config Release --target llama-server -j"$BUILD_JOBS" \
    || fail "llama.cpp compilation failed"

# Verify build output
LLAMA_SERVER_PATH=$(find build -name "llama-server" -type f -executable 2>/dev/null | head -1)
LLAMA_APP_PATH=$(find build -name "llama" -type f -executable 2>/dev/null | head -1)
if [ -z "$LLAMA_SERVER_PATH" ] && [ -z "$LLAMA_APP_PATH" ]; then
    fail "Build completed but no llama-server or llama binary found"
fi

ok "llama.cpp built successfully"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 4 — Download the BEST model for this hardware (dynamic, always up-to-date)
# ═══════════════════════════════════════════════════════════════════════════════
MODEL_DIR="$HOME/models"
mkdir -p "$MODEL_DIR"

info "Step 4/11: Finding the best model for your hardware..."

# ── Budget: how many GB the model file may be ──
# GPU present: reserve enough VRAM for Windows graphics, CUDA work buffers, and
# the KV cache. Prefer a dense agent model that fits fully in the remaining
# VRAM; CPU-heavy hybrid offload is retained only as a lower-priority fallback.
if [ "$HAS_NVIDIA" -eq 1 ] && [ "${GPU_VRAM_MB:-0}" -gt 0 ]; then
    GPU_BUDGET_GB=$(( (GPU_VRAM_MB / 1024) - 5 ))
    [ "$GPU_BUDGET_GB" -lt 2 ] && GPU_BUDGET_GB=2
else
    GPU_BUDGET_GB=0
fi

EFFECTIVE_RAM_GB="$MEM_GB"
if [ -n "${WSLCONFIG:-}" ] && [ -f "$WSLCONFIG" ]; then
    CFG_MEM=$(grep -iE '^[[:space:]]*memory[[:space:]]*=' "$WSLCONFIG" 2>/dev/null | head -1 | tr -dc '0-9')
    if [ -n "$CFG_MEM" ] && [ "$CFG_MEM" -gt 0 ]; then
        EFFECTIVE_RAM_GB=$CFG_MEM
    fi
fi
RAM_BUDGET_GB=$(( EFFECTIVE_RAM_GB - 2 ))
[ "$RAM_BUDGET_GB" -lt 1 ] && RAM_BUDGET_GB=1

if [ "$GPU_BUDGET_GB" -gt 0 ]; then
    HYBRID_BUDGET_GB=$(( GPU_BUDGET_GB + (RAM_BUDGET_GB - GPU_BUDGET_GB) / 3 ))
    MODEL_BUDGET_GB=$HYBRID_BUDGET_GB
    [ "$MODEL_BUDGET_GB" -gt 28 ] && MODEL_BUDGET_GB=28
    [ "$MODEL_BUDGET_GB" -lt "$GPU_BUDGET_GB" ] && MODEL_BUDGET_GB=$GPU_BUDGET_GB
else
    MODEL_BUDGET_GB=$RAM_BUDGET_GB
fi
info "  Model budget: ${MODEL_BUDGET_GB} GB (GPU: ${GPU_BUDGET_GB} GB, RAM: ${RAM_BUDGET_GB} GB)"

# ── Static fallback chain (used only if live discovery is unreachable) ──
# Format: repo|filename|size_GB|label. Sizes verified on HuggingFace 2026-08.
MODEL_CANDIDATES=(
    "unsloth/rnj-1-instruct-GGUF|rnj-1-instruct-UD-Q6_K_XL.gguf|7.47|RNJ-1 Instruct Q6 (dense agentic coding and tool use)"
    "unsloth/Qwen3.6-35B-A3B-MTP-GGUF|Qwen3.6-35B-A3B-UD-Q4_K_XL.gguf|21.3|Qwen3.6 35B-A3B (multimodal agentic MoE, MTP)"
    "unsloth/Qwen3.6-35B-A3B-GGUF|Qwen3.6-35B-A3B-UD-IQ3_S.gguf|12.7|Qwen3.6-35B-A3B (multimodal agentic MoE)"
    "unsloth/Qwen3.6-27B-MTP-GGUF|Qwen3.6-27B-Q3_K_S.gguf|11.7|Qwen3.6 27B (agentic, MTP)"
    "unsloth/North-Mini-Code-1.0-GGUF|North-Mini-Code-1.0-UD-Q4_K_XL.gguf|17.9|North Mini Code 30B-A3B (agentic engineering)"
    "unsloth/GLM-4.7-Flash-GGUF|GLM-4.7-Flash-Q3_K_S.gguf|12.4|GLM-4.7-Flash 30B (agentic SOTA, 3B active MoE)"
    "unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF|Qwen3-Coder-30B-A3B-Instruct-Q3_K_S.gguf|12.4|Qwen3-Coder-30B-A3B (agentic coding MoE)"
    "unsloth/gemma-4-12b-it-GGUF|gemma-4-12b-it-Q6_K.gguf|9.1|Gemma 4 12B Q6_K (multimodal agentic)"
    "unsloth/DeepSeek-V4-Flash-0731-GGUF|DeepSeek-V4-Flash-0731-Q3_K_S.gguf|12.4|DeepSeek V4 Flash"
    "unsloth/MiniMax-H3-GGUF|MiniMax-H3-Q3_K_S.gguf|12.4|MiniMax H3"
    "unsloth/GLM-4.7-GGUF|GLM-4.7-Q3_K_S.gguf|12.4|GLM-4.7 (agentic)"
    "unsloth/gemma-4-12b-it-GGUF|gemma-4-12b-it-Q5_K_M.gguf|7.8|Gemma 4 12B Q5_K_M"
    "unsloth/Qwen3-14B-GGUF|Qwen3-14B-Q6_K.gguf|11.4|Qwen3 14B Q6_K"
    "unsloth/Qwen3-8B-GGUF|Qwen3-8B-Q8_0.gguf|8.9|Qwen3 8B Q8_0"
    "unsloth/gemma-3-12b-it-GGUF|gemma-3-12b-it-Q5_K_M.gguf|10.5|Gemma 3 12B Q5_K_M"
    "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q8_0.gguf|8.5|Llama 3.1 8B Q8_0"
    "bartowski/Meta-Llama-3.1-8B-Instruct-GGUF|Meta-Llama-3.1-8B-Instruct-Q6_K.gguf|6.5|Llama 3.1 8B Q6_K"
    "Qwen/Qwen2.5-3B-Instruct-GGUF|qwen2.5-3b-instruct-q8_0.gguf|3.2|Qwen 2.5 3B Q8_0"
)

hf_file_exists() {
    local repo="$1" file="$2" code
    code=$(curl -s -o /dev/null -w "%{http_code}" -m 25 -r 0-0 -L "https://huggingface.co/${repo}/resolve/main/${file}" 2>/dev/null)
    [ "$code" = "206" ] || [ "$code" = "200" ]
}

valid_gguf() {
    local file="$1"
    [ -f "$file" ] || return 1
    [ "$(head -c 4 "$file" 2>/dev/null)" = "GGUF" ]
}

is_main_model_file() {
    local name
    name=$(basename "$1" | tr '[:upper:]' '[:lower:]')
    case "$name" in
        *mmproj*|*projector*|*mtp*|*draft*) return 1 ;;
    esac
    return 0
}

download_model() {
    local url="$1" dest="$2" label="$3" size="$4" frac="${5:-0.9}"
    local expect_bytes total_bytes cur sz2
    mkdir -p "$(dirname "$dest")" || {
        warn "  Cannot create the model directory for $label"
        return 1
    }
    expect_bytes=$(awk -v g="$size" -v f="$frac" 'BEGIN{printf "%d", g*1073741824*f}')
    total_bytes=$(awk -v g="$size" 'BEGIN{printf "%d", g*1073741824}')
    # Resume support: a leftover .part from an interrupted run is KEPT and
    # resumed with wget -c / curl -C -, so a 13 GB model never restarts from
    # zero after a network drop or a Ctrl+C.
    if [ -f "${dest}.part" ]; then
        cur=$(stat -c %s "${dest}.part" 2>/dev/null || echo 0)
        if [ "$cur" -ge "$expect_bytes" ] && valid_gguf "${dest}.part"; then
            mv "${dest}.part" "$dest"
            ok "  $label completed from a size-checked GGUF partial ($(du -h "$dest" | cut -f1))"
            return 0
        fi
        info "  Resuming partial download of $label ($(du -h "${dest}.part" | cut -f1) so far)..."
    fi
    if [ -f "$dest" ]; then
        cur=$(stat -c %s "$dest" 2>/dev/null || echo 0)
        if [ "$cur" -ge "$expect_bytes" ] && valid_gguf "$dest"; then
            ok "  $label already present with a valid GGUF header ($(du -h "$dest" | cut -f1))"
            return 0
        fi
        warn "  $label exists but fails the size or GGUF-header check - re-downloading"
        rm -f "$dest"
    fi
    info "  Downloading $label (~$size GB file, may take several minutes)..."
    set_download_progress "${dest}.part" "$total_bytes"
    if wget --quiet --https-only -c -O "${dest}.part" "$url" \
        || curl --fail --silent --show-error --location --retry 3 -C - \
            -o "${dest}.part" "$url"; then
        sz2=$(stat -c %s "${dest}.part" 2>/dev/null || echo 0)
        if [ "$sz2" -ge "$expect_bytes" ] && valid_gguf "${dest}.part"; then
            mv "${dest}.part" "$dest"
            ok "  Downloaded and validated GGUF: $label ($(du -h "$dest" | cut -f1))"
            return 0
        fi
        # The .part is corrupt (e.g. an HTML error page) - drop it, try next
        rm -f "${dest}.part"
        warn "  Download of $label incomplete - trying next best model"
        return 1
    fi
    # Keep the .part so a re-run RESUMES instead of starting over
    warn "  Download failed for $label (partial kept - re-running the script resumes it) - trying next best model"
    return 1
}

CHOSEN_MODEL=""
CHOSEN_LABEL=""
CHOSEN_REPO=""

# ── LIVE DISCOVERY: query HuggingFace RIGHT NOW for the best current model ──
# A small Python helper (python3 ships with Ubuntu) asks the HF API for:
#   1) a curated list of the best agentic model families of 2026 (ranked),
#   2) the top TRENDING GGUF repos right now (so brand-new models get picked).
# For each repo it lists actual files+sizes, keeps the best quant that fits the
# budget, and prints ranked candidates. If HF is unreachable, we fall back to
# the static MODEL_CANDIDATES chain above.
info "  Querying HuggingFace for the best model available RIGHT NOW..."
DISCOVERY_OUT="$(mktemp)"
python3 - "$MODEL_BUDGET_GB" "$GPU_BUDGET_GB" "$MODEL_DIR" > "$DISCOVERY_OUT" 2>/dev/null <<'DISCOVERYEOF' || true
import json, sys, urllib.request, re, time

budget_gb = float(sys.argv[1]) if len(sys.argv) > 1 else 0
full_gpu_budget_gb = float(sys.argv[2]) if len(sys.argv) > 2 else 0
model_dir = sys.argv[3] if len(sys.argv) > 3 else ""

# Fast connectivity probe: if HuggingFace is unreachable, bail out in ~5s
# instead of looping through every family with long timeouts.
try:
    urllib.request.urlopen("https://huggingface.co", timeout=8).close()
except Exception:
    sys.exit(0)

# Curated agentic families are a high-quality seed, not a permanent winner.
# The API metadata, recency, downloads, task tags, architecture and quant
# quality determine the final score on every install.
FAMILIES = [
    ("unsloth/Qwen3.8-27B-GGUF",                  176, "Qwen3.8 27B (current multimodal agentic model)"),
    ("unsloth/NVIDIA-Nemotron-3.5-Lightning-30B-A3B-GGUF", 168,
                                                        "NVIDIA Nemotron 3.5 Lightning 30B-A3B (current agentic MoE)"),
    ("unsloth/rnj-1-instruct-GGUF",              160, "RNJ-1 Instruct Q6 (dense agentic coding and tool use)"),
    ("unsloth/Qwen3.6-35B-A3B-MTP-GGUF",         126, "Qwen3.6 35B-A3B (multimodal agentic MoE, MTP)"),
    ("unsloth/Qwen3.6-35B-A3B-GGUF",             122, "Qwen3.6-35B-A3B (multimodal agentic MoE)"),
    ("unsloth/Qwen3.6-27B-MTP-GGUF",             118, "Qwen3.6 27B (agentic, MTP)"),
    ("unsloth/North-Mini-Code-1.0-GGUF",         106, "North Mini Code 30B-A3B (agentic engineering)"),
    ("unsloth/Qwen3-Coder-Next-GGUF",            104, "Qwen3 Coder Next (agentic coding)"),
    ("unsloth/GLM-4.7-Flash-GGUF",             100, "GLM-4.7-Flash 30B (agentic SOTA, 3B active MoE)"),
    ("unsloth/Qwen3-Coder-30B-A3B-Instruct-GGUF", 98, "Qwen3-Coder-30B-A3B (agentic coding MoE)"),
    ("unsloth/gemma-4-12b-it-GGUF",            95, "Gemma 4 12B (multimodal agentic, vision)"),
    ("unsloth/DeepSeek-V4-Flash-0731-GGUF",    90, "DeepSeek V4 Flash"),
    ("unsloth/MiniMax-H3-GGUF",                88, "MiniMax H3"),
    ("unsloth/GLM-4.7-GGUF",                   86, "GLM-4.7 (agentic)"),
    ("unsloth/Qwen3-14B-GGUF",                 80, "Qwen3 14B"),
    ("unsloth/gemma-3-12b-it-GGUF",            78, "Gemma 3 12B (multimodal)"),
    ("unsloth/Qwen3-8B-GGUF",                  74, "Qwen3 8B"),
    ("bartowski/Meta-Llama-3.1-8B-Instruct-GGUF", 70, "Llama 3.1 8B"),
    ("Qwen/Qwen2.5-3B-Instruct-GGUF",          60, "Qwen 2.5 3B"),
]

# Quant quality rank (best first) - matched as whole dash-tokens so
# Q2_K_XL is never confused with Q2_K, and IQ3_S with IQ3_XXS.
QUANT_RANK = {
    "Q8_K_XL": 0, "Q8_0": 1, "Q6_K_XL": 2, "Q6_K": 3, "Q5_K_XL": 4,
    "Q5_K_M": 5, "Q5_K_S": 6, "Q4_K_XL": 7, "Q4_K_M": 8, "Q4_K_S": 9,
    "Q3_K_XL": 10, "Q3_K_M": 11, "Q3_K_S": 12, "Q2_K_XL": 13, "Q2_K_L": 14,
    "Q2_K": 15, "IQ4_NL": 16, "IQ4_XS": 17, "IQ3_XXS": 18, "IQ3_S": 19,
    "IQ3_XS": 20, "IQ2_M": 21, "IQ1_M": 22, "TQ1_0": 23, "MXFP4": 24,
}

PREFERRED_FILES = {
    # Live testing on this host showed that this dense 8.3B quant keeps the
    # whole model on the RTX GPU with working headroom. Ornith is intentionally
    # excluded because its Gated Delta Net path fell back to unsupported,
    # CPU-heavy execution in the installed llama.cpp build.
    "unsloth/rnj-1-instruct-GGUF": "rnj-1-instruct-UD-Q6_K_XL.gguf",
}

def qrank(name):
    for t in re.split(r"[.-]", name):
        if t in QUANT_RANK:
            return QUANT_RANK[t]
    return 99

def fetch(url, tries=2):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "local-ai-installer"})
            with urllib.request.urlopen(req, timeout=25) as r:
                return json.loads(r.read().decode())
        except Exception:
            time.sleep(2)
    return None

def good_file(n):
    """A valid single-file GGUF we could run: not BF16, not sharded, not a
    vision projector or draft head, not a non-quant auxiliary file."""
    low = n.lower()
    if not n.endswith(".gguf"):
        return False
    if "bf16" in low or "-0000" in n or "mmproj" in low or "mtp" in low:
        return False
    return True

def pick_best(repo):
    """Return (filename, size_gb, quant_rank) for the best file fitting budget.

    Within a family, the LARGEST file that fits is the best quant (more bits =
    higher quality). Families whose smallest file is still way over budget are
    skipped entirely (they cannot run on this hardware).
    """
    d = fetch(f"https://huggingface.co/api/models/{repo}?blobs=true")
    if not d or "siblings" not in d:
        return None
    files = []
    for s in d["siblings"]:
        n = s.get("rfilename", "")
        if not good_file(n):
            continue
        size_gb = s.get("size", 0) / (1024 ** 3)
        if size_gb < 1:
            continue
        files.append((n, size_gb, qrank(n)))
    if not files:
        return None
    preferred_name = PREFERRED_FILES.get(repo)
    if preferred_name:
        preferred = next((f for f in files if f[0] == preferred_name), None)
        if preferred and preferred[1] <= budget_gb + 0.2:
            return preferred, d
    fast_budget = min(budget_gb, full_gpu_budget_gb) if full_gpu_budget_gb > 0 else budget_gb
    fits = [f for f in files if f[1] <= fast_budget + 0.2]
    if fits:
        fits.sort(key=lambda f: -f[1])
        return fits[0], d
    hybrid_fits = [f for f in files if f[1] <= budget_gb + 0.2]
    if hybrid_fits:
        hybrid_fits.sort(key=lambda f: -f[1])
        return hybrid_fits[0], d
    # Nothing fits - only keep the family if it is just barely over budget
    smallest = min(files, key=lambda f: f[1])
    if smallest[1] <= budget_gb + 2.0:
        return smallest, d
    return None

def metadata_score(d):
    tags = " ".join(d.get("tags") or []).lower()
    pipeline = (d.get("pipeline_tag") or "").lower()
    score = 0
    for needle, points in [
        ("agent", 24), ("tool", 22), ("function", 18), ("coding", 16),
        ("reasoning", 12), ("instruct", 10), ("image-text-to-text", 8),
        ("mtp", 6), ("llama.cpp", 4),
    ]:
        if needle in tags or needle in pipeline:
            score += points
    if any(x in tags for x in ["base_model:", "license:"]):
        score += 2
    if any(x in tags for x in ["uncensored", "abliterated", "heretic", "roleplay"]):
        score -= 30
    downloads = int(d.get("downloads") or 0)
    score += min(20, downloads // 100000)
    return score

candidates = []  # (repo, file, size_gb, label, score)
for repo, rank, label in FAMILIES:
    best = pick_best(repo)
    if best:
        file_info, meta = best
        candidates.append((repo, file_info[0], file_info[1], label,
                           rank * 10 + metadata_score(meta) + (20 - file_info[2])))

# Trending discovery: catch brand-new models the curated list doesn't know yet
seen = {c[0] for c in candidates}
try:
    tr = fetch("https://huggingface.co/api/models?search=gguf&sort=trendingScore&direction=-1&limit=30")
    for m in tr or []:
        rid = m.get("id", "")
        if "ornith" in rid.lower():
            continue
        if rid in seen or not any(k in rid.lower() for k in
            ["glm", "qwen", "gemma", "deepseek", "minimax", "mistral", "llama",
             "nemotron", "phi", "granite", "rnj", "north", "mimo"]):
            continue
        dl = m.get("downloads", 0)
        if dl < 50000:
            continue
        best = pick_best(rid)
        if best:
            file_info, meta = best
            # Trending popularity boosts the score so a genuinely NEW SOTA model
            # (millions of downloads, not in our curated list) can win over
            # older curated families. Caps below the very top curated pick.
            tscore = 500 + metadata_score(meta) + min(80, dl // 100000)
            candidates.append((rid, file_info[0], file_info[1],
                               f"{rid} (live discovery, {dl} downloads)", tscore))
        seen.add(rid)
except Exception:
    pass

# Sort: score desc, then size desc (bigger = more capable)
candidates.sort(key=lambda c: (-c[4], -c[2]))
for repo, file, size_gb, label, score in candidates[:12]:
    print(f"{repo}|{file}|{size_gb:.1f}|{label}|{score}")
DISCOVERYEOF

if [ -s "$DISCOVERY_OUT" ]; then
    info "  Best models found online right now (best first):"
    head -6 "$DISCOVERY_OUT" | while IFS='|' read -r r f s l sc; do
        info "    - $l ($s GB)"
    done
fi

# Try live-discovered candidates first, then the static chain
if [ -s "$DISCOVERY_OUT" ]; then
    while IFS='|' read -r repo file size label score; do
        [ -z "$repo" ] && continue
        if ! awk -v s="$size" -v b="$MODEL_BUDGET_GB" 'BEGIN{exit !(s <= b + 0.2)}' 2>/dev/null; then
            continue
        fi
        dest="$MODEL_DIR/$file"
        if [ -f "$dest" ]; then
            ok "  Using already-downloaded best model: $label"
            CHOSEN_MODEL="$dest"; CHOSEN_LABEL="$label"; CHOSEN_REPO="$repo"
            break
        fi
        if hf_file_exists "$repo" "$file"; then
            if download_model "https://huggingface.co/${repo}/resolve/main/${file}" "$dest" "$label" "$size"; then
                CHOSEN_MODEL="$dest"; CHOSEN_LABEL="$label"; CHOSEN_REPO="$repo"
                break
            fi
        else
            info "  $label not available on HuggingFace right now - checking next best"
        fi
    done < "$DISCOVERY_OUT"
fi

if [ -z "$CHOSEN_MODEL" ]; then
    warn "  Live discovery found nothing - using verified fallback chain"
    for entry in "${MODEL_CANDIDATES[@]}"; do
        repo="${entry%%|*}"; rest="${entry#*|}"
        file="${rest%%|*}"; rest="${rest#*|}"
        size="${rest%%|*}"; label="${rest#*|}"
        if ! awk -v s="$size" -v b="$MODEL_BUDGET_GB" 'BEGIN{exit !(s <= b)}' 2>/dev/null; then
            continue
        fi
        dest="$MODEL_DIR/$file"
        if [ -f "$dest" ]; then
            ok "  Using already-downloaded best model: $label"
            CHOSEN_MODEL="$dest"; CHOSEN_LABEL="$label"; CHOSEN_REPO="$repo"
            break
        fi
        if hf_file_exists "$repo" "$file"; then
            if download_model "https://huggingface.co/${repo}/resolve/main/${file}" "$dest" "$label" "$size"; then
                CHOSEN_MODEL="$dest"; CHOSEN_LABEL="$label"; CHOSEN_REPO="$repo"
                break
            fi
        else
            info "  $label not available on HuggingFace right now - checking next best"
        fi
    done
fi
rm -f "$DISCOVERY_OUT"

# Last resort: keep any existing model so the agent always has something to use
if [ -z "$CHOSEN_MODEL" ]; then
    BEST_LOCAL=$(find "$MODEL_DIR" -maxdepth 1 -name '*.gguf' -type f -printf '%s %p\n' 2>/dev/null \
        | while read -r size path; do
            is_main_model_file "$path" && printf '%s %s\n' "$size" "$path"
          done \
        | sort -rn | head -1 | cut -d' ' -f2-)
    if [ -n "$BEST_LOCAL" ] && [ -f "$BEST_LOCAL" ]; then
        warn "  Could not download a new model - keeping existing: $(basename "$BEST_LOCAL")"
        CHOSEN_MODEL="$BEST_LOCAL"
        CHOSEN_LABEL="existing $(basename "$BEST_LOCAL")"
    else
        # Absolute last resort: a tiny universal model that fits ANY hardware.
        # Even a 1.5B model gives a fully working interactive agent.
        info "  Downloading the smallest reliable model (Qwen 2.5 1.5B Q4, ~1GB)..."
        for entry in \
            "Qwen/Qwen2.5-1.5B-Instruct-GGUF|qwen2.5-1.5b-instruct-q4_k_m.gguf|1.1|Qwen 2.5 1.5B Q4_K_M"; do
            repo="${entry%%|*}"; rest="${entry#*|}"
            file="${rest%%|*}"; rest="${rest#*|}"
            size="${rest%%|*}"; label="${rest#*|}"
            dest="$MODEL_DIR/$file"
            if hf_file_exists "$repo" "$file"; then
                if download_model "https://huggingface.co/${repo}/resolve/main/${file}" "$dest" "$label" "$size"; then
                    CHOSEN_MODEL="$dest"; CHOSEN_LABEL="$label"; CHOSEN_REPO="$repo"
                    ok "  Fallback model selected: $label"
                    break
                fi
            else
                warn "  Last-resort model unavailable. Check your internet connection and re-run."
            fi
        done
    fi
fi

if [ -n "$CHOSEN_MODEL" ]; then
    echo "$(basename "$CHOSEN_MODEL")" > "$MODEL_DIR/.chosen-model"
    ok "  BEST MODEL SELECTED: $CHOSEN_LABEL"
fi

# ── Vision encoder (mmproj) + MTP draft head for the CHOSEN model ──
# Whichever model won selection, we look in its own repo for:
#   - mmproj-*.gguf   (vision encoder -> image understanding capability)
#   - MTP/mtp-*.gguf  (optional speculative-decoding draft head; benchmark required)
# This is fully generic: new models get vision + spec-decoding automatically.
CHOSEN_MMPROJ=""
CHOSEN_DRAFT=""
if [ -n "$CHOSEN_REPO" ]; then
    EXTRAS_OUT="$(mktemp)"
    python3 - "$CHOSEN_REPO" > "$EXTRAS_OUT" 2>/dev/null <<'EXTRASEOF' || true
import json, sys, urllib.request, time
repo = sys.argv[1]
def fetch(url, tries=2):
    for i in range(tries):
        try:
            req = urllib.request.Request(url, headers={"User-Agent": "local-ai-installer"})
            with urllib.request.urlopen(req, timeout=25) as r:
                return json.loads(r.read().decode())
        except Exception:
            time.sleep(2)
    return None
d = fetch(f"https://huggingface.co/api/models/{repo}?blobs=true")
if not d or "siblings" not in d:
    sys.exit(0)
mmprojs = []
drafts = []
for s in d["siblings"]:
    n = s.get("rfilename", "")
    low = n.lower()
    size = s.get("size", 0) / (1024 ** 3)
    if size < 0.05:
        continue
    if "mmproj" in low and n.endswith(".gguf") and "bf16" not in low:
        mmprojs.append((n, size, 0 if "f16" in low else 1))
    elif "/mtp-" in n.lower() or (n.lower().startswith("mtp/") and n.endswith(".gguf")):
        drafts.append((n, size, 0 if "q8" in low else (1 if "f16" in low else 2)))
# Prefer F16 mmproj (small, fast); prefer Q8_0 draft (smallest, fastest spec decode)
if mmprojs:
    best = min(mmprojs, key=lambda x: (x[2], x[1]))
    print(f"MMPROJ|{best[0]}|{best[1]:.2f}")
if drafts:
    best = min(drafts, key=lambda x: (x[2], x[1]))
    print(f"DRAFT|{best[0]}|{best[1]:.2f}")
EXTRASEOF
    while IFS='|' read -r kind file size; do
        [ -z "$kind" ] && continue
        if [ "$kind" = "MMPROJ" ]; then
            DEST="$MODEL_DIR/$file"
            if [ ! -f "$DEST" ] && hf_file_exists "$CHOSEN_REPO" "$file"; then
                download_model "https://huggingface.co/${CHOSEN_REPO}/resolve/main/${file}" \
                    "$DEST" "Vision encoder $file" "$size" "0.8" || true
            fi
            if [ -f "$DEST" ]; then
                CHOSEN_MMPROJ="$DEST"
                echo "$file" > "$MODEL_DIR/.chosen-mmproj"
                ok "  Vision encoder downloaded - image input remains unverified until a live probe passes"
            fi
        elif [ "$kind" = "DRAFT" ]; then
            DEST="$MODEL_DIR/MTP/$(basename "$file")"
            mkdir -p "$MODEL_DIR/MTP"
            if [ ! -f "$DEST" ] && hf_file_exists "$CHOSEN_REPO" "$file"; then
                download_model "https://huggingface.co/${CHOSEN_REPO}/resolve/main/${file}" \
                    "$DEST" "MTP draft $(basename "$file")" "$size" "0.8" || true
            fi
            if [ -f "$DEST" ]; then
                CHOSEN_DRAFT="$DEST"
                echo "$(basename "$file")" > "$MODEL_DIR/.chosen-draft"
                ok "  MTP draft downloaded - performance remains unverified until benchmarked"
            fi
        fi
    done < "$EXTRAS_OUT"
    rm -f "$EXTRAS_OUT"
fi
if [ -z "$CHOSEN_DRAFT" ]; then
    rm -f "$MODEL_DIR/.chosen-draft"
fi
if [ -z "$CHOSEN_MMPROJ" ]; then
    rm -f "$MODEL_DIR/.chosen-mmproj"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 5 — Passwordless sudo
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 5/11: Configuring passwordless sudo..."
SUDOERS_FILE="/etc/sudoers.d/local-ai-agent"
SUDOERS_NEXT=$(mktemp)
cat > "$SUDOERS_NEXT" <<SUDOERS
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dpkg, /usr/bin/apt-mark
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/systemctl, /usr/bin/systemd-run
$(whoami) ALL=(ALL) NOPASSWD: /usr/sbin/useradd, /usr/sbin/usermod, /usr/sbin/userdel
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/chmod, /usr/bin/chown
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/mkdir, /usr/bin/touch, /usr/bin/cp, /usr/bin/mv, /usr/bin/rm
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/mount
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/tar, /usr/bin/gzip, /usr/bin/gunzip
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/docker
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/crontab
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/sed, /usr/bin/grep, /usr/bin/find, /usr/bin/xargs
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/curl, /usr/bin/wget
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/python3, /usr/bin/python3.12, /usr/bin/python3.11, /usr/bin/python3.10
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/pip3
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/npm, /usr/bin/npx, /usr/bin/node
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/git
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/dockerd, /usr/bin/docker-compose
$(whoami) ALL=(ALL) NOPASSWD: /sbin/reboot, /sbin/shutdown
$(whoami) ALL=(ALL) NOPASSWD: /usr/bin/kill, /bin/kill
SUDOERS
sudo visudo -cf "$SUDOERS_NEXT" >/dev/null ||
    fail "The generated Local AI sudo policy did not pass visudo validation"
sudo cp "$SUDOERS_NEXT" "$SUDOERS_FILE"
sudo chmod 0440 "$SUDOERS_FILE"
rm -f "$SUDOERS_NEXT"
ok "Passwordless sudo configured"
install_wsl_interop_guard ||
    fail "WSL-to-Windows executable recovery could not be installed and verified"
ensure_wsl_interop ||
    fail "WSL-to-Windows executable support remained unavailable after three repair attempts"
ok "WSL-to-Windows executable support is live and protected across systemd starts"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 6 — Windows tools (win-tools + PowerShell helper)
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 6/11: Installing Windows tools..."
mkdir -p "$HOME/.local/bin"

# ── PowerShell helper on Windows side ──
WIN_PUBLIC="/mnt/c/Users/Public"
if [ -d "$WIN_PUBLIC" ]; then
    ensure_wsl_interop ||
        fail "Windows helper installation cannot continue because WSL interop could not be restored"
    # Write with a UTF-8 BOM so Windows PowerShell 5.1 reads it as UTF-8.
    # Without a BOM, PS 5.1 assumes ANSI (Windows-1252): any non-ASCII byte
    # (e.g. an em dash) decodes to a stray quote and BREAKS the whole script.
    printf '\xEF\xBB\xBF' > "$WIN_PUBLIC/llama-win-tools.ps1"
    cat >> "$WIN_PUBLIC/llama-win-tools.ps1" <<'PSEOF'
param(
    [string]$Action = "help",
    [string]$Drive = "C"
)
# Any extra args (e.g. the search pattern) arrive via $args with -File.
$Top = 10
$pattern = $args[0]
$searchMode = if ($args.Count -gt 1) { ([string]$args[1]).Trim().ToUpperInvariant() } else { "ALL" }

function Get-LlamaSearchRoots {
    param([string]$Drive)
    $requested = [string]$Drive
    if ([string]::IsNullOrWhiteSpace($requested)) {
        $requested = "C"
    }
    $requested = $requested.Trim().TrimEnd(':')
    if ($requested -match '^(?i:all)$') {
        return @(
            [System.IO.DriveInfo]::GetDrives() |
                Where-Object { $_.IsReady -and $_.DriveType -eq 'Fixed' } |
                ForEach-Object { $_.RootDirectory.FullName } |
                Sort-Object
        )
    }
    if ($requested -notmatch '^[A-Za-z]$') {
        return @()
    }
    return @("${requested}:\")
}

function Write-LlamaProgress {
    param(
        [string]$Operation,
        [string]$Phase,
        [string]$Drive,
        [hashtable]$State,
        [string]$CurrentPath
    )
    $pathText = (([string]$CurrentPath) -replace '\|', '/').Trim()
    Write-Output (
        "LLAMA_PROGRESS|{0}|{1}|{2}|{3}|{4}|{5}|{6}" -f
        $Operation, $Phase, $Drive, $State.Directories, $State.Files,
        $State.Matches, $pathText
    )
}

function Invoke-LlamaFileWalk {
    param(
        [string[]]$Roots,
        [string]$Operation,
        [scriptblock]$OnFile,
        [ref]$StateOut
    )
    $state = @{
        Directories = [long]0
        Files = [long]0
        Matches = [long]0
        Root = ""
        Drive = ""
        LastProgressAt = [DateTime]::UtcNow
        LastProgressDirectories = [long]0
        LastProgressFiles = [long]0
        StopRequested = $false
    }
    foreach ($root in $Roots) {
        if ($state.StopRequested) {
            break
        }
        if (-not (Test-Path -LiteralPath $root)) {
            continue
        }
        $state.Root = $root
        $state.Drive = $root.Substring(0, 2)
        Write-LlamaProgress $Operation "started" $state.Drive $state $root
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($root)
        while ($pending.Count -gt 0 -and -not $state.StopRequested) {
            $directory = $pending.Pop()
            $state.Directories++
            try {
                foreach ($filePath in [System.IO.Directory]::EnumerateFiles($directory)) {
                    $state.Files++
                    & $OnFile $filePath $state
                    if ($state.StopRequested) {
                        break
                    }
                    $elapsed = ([DateTime]::UtcNow - $state.LastProgressAt).TotalSeconds
                    if (
                        ($state.Files - $state.LastProgressFiles -ge 2000) -or
                        ($state.Directories - $state.LastProgressDirectories -ge 250) -or
                        ($elapsed -ge 1.0)
                    ) {
                        Write-LlamaProgress $Operation "scanning" $state.Drive $state $directory
                        $state.LastProgressAt = [DateTime]::UtcNow
                        $state.LastProgressDirectories = $state.Directories
                        $state.LastProgressFiles = $state.Files
                    }
                }
            } catch {}
            if (-not $state.StopRequested) {
                try {
                    foreach ($child in [System.IO.Directory]::EnumerateDirectories($directory)) {
                        try {
                            if (([System.IO.File]::GetAttributes($child) -band [System.IO.FileAttributes]::ReparsePoint) -eq 0) {
                                $pending.Push($child)
                            }
                        } catch {}
                    }
                } catch {}
            }
        }
        $phase = if ($state.StopRequested) { "stopped-after-exact-match" } else { "complete" }
        Write-LlamaProgress $Operation $phase $state.Drive $state $root
    }
    $StateOut.Value = $state
}

switch ($Action) {
    "scan" {
        $driveLetter = $Drive.TrimEnd(':')
        $roots = Get-LlamaSearchRoots $driveLetter
        if (-not $roots) {
            Write-Host "Drive ${driveLetter}: not found" -ForegroundColor Yellow
            return
        }
        Write-Host "Scanning ${driveLetter}: drive - measuring top-level folder sizes with live traversal checkpoints..." -ForegroundColor Cyan
        $sizes = @{}
        $walk = $null
        Invoke-LlamaFileWalk $roots "scan" {
            param($filePath, $state)
            try {
                $relative = $filePath.Substring($state.Root.Length).TrimStart('\')
                $first = ($relative -split '\\', 2)[0]
                if (-not $first) { $first = "(root)" }
                $key = Join-Path -Path $state.Root -ChildPath $first
                $length = ([System.IO.FileInfo]$filePath).Length
                $knownSize = if ($sizes.ContainsKey($key)) { [long]$sizes[$key] } else { [long]0 }
                $sizes[$key] = $knownSize + $length
            } catch {}
        } ([ref]$walk)
        $sizes.GetEnumerator() |
            Sort-Object Value -Descending |
            Select-Object -First $Top |
            ForEach-Object {
                Write-Host ("{0}|{1} GB" -f $_.Key, [math]::Round($_.Value / 1GB, 2))
            }
        if ($walk) {
            Write-Host ("SUMMARY|scan|folders={0}|directories={1}|files={2}" -f $sizes.Count, $walk.Directories, $walk.Files)
        }
    }
    "files" {
        $driveLetter = $Drive.TrimEnd(':')
        $requestedTop = 50
        $parsedTop = 0
        if ($args.Count -gt 0 -and [int]::TryParse([string]$args[0], [ref]$parsedTop)) {
            $requestedTop = [math]::Min(200, [math]::Max(1, $parsedTop))
        }
        $roots = Get-LlamaSearchRoots $driveLetter
        if (-not $roots) {
            Write-Host "Drive ${driveLetter}: not found" -ForegroundColor Yellow
            return
        }
        Write-Host "Scanning ${driveLetter}: drive - retaining only the $requestedTop largest files while reporting real traversal checkpoints." -ForegroundColor Cyan
        $rank = @{
            Items = New-Object 'System.Collections.Generic.List[object]'
            MinIndex = -1
            MinLength = [long]::MaxValue
        }
        $walk = $null
        Invoke-LlamaFileWalk $roots "files" {
            param($filePath, $state)
            try {
                $info = [System.IO.FileInfo]$filePath
                $candidate = [PSCustomObject]@{ FullName = $info.FullName; Length = [long]$info.Length }
                if ($rank.Items.Count -lt $requestedTop) {
                    $rank.Items.Add($candidate)
                    if ($candidate.Length -lt $rank.MinLength) {
                        $rank.MinLength = $candidate.Length
                        $rank.MinIndex = $rank.Items.Count - 1
                    }
                } else {
                    if ($candidate.Length -gt $rank.MinLength) {
                        $rank.Items[$rank.MinIndex] = $candidate
                        $nextMinIndex = 0
                        $nextMinLength = [long]$rank.Items[0].Length
                        for ($index = 1; $index -lt $rank.Items.Count; $index++) {
                            $length = [long]$rank.Items[$index].Length
                            if ($length -lt $nextMinLength) {
                                $nextMinLength = $length
                                $nextMinIndex = $index
                            }
                        }
                        $rank.MinIndex = $nextMinIndex
                        $rank.MinLength = $nextMinLength
                    }
                }
            } catch {}
        } ([ref]$walk)
        $rank.Items | Sort-Object Length -Descending | ForEach-Object {
            Write-Host ("{0}|{1}|{2} GB" -f $_.FullName, $_.Length, [math]::Round($_.Length / 1GB, 3))
        }
        if ($walk) {
            Write-Host ("SUMMARY|files|ranked={0}|directories={1}|files={2}" -f $rank.Items.Count, $walk.Directories, $walk.Files)
        }
    }
    "search" {
        $driveLetter = $Drive.TrimEnd(':')
        if (-not $pattern) { Write-Host "Usage: win-tools search [drive|ALL] <pattern> [FIRST|ALL]"; return }
        $firstExact = $searchMode -eq "FIRST"
        $roots = Get-LlamaSearchRoots $driveLetter
        if (-not $roots) {
            Write-Host "Drive ${driveLetter}: not found" -ForegroundColor Yellow
            return
        }
        $modeText = if ($firstExact) {
            "the first exact filename '$pattern'"
        } else {
            "all filenames containing '$pattern'"
        }
        Write-Host "Searching $($roots.Count) fixed Windows drive(s) for $modeText with live directory and file counts..." -ForegroundColor Cyan
        $matches = New-Object System.Collections.ArrayList
        $walk = $null
        Invoke-LlamaFileWalk $roots "search" {
            param($filePath, $state)
            try {
                $name = [System.IO.Path]::GetFileName($filePath)
                $isMatch = if ($firstExact) {
                    [string]::Equals(
                        $name,
                        $pattern,
                        [System.StringComparison]::OrdinalIgnoreCase
                    )
                } else {
                    $name -like "*$pattern*"
                }
                if ($isMatch) {
                    $state.Matches++
                    $info = [System.IO.FileInfo]$filePath
                    if ($matches.Count -lt 50) {
                        [void]$matches.Add([PSCustomObject]@{
                            FullName = $info.FullName
                            Length = [long]$info.Length
                        })
                        Write-LlamaProgress "search" "match" $state.Drive $state $info.FullName
                    }
                    if ($firstExact) {
                        $state.StopRequested = $true
                    }
                }
            } catch {}
        } ([ref]$walk)
        $matches | ForEach-Object {
            Write-Host ("MATCH|{0}|{1}" -f $_.FullName, $_.Length)
        }
        if ($walk) {
            Write-Host ("SUMMARY|search|mode={0}|matches={1}|reported={2}|directories={3}|files={4}|stopped_early={5}" -f $searchMode, $walk.Matches, $matches.Count, $walk.Directories, $walk.Files, $walk.StopRequested)
        }
    }
    "dir" {
        $foldersOnly = ([string]$pattern).Trim().ToUpperInvariant() -eq "FOLDERS"
        $driveLetter = $Drive.Trim().TrimEnd(':').ToUpperInvariant()
        if ($driveLetter -notmatch '^[A-Z]$') {
            Write-Host "ERROR|Invalid Windows drive '$Drive'. Supply one drive letter." -ForegroundColor Red
            exit 2
        }
        $root = "${driveLetter}:\"
        if (-not [System.IO.Directory]::Exists($root)) {
            Write-Host "ERROR|Windows drive ${driveLetter}: is not available." -ForegroundColor Red
            exit 3
        }
        try {
            $items = @(Get-ChildItem -LiteralPath $root -Force -ErrorAction Stop)
        } catch {
            Write-Host ("ERROR|Could not list Windows drive {0}: {1}" -f $driveLetter, $_.Exception.Message) -ForegroundColor Red
            exit 4
        }
        $folderItems = @($items | Where-Object { $_.PSIsContainer })
        $shownFolders = if ($foldersOnly) {
            $folderItems
        } else {
            @($folderItems | Select-Object -First $Top)
        }
        Write-Host "Top-level folders on ${driveLetter} (NAME|LASTWRITE):" -ForegroundColor Cyan
        $shownFolders |
            Select-Object Name, LastWriteTime |
            ForEach-Object { Write-Host ("FOLDER|{0}|{1}" -f $_.Name, $_.LastWriteTime) }
        if (-not $foldersOnly) {
            Write-Host ""
            Write-Host "Top-level files on ${driveLetter} (NAME|MB):" -ForegroundColor Cyan
            $items | Where-Object { -not $_.PSIsContainer } |
                Select-Object -First $Top Name, @{N='MB';E={[math]::Round($_.Length/1MB,1)}} |
                ForEach-Object { Write-Host ("FILE|{0}|{1}" -f $_.Name, $_.MB) }
        }
        $folderCount = $folderItems.Count
        $fileCount = @($items | Where-Object { -not $_.PSIsContainer }).Count
        if ($foldersOnly) {
            Write-Host ("SUMMARY|dir|drive={0}|folders={1}|mode=folders-only" -f $driveLetter, $folderCount)
        } else {
            Write-Host ("SUMMARY|dir|drive={0}|folders={1}|files={2}" -f $driveLetter, $folderCount, $fileCount)
        }
    }
    "startup" {
        Write-Host "Programs that run at Windows boot:" -ForegroundColor Cyan
        $items = @()
        $runKeys = @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )
        foreach ($k in $runKeys) {
            if (Test-Path $k) {
                $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
                $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                    $items += [PSCustomObject]@{ 'Item' = $_.Name; 'Command' = $_.Value }
                }
            }
        }
        $startupDirs = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        )
        foreach ($d in $startupDirs) {
            if (Test-Path $d) {
                Get-ChildItem $d -ErrorAction SilentlyContinue | ForEach-Object {
                    $items += [PSCustomObject]@{ 'Item' = $_.Name; 'Command' = $_.FullName }
                }
            }
        }
        if ($items.Count -gt 0) {
            $items | Select-Object -First $Top | ForEach-Object {
                Write-Host ("{0}|{1}" -f $_.Item, $_.Command)
            }
        } else {
            Write-Host "No startup items found."
        }
        Write-Host ""
        Write-Host "Top CPU consumers right now (NAME|CPU_SEC|RAM_MB):" -ForegroundColor Cyan
        Get-Process | Sort-Object CPU -Descending |
            Select-Object -First $Top Name, @{N='CPU s';E={[math]::Round($_.CPU,0)}}, @{N='RAM MB';E={[math]::Round($_.WorkingSet64/1MB,0)}} |
            ForEach-Object { Write-Host ("{0}|{1}|{2}" -f $_.Name, $_.'CPU s', $_.'RAM MB') }
    }
    "disk" {
        $driveLetter = $Drive.TrimEnd(':')
        try {
            $d = [System.IO.DriveInfo]::new("${driveLetter}:\")
        } catch {
            $d = $null
        }
        if ($d -and $d.IsReady) {
            $totalBytes = $d.TotalSize
            $freeBytes = $d.AvailableFreeSpace
            $usedBytes = $totalBytes - $freeBytes
            $usedGB = [math]::Round($usedBytes/1GB,2)
            $freeGB = [math]::Round($freeBytes/1GB,2)
            $totalGB = [math]::Round($totalBytes/1GB,2)
            Write-Host "${driveLetter}: Drive" -ForegroundColor Cyan
            Write-Host "  Used:      $usedGB GB"
            Write-Host "  Free:      $freeGB GB"
            Write-Host "  Total:     $totalGB GB"
        } else {
            Write-Host "Drive ${driveLetter}: not found" -ForegroundColor Yellow
        }
    }
    "processes" {
        Write-Host "Top memory-consuming processes (NAME|RAM_MB):" -ForegroundColor Cyan
        Get-Process | Sort-Object WorkingSet64 -Descending |
            Select-Object -First 15 Name, @{N='RAM MB';E={[math]::Round($_.WorkingSet64/1MB,0)}} |
            ForEach-Object { Write-Host ("{0}|{1}" -f $_.Name, $_.'RAM MB') }
    }
    "services" {
        Write-Host "Running services (NAME|DISPLAY):" -ForegroundColor Cyan
        Get-Service | Where-Object Status -eq Running |
            Select-Object -First 20 Name, DisplayName |
            ForEach-Object { Write-Host ("{0}|{1}" -f $_.Name, $_.DisplayName) }
    }
    "boot" {
        # EVERYTHING that runs at Windows boot, correlated with live CPU/RAM.
        Write-Host "Everything that runs at Windows boot (ranked by current CPU/RAM):" -ForegroundColor Cyan
        $items = @()
        $runKeys = @(
            'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\Microsoft\Windows\CurrentVersion\Run',
            'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
        )
        foreach ($k in $runKeys) {
            if (Test-Path $k) {
                $p = Get-ItemProperty -Path $k -ErrorAction SilentlyContinue
                $p.PSObject.Properties | Where-Object { $_.Name -notmatch '^PS' } | ForEach-Object {
                    $items += [PSCustomObject]@{ 'Item' = $_.Name; 'Source' = 'Registry Run key'; 'Command' = $_.Value }
                }
            }
        }
        $startupDirs = @(
            "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
            "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        )
        foreach ($d in $startupDirs) {
            if (Test-Path $d) {
                Get-ChildItem $d -ErrorAction SilentlyContinue | ForEach-Object {
                    $items += [PSCustomObject]@{ 'Item' = $_.BaseName; 'Source' = 'Startup folder'; 'Command' = $_.FullName }
                }
            }
        }
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            ($_.Triggers | Where-Object { $_.CimClass.CimClassName -match 'Logon|Boot' }) -and $_.State -ne 'Disabled'
        } | ForEach-Object {
            $items += [PSCustomObject]@{ 'Item' = $_.TaskName; 'Source' = 'Scheduled task (logon/boot)'; 'Command' = $_.TaskPath }
        }
        Get-CimInstance Win32_Service -ErrorAction SilentlyContinue | Where-Object { $_.StartMode -eq 'Auto' -and $_.State -eq 'Running' } | ForEach-Object {
            $items += [PSCustomObject]@{
                'Item' = $_.Name; 'Source' = 'Auto-start service'
                'Command' = $_.PathName; 'ProcessId' = [int]$_.ProcessId
            }
        }
        $procs = Get-Process -ErrorAction SilentlyContinue
        $report = foreach ($it in $items) {
            $base = ""
            try { $base = [System.IO.Path]::GetFileNameWithoutExtension($it.Command) } catch {}
            $matches = @()
            if ($it.Source -eq 'Auto-start service' -and $it.ProcessId -gt 0) {
                $matches = @($procs | Where-Object { $_.Id -eq $it.ProcessId })
            } elseif ($base) {
                $matches = @($procs | Where-Object { $_.ProcessName -like "$base*" })
            }
            if (-not $matches -and $it.Source -ne 'Auto-start service' -and $it.Item) {
                $matches = @($procs | Where-Object { $_.ProcessName -like "$($it.Item)*" })
            }
            $cpu = 0; $ram = 0; $procName = "(not running)"
            if ($matches) {
                $procName = ($matches | Select-Object -First 1).ProcessName
                if ($matches.Count -gt 1) { $procName += " (+$($matches.Count - 1) more)" }
                foreach ($m in $matches) { $cpu += $m.CPU; $ram += $m.WorkingSet64 }
            }
            [PSCustomObject]@{
                'Startup Item'    = $it.Item
                'Source'          = $it.Source
                'Matched Process' = $procName
                'CPU s'           = [math]::Round($cpu, 0)
                'RAM MB'          = [math]::Round($ram / 1MB, 0)
            }
        }
        $report | Sort-Object `
            @{Expression='CPU s'; Descending=$true}, `
            @{Expression='RAM MB'; Descending=$true}, `
            @{Expression='Startup Item'; Descending=$false} | ForEach-Object {
            Write-Host ("{0}|{1}|{2}|{3}|{4}" -f $_.'Startup Item', $_.Source, $_.'Matched Process', $_.'CPU s', $_.'RAM MB')
        }
        Write-Host ""
        Write-Host "Format: ITEM|SOURCE|MATCHED_PROCESS|CPU_SEC|RAM_MB - CPU s is cumulative since boot, RAM MB is current." -ForegroundColor DarkGray
    }
    "scheduled" {
        Write-Host "Scheduled tasks (enabled) (NAME|STATE|TRIGGER):" -ForegroundColor Cyan
        Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object { $_.State -ne 'Disabled' } |
            Select-Object -First 30 TaskName, State, @{N='Trigger';E={($_.Triggers | Select-Object -First 1).CimClass.CimClassName}} |
            ForEach-Object { Write-Host ("{0}|{1}|{2}" -f $_.TaskName, $_.State, $_.Trigger) }
    }
    "gui" {
        # GUI automation: activate a window by title substring, then send keys.
        # Usage: win-tools gui <window-title> <keys>   (e.g. Notepad "Hello{ENTER}")
        $title = $args[0]
        $keys = $args[1]
        if (-not $title) { Write-Host "Usage: win-tools gui <window-title> <keys>"; return }
        if (-not $keys) { Write-Host "Usage: win-tools gui <window-title> <keys>"; return }
        $wsh = New-Object -ComObject WScript.Shell
        $ok = $wsh.AppActivate($title)
        if (-not $ok) { Write-Host "No window titled '$title' found"; return }
        Start-Sleep -Milliseconds 300
        $wsh.SendKeys($keys)
        Write-Host "Sent keys to window: $title"
    }
    "clip" {
        $mode = $args[0]
        if ($mode -eq 'set') {
            $text = $args[1]
            if (-not $text) { Write-Host "Usage: win-tools clip set <text>"; return }
            Set-Clipboard -Value $text
            Write-Host "Clipboard set: $text"
        } else {
            $c = Get-Clipboard -Raw -ErrorAction SilentlyContinue
            if ($c) { Write-Host $c } else { Write-Host "(clipboard is empty)" }
        }
    }
    "notify" {
        $title = $args[0]
        $msg = $args[1]
        if (-not $title) { $title = "Local AI Agent" }
        if (-not $msg) { $msg = "Task finished" }
        Add-Type -AssemblyName System.Windows.Forms
        $n = New-Object System.Windows.Forms.NotifyIcon
        $n.Icon = [System.Drawing.SystemIcons]::Information
        $n.Visible = $true
        $n.BalloonTipTitle = $title
        $n.BalloonTipText = $msg
        $n.ShowBalloonTip(5000)
        Write-Host "Notification sent: $title - $msg"
    }
    "shot" {
        Add-Type -AssemblyName System.Windows.Forms
        Add-Type -AssemblyName System.Drawing
        $b = [System.Windows.Forms.SystemInformation]::VirtualScreen
        $bmp = New-Object System.Drawing.Bitmap $b.Width, $b.Height
        $g = [System.Drawing.Graphics]::FromImage($bmp)
        $g.CopyFromScreen($b.Left, $b.Top, 0, 0, $bmp.Size)
        $out = "C:\Users\Public\llama-shot.png"
        $bmp.Save($out, [System.Drawing.Imaging.ImageFormat]::Png)
        $g.Dispose(); $bmp.Dispose()
        Write-Host "Screenshot saved to: $out"
        Write-Host "Linux path: /mnt/c/Users/Public/llama-shot.png"
        $ocr = Get-Command tesseract -ErrorAction SilentlyContinue
        if ($ocr) {
            $txt = & tesseract $out stdout 2>$null
            if ($txt) { Write-Host "OCR text:"; Write-Host $txt }
        } else {
            Write-Host "Windows tesseract not found - OCR available from WSL2 with: tesseract /mnt/c/Users/Public/llama-shot.png stdout"
        }
    }
    "net" {
        Write-Host "Network adapters (INTERFACE|IPv4):" -ForegroundColor Cyan
        Get-NetIPConfiguration -ErrorAction SilentlyContinue |
            Select-Object InterfaceAlias, @{N='IPv4';E={$_.IPv4Address.IPAddress}} |
            ForEach-Object { Write-Host ("{0}|{1}" -f $_.InterfaceAlias, $_.IPv4) }
        Write-Host "Adapters (NAME|STATUS|SPEED):" -ForegroundColor Cyan
        Get-NetAdapter -ErrorAction SilentlyContinue |
            Select-Object Name, Status, LinkSpeed |
            ForEach-Object { Write-Host ("{0}|{1}|{2}" -f $_.Name, $_.Status, $_.LinkSpeed) }
        $wifi = netsh wlan show interfaces 2>$null
        if ($wifi) { Write-Host ($wifi | Out-String) }
    }
    "gpu" {
        Write-Host "GPU (NAME|DRIVER):" -ForegroundColor Cyan
        Get-CimInstance Win32_VideoController -ErrorAction SilentlyContinue |
            Select-Object Name, DriverVersion |
            ForEach-Object { Write-Host ("{0}|{1}" -f $_.Name, $_.DriverVersion) }
    }
    "battery" {
        $b = Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue
        if ($b) {
            $pct = $b.EstimatedChargeRemaining
            $status = switch ($b.BatteryStatus) { 1 {"Discharging"} 2 {"On AC power"} 3 {"Fully charged"} default {"Unknown"} }
            Write-Host "Battery: $pct% ($status)"
        } else {
            Write-Host "No battery detected (desktop or VM)."
        }
    }
    default {
        Write-Host "Usage: win-tools <action> [args]"
        Write-Host ""
        Write-Host "Drive actions:"
        Write-Host "  scan [drive]          Scan top heaviest folders (default: C)"
        Write-Host "  files [drive] [count] Rank largest files (default: top 50)"
        Write-Host "  dir [drive]           List top-level folders and files"
        Write-Host "  disk [drive]          Show disk space"
Write-Host "  search [drive|ALL] <pat>  Search fixed Windows drives by name with live checkpoints"
        Write-Host ""
        Write-Host "System actions:"
        Write-Host "  processes             List top memory processes"
        Write-Host "  services              List running services"
        Write-Host "  startup               Programs that run at boot + top CPU users"
        Write-Host "  boot                  Everything that runs at boot, ranked by CPU/RAM"
        Write-Host "  scheduled             List enabled scheduled tasks"
        Write-Host "  net                   Network adapters / IPs / Wi-Fi"
        Write-Host "  gpu                   GPU info"
        Write-Host "  battery               Battery status"
        Write-Host ""
        Write-Host "Automation actions:"
        Write-Host "  gui <title> <keys>    Activate window and send keys"
        Write-Host "  clip [set <text>]     Read or set the Windows clipboard"
        Write-Host "  notify [title] [msg]  Show a Windows notification"
        Write-Host "  shot                  Screenshot + OCR to C:\Users\Public\llama-shot.png"
    }
}
PSEOF
    # Exercise the installed helper through the same WSL-to-Windows boundary
    # that the agent uses. This catches parser, interop, path, and runtime errors.
    WIN_TOOL_SELF_CHECK=""
    for attempt in 1 2 3; do
        ensure_wsl_interop || {
            WIN_TOOL_SELF_CHECK="WSL interop repair failed before Windows helper attempt $attempt"
            continue
        }
        WIN_TOOL_SELF_CHECK=$(timeout 20s "$WINDOWS_POWERSHELL" \
            -NoProfile -NonInteractive -ExecutionPolicy Bypass \
            -File "C:/Users/Public/llama-win-tools.ps1" disk C 2>&1 || true)
        if printf '%s' "$WIN_TOOL_SELF_CHECK" |
             grep -qiE 'C: Drive|Used:|Free:'; then
            break
        fi
        sleep "$attempt"
    done
    if printf '%s' "$WIN_TOOL_SELF_CHECK" |
         grep -qiE 'C: Drive|Used:|Free:'; then
        ok "Windows helper parsed and returned live C: drive evidence"
    else
        fail "Windows helper did not execute correctly after three bounded attempts: ${WIN_TOOL_SELF_CHECK:-no output}"
    fi
fi

# ── Bash wrapper for win-tools ──
cat > "$HOME/.local/bin/win-tools" <<'WINEOF'
#!/usr/bin/env bash
# win-tools: bridge to Windows PowerShell operations from WSL2
set -uo pipefail
INTEROP_GUARD="/usr/local/libexec/local-ai-wsl-interop-guard"
POWERSHELL="/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
if { [ -z "${WSL_INTEROP:-}" ] || [ ! -S "$WSL_INTEROP" ]; } &&
   [ -S /run/WSL/1_interop ]; then
    export WSL_INTEROP=/run/WSL/1_interop
fi
if [ ! -x "$INTEROP_GUARD" ] || ! "$INTEROP_GUARD"; then
    printf 'Windows tools cannot run because WSL interop could not be restored.\n' >&2
    exit 126
fi
ACTION="${1:-help}"
shift 1 2>/dev/null || true
EXTRA=("$@")
DRIVE="C"

normalize_drive() {
    local token="${1:-}"
    token="${token,,}"
    token="${token//[[:space:]]/}"
    token="${token%:}"
    case "$token" in
        [a-z]) printf '%s' "${token^^}" ;;
        see|sea) printf 'C' ;;
        dee) printf 'D' ;;
        ee) printf 'E' ;;
        eff) printf 'F' ;;
        gee) printf 'G' ;;
        aitch) printf 'H' ;;
        eye) printf 'I' ;;
        jay) printf 'J' ;;
        kay) printf 'K' ;;
        el) printf 'L' ;;
        em) printf 'M' ;;
        en) printf 'N' ;;
        oh) printf 'O' ;;
        pee) printf 'P' ;;
        cue|queue) printf 'Q' ;;
        are|air) printf 'R' ;;
        ess) printf 'S' ;;
        tee|tea) printf 'T' ;;
        you) printf 'U' ;;
        vee) printf 'V' ;;
        doubleyou|double-u) printf 'W' ;;
        ex) printf 'X' ;;
        why) printf 'Y' ;;
        zee|zed) printf 'Z' ;;
        all) printf 'ALL' ;;
        *) return 1 ;;
    esac
}

# Drive-consuming actions normalize speech-to-text drive names before invoking
# PowerShell. Invalid values never leak into positional parameter binding.
case "$ACTION" in
    scan|files|dir|disk)
        if [ "${#EXTRA[@]}" -gt 0 ]; then
            if ! DRIVE=$(normalize_drive "${EXTRA[0]}"); then
                printf "ERROR|Invalid Windows drive '%s'. Supply one drive letter.\n" "${EXTRA[0]}" >&2
                exit 2
            fi
            if [ "$DRIVE" = "ALL" ]; then
                printf "ERROR|Action '%s' requires one Windows drive letter, not ALL.\n" "$ACTION" >&2
                exit 2
            fi
            EXTRA=("${EXTRA[@]:1}")
        fi
        ;;
    search)
        if [ "${#EXTRA[@]}" -gt 0 ] &&
           DRIVE_CANDIDATE=$(normalize_drive "${EXTRA[0]}"); then
            DRIVE="$DRIVE_CANDIDATE"
            EXTRA=("${EXTRA[@]:1}")
        fi
        ;;
esac
if [ "${#EXTRA[@]}" -gt 0 ]; then
    "$POWERSHELL" -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "C:/Users/Public/llama-win-tools.ps1" \
        -Action "$ACTION" -Drive "$DRIVE" "${EXTRA[@]}" 2>&1
else
    "$POWERSHELL" -NoProfile -NonInteractive -ExecutionPolicy Bypass \
        -File "C:/Users/Public/llama-win-tools.ps1" \
        -Action "$ACTION" -Drive "$DRIVE" 2>&1
fi
WINEOF
chmod +x "$HOME/.local/bin/win-tools"

# ── Browse for Chrome automation ──
cat > "$HOME/.local/bin/browse" <<'BEOF'
#!/usr/bin/env python3
"""browse - exact Chrome Profile 2 URL opener and capability verifier.

Commands:
  browse status            Verify Chrome and the exact profile
  browse open <url>        Open URL in Chrome Profile 2
  browse newwindow <url>   Open new Chrome window
  browse newtab            Open new tab (blank)
"""
import sys, subprocess, os, json, glob

CHROME_PATHS = [
    "/mnt/c/Program Files/Google/Chrome/Application/chrome.exe",
]
INTEROP_GUARD = "/usr/local/libexec/local-ai-wsl-interop-guard"
PROFILE_DIR = "Profile 2"
EXTENSION_ID = "hehggadaopoacecdllhhajmbjkdcmajg"

def ensure_windows_interop():
    current_interop = os.environ.get("WSL_INTEROP", "")
    if (
        (not current_interop or not os.path.exists(current_interop))
        and os.path.exists("/run/WSL/1_interop")
    ):
        os.environ["WSL_INTEROP"] = "/run/WSL/1_interop"
    try:
        result = subprocess.run(
            [INTEROP_GUARD],
            text=True,
            capture_output=True,
            timeout=12,
        )
    except Exception as exc:
        print(f"ERROR: WSL interop recovery could not run: {exc}")
        sys.exit(1)
    if result.returncode != 0:
        detail = (result.stderr or result.stdout).strip()
        print(
            "ERROR: WSL cannot launch Windows applications after automatic "
            f"interop recovery: {detail or 'no diagnostic output'}"
        )
        sys.exit(1)

def find_profile():
    matches = glob.glob(
        "/mnt/c/Users/*/AppData/Local/Google/Chrome/User Data/Profile 2"
    )
    return matches[0] if len(matches) == 1 else None

def find_chrome():
    for p in CHROME_PATHS:
        if os.path.exists(p):
            return p
    return None

def main():
    ensure_windows_interop()
    chrome = find_chrome()
    if not chrome:
        print("ERROR: Chrome not found on Windows. Install Chrome on Windows first.")
        sys.exit(1)

    profile_path = find_profile()
    if not profile_path:
        print("ERROR: Could not uniquely locate Chrome Profile 2 under the Windows user profiles.")
        sys.exit(1)

    profile_name = "unknown"
    try:
        with open(os.path.join(profile_path, "Preferences"), encoding="utf-8") as fh:
            profile_name = json.load(fh).get("profile", {}).get("name", "unknown")
    except Exception:
        pass
    if profile_name != "Person 1":
        print(f"ERROR: Profile 2 was found but its visible name is {profile_name!r}, not 'Person 1'.")
        sys.exit(1)

    if len(sys.argv) < 2:
        print("browse status            Verify Chrome Profile 2 / Person 1")
        print("browse open <url>        Open URL in Chrome Profile 2")
        print("browse newwindow <url>   Open new Chrome window")
        print("browse newtab            Open new blank tab")
        return

    action = sys.argv[1].lower()
    url = sys.argv[2] if len(sys.argv) > 2 else "about:blank"
    chrome_args = [chrome, f"--profile-directory={PROFILE_DIR}"]

    if action == "status":
        extension_glob = os.path.join(
            profile_path, "Extensions", EXTENSION_ID, "*", "manifest.json"
        )
        extension_ready = len(glob.glob(extension_glob)) > 0
        native_manifest = (
            "/mnt/c/Users/micha/AppData/Local/OpenAI/extension/"
            "com.openai.codexextension.json"
        )
        print(
            f"OPEN_READY|Chrome={chrome}|Profile={PROFILE_DIR}|Name={profile_name}|"
            f"Extension={EXTENSION_ID}|ExtensionInstalled={extension_ready}|"
            f"NativeManifest={os.path.exists(native_manifest)}|"
            "InteractiveTabControl=UNAVAILABLE_IN_STANDALONE_WSL|"
            "Reason=requires fresh privileged extension-host tab claim"
        )
    elif action in ("open", "newtab"):
        try:
            subprocess.Popen(chrome_args + ["--new-tab", url],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           start_new_session=True)
            print(
                f"Opened URL in Chrome Profile 2 (Person 1): {url}. "
                "This confirms profile-targeted opening, not interactive tab control."
            )
        except Exception as e:
            print(f"ERROR opening Chrome: {e}")
            sys.exit(1)
    elif action in ("new-window", "newwindow"):
        try:
            subprocess.Popen(chrome_args + ["--new-window", url],
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                           start_new_session=True)
            print(f"New Chrome Profile 2 (Person 1) window: {url}")
        except Exception as e:
            print(f"ERROR opening Chrome: {e}")
            sys.exit(1)
    else:
        print(f"Unknown action: {action}")
        print("Usage: browse open|newwindow|newtab [url]")
        sys.exit(1)

if __name__ == "__main__":
    main()
BEOF
chmod +x "$HOME/.local/bin/browse"

ok "Windows tools installed (win-tools, browse)"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 7 — Playwright (REAL-TIME PROGRESS)
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 7/11: Installing Playwright for browser automation..."

info "  Downloading Chromium browser (may take a minute)..."
PLAYWRIGHT_LOG=$(mktemp)
if "$AGENT_VENV/bin/python" -m playwright install chromium >"$PLAYWRIGHT_LOG" 2>&1; then
    ok "Playwright installed"
else
    warn "Playwright chromium download failed (non-critical — browse still works)"
    tail -8 "$PLAYWRIGHT_LOG"
fi
rm -f "$PLAYWRIGHT_LOG"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 8 - The AI Agent (the brain) - llama-agent v11
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 8/11: Installing the AI agent (llama-agent v11)..."

cat > "$HOME/.local/bin/llama-agent" <<'AGENTEOF'
#!/usr/bin/env python3
"""
llama-agent v11 - resumable hardware-adaptive local AI agent for WSL2.

Features:
- Explains every action in plain English before AND after doing it
- Auto-executes commands, writes files, runs Python
- Uses win-tools for Windows operations (never Linux du/find on C:)
- Uses browse for Chrome automation (never google-chrome or xdotool)
- Command interception: auto-fixes wrong commands before execution
- Tries every available local capability and reports any real external boundary
- Error recovery: if one approach fails, tries another
- No fixed task-round ceiling; unfinished work continues until honestly verified
- Atomic task checkpoints and automatic recovery after interruption
"""
import os, sys, json, time, signal, subprocess, re, tempfile, threading, hashlib, uuid, shlex, shutil, base64, mimetypes, select, codecs, math, struct, wave
import urllib.request, urllib.error
from pathlib import Path
from contextlib import contextmanager

# ─── Configuration ──────────────────────────────────────────────────────────
HOME = Path.home()
LLAMA_DIR = HOME / "llama.cpp"
MODEL_DIR = HOME / "models"
LOG_DIR = HOME / ".local" / "share" / "llama-agent"
LOG_DIR.mkdir(parents=True, exist_ok=True)

SERVER_HOST = "127.0.0.1"
SERVER_PORT = 8080
RESPONSE_MAX_TOKENS = int(os.environ.get("LLAMA_RESPONSE_MAX_TOKENS", "8192"))
API_TIMEOUT = int(os.environ.get("LLAMA_API_IDLE_TIMEOUT", "3600"))
# Interactive work must either start producing a usable answer/tool call quickly
# or retry with a more direct instruction. Private reasoning is not progress for
# a task that can already be inspected, created, or tested.
MODEL_ACTION_TIMEOUT = int(os.environ.get("LLAMA_MODEL_ACTION_TIMEOUT", "25"))
DISABLE_MODEL_THINKING = os.environ.get(
    "LLAMA_DISABLE_MODEL_THINKING", "1"
).strip().lower() not in ("0", "false", "no", "off")
MODEL_STREAM_IDLE_TIMEOUT = int(
    os.environ.get("LLAMA_MODEL_STREAM_IDLE_TIMEOUT", "120")
)
FOCUSED_ACTION_MAX_TOKENS = int(
    os.environ.get("LLAMA_FOCUSED_ACTION_MAX_TOKENS", "4096")
)
MAX_MUTATIONS_WITHOUT_VERIFICATION = max(
    1, int(os.environ.get("LLAMA_MAX_MUTATIONS_WITHOUT_VERIFICATION", "6"))
)
CONTEXT_TOKENS = 32768   # actual server context (read from /props at runtime)
CMD_TIMEOUT_DEFAULT = int(os.environ.get("LLAMA_COMMAND_TIMEOUT", "0"))
CMD_TIMEOUT_LONG = int(os.environ.get("LLAMA_LONG_COMMAND_TIMEOUT", "0"))
CMD_STALL_TIMEOUT = int(os.environ.get("LLAMA_COMMAND_STALL_TIMEOUT", "25"))
LIVE_REFRESH_SECONDS = max(
    0.10, float(os.environ.get("LLAMA_LIVE_REFRESH_SECONDS", "0.25"))
)
LIVE_LOG_HEARTBEAT_SECONDS = min(
    8.0,
    max(1.0, float(os.environ.get("LLAMA_LIVE_LOG_HEARTBEAT_SECONDS", "8"))),
)
COMPLETION_SOUND_ENABLED = (
    os.environ.get("LLAMA_COMPLETION_SOUND", "1").strip().lower()
    not in ("0", "false", "no", "off")
)
ACTIVE_TASK_FILE = LOG_DIR / "active-task.json"
TASK_HISTORY_DIR = LOG_DIR / "tasks"
TASK_HISTORY_DIR.mkdir(parents=True, exist_ok=True)
PROMPT_HISTORY_FILE = LOG_DIR / "prompt-history"
CUSTOM_COMMANDS_FILE = LOG_DIR / "commands.json"
CONTEXT_FILES_FILE = LOG_DIR / "context-files.json"
MCP_CONFIG_FILE = LOG_DIR / "mcp-servers.json"
CAPABILITY_STATE_FILE = LOG_DIR / "capabilities.json"
EVENT_LOG_FILE = LOG_DIR / "events.jsonl"
RUNTIME_CONFIG_FILE = LOG_DIR / "config.json"
COMPLETION_CHIME_FILE = LOG_DIR / "nature-complete.wav"
WINDOWS_INTEROP_GUARD = Path(
    "/usr/local/libexec/local-ai-wsl-interop-guard"
)
WINDOWS_POWERSHELL = Path(
    "/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe"
)
EXPORT_DIR = LOG_DIR / "exports"
EXPORT_DIR.mkdir(parents=True, exist_ok=True)
JOB_DIR = LOG_DIR / "jobs"
JOB_DIR.mkdir(parents=True, exist_ok=True)
MAX_WHOLE_FILE_CHARS = int(os.environ.get("LLAMA_MAX_WHOLE_FILE_CHARS", "12000"))
MAX_PATCH_CHARS = int(os.environ.get("LLAMA_MAX_PATCH_CHARS", "60000"))
MAX_TOOL_OUTPUT_CHARS = int(os.environ.get("LLAMA_MAX_TOOL_OUTPUT_CHARS", "50000"))
CURRENT_TASK_STATE = None
CURRENT_CONVERSATION = None

# Build a robust PATH that includes everything the agent might need
AGENT_PATH = ":".join([
    str(HOME / ".local/bin"),
    str(HOME / ".local/share/mise/shims"),
    str(HOME / ".cargo/bin"),
    str(LLAMA_DIR / "build" / "bin"),
    "/usr/local/cuda/bin",
    "/usr/lib/wsl/lib",
    "/mnt/c/Windows/System32/WindowsPowerShell/v1.0",
    "/mnt/c/Windows/System32",
    "/usr/local/sbin", "/usr/local/bin",
    "/usr/sbin", "/usr/bin", "/sbin", "/bin",
])

# ─── System prompt ──────────────────────────────────────────────────────────
SYSTEM_PROMPT = r"""You are Nature, a highly capable local AI assistant running inside WSL2 on the user's Windows PC. You can use the installed Linux, Windows, file, coding, automation, browser, media, document, network, and system tools.

## THE GOLDEN RULE: REAL-TIME ENGLISH NARRATION
The runtime narrates every tool call and result in plain English. For a task that needs work, your FIRST response must therefore be one complete native tool call, not a greeting, plan, recap, or hidden reasoning. After tool results, emit the next useful native tool call immediately. Reserve visible prose for a concise final answer after fresh verification. Never dump raw command output.
- Start the first concrete tool action as soon as its target is known. Do not spend time restating, planning, or drafting a huge payload before acting.
- For project work, create the smallest runnable structure first, then add focused bounded pieces and test them. Never compose an entire large application inside one tool call.

## CORE RULES - NON-NEGOTIABLE
1. Attempt every requested part with the capabilities actually available on this machine.
2. Do not hand work back to the user when a tool can perform it directly.
3. If one method fails, diagnose the cause and try materially different available methods.
4. Never pretend a blocked or unverified action succeeded. Name the exact boundary and preserve completed work.
5. The runtime explains every tool action and result in plain English. Emit complete native tool calls directly so it can begin work immediately.
6. When something fails, immediately try a different approach. Never give up.
7. Be warm, confident, and helpful. Like a brilliant friend who owns the computer.
8. Preserve the user's literal objective. A domain word inside a build request (for example "startup app") does not turn that request into an inventory query.
9. Continue for as many action rounds as the task genuinely needs. Never use elapsed time, token length, context compaction, or a round count as permission to stop early.
10. A submitted task ends only after every requested criterion has fresh verification evidence, or after the user explicitly cancels or interrupts it. A missing dependency, stalled subprocess, model-server outage, or failed test is a recovery event, never permission to stop.
11. For a Windows desktop GUI requested at a Windows drive path, build and exercise it with a Windows runtime through PowerShell or win-tools. Do not substitute a headless Linux Tk/Xvfb process as proof that a Windows application works.
12. When a command is missing, identify the real toolchain from the command and project manifests, install it once through the curated package path, verify the executable, then retry the original command exactly once. Never repeat a successful install.
13. For installed-application tools, collect registered uninstall/package evidence and invoke only the selected application's registered uninstaller after explicit confirmation. Never claim that recursive raw-folder deletion, ownership takeover, or a blanket Remove-Item operation is a safe uninstall.
14. Never run apt, apt-get, winget, choco, brew, npm install, or another package manager as part of a project build command. First probe the requested executable. The runtime performs one isolated curated recovery only after a missing-command result.

## DEFINITIVE-ANSWER PROTOCOL (MOST IMPORTANT)
- ALWAYS complete the ENTIRE task before writing your final answer. Never stop at partial results.
- NEVER end with "we would need to...", "I could...", "it would be necessary to...", or any hedged phrasing. If you need more data to answer completely, GET IT YOURSELF using your tools, then answer.
- Give the user EXACTLY what they asked for: no less, no more. If they asked for a ranked list of 10, give exactly 10 ranked items with the requested numbers (CPU time, RAM, size in GB, etc).
- Format final answers with clear structure: numbered lists, bold headers, and numbers in real units.
- When asked to compare or correlate (e.g. which startup programs use the most CPU/RAM), DO the correlation yourself and present the merged, ranked result.
- VERIFY YOUR WORK before answering: if you created a file, check it exists; if you ran a scan, re-read the key numbers from the tool output; if something looks inconsistent, investigate and fix it yourself.
- For every create, build, implement, install, repair, update, or modify request, perform at least one real modifying action and then run a separate readback, syntax check, test, or runtime check after the final modification.
- If the user explicitly requires read-only work or forbids changes, never create, edit, delete, or move anything merely to satisfy an action gate. Use read-only tool evidence and verification instead.
- A plan, explanation, inventory, or promise is not implementation evidence.
- End a genuinely complete final response with exactly `[TASK_COMPLETE]` on its own line. Never emit that marker while any requested part is unfinished or unverified.

## THE HALLUCINATION BAN (ABSOLUTE - NEVER VIOLATE)
- You are ONLY allowed to report numbers, names, and values that ACTUALLY appear in your tool output. Every figure in your final answer must be traceable to a line of tool output you really received.
- A word, character, byte, row, or item count is valid only when a tool emitted it or you computed it exactly from the verified value. If prose conflicts with tool evidence, correct the prose before completion.
- If tool output is truncated or you cannot see a value, say "the output was cut off" and RE-RUN the tool with a narrower query or the win-tools pipe format - never guess, never invent, never fabricate.
- NEVER invent identical values for many rows (e.g. the same RAM for every service). If data is missing, get it.
- If you catch yourself unsure whether a number is real, that is a red flag: re-run the tool before writing it down.

## TOOL CHOICE MAP (pick the RIGHT tool on the FIRST try - no wasted rounds)
Use these shortcuts only when the whole request is a direct read-only query. Never apply them to a request to create, build, code, design, fix, install, or modify a project that merely mentions the same subject:
- "everything at boot / startup items / what runs at boot / ranked by CPU+RAM" -> win-tools boot   (this ONE command returns the full ranked report - do NOT also run startup/scheduled/services)
- "largest files / heaviest files / top files" -> win-tools files <drive> <count>
- "heaviest folders / what takes space / scan drive" -> win-tools scan <drive>
- "list folders on drive X" -> win-tools dir X:
- "disk space / free space" -> win-tools disk <drive>
- "find the full path of one exact Windows filename" -> win-tools search ALL <filename> FIRST
- "search for every Windows filename containing text" -> win-tools search ALL <pattern> ALL (or one explicit drive)
- "running processes / task manager / top memory" -> win-tools processes
- "running services" -> win-tools services
- "scheduled tasks" -> win-tools scheduled
- "open website in Chrome" -> browse open <url>
- Windows system inventory and operating-system controls -> win-tools.
- Creating, editing, testing, or managing project files at a Windows path -> convert the path to `/mnt/<drive>/...` and use bash, Python, read_file, or write_file.
For a multi-step project, use as many distinct commands and checks as necessary. Do not collapse implementation into a read-only shortcut.

## PERSISTENT MEMORY PROTOCOL
You have long-term memory that persists across sessions. At the end of a task that produced durable facts (paths, preferences, installed tools, decisions, system details), end your answer with a [MEMORY] block containing one compact line per fact:
[MEMORY]
- user's F: drive has folders backup, games, study
- installed yt-dlp for video downloads
[/MEMORY]
Do not repeat facts already in the PERSISTENT MEMORY section above.

## PLAN-FIRST PROTOCOL (understand immediately)
When you receive a request, in your first message line restate in ONE short English sentence exactly what you understood the task to be. Then act immediately. Preserve every explicit path and deliverable. Make a reasonable reversible interpretation when possible; ask only when an unsafe ambiguity truly cannot be resolved from the machine.

## HOW TO RUN COMMANDS
PREFERRED: use the native tools provided to you (win_tools, browse, run_command, run_python, write_file, append_file, apply_patch, read_file) by emitting a single tool call - the harness executes it for you and hands you the result. Use apply_patch for existing files. Never stream an entire large file through write_file; use focused patches or bounded append chunks. Do NOT both emit a tool call AND write a code block for the same action.

FALLBACK (only if native tool calling is not available): put commands in bash code blocks:
```bash
your command here
```

You can also use Python:
```python
your python code here
```

## YOUR FULL CAPABILITY TOOLKIT
System commands (Linux/WSL): shell commands, Python, file read/write, package installs with sudo, git, docker, curl/wget, ffmpeg (media conversion), imagemagick (images), pandoc (document conversion), sqlite3 (databases), nmap (network scanning), tesseract (OCR), pdftotext (PDF to text), yt-dlp (video download), gh (GitHub).

Windows operations - ALWAYS via win-tools:
```bash
win-tools scan C          # heaviest folders on a drive
win-tools files C 50      # 50 largest files on a drive
win-tools dir F:          # top-level folders and files on a drive
win-tools disk C          # disk space
win-tools search ALL app.exe FIRST # stop after the first exact executable filename
win-tools search ALL name ALL      # exhaustively find every filename containing text
win-tools processes       # top memory processes
win-tools services        # running services
win-tools startup         # programs at boot + top CPU users
win-tools boot            # EVERYTHING at boot (registry + startup folder + scheduled tasks + auto services) ranked by CPU/RAM
win-tools scheduled       # enabled scheduled tasks
win-tools gui <title> <keys>  # activate a Windows window and send keystrokes
win-tools clip [set <text>]   # read or set the Windows clipboard
win-tools notify [title] [msg] # show a Windows notification
win-tools shot            # screenshot + OCR of the Windows screen
win-tools net             # network adapters / IPs / Wi-Fi
win-tools gpu             # GPU info
win-tools battery         # battery status
```

Chrome Profile 2 URL opening - via browse:
```bash
browse open https://www.youtube.com   # opens in the user's EXISTING Chrome profile
browse newwindow https://example.com  # new Chrome window
browse newtab                         # new blank tab
```
`browse` verifies Profile 2 / Person 1 and opens URLs there. It does not prove interactive control of the signed-in tab. Before any click, typing, form, or tab-reading task, inspect the browser capability state and fail closed unless a supported privileged extension-host session can freshly enumerate and claim the exact visible tab. Never substitute isolated Playwright and never claim sign-in from URL opening alone.

## WINDOWS DESKTOP ROUTING
When the user asks for a Windows desktop app, build a Windows-native target
(for example .NET/WPF/WinUI or a verified Windows-hosted web app). Do not
silently build Linux Tk under WSL. WSL GUI support is not proof that a Windows
desktop deliverable was created; launch and verify the actual requested host.

Windows paths in Linux tools:
- Convert `F:\folder\project` to `/mnt/f/folder/project` before using bash, Python, read_file, or write_file.
- A Windows path in a create/build request is the destination, not evidence that the user wants a drive scan.

## CRITICAL: WINDOWS DRIVES
Windows drives mount under /mnt/ (C: is /mnt/c). Use win-tools for broad whole-drive inventory scans because recursive Linux scans across an entire Windows drive are slow. For an explicitly named project path, use normal bash/Python/file tools on its exact `/mnt/<drive>/...` path so you can create, edit, test, and verify the project.

## SYSTEM ADMIN
You have passwordless sudo: install packages, manage services, docker, git, any file operation, process management, networking.

## WHEN THINGS GO WRONG
1. Read the error message carefully.
2. Try a completely different approach.
3. On Windows paths, switch to win-tools.
4. If a package/tool is missing, install it yourself.
5. Resolve problems directly whenever the available tools can do so. Ask only
   when missing authorization, credentials, physical access, or an unsafe
   ambiguity truly requires the user.

## STYLE
- Write like a competent human, not a robot.
- Start with a friendly English explanation, narrate as you work, end with a clear structured summary.
"""

# ─── Native tools ──────────────────────────────────────────────────────────
# Tool schemas are indexed and routed per request. Compact, relevant schemas
# improve local-model reliability and leave more context for the actual task.
TOOL_CATALOG = {
    "win_tools": {"type": "function", "function": {
        "name": "win_tools",
        "description": "Run Windows system inventory/control via win-tools (scan folders, files largest files, dir, disk, search fixed drives by filename with live checkpoints, processes, services, startup, boot, scheduled, gui, clip, notify, shot, net, gpu, battery). Do not use this for creating or editing project files at an explicit Windows path; use run_command/write_file with its /mnt path.",
        "parameters": {"type": "object", "properties": {
            "action": {"type": "string", "description": "One of: scan, files, dir, disk, search, processes, services, startup, boot, scheduled, gui, clip, notify, shot, net, gpu, battery"},
            "drive": {"type": "string", "description": "Drive letter for scan/files/dir/disk/search, or ALL for a search across every fixed Windows drive"},
            "args": {"type": "array", "items": {"type": "string"}, "description": "Extra arguments: files count, search pattern, gui window title + keys, clip set text, notify title + msg"}
        }, "required": ["action"]}
    }},
    "browse": {"type": "function", "function": {
        "name": "browse",
        "description": "Open a URL or window through the Windows Chrome helper. This does not imply interactive control of a signed-in tab; use browser status checks before claiming that capability.",
        "parameters": {"type": "object", "properties": {
            "action": {"type": "string", "enum": ["open", "newwindow", "newtab"]},
            "url": {"type": "string"}
        }, "required": ["action"]}
    }},
    "run_command": {"type": "function", "function": {
        "name": "run_command",
        "description": "Run any bash command in WSL2 (with sudo where needed). Use for Linux tasks and for creating, editing, testing, and managing projects at Windows paths converted to /mnt/<drive>/....",
        "parameters": {"type": "object", "properties": {
            "command": {"type": "string"}
        }, "required": ["command"]}
    }},
    "run_python": {"type": "function", "function": {
        "name": "run_python",
        "description": "Run a Python script in WSL2 for data processing, calculations, web scraping, file manipulation.",
        "parameters": {"type": "object", "properties": {
            "code": {"type": "string"}
        }, "required": ["code"]}
    }},
    "write_file": {"type": "function", "function": {
        "name": "write_file",
        "description": "Create or replace a small file. Content is capped; for existing or large files use apply_patch or append_file.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "content": {"type": "string"}
        }, "required": ["path", "content"]}
    }},
    "append_file": {"type": "function", "function": {
        "name": "append_file",
        "description": "Append one bounded chunk to a file. Use repeated chunks for generated data and logs.",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"},
            "content": {"type": "string"}
        }, "required": ["path", "content"]}
    }},
    "apply_patch": {"type": "function", "function": {
        "name": "apply_patch",
        "description": "Update existing files with a unified diff. The patch is validated before mutation and is preferred over whole-file rewrites.",
        "parameters": {"type": "object", "properties": {
            "patch": {"type": "string", "description": "A unified diff using paths relative to the current directory."}
        }, "required": ["patch"]}
    }},
    "mcp_call": {"type": "function", "function": {
        "name": "mcp_call",
        "description": "Call one tool on a user-trusted MCP stdio server configured in Nature.",
        "parameters": {"type": "object", "properties": {
            "server": {"type": "string"},
            "tool": {"type": "string"},
            "arguments": {"type": "object", "additionalProperties": True}
        }, "required": ["server", "tool"]}
    }},
    "read_file": {"type": "function", "function": {
        "name": "read_file",
        "description": "Read a file's contents (any path, Windows paths via /mnt/).",
        "parameters": {"type": "object", "properties": {
            "path": {"type": "string"}
        }, "required": ["path"]}
    }},
}
TOOLS_SPEC = list(TOOL_CATALOG.values())

def select_tools(objective):
    """Expose the smallest complete tool set for this request."""
    low = (objective or "").lower()
    names = {"run_command", "read_file"}
    if any(x in low for x in ("python", "data", "calculate", "scrape", "json", "csv")):
        names.add("run_python")
    if objective_requires_action(low) or any(x in low for x in (
        "file", "code", "project", "app", "website", "script", "edit", "write",
    )):
        names.update(("write_file", "append_file", "apply_patch"))
    if any(x in low for x in (
        "windows", "pc", "process", "service", "startup", "boot", "clipboard",
        "screenshot", "battery", "gpu", "wifi", "drive", "powershell",
    )) or re.search(r"[A-Za-z]:\\", objective or "") or re.search(
        r"\b(?:find|search|locate|where|path)\b.{0,120}\b[\w.-]+\.?exe\b",
        objective or "", re.IGNORECASE,
    ):
        names.add("win_tools")
    if any(x in low for x in (
        "browser", "chrome", "website", "web page", "url", "http://", "https://",
    )):
        names.add("browse")
    if any(x in low for x in (
        "mcp", "connector", "integration", "external service", "tool server",
    )) and _load_mcp_config():
        names.add("mcp_call")
    return [TOOL_CATALOG[name] for name in TOOL_CATALOG if name in names]

# ─── Helpers ────────────────────────────────────────────────────────────────

DEBUG_TO_CONSOLE = (
    os.environ.get("LLAMA_DEBUG", "0").strip().lower()
    in ("1", "true", "yes", "on")
)


def log(msg):
    """Retain diagnostics without dumping internal commands into normal output."""
    line = f"{time.strftime('%Y-%m-%d %H:%M:%S')} {msg}\n"
    try:
        LOG_DIR.mkdir(parents=True, exist_ok=True)
        with (LOG_DIR / "agent.log").open("a", encoding="utf-8") as handle:
            handle.write(line)
    except OSError:
        pass
    if DEBUG_TO_CONSOLE:
        print(f"[DEBUG] {msg}", file=sys.stderr, flush=True)

def progress_event(value):
    """Return a stable evidence key and its plain-English user-facing message."""
    if isinstance(value, tuple) and len(value) == 2:
        key, message = value
    else:
        key = message = value
    message = _one_line(str(message or ""), 300)
    if not message:
        message = (
            "The caller did not identify the operation, so no progress claim "
            "can be made until it supplies one."
        )
    key = _one_line(str(key or message), 300)
    return key, message

class LiveProgress:
    """Show one live status row and append output only for real state changes."""
    _process_logged_lines = set()
    _job_rendered_lines = set()
    _process_log_lock = threading.Lock()

    @classmethod
    def begin_job(cls):
        """Reset exact-status history only when a new submitted job begins."""
        with cls._process_log_lock:
            cls._process_logged_lines.clear()
            cls._job_rendered_lines.clear()

    def __init__(self, stream=None, interactive=None):
        self._lock = threading.Lock()
        self._output_lock = threading.Lock()
        self._stream_override = stream
        self._interactive_override = interactive
        self._stream = stream if stream is not None else sys.stdout
        self._owns_stream = False
        self._interactive = False
        self._event_key = "unidentified-operation"
        self._message = (
            "The caller did not identify the operation, so no progress claim "
            "can be made until it supplies one."
        )
        self._started = time.monotonic()
        self._stop = threading.Event()
        self._thread = None
        self._reporter = None
        self._last_event_key = None
        self._last_message = ""
        self._last_rendered = ""
        self._last_logged_at = 0.0
        self._last_visible_at = 0.0
        self._transient_visible = False
        self._logged_lines = set()

    @staticmethod
    def _stdio_has_terminal():
        for stream in (sys.stdin, sys.stdout, sys.stderr):
            try:
                if stream.isatty():
                    return True
            except Exception:
                continue
        return False

    def _bind_stream(self):
        self._owns_stream = False
        if self._stream_override is not None:
            self._stream = self._stream_override
        elif (
            self._interactive_override is not False
            and self._stdio_has_terminal()
        ):
            try:
                self._stream = open(
                    "/dev/tty",
                    "w",
                    encoding="utf-8",
                    errors="replace",
                    buffering=1,
                )
                self._owns_stream = True
            except OSError:
                self._stream = sys.stdout
        else:
            self._stream = sys.stdout
        if self._interactive_override is None:
            try:
                self._interactive = bool(self._stream.isatty())
            except Exception:
                self._interactive = False
        else:
            self._interactive = bool(self._interactive_override)

    def set(self, message):
        event_key, rendered_message = progress_event(message)
        with self._lock:
            self._event_key = event_key
            self._message = rendered_message

    def start(self, message, reporter=None):
        if self._thread and self._thread.is_alive():
            self.stop()
        self._bind_stream()
        self.set(message)
        self._reporter = reporter
        self._started = time.monotonic()
        self._last_event_key = None
        self._last_message = ""
        self._last_rendered = ""
        self._last_logged_at = 0.0
        self._last_visible_at = 0.0
        self._transient_visible = False
        self._logged_lines = set()
        self._stop.clear()
        self._thread = threading.Thread(target=self._run, daemon=True)
        self._thread.start()
        self.refresh(force=True)

    def _run(self):
        while not self._stop.wait(LIVE_REFRESH_SECONDS):
            self.refresh()

    def _format_line(self, elapsed, message):
        prefix = "  [WORKING] "
        if self._interactive:
            try:
                width = os.get_terminal_size(self._stream.fileno()).columns
            except Exception:
                width = shutil.get_terminal_size(fallback=(140, 24)).columns
            if width <= len(prefix) + 4:
                width = 80
            available = max(4, width - len(prefix) - 1)
            message = _one_line(message, 500)
            if len(message) > available:
                clipped = message[:max(1, available - 3)].rstrip()
                word_boundary = clipped.rsplit(" ", 1)[0].rstrip(" ,;:|")
                if len(word_boundary) >= max(8, available // 2):
                    clipped = word_boundary
                message = clipped + "..."
        else:
            message = _one_line(message, 500)
        return f"\033[2m{prefix}\033[0m{message}"

    def _write_transient(self, rendered):
        self._stream.write("\r\033[2K" + rendered)
        self._stream.flush()
        self._transient_visible = True

    def _clear_transient(self):
        if self._transient_visible:
            self._stream.write("\r\033[2K")
            self._stream.flush()
            self._transient_visible = False

    def refresh(self, force=False):
        """Refresh the current fact without appending a duplicate status line."""
        if self._stop.is_set():
            return
        with self._lock:
            event_key = self._event_key
            message = self._message
            reporter = self._reporter
        raw_elapsed = max(0.0, time.monotonic() - self._started)
        elapsed = int(raw_elapsed)
        if reporter is not None:
            try:
                event_key, message = progress_event(reporter(elapsed))
            except Exception as exc:
                event_key = f"telemetry-error:{type(exc).__name__}"
                message = (
                    f"Live telemetry for this operation could not be read "
                    f"({type(exc).__name__}); the operation has not been marked complete."
                )
        now = time.monotonic()
        rendered = self._format_line(elapsed, message)
        event_changed = event_key != self._last_event_key
        message_changed = message != self._last_message
        with self._output_lock:
            if rendered == self._last_rendered:
                self._last_event_key = event_key
                self._last_message = message
                return
            with self._process_log_lock:
                first_job_occurrence = rendered not in self._job_rendered_lines
                if first_job_occurrence:
                    self._job_rendered_lines.add(rendered)
            if not first_job_occurrence:
                self._last_event_key = event_key
                self._last_message = message
                self._last_rendered = rendered
                return
            if self._interactive:
                if force or event_changed or message_changed:
                    self._write_transient(rendered)
                    self._last_visible_at = now
            elif (
                force
                or event_changed
                or (
                    message_changed
                    and now - self._last_logged_at >= LIVE_LOG_HEARTBEAT_SECONDS
                )
            ):
                with self._process_log_lock:
                    first_process_occurrence = (
                        rendered not in self._process_logged_lines
                    )
                    if first_process_occurrence:
                        self._process_logged_lines.add(rendered)
                if rendered not in self._logged_lines and first_process_occurrence:
                    print(rendered, file=self._stream, flush=True)
                    self._logged_lines.add(rendered)
                    self._last_logged_at = now
                    self._last_visible_at = now
            self._last_event_key = event_key
            self._last_message = message
            self._last_rendered = rendered

    def stop(self):
        if not self._stop.is_set():
            self.refresh()
        self._stop.set()
        if self._thread:
            self._thread.join(timeout=1.5)
        with self._output_lock:
            self._clear_transient()
        self._thread = None
        self._reporter = None
        if self._owns_stream:
            try:
                self._stream.close()
            except Exception:
                pass
            self._owns_stream = False
            self._stream = self._stream_override or sys.stdout

LIVE = LiveProgress()

@contextmanager
def working(message, reporter=None):
    LIVE.start(message, reporter=reporter)
    try:
        yield
    finally:
        LIVE.stop()

def wait_with_progress(seconds, message):
    """Wait without creating a silent gap between failed and retried work."""
    seconds = max(0.0, float(seconds))
    started = time.monotonic()

    def report(elapsed):
        remaining = max(0.0, seconds - (time.monotonic() - started))
        return f"{message}; the next attempt starts in {remaining:.1f}s"

    with working(message, reporter=report):
        while time.monotonic() - started < seconds:
            remaining = max(0.0, seconds - (time.monotonic() - started))
            time.sleep(min(0.1, remaining))


_CHIME_LOCK = threading.Lock()
_JOB_CHIME_DEPTH = threading.local()


def _ensure_completion_chime():
    """Create Nature's short PCM completion melody once, using stdlib only."""
    if COMPLETION_CHIME_FILE.exists() and COMPLETION_CHIME_FILE.stat().st_size > 1000:
        return COMPLETION_CHIME_FILE
    with _CHIME_LOCK:
        if COMPLETION_CHIME_FILE.exists() and COMPLETION_CHIME_FILE.stat().st_size > 1000:
            return COMPLETION_CHIME_FILE
        sample_rate = 44100
        melody = [
            (659.25, 0.13), (0.0, 0.035),
            (783.99, 0.13), (0.0, 0.035),
            (987.77, 0.16), (0.0, 0.045),
            (1318.51, 0.34),
        ]
        frames = bytearray()
        for frequency, duration in melody:
            count = max(1, int(sample_rate * duration))
            fade = max(1, int(sample_rate * min(0.012, duration / 4)))
            for index in range(count):
                envelope = min(
                    1.0,
                    index / fade,
                    (count - index - 1) / fade,
                )
                sample = (
                    0.0
                    if frequency <= 0
                    else math.sin(2.0 * math.pi * frequency * index / sample_rate)
                )
                frames.extend(struct.pack("<h", int(32767 * 0.24 * envelope * sample)))
        temp_path = COMPLETION_CHIME_FILE.with_suffix(".wav.tmp")
        with wave.open(str(temp_path), "wb") as output:
            output.setnchannels(1)
            output.setsampwidth(2)
            output.setframerate(sample_rate)
            output.writeframes(bytes(frames))
        os.replace(temp_path, COMPLETION_CHIME_FILE)
    return COMPLETION_CHIME_FILE


def _completion_chime_command(path):
    """Build a Windows SoundPlayer command for one local WAV."""
    _ensure_windows_interop_runtime()
    converted = subprocess.run(
        ["wslpath", "-w", str(path)],
        text=True,
        capture_output=True,
        timeout=5,
    )
    if converted.returncode != 0 or not converted.stdout.strip():
        raise RuntimeError(converted.stderr.strip() or "wslpath did not return a path")
    windows_path = converted.stdout.strip().replace("'", "''")
    script = (
        "$ErrorActionPreference='Stop'; "
        f"$player=New-Object System.Media.SoundPlayer '{windows_path}'; "
        "$player.Load(); $player.PlaySync()"
    )
    encoded = base64.b64encode(script.encode("utf-16le")).decode("ascii")
    powershell = str(WINDOWS_POWERSHELL)
    return [
        powershell,
        "-NoProfile",
        "-NonInteractive",
        "-ExecutionPolicy", "Bypass",
        "-EncodedCommand", encoded,
    ]


def _ensure_windows_interop_runtime():
    """Repair the WSL kernel bridge before launching any Windows process."""
    stable_interop = Path("/run/WSL/1_interop")
    current_interop = Path(os.environ.get("WSL_INTEROP", "/missing"))
    if not current_interop.exists() and stable_interop.exists():
        os.environ["WSL_INTEROP"] = str(stable_interop)
    if not WINDOWS_INTEROP_GUARD.is_file():
        raise RuntimeError(
            f"WSL interop recovery helper is missing: {WINDOWS_INTEROP_GUARD}"
        )
    repaired = subprocess.run(
        [str(WINDOWS_INTEROP_GUARD)],
        text=True,
        capture_output=True,
        timeout=12,
    )
    if repaired.returncode != 0:
        detail = (repaired.stderr or repaired.stdout).strip()
        raise RuntimeError(
            "WSL could not restore Windows executable support: "
            + (detail or "the recovery helper returned no diagnostic output")
        )
    return str(WINDOWS_POWERSHELL)


def play_completion_chime(wait=False):
    """Play the unique completion ringtone once without delaying the next job."""
    if not COMPLETION_SOUND_ENABLED:
        return False
    try:
        process = subprocess.Popen(
            _completion_chime_command(_ensure_completion_chime()),
            stdin=subprocess.DEVNULL,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            start_new_session=True,
        )
        if wait:
            return process.wait(timeout=10) == 0
        return True
    except Exception:
        try:
            sys.stdout.write("\a")
            sys.stdout.flush()
        except Exception:
            pass
        return False


@contextmanager
def completion_chime_after_job():
    """Ring once when the outermost user job returns, fails, or is interrupted."""
    depth = int(getattr(_JOB_CHIME_DEPTH, "value", 0))
    if depth == 0:
        LiveProgress.begin_job()
    _JOB_CHIME_DEPTH.value = depth + 1
    try:
        yield
    finally:
        _JOB_CHIME_DEPTH.value = depth
        if depth == 0:
            play_completion_chime()


_ANSI_RE = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]")

def _one_line(text, limit=150):
    text = _ANSI_RE.sub("", text or "")
    text = " ".join(text.replace("\r", " ").replace("\n", " ").split())
    return text[:limit] + ("..." if len(text) > limit else "")

_ACTION_WORDS = (
    "create", "build", "implement", "make", "write", "develop", "design",
    "fix", "repair", "upgrade", "update", "change", "modify", "install",
    "configure", "set up", "setup", "remove", "delete", "move", "copy",
    "deploy", "automate", "generate", "convert",
)
_PROJECT_WORDS = (
    "project", "app", "application", "script", "program", "tool", "website",
    "api", "cli", "tui", "package", "repository", "codebase", "dashboard",
)
_READ_ONLY_WORDS = (
    "show", "list", "tell me", "what", "which", "check", "inspect", "scan",
    "report", "find", "rank", "how much", "status",
)
_ACTION_PATTERN = re.compile(
    r"(?<![a-z0-9_])(?:"
    r"creat(?:e|es|ed|ing)|build(?:s|ing)?|built|"
    r"implement(?:s|ed|ing|ation|ations)?|mak(?:e|es|ing)|made|"
    r"writ(?:e|es|ing|ten)|develop(?:s|ed|ing|ment)?|"
    r"design(?:s|ed|ing)?|fix(?:es|ed|ing)?|repair(?:s|ed|ing)?|"
    r"upgrad(?:e|es|ed|ing)|updat(?:e|es|ed|ing)|"
    r"chang(?:e|es|ed|ing)|modif(?:y|ies|ied|ying|ication|ications)|"
    r"install(?:s|ed|ing|ation|ations)?|"
    r"configur(?:e|es|ed|ing|ation|ations)|"
    r"set\s+up|setting\s+up|setup|remov(?:e|es|ed|ing)|"
    r"delet(?:e|es|ed|ing)|mov(?:e|es|ed|ing)|"
    r"cop(?:y|ies|ied|ying)|deploy(?:s|ed|ing|ment)?|"
    r"automat(?:e|es|ed|ing|ion)|generat(?:e|es|ed|ing|ion)|"
    r"convert(?:s|ed|ing)?"
    r")(?![a-z0-9_])",
    re.IGNORECASE,
)

_NEGATED_ACTION_PREFIX = re.compile(
    r"(?:"
    r"\b(?:do\s+not|don't|must\s+not|never|avoid|avoiding|without)\b|"
    r"\brefrain\s+from\b"
    r")"
    r"(?:\s+(?:"
    r"ever|again|also|directly|silently|automatically|"
    r"make|making|perform|performing|apply|applying|"
    r"any|the|a|an|file|files|source|project|code"
    r")){0,6}\s*$",
    re.IGNORECASE,
)

def _action_match_is_negated(text, match):
    """Recognize a local prohibition without hiding later positive actions."""
    prefix = (text or "")[max(0, match.start() - 120):match.start()]
    clause = re.split(
        r"[.;:!?]|\b(?:but|however|instead)\b",
        prefix,
        flags=re.IGNORECASE,
    )[-1]
    return _NEGATED_ACTION_PREFIX.search(clause) is not None

def objective_requires_action(text):
    source = text or ""
    return any(
        not _action_match_is_negated(source, match)
        for match in _ACTION_PATTERN.finditer(source)
    )

def objective_requires_verification(text):
    low = (text or "").lower()
    explicit_evidence = re.search(
        r"\b(?:verify|verified|verification|cross-check|using\s+tools?)\b",
        low,
    ) is not None
    modifying_work = objective_requires_action(low) and (
        any(word in low for word in _PROJECT_WORDS)
        or any(word in low for word in (
            "fix", "repair", "upgrade", "update", "modify", "install",
            "configure", "deploy",
        ))
    )
    return explicit_evidence or modifying_work

def is_direct_boot_inventory_request(text):
    """True only when the whole request asks to inspect boot configuration."""
    low = (text or "").lower()
    boot = any(word in low for word in (
        "boot", "startup items", "startup programs", "start with windows",
        "run at startup", "on boot", "at boot",
    ))
    read_only = any(word in low for word in _READ_ONLY_WORDS)
    project_or_action = (
        objective_requires_action(low)
        or re.search(r"[A-Za-z]:\\", text or "") is not None
    )
    return boot and read_only and not project_or_action

def normalize_user_path(raw):
    """Convert a Windows drive path to its WSL mount without losing spaces."""
    value = (raw or "").strip().strip("`\"'")
    match = re.match(r"^([A-Za-z]):[\\/]*(.*)$", value)
    if not match:
        return value
    drive = match.group(1).lower()
    rest = match.group(2).replace("\\", "/").lstrip("/")
    return f"/mnt/{drive}/{rest}" if rest else f"/mnt/{drive}"

def normalize_windows_paths_in_bash(command):
    """Convert literal drive paths only when Bash, not Windows, will parse them."""
    text = command or ""
    if re.search(
        r"(?i)\b(?:powershell(?:\.exe)?|pwsh(?:\.exe)?|cmd(?:\.exe)?|"
        r"win-tools|wslpath)\b",
        text,
    ):
        return text

    def quoted(match):
        quote, drive, rest = match.group(1), match.group(2), match.group(3)
        return f"{quote}/mnt/{drive.lower()}/{rest.replace(chr(92), '/')}{quote}"

    text = re.sub(
        r"""(["'])([A-Za-z]):\\([^"']*)\1""",
        quoted,
        text,
    )

    def bare(match):
        drive, rest = match.group(1), match.group(2)
        return f"/mnt/{drive.lower()}/{rest.replace(chr(92), '/')}"

    return re.sub(
        r"(?<![\w/])([A-Za-z]):\\([^\s;&|<>()]+)",
        bare,
        text,
    )

def _sentence_windows_path_prefix(raw):
    """Extract a Windows path from prose without probing a mounted filesystem."""
    candidate = (raw or "").strip().strip("`\"'").rstrip(" .!?")
    boundary = re.search(
        r"(?i)\s+(?="
        r"in\s+(?:this|the)\s+(?:specific\s+)?path\b|"
        r"for\s+(?:this|the)\s+(?:specific\s+)?project\b|"
        r"(?:then|and\s+then|where|that)\s+(?:create|build|make|will)\b|"
        r"that\s+(?:lists?|opens?|launches?|runs?|displays?|scans?|"
        r"manages?|can|should|must)\b"
        r")",
        candidate,
    )
    if boundary:
        candidate = candidate[:boundary.start()].rstrip()
    return normalize_user_path(candidate) if candidate else ""

def extract_target_paths(objective):
    targets = []

    def add_target(value):
        if value and value not in targets:
            targets.append(value)

    source = objective or ""
    for match in re.finditer(r"(?i)[`\"]([A-Z]:\\[^`\"\r\n]+)[`\"]", source):
        raw = match.group(1).strip().rstrip(" .!?")
        add_target(normalize_user_path(raw))

    # An unquoted Windows path may contain spaces and be followed by prose.
    # Prefer the longest real prefix so "F:\Downloads\New folder in ..." does
    # not degrade to the nonexistent "/mnt/f/Downloads/New".
    spaced_matches = list(re.finditer(
        r"(?i)(?<!\w)([A-Z]:\\[^\r\n<>,;`\"]+)",
        source,
    ))
    for match in spaced_matches:
        add_target(_sentence_windows_path_prefix(match.group(1)))

    unquoted = re.sub(r"(?i)[`\"]([A-Z]:\\[^`\"\r\n]+)[`\"]", " ", source)
    for match in re.finditer(r"(?i)(?<!\w)([A-Z]:\\[^\s<>,;`\"]+)", unquoted):
        if any(
            broad.start() <= match.start() < broad.end()
            for broad in spaced_matches
        ):
            continue
        raw = match.group(1).strip().rstrip(" .!?")
        add_target(normalize_user_path(raw))
    for match in re.finditer(r"(?<!\w)(/mnt/[a-zA-Z]/[^\s\r\n,;`\"]+)", source):
        raw = match.group(1).strip().strip("`\"'").rstrip(" .!?")
        add_target(raw)
    return targets

def command_uses_direct_windows_powershell(command):
    text = command or ""
    executable = (
        rf"(?:{re.escape(str(WINDOWS_POWERSHELL))}|powershell(?:\.exe)?)"
    )
    return re.match(rf"(?i)^\s*{executable}(?=\s|$)", text) is not None

def normalize_direct_windows_powershell(command):
    """Run a direct PowerShell command through WSL's Windows interop bridge."""
    text = command or ""
    if not command_uses_direct_windows_powershell(text):
        return text
    executable = (
        rf"(?:{re.escape(str(WINDOWS_POWERSHELL))}|powershell(?:\.exe)?)"
    )
    direct_match = re.match(
        rf"(?i)^\s*(?P<executable>{executable})(?=\s|$)",
        text,
    )
    assert direct_match is not None
    executable_placeholder = "__NATURE_WINDOWS_POWERSHELL__"
    text = (
        text[:direct_match.start("executable")]
        + executable_placeholder
        + text[direct_match.end("executable"):]
    )

    def mounted_path(match):
        raw = re.sub(r"\\+\s", " ", match.group(1))
        parts = raw.split("/", 3)
        drive = parts[2].upper()
        rest = parts[3].replace("/", "\\") if len(parts) == 4 else ""
        windows_path = f"{drive}:\\{rest}" if rest else f"{drive}:\\"
        before = text[match.start() - 1] if match.start() else ""
        after = text[match.end()] if match.end() < len(text) else ""
        already_single_quoted = before == "'" and after == "'"
        if any(char.isspace() for char in windows_path) and not already_single_quoted:
            return "'" + windows_path.replace("'", "''") + "'"
        return windows_path

    text = re.sub(
        r"(?<![\w/])(/mnt/[A-Za-z](?:/(?:[^\s\"'`;|&<>()\\]|\\+\s)*)?)",
        mounted_path,
        text,
    )

    return text.replace(
        executable_placeholder, shlex.quote(str(WINDOWS_POWERSHELL))
    )

def incomplete_shell_heredoc_marker(command):
    """Return an unterminated heredoc marker before a shell can block on it."""
    text = command or ""
    for match in re.finditer(
        r"(?m)(?:^|&&|\|\||[;|])\s*(?:cat|tee)\s+<<-?\s*"
        r"(['\"]?)([A-Za-z_][A-Za-z0-9_]*)\1",
        text,
    ):
        marker = match.group(2)
        remainder = text[match.end():]
        if not re.search(r"(?m)^\s*" + re.escape(marker) + r"\s*$", remainder):
            return marker
    return ""

_MISSING_COMMAND_RECOVERY = {
    "dotnet": ("dotnet-sdk-10.0", "dotnet --info"),
    "go": ("golang-go", "go version"),
    "javac": ("default-jdk", "javac -version"),
    "java": ("default-jdk", "java -version"),
    "mvn": ("maven", "mvn -version"),
    "gradle": ("gradle", "gradle --version"),
    "ruby": ("ruby-full", "ruby --version"),
    "gem": ("ruby-full", "gem --version"),
    "php": ("php-cli", "php --version"),
    "composer": ("composer", "composer --version"),
    "lua": ("lua5.4", "lua -v"),
    "luac": ("lua5.4", "luac -v"),
    "luarocks": ("luarocks", "luarocks --version"),
    "r": ("r-base", "R --version"),
    "rscript": ("r-base", "Rscript --version"),
    "ghc": ("ghc", "ghc --version"),
    "cabal": ("cabal-install", "cabal --version"),
    "nim": ("nim", "nim --version"),
    "crystal": ("crystal", "crystal --version"),
    "erl": ("erlang", "erl -eval 'halt().' -noshell"),
    "elixir": ("elixir", "elixir --version"),
    "ocaml": ("ocaml", "ocaml -version"),
    "opam": ("opam", "opam --version"),
    "clojure": ("clojure", "clojure --help"),
    "kotlinc": ("kotlin", "kotlinc -version"),
    "scala": ("scala", "scala -version"),
    "scalac": ("scala", "scalac -version"),
    "clang": ("clang", "clang --version"),
    "clang++": ("clang", "clang++ --version"),
    "ninja": ("ninja-build", "ninja --version"),
    "meson": ("meson", "meson --version"),
    "cargo": ("rustup", "cargo --version"),
    "rustc": ("rustup", "rustc --version"),
    "rustfmt": ("rustup", "rustfmt --version"),
    "clippy-driver": ("rustup", "clippy-driver --version"),
    "zig": ("mise:zig", "zig version"),
    "deno": ("mise:deno", "deno --version"),
    "bun": ("mise:bun", "bun --version"),
    "julia": ("mise:julia", "julia --version"),
    "swift": ("mise:swift", "swift --version"),
    "dart": ("mise:dart", "dart --version"),
    "flutter": ("mise:flutter", "flutter --version"),
    "sbt": ("mise:sbt", "sbt --version"),
    "terraform": ("mise:terraform", "terraform version"),
    "kubectl": ("mise:kubectl", "kubectl version --client"),
    "pwsh": ("powershell", "pwsh --version"),
}

def missing_command_recovery(command_name):
    return _MISSING_COMMAND_RECOVERY.get((command_name or "").strip().lower())

def extract_missing_command(output):
    matches = re.findall(
        r"(?:^|\n)(?:/bin/bash:\s+line\s+\d+:\s+|"
        r"bash:\s+line\s+\d+:\s+|)?"
        r"([A-Za-z0-9_.+:-]+):\s+command not found\b",
        output or "",
        re.IGNORECASE,
    )
    return matches[-1] if matches else ""

def is_foreground_gui_command(command):
    """Identify a direct app launch that can wait forever in its event loop."""
    cmd = (command or "").strip()
    low = cmd.lower()
    if not cmd or re.search(r"(?:^|[;&]\s*)timeout\s+\d+", low):
        return False
    if re.search(r"(?:^|[^&])&\s*(?:$|[;])", cmd):
        return False
    if re.search(
        r"\b(py_compile|compileall|pytest|unittest|pylint|ruff|mypy|"
        r"flake8|pyright|php\s+-l|ruby\s+-c|luac\s+-p|"
        r"clang\s+-fsyntax-only|dotnet\s+(?:test|build))\b",
        low,
    ):
        return False
    if re.search(
        r"\bpython(?:3(?:\.\d+)?)?\s+(?:[^\s;&|]*/)?"
        r"(?:test_[^/\s;&|]+|[^/\s;&|]+_test|final_check|"
        r"check_[^/\s;&|]+|verify[^/\s;&|]*)\.py\b",
        low,
    ):
        return False
    return bool(
        re.search(r"\bpython(?:3(?:\.\d+)?)?\s+\S+\.(?:py|pyw)\b", low)
        or re.search(r"\bdotnet\s+run\b|\bjava\s+-jar\b", low)
    )

def objective_requests_windows_gui(text):
    low = (text or "").lower()
    return (
        re.search(r"[A-Za-z]:\\", text or "") is not None
        and any(word in low for word in (
            "gui", "desktop app", "window", "windows app", "one click",
        ))
    )

def align_call_to_requested_targets(call, objective):
    """Repair a hallucinated C-profile mirror when the objective names a drive path."""
    repaired = dict(call or {})
    replacements = []
    for target in extract_target_paths(objective):
        match = re.fullmatch(r"/mnt/([a-zA-Z])/(.+)", target.rstrip("/"))
        if not match:
            continue
        drive = match.group(1).lower()
        components = [part for part in match.group(2).split("/") if part]
        if not components or drive == "c":
            continue
        mirror_prefix = f"{drive.upper()}_{components[0]}"
        mirror_suffix = "/".join(components[1:])
        pattern = (
            r"/mnt/c/Users/[^/\s'\";|&]+/"
            + re.escape(mirror_prefix)
            + (r"/" + re.escape(mirror_suffix) if mirror_suffix else "")
            + r"(?=$|[/\s'\";|&])"
        )
        replacements.append((re.compile(pattern, re.IGNORECASE), target.rstrip("/")))
    if not replacements:
        return repaired

    changed_targets = []
    for key in ("cmd", "path", "patch"):
        value = repaired.get(key)
        if not isinstance(value, str) or not value:
            continue
        fixed = value
        for pattern, target in replacements:
            fixed, count = pattern.subn(target, fixed)
            if count:
                changed_targets.append(target)
        if fixed != value:
            repaired[key] = fixed
    if changed_targets:
        target_list = ", ".join(dict.fromkeys(changed_targets))
        note = (
            "corrected a hallucinated C: user-profile mirror to the explicit "
            f"requested target {target_list}"
        )
        previous = repaired.get("intent_repaired")
        repaired["intent_repaired"] = f"{previous}; {note}" if previous else note
    return repaired

def _atomic_write_json(path, payload):
    path.parent.mkdir(parents=True, exist_ok=True)
    temp_path = path.with_name(path.name + ".tmp")
    with open(temp_path, "w", encoding="utf-8") as handle:
        json.dump(payload, handle, ensure_ascii=True, indent=2)
        handle.flush()
        os.fsync(handle.fileno())
    os.replace(temp_path, path)
    try:
        directory_fd = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_fd)
        finally:
            os.close(directory_fd)
    except Exception:
        pass

def emit_event(kind, status="info", message="", **fields):
    """Append one durable, machine-readable runtime event."""
    event = {
        "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        "monotonic_ms": int(time.monotonic() * 1000),
        "kind": kind,
        "status": status,
        "message": _one_line(message, 800),
    }
    event.update({key: value for key, value in fields.items() if value is not None})
    try:
        EVENT_LOG_FILE.parent.mkdir(parents=True, exist_ok=True)
        with open(EVENT_LOG_FILE, "a", encoding="utf-8") as handle:
            handle.write(json.dumps(event, ensure_ascii=True) + "\n")
            handle.flush()
    except Exception:
        pass

def _tool_failed(output):
    low = (output or "").lower()
    return (
        low.startswith("[error:")
        or low.startswith("[no change:")
        or low.startswith("[loop guard:")
        or low.startswith("[interrupted action blocked:")
        or low.startswith("[interrupted subprocess:")
        or low.startswith("[stalled subprocess:")
        or low.startswith("[recovery required:")
        or low.startswith("[verification required:")
        or low.startswith("[rolled back:")
        or "[exit code:" in low
        or "traceback (most recent call last)" in low
        or "command not found" in low
        or "file not found" in low
        or "timed out" in low
        or re.search(r"(?m)^\s*error\|", low) is not None
        or "parameterbindingexception" in low
        or "fullyqualifiederrorid" in low
        or "a parameter cannot be found that matches parameter name" in low
        or re.search(r"(?m)^\s*get-childitem\s*:", low) is not None
    )

def _call_fingerprint(call, user_message=""):
    if call.get("type") == "command":
        value = intercept_command(call.get("cmd", ""), user_message)
    else:
        stable_call = {
            key: value
            for key, value in call.items()
            if key not in {"tool_call_id", "intent_repaired"}
        }
        value = json.dumps(stable_call, sort_keys=True, ensure_ascii=True)
    return hashlib.sha256(value.encode("utf-8", errors="replace")).hexdigest()[:16]

def _command_edits_project_files(command):
    """Identify shell commands whose claimed progress should change project bytes."""
    cmd = command or ""
    if re.search(
        r"\b(?:sed\s+-i|perl\s+-[^\n;]*i|tee(?:\s+-a)?|truncate)\b",
        cmd,
        re.IGNORECASE | re.MULTILINE,
    ):
        return True
    working_dir = Path.cwd().resolve()
    cd_matches = list(re.finditer(
        r"(?:^|[;&|]\s*)cd\s+(?:--\s+)?"
        r"(?:\"([^\"]+)\"|'([^']+)'|([^\s;&|]+))",
        cmd,
        re.IGNORECASE,
    ))
    if cd_matches:
        raw_cd = next((part for part in cd_matches[-1].groups() if part), "")
        expanded_cd = Path(os.path.expandvars(os.path.expanduser(raw_cd)))
        working_dir = (
            expanded_cd if expanded_cd.is_absolute()
            else working_dir / expanded_cd
        ).resolve()
    redirect_pattern = re.compile(
        r"(?<!<)(?:^|[\s;|])(?:\d*|&)>{1,2}\s*"
        r"(?:\"([^\"]+)\"|'([^']+)'|([^\s;&|]+))"
    )
    for match in redirect_pattern.finditer(cmd):
        raw_target = next((part for part in match.groups() if part), "")
        if not raw_target or raw_target.startswith("&"):
            continue
        expanded = Path(os.path.expandvars(os.path.expanduser(raw_target)))
        target = (
            expanded if expanded.is_absolute()
            else working_dir / expanded
        ).resolve()
        try:
            target.relative_to(working_dir)
        except ValueError:
            continue
        return True
    return bool(
        re.search(r"\bpython(?:3(?:\.\d+)?)?\b", cmd, re.IGNORECASE)
        and re.search(
            r"\b(?:write_text|write_bytes|writelines?|os\.replace|"
            r"shutil\.(?:copy|copy2|copyfile|move)|"
            r"open\s*\([^)]*,\s*['\"][wax+])",
            cmd,
            re.IGNORECASE | re.DOTALL,
        )
    )

def _identical_sed_substitution(command):
    """Return an identical sed search/replacement pair, if one is explicit."""
    try:
        tokens = shlex.split(command)
    except ValueError:
        return None
    for index, token in enumerate(tokens):
        if token != "sed":
            continue
        for expression in tokens[index + 1:index + 4]:
            if expression.startswith("-"):
                continue
            if len(expression) < 4 or expression[0] != "s":
                break
            delimiter = expression[1]
            if delimiter.isalnum() or delimiter.isspace():
                break
            parts = expression[2:].split(delimiter)
            if len(parts) >= 3 and parts[0] == parts[1]:
                return parts[0], parts[1]
            break
    return None

def repair_identical_numeric_sed_from_message(call, message):
    """Align a provably identical sed edit with one explicit literal intent."""
    if call.get("type") != "command":
        return call
    cmd = call.get("cmd") or ""
    identical = _identical_sed_substitution(cmd)
    if identical is None:
        return call
    old, _ = identical
    objective = (
        CURRENT_TASK_STATE.objective
        if CURRENT_TASK_STATE is not None else ""
    )
    evidence = "\n".join(part for part in (objective, message or "") if part)
    literal_matches = re.findall(
        r"current\s+(?:invalid\s+)?source\s+is\s+exactly:\s*"
        r"(?P<old>.+?)\s+and\b.*?"
        r"(?:change|replace).*?\bto\s+exactly:\s*"
        r"(?P<new>.+?)(?=\s+(?:using|then|after|before)\b|$)",
        evidence,
        re.IGNORECASE | re.DOTALL,
    )
    literal_candidates = {
        (source.strip().strip("`\"'"), destination.strip().strip("`\"'"))
        for source, destination in literal_matches
        if source.strip().strip("`\"'") == old
        and destination.strip().strip("`\"'") != old
    }
    if len(literal_candidates) == 1:
        _, replacement = literal_candidates.pop()
        for delimiter in ("/", "|", "#", "@", ":"):
            needle = f"s{delimiter}{old}{delimiter}{old}{delimiter}"
            if needle in cmd and delimiter not in replacement:
                repaired = dict(call)
                repaired["cmd"] = cmd.replace(
                    needle,
                    f"s{delimiter}{old}{delimiter}{replacement}{delimiter}",
                    1,
                )
                repaired["intent_repaired"] = (
                    "aligned an identical sed destination with the one explicit "
                    "literal destination in the durable task objective"
                )
                return repaired
    number_match = re.search(r"(\d+)(?!.*\d)", old)
    if not number_match:
        return call
    old_number = number_match.group(1)
    candidates = set()
    intent_patterns = (
        rf"\bfrom\s+[`'\"\s]*{re.escape(old_number)}\)?[`'\"\s]*"
        rf"\bto\s+[`'\"\s]*(\d+)",
        rf"[`'\"]?{re.escape(old_number)}\)?[`'\"]?\s+instead\s+of\s+"
        rf"[`'\"]?(\d+)",
        rf"\bshould\s+be\s+[`'\"\s]*(\d+)",
    )
    for pattern in intent_patterns:
        candidates.update(
            match.group(1)
            for match in re.finditer(pattern, evidence, re.IGNORECASE)
            if match.group(1) != old_number
        )
    if len(candidates) != 1:
        return call
    destination_number = candidates.pop()
    replacement = (
        old[:number_match.start()]
        + destination_number
        + old[number_match.end():]
    )
    for delimiter in ("/", "|", "#", "@", ":"):
        needle = f"s{delimiter}{old}{delimiter}{old}{delimiter}"
        if needle in cmd:
            repaired = dict(call)
            repaired["cmd"] = cmd.replace(
                needle, f"s{delimiter}{old}{delimiter}{replacement}{delimiter}", 1
            )
            repaired["intent_repaired"] = (
                f"aligned identical sed destination {old_number} with the "
                f"explicit message destination {destination_number}"
            )
            return repaired
    return call

def repair_missing_python_loop_variable(call, message):
    """Restore a dropped ``i`` only when the durable objective proves intent."""
    objective = (
        CURRENT_TASK_STATE.objective
        if CURRENT_TASK_STATE is not None else ""
    )
    evidence = "\n".join(part for part in (objective, message or "") if part)
    if not (
        re.search(r"\bmissing\s+(?:loop\s+)?variable\s+[`'\"]?i\b", evidence, re.I)
        or re.search(
            r"\brestore\s+(?:the\s+)?missing\s+(?:loop\s+)?variable\s+[`'\"]?i\b",
            evidence,
            re.I,
        )
    ):
        return call

    repaired = dict(call)
    call_type = repaired.get("type")
    changed = False
    if call_type == "python":
        source = repaired.get("code") or ""
        fixed = re.sub(
            r"(?m)^(\s*)for\s+in\s+range\s*\(",
            r"\1for i in range(",
            source,
        )
        if fixed != source:
            repaired["code"] = fixed
            changed = True
    elif call_type == "command":
        source = repaired.get("cmd") or ""
        fixed = re.sub(r"\bfor\s+in\s+range\s*\(", "for i in range(", source)
        if fixed != source:
            repaired["cmd"] = fixed
            changed = True
    elif call_type == "patch":
        source = repaired.get("patch") or ""
        fixed = re.sub(
            r"(?m)^(\+\s*)for\s+in\s+range\s*\(",
            r"\1for i in range(",
            source,
        )
        if fixed != source:
            repaired["patch"] = fixed
            changed = True

    if changed:
        repaired["intent_repaired"] = (
            "restored the explicitly required Python loop variable i after "
            "the streamed tool arguments dropped it"
        )
    return repaired

def _is_mutating_call(call):
    call_type = call.get("type", "command")
    if call_type in ("write", "append", "patch", "mcp"):
        return True
    if call_type == "python":
        code = (call.get("code") or "").lower()
        return bool(re.search(
            r"\b(write_text|write_bytes|mkdir|makedirs|remove|unlink|rename|"
            r"replace|rmtree|copy|copy2|move|open\s*\([^)]*,\s*['\"](?:w|a|x)|"
            r"subprocess\.(?:run|popen|call)|os\.system)\b",
            code,
        ))
    if call_type != "command":
        return False
    cmd = (call.get("cmd") or "").lower()
    if _command_edits_project_files(cmd):
        return True
    return bool(re.search(
        r"(^|[;&|]\s*)(mkdir|touch|cp|mv|rm|install|git\s+(clone|commit|merge|rebase|apply)|"
        r"npm\s+(install|run\s+build)|pip\s+install|sed\s+-i|tee|chmod|chown|"
        r"powershell(?:\.exe)?.*(new-item|set-content|add-content|copy-item|move-item|remove-item)|"
        r"docker\s+(build|run|compose\s+up))\b",
        cmd,
    ))

def _is_verification_call(call):
    call_type = call.get("type", "command")
    if call_type == "read":
        return True
    if call_type != "command":
        return False
    if _is_mutating_call(call):
        return False
    cmd = (call.get("cmd") or "").lower()
    return bool(re.search(
        r"\b(pytest|pester|test-path|npm\s+test|npm\s+run\s+test|"
        r"python(?:3)?\s+-m\s+(?:py_compile|compileall|unittest)|"
        r"python(?:3)?\s+\S*(?:test|verification|verify|check)\S*|"
        r"(?:cmd(?:\.exe)?\s+/c|powershell(?:\.exe)?).*"
        r"(?:test|verification|verify|check)|"
        r"bash\s+-n|shellcheck|node\s+--check|"
        r"test\s+-[efsd]|get-content|sha256sum|cmp\b|diff\b|"
        r"dotnet\s+(?:test|build|--info|--version)|cargo\s+(?:test|check)|go\s+test|"
        r"(?:mvn|gradle)\s+(?:test|check|build)|eslint|tsc\b|"
        r"pylint|ruff\s+(?:check|format\s+--check)|mypy|flake8|pyright|"
        r"php\s+-l|ruby\s+-c|luac\s+-p|javac\b|"
        r"clang(?:\+\+)?\s+-fsyntax-only|"
        r"git\s+diff\s+--check|curl\b|invoke-webrequest|"
        r"get-childitem|select-string|cat\b|head\b|tail\b|stat\b|wc\b|"
        r"ls\b|find\b)\b",
        cmd,
    ))

def automatic_verification_checkpoint_call(user_message=""):
    """Return a bounded, read-only workspace checkpoint.

    A local model can occasionally ignore a tool-schema restriction after a
    restored task has reached verification pressure. Instead of allowing that
    mistake to consume action rounds against the guard, collect fresh real
    workspace evidence before asking for another model response.
    """
    targets = extract_target_paths(user_message)
    target = targets[0] if targets else "."
    quoted_target = shlex.quote(target)
    return {
        "type": "command",
        "cmd": (
            f"if test -d {quoted_target}; then "
            "printf 'AUTOMATIC_VERIFICATION_CHECKPOINT\\n'; "
            f"printf 'CHECKPOINT_ROOT=%s\\n' {quoted_target}; "
            f"find {quoted_target} -maxdepth 2 -type f "
            "-printf '%p\\t%s\\t%TY-%Tm-%TdT%TH:%TM:%TS\\n' "
            "| LC_ALL=C sort | head -80; "
            "else "
            f"printf 'AUTOMATIC_VERIFICATION_CHECKPOINT_MISSING_ROOT=%s\\n' {quoted_target}; "
            "fi"
        ),
    }

def project_file_snapshot(root=None):
    """Hash bounded project files so scripted no-op writes cannot count as work."""
    base = Path(root or Path.cwd()).resolve()
    snapshot = {}
    skipped = {".git", ".venv", "venv", "node_modules", "__pycache__", ".nature"}
    try:
        paths = base.rglob("*")
        for path in paths:
            if any(part in skipped for part in path.parts):
                continue
            try:
                if not path.is_file() or path.stat().st_size > 8 * 1024 * 1024:
                    continue
                relative = str(path.relative_to(base))
                snapshot[relative] = hashlib.sha256(path.read_bytes()).hexdigest()
            except (OSError, ValueError):
                continue
    except OSError:
        return {}
    return snapshot

def project_python_backup(root=None):
    """Capture bounded Python sources for transactional shell-edit rollback."""
    base = Path(root or Path.cwd()).resolve()
    backup = {}
    skipped = {".git", ".venv", "venv", "node_modules", "__pycache__", ".nature"}
    try:
        for path in base.rglob("*.py"):
            if any(part in skipped for part in path.parts):
                continue
            try:
                if path.is_file() and path.stat().st_size <= 8 * 1024 * 1024:
                    backup[str(path.relative_to(base))] = path.read_bytes()
            except (OSError, ValueError):
                continue
    except OSError:
        pass
    return base, backup

def project_python_syntax_error(root=None):
    """Return fresh compile evidence for the first invalid project Python file."""
    base = Path(root or Path.cwd()).resolve()
    skipped = {".git", ".venv", "venv", "node_modules", "__pycache__", ".nature"}
    try:
        paths = sorted(base.rglob("*.py"))
    except OSError:
        return ""
    for path in paths:
        if any(part in skipped for part in path.parts):
            continue
        result = subprocess.run(
            [sys.executable, "-m", "py_compile", str(path)],
            capture_output=True,
            text=True,
        )
        if result.returncode != 0:
            return _one_line(result.stderr or result.stdout, 1200)
    return ""

def restore_project_python_backup(base, backup):
    """Restore Python files exactly and remove Python files created by the action."""
    current = set()
    try:
        current = {
            str(path.relative_to(base))
            for path in base.rglob("*.py")
            if path.is_file()
        }
    except OSError:
        pass
    for relative in current - set(backup):
        try:
            (base / relative).unlink()
        except OSError:
            pass
    for relative, content in backup.items():
        path = base / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.with_name(path.name + ".nature-rollback")
        temp.write_bytes(content)
        os.replace(temp, path)

def objective_exact_line_patch_calls(objective, root=None):
    """Build verified one-line patches from explicit OLD -> NEW objective facts."""
    text = objective or ""
    quoted = re.compile(
        r"current\s+line\s+(\d+)\s+is\s+exactly\s+([\"'`])(.+?)\2,?\s+"
        r"but\s+must\s+be\s+([\"'`])(.+?)\4",
        re.IGNORECASE,
    )
    pairs = [
        (match.group(1), match.group(3), match.group(5))
        for match in quoted.finditer(text)
    ]
    if not pairs:
        pairs = re.findall(
            r"current\s+line\s+(?P<line>\d+)\s+is\s+exactly\s+(?P<old>.+?)\s+"
            r"but\s+must\s+be\s+(?P<new>.+?)(?=;\s*current\s+line|;\s*"
            r"current\s+line|;\s*(?:The|Make|Then|Run|Report|Maintain|Emit)\b|"
            r"\.\s+(?:The|Make|Then|Run|Report|Maintain|Emit)\b|$)",
            text,
            re.IGNORECASE,
        )
    if not pairs:
        return []
    base = Path(root or Path.cwd()).resolve()
    calls = []
    for raw_line_number, raw_old, raw_new in pairs:
        expected_line_number = int(raw_line_number)
        old = raw_old.strip().strip("`\"'")
        new = raw_new.strip().strip("`\"'")
        if not old or not new or old == new:
            continue
        matches = []
        try:
            paths = sorted(base.rglob("*"))
        except OSError:
            paths = []
        for path in paths:
            try:
                if (
                    not path.is_file()
                    or path.stat().st_size > 8 * 1024 * 1024
                    or any(
                        part in {
                            ".git", ".venv", "venv", "node_modules",
                            "__pycache__", ".nature",
                        }
                        for part in path.parts
                    )
                ):
                    continue
                lines = path.read_text(encoding="utf-8").splitlines()
            except (OSError, UnicodeError):
                continue
            for index, line in enumerate(lines, 1):
                if index != expected_line_number:
                    continue
                stripped = line.strip()
                wrapper = ("", "")
                if stripped == old:
                    matches.append((path, index, line, wrapper))
                    continue
                for quote in ('"', "'"):
                    for suffix in (quote, quote + ","):
                        prefix = quote
                        if (
                            stripped.startswith(prefix)
                            and stripped.endswith(suffix)
                            and stripped[len(prefix):len(stripped) - len(suffix)] == old
                        ):
                            matches.append((path, index, line, (prefix, suffix)))
                            break
                    if matches and matches[-1][0] == path and matches[-1][1] == index:
                        break
        if len(matches) != 1:
            continue
        path, line_number, original_line, wrapper = matches[0]
        indent = original_line[:len(original_line) - len(original_line.lstrip())]
        replacement_line = indent + wrapper[0] + new + wrapper[1]
        relative = path.relative_to(base).as_posix()
        patch = (
            f"--- a/{relative}\n"
            f"+++ b/{relative}\n"
            f"@@ -{line_number},1 +{line_number},1 @@\n"
            f"-{original_line}\n"
            f"+{replacement_line}\n"
        )
        calls.append({
            "type": "patch",
            "patch": patch,
            "objective_literal_repair": f"{old} -> {new}",
        })
    return calls

def rebase_patch_paths(patch):
    """Rebase missing relative patch targets when each suffix has one exact match."""
    base = Path.cwd().resolve()
    replacements = {}
    for line in patch.splitlines():
        if not line.startswith(("--- ", "+++ ")):
            continue
        raw_path = line[4:].split("\t", 1)[0].strip()
        if raw_path == "/dev/null":
            continue
        prefix = raw_path[:2] if raw_path.startswith(("a/", "b/")) else ""
        normalized = raw_path[2:] if prefix else raw_path
        relative = Path(normalized)
        if relative.is_absolute() or ".." in relative.parts:
            continue
        if (base / relative).exists():
            continue
        matches = []
        try:
            for candidate in base.rglob(relative.name):
                if not candidate.is_file():
                    continue
                candidate_relative = candidate.relative_to(base)
                if tuple(candidate_relative.parts[-len(relative.parts):]) == relative.parts:
                    matches.append(candidate_relative)
                    if len(matches) > 1:
                        break
        except (OSError, ValueError):
            continue
        if len(matches) == 1:
            replacements[raw_path] = prefix + matches[0].as_posix()
    if not replacements:
        return patch
    rebased = []
    for line in patch.splitlines():
        if line.startswith(("--- ", "+++ ")):
            marker, value = line[:4], line[4:]
            raw_path, separator, timestamp = value.partition("\t")
            replacement = replacements.get(raw_path.strip())
            if replacement:
                line = marker + replacement + (separator + timestamp if separator else "")
        rebased.append(line)
    return "\n".join(rebased) + ("\n" if patch.endswith("\n") else "")

def apply_unique_single_line_patch(patch):
    """Recover a stale-context diff by replacing one unique exact line."""
    lines = patch.splitlines()
    removed = [
        line[1:] for line in lines
        if line.startswith("-") and not line.startswith("--- ")
    ]
    added = [
        line[1:] for line in lines
        if line.startswith("+") and not line.startswith("+++ ")
    ]
    targets = [
        line[4:].split("\t", 1)[0].strip()
        for line in lines if line.startswith("+++ ")
    ]
    if len(removed) != 1 or len(added) != 1 or len(targets) != 1:
        return None
    raw_path = targets[0]
    if raw_path == "/dev/null":
        return None
    normalized = raw_path[2:] if raw_path.startswith(("a/", "b/")) else raw_path
    target = Path(normalized)
    if target.is_absolute() or ".." in target.parts or not target.is_file():
        return None
    try:
        original = target.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return None
    old_line, new_line = removed[0], added[0]
    old_with_lf = old_line + "\n"
    occurrences = original.count(old_with_lf)
    trailing_without_lf = (
        original.endswith(old_line) and not original.endswith(old_with_lf)
    )
    if occurrences + int(trailing_without_lf) != 1:
        return None
    if occurrences == 1:
        updated = original.replace(old_with_lf, new_line + "\n", 1)
    else:
        updated = original[:-len(old_line)] + new_line
    if updated == original:
        return "[NO CHANGE: The focused replacement already matches the target file.]"
    target.write_text(updated, encoding="utf-8")
    return (
        f"[PATCH APPLIED: Recovered stale hunk context by replacing one unique "
        f"exact line in {target} and verified that the file bytes changed.]"
    )

def patch_refresh_evidence(patch, max_chars=12000):
    """Return fresh exact target bytes after stale patch validation fails."""
    targets = [
        line[4:].split("\t", 1)[0].strip()
        for line in (patch or "").splitlines()
        if line.startswith("+++ ")
    ]
    if len(targets) != 1 or targets[0] == "/dev/null":
        return ""
    raw_path = targets[0]
    normalized = raw_path[2:] if raw_path.startswith(("a/", "b/")) else raw_path
    target = Path(normalized)
    if target.is_absolute() or ".." in target.parts or not target.is_file():
        return ""
    try:
        current = target.read_text(encoding="utf-8")
    except (OSError, UnicodeError):
        return ""
    if len(current) > max_chars:
        hunk = next(
            (line for line in patch.splitlines() if line.startswith("@@ ")),
            "",
        )
        match = re.match(r"@@ -(\d+)", hunk)
        center = int(match.group(1)) if match else 1
        lines = current.splitlines()
        start = max(0, center - 41)
        end = min(len(lines), center + 40)
        current = "\n".join(lines[start:end])
        location = f"lines {start + 1}-{end}"
    else:
        location = "complete file"
    return (
        f"\n[FRESH TARGET EVIDENCE: {target} ({location}). Build the next "
        "single-hunk patch from these exact current bytes; do not reuse stale "
        "context.]\n" + current
    )

class TaskState:
    """Durable evidence ledger used by the completion gate and crash recovery."""
    def __init__(self, objective, restored=None):
        data = restored or {}
        self.task_id = data.get("task_id") or (
            time.strftime("%Y%m%d-%H%M%S") + "-" + uuid.uuid4().hex[:8]
        )
        self.objective = data.get("objective") or objective
        self.status = data.get("status", "running")
        self.round = int(data.get("round", 0))
        self.sequence = int(data.get("sequence", 0))
        self.requires_action = bool(data.get(
            "requires_action", objective_requires_action(self.objective)
        ))
        self.requires_verification = bool(data.get(
            "requires_verification", objective_requires_verification(self.objective)
        ))
        fresh_target_paths = extract_target_paths(self.objective)
        self.target_paths = fresh_target_paths or list(data.get("target_paths") or [])
        self.target_checks = dict(data.get("target_checks") or {})
        self.successful_actions = int(data.get("successful_actions", 0))
        self.mutations = int(data.get("mutations", 0))
        self.verifications = int(data.get("verifications", 0))
        self.last_mutation_sequence = int(data.get("last_mutation_sequence", 0))
        self.last_verification_sequence = int(data.get("last_verification_sequence", 0))
        self.verified_mutation_count = int(data.get(
            "verified_mutation_count",
            self.mutations if self.verifications else 0,
        ))
        self.verification_pressure_at_mutation = int(data.get(
            "verification_pressure_at_mutation", 0
        ))
        self.model_failures = int(data.get("model_failures", 0))
        self.no_progress_rounds = int(data.get("no_progress_rounds", 0))
        self.last_completion_rejection = str(
            data.get("last_completion_rejection") or ""
        )
        self.completion_rejection_repeats = int(
            data.get("completion_rejection_repeats", 0)
        )
        self.total_completion_rejections = int(
            data.get("total_completion_rejections", 0)
        )
        self.interrupted_actions = dict(data.get("interrupted_actions") or {})
        restored_inflight = data.get("inflight")
        if restored_inflight and restored_inflight.get("type") == "command":
            restored_inflight = dict(restored_inflight)
            restored_inflight["mutating"] = _is_mutating_call({
                "type": "command",
                "cmd": restored_inflight.get("description") or "",
            })
        if restored_inflight:
            restored_fingerprint = restored_inflight.get("fingerprint")
            if not restored_fingerprint:
                restored_call = {
                    "type": restored_inflight.get("type", "command"),
                    "cmd": restored_inflight.get("description") or "",
                }
                restored_fingerprint = _call_fingerprint(
                    restored_call, self.objective
                )
            self.interrupted_actions[restored_fingerprint] = {
                "description": _one_line(
                    restored_inflight.get("description") or "unknown action",
                    300,
                ),
                "reason": (
                    "The process ended while this action was still running. "
                    "Its exact command is blocked from automatic replay."
                ),
                "interrupted_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            }
        self.inflight = None
        self.pending_reconciliation = (
            data.get("pending_reconciliation") or (
                restored_inflight
                if restored_inflight and restored_inflight.get("mutating")
                else None
            )
        )
        if (
            self.pending_reconciliation
            and "no-op mutation was rejected" in (
                self.pending_reconciliation.get("description") or ""
            ).lower()
        ):
            self.pending_reconciliation = None
        self.events = list(data.get("events") or [])[-300:]
        self.fingerprints = dict(data.get("fingerprints") or {})

    def record(self, kind, detail, success=True):
        self.sequence += 1
        self.events.append({
            "sequence": self.sequence,
            "time": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
            "kind": kind,
            "success": bool(success),
            "detail": _one_line(detail, 500),
        })
        self.events = self.events[-300:]
        emit_event(
            kind,
            "completed" if success else "failed",
            detail,
            task_id=self.task_id,
            sequence=self.sequence,
            round=self.round,
        )

    def observe_tool(self, call, output, user_message=""):
        success = not _tool_failed(output)
        fingerprint = _call_fingerprint(call, user_message)
        output_hash = hashlib.sha256(
            (output or "").encode("utf-8", errors="replace")
        ).hexdigest()[:16]
        previous = self.fingerprints.get(fingerprint)
        repeats = int(previous.get("repeats", 0)) + 1 if (
            previous and previous.get("output_hash") == output_hash
        ) else 1
        self.fingerprints[fingerprint] = {
            "output_hash": output_hash,
            "repeats": repeats,
            "sequence": self.sequence + 1,
        }
        call_detail = (
            call.get("cmd") or call.get("path") or
            _one_line(call.get("patch", ""), 180) or
            _one_line(call.get("code", ""), 180) or narrate(call)
        )
        output_detail = _one_line(output, 240)
        self.record(
            "tool",
            f"{call.get('type', 'command')}: {call_detail}; result: {output_detail}",
            success,
        )
        self.inflight = None
        if success:
            checkpoint_root = re.search(
                r"(?m)^CHECKPOINT_ROOT=(.+)$",
                output or "",
            )
            if checkpoint_root:
                root = normalize_user_path(checkpoint_root.group(1).strip())
                checkpoint_lines = [
                    line for line in (output or "").splitlines()
                    if line and not line.startswith((
                        "AUTOMATIC_VERIFICATION_CHECKPOINT",
                        "CHECKPOINT_ROOT=",
                    ))
                ]
                self.target_checks[root] = {
                    "exists": True,
                    "nonempty": bool(checkpoint_lines),
                    "kind": "directory",
                }
            missing_checkpoint_root = re.search(
                r"(?m)^AUTOMATIC_VERIFICATION_CHECKPOINT_MISSING_ROOT=(.+)$",
                output or "",
            )
            if missing_checkpoint_root:
                root = normalize_user_path(missing_checkpoint_root.group(1).strip())
                self.target_checks[root] = {
                    "exists": False,
                    "nonempty": False,
                    "kind": "missing",
                }
            self.successful_actions += 1
            if _is_mutating_call(call):
                self.mutations += 1
                self.last_mutation_sequence = self.sequence
            if _is_verification_call(call):
                self.verifications += 1
                self.last_verification_sequence = self.sequence
                self.verified_mutation_count = self.mutations
                self.verification_pressure_at_mutation = 0
                if self.pending_reconciliation:
                    self.record(
                        "reconciliation",
                        "a read-only verification resolved the interrupted action outcome",
                        True,
                    )
                    self.pending_reconciliation = None
            self.no_progress_rounds = 0
            self.last_completion_rejection = ""
            self.completion_rejection_repeats = 0
        else:
            self.no_progress_rounds += 1
            low_output = (output or "").lower()
            if low_output.startswith((
                "[interrupted subprocess:",
                "[stalled subprocess:",
            )):
                self.interrupted_actions[fingerprint] = {
                    "description": _one_line(
                        call.get("cmd") or call.get("path") or
                        call.get("code") or narrate(call),
                        300,
                    ),
                    "reason": _one_line(output, 500),
                    "interrupted_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                }
                self.record(
                    "strategy-guard",
                    (
                        "the interrupted or stalled action was permanently "
                        "blocked from exact replay for this task"
                    ),
                    False,
                )
            if (output or "").lower().startswith("[no change:"):
                self.record(
                    "strategy-guard",
                    "a completed no-op was rejected and requires a different action",
                    False,
                )
        return success, repeats

    def begin_tool(self, call, user_message=""):
        fingerprint = _call_fingerprint(call, user_message)
        self.inflight = {
            "fingerprint": fingerprint,
            "type": call.get("type", "command"),
            "mutating": _is_mutating_call(call),
            "description": _one_line(
                call.get("cmd") or call.get("path") or
                call.get("code") or narrate(call),
                300,
            ),
            "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
        }
        self.record(
            "tool-start",
            f"started {self.inflight['type']}: {self.inflight['description']}",
        )
        return fingerprint

    def identical_result_repeats(self, call, user_message=""):
        previous = self.fingerprints.get(
            _call_fingerprint(call, user_message)
        ) or {}
        return int(previous.get("repeats", 0))

    def action_was_interrupted(self, call, user_message=""):
        return (
            _call_fingerprint(call, user_message)
            in self.interrupted_actions
        )

    def interrupted_action_reason(self, call, user_message=""):
        interrupted = self.interrupted_actions.get(
            _call_fingerprint(call, user_message)
        ) or {}
        return interrupted.get("description") or interrupted.get("reason") or ""

    def requires_reconciliation_before(self, call, user_message=""):
        if not self.pending_reconciliation:
            return False
        return not _is_verification_call(call)

    def verification_due(self):
        return (
            self.requires_verification
            and self.mutations > self.verified_mutation_count
            and (
                self.mutations - self.verified_mutation_count
                >= MAX_MUTATIONS_WITHOUT_VERIFICATION
            )
        )

    def target_evidence(self):
        evidence = []
        for raw in self.target_paths:
            normalized = normalize_user_path(raw)
            if re.match(r"(?i)^/mnt/[a-z](?:/|$)", normalized):
                observed = self.target_checks.get(normalized)
                if observed:
                    evidence.append({
                        "path": normalized,
                        "exists": bool(observed.get("exists")),
                        "nonempty": bool(observed.get("nonempty")),
                        "kind": observed.get("kind", "missing"),
                    })
                else:
                    evidence.append({
                        "path": normalized,
                        "exists": False,
                        "nonempty": False,
                        "kind": "unverified",
                    })
                continue
            path = Path(normalized).expanduser()
            exists = path.exists()
            nonempty = True
            if exists and path.is_dir():
                try:
                    nonempty = any(path.iterdir())
                except Exception:
                    nonempty = False
            evidence.append({
                "path": str(path),
                "exists": exists,
                "nonempty": nonempty,
                "kind": "directory" if exists and path.is_dir() else (
                    "file" if exists else "missing"
                ),
            })
        return evidence

    def completion_gaps(self, content, finish_reason=""):
        gaps = []
        if finish_reason in ("length", "max_tokens"):
            gaps.append("the model response hit its token limit and must continue")
        if self.inflight or self.pending_reconciliation:
            gaps.append(
                "an interrupted action has an unknown outcome and must be reconciled"
            )
        if "[TASK_COMPLETE]" not in (content or ""):
            gaps.append("the final completion marker is missing")
        if self.requires_action and self.mutations < 1:
            gaps.append("no successful modifying action has been recorded")
        if (
            self.requires_verification
            and self.last_verification_sequence <= self.last_mutation_sequence
        ):
            gaps.append(
                "no successful verification has run after the latest modification"
                if self.last_mutation_sequence
                else "no successful verification action has been recorded"
            )
        for item in self.target_evidence():
            if not item["exists"]:
                gaps.append(f"the requested target does not exist: {item['path']}")
            elif item["kind"] == "directory" and not item["nonempty"]:
                gaps.append(f"the requested target directory is empty: {item['path']}")
        low = (content or "").lower()
        if any(text in low for text in (
            "please try again", "i will now", "i'll now", "let me ",
            "could not produce", "did not produce", "[api error",
        )):
            gaps.append("the response describes unfinished work or an error")
        if response_delegates_action_to_user(content):
            gaps.append(
                "the response asks the user to perform work that the agent must execute"
            )
        return list(dict.fromkeys(gaps))

    def context_summary(self):
        targets = ", ".join(self.target_paths) if self.target_paths else "none explicitly named"
        recent = "; ".join(
            f"{event['kind']}={'ok' if event['success'] else 'failed'}:{event['detail']}"
            for event in self.events[-8:]
        )
        inflight = ""
        uncertain = self.pending_reconciliation or self.inflight
        if uncertain:
            inflight = (
                "\nInterrupted action with unknown outcome: "
                f"{uncertain.get('description', 'unknown action')}. "
                "Run a read-only check to reconcile its real outcome before "
                "repeating that modifying action."
            )
        action_pressure = ""
        evidence_since_mutation = self.sequence - self.last_mutation_sequence
        if (
            self.requires_action
            and (
                (self.mutations == 0 and self.verifications >= 12)
                or (self.mutations > 0 and evidence_since_mutation >= 12)
            )
            and self.no_progress_rounds < 3
        ):
            action_pressure = (
                "\nAction pressure: enough read-only evidence has been collected. "
                "The next successful step must be one apply_patch call for one file "
                "and one minimal hunk, no more than 80 diff lines, that addresses a "
                "proven defect, or an exact blocker with fresh proof. "
                "Do not reread files already represented in recent evidence."
            )
        verification_pressure = ""
        if self.verification_due():
            pending = self.mutations - self.verified_mutation_count
            verification_pressure = (
                f"\nVerification pressure: {pending} successful modifications "
                "have accumulated since the last test or readback. The next tool "
                "must be a read-only verification command or file read. Do not "
                "write, append, patch, install, or otherwise mutate anything until "
                "fresh verification succeeds."
            )
        interrupted_guard = ""
        if self.interrupted_actions:
            recent_blocked = list(self.interrupted_actions.values())[-3:]
            blocked_descriptions = "; ".join(
                item.get("description") or "unknown interrupted action"
                for item in recent_blocked
            )
            interrupted_guard = (
                "\nInterrupted-action guard: these exact actions must not be "
                f"replayed: {blocked_descriptions}. Use a materially different "
                "command, implementation, or verification strategy."
            )
        return (
            "[DURABLE TASK STATE]\n"
            f"Objective: {compact_text(self.objective, 6000)}\n"
            f"Current working directory: {Path.cwd()}.\n"
            f"Round: {self.round}; successful actions: {self.successful_actions}; "
            f"modifications: {self.mutations}; verifications: {self.verifications}.\n"
            f"Target paths: {targets}.\n"
            f"Recent evidence: {recent or 'no tool evidence yet'}.{inflight}"
            f"{action_pressure}{verification_pressure}{interrupted_guard}\n"
            "Continue the same objective. Do not declare completion until every gate is satisfied."
        )

    def to_dict(self):
        return {
            "task_id": self.task_id,
            "objective": self.objective,
            "status": self.status,
            "round": self.round,
            "sequence": self.sequence,
            "requires_action": self.requires_action,
            "requires_verification": self.requires_verification,
            "target_paths": self.target_paths,
            "target_checks": self.target_checks,
            "successful_actions": self.successful_actions,
            "mutations": self.mutations,
            "verifications": self.verifications,
            "last_mutation_sequence": self.last_mutation_sequence,
            "last_verification_sequence": self.last_verification_sequence,
            "verified_mutation_count": self.verified_mutation_count,
            "verification_pressure_at_mutation": self.verification_pressure_at_mutation,
            "model_failures": self.model_failures,
            "no_progress_rounds": self.no_progress_rounds,
            "last_completion_rejection": self.last_completion_rejection,
            "completion_rejection_repeats": self.completion_rejection_repeats,
            "total_completion_rejections": self.total_completion_rejections,
            "inflight": self.inflight,
            "pending_reconciliation": self.pending_reconciliation,
            "interrupted_actions": self.interrupted_actions,
            "events": self.events,
            "fingerprints": self.fingerprints,
        }

def checkpoint_task(state, conversation):
    global CURRENT_TASK_STATE, CURRENT_CONVERSATION
    CURRENT_TASK_STATE = state
    CURRENT_CONVERSATION = conversation
    payload = state.to_dict()
    payload["conversation"] = conversation
    payload["checkpointed_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    _atomic_write_json(ACTIVE_TASK_FILE, payload)

def load_pending_task():
    try:
        data = json.loads(ACTIVE_TASK_FILE.read_text())
        if data.get("status") in ("running", "recovering", "interrupted"):
            return data
    except Exception:
        pass
    return None

def sanitize_resume_conversation(saved_conversation, objective):
    """Rebuild an external resume from requirements and bounded durable facts.

    A checkpoint can survive a runtime upgrade after several failed model turns.
    Replaying those assistant command proposals makes a local model imitate the
    same invalid command even when the command router has since been repaired.
    Keep the user objective and current target evidence, but not stale proposals
    or tool-error transcripts.
    """
    targets = extract_target_paths(objective)
    target_text = ", ".join(targets) if targets else "no explicit target path"
    checkpoint_roots = []
    for message in reversed(saved_conversation or []):
        if message.get("role") != "system":
            continue
        content = str(message.get("content") or "")
        if not content.startswith("[AUTOMATIC"):
            continue
        for root in re.findall(r"(?m)^CHECKPOINT_ROOT=(.+)$", content):
            root = root.strip()
            if root and root not in checkpoint_roots:
                checkpoint_roots.append(root)
        if checkpoint_roots:
            break
    facts = (
        "Last verified checkpoint root: " + ", ".join(checkpoint_roots)
        if checkpoint_roots else
        "No prior checkpoint root is trusted; collect a fresh bounded checkpoint."
    )
    return [
        {"role": "system", "content": build_system_prompt()},
        {
            "role": "system",
            "content": (
                "[RESUME RECOVERY CONTEXT]\n"
                "This is a recovered task. The original objective is authoritative. "
                "All prior model-generated commands, code blocks, and tool-error "
                "transcripts were discarded because they repeatedly failed or were "
                "interrupted. Do not replay them. Reassess the current project "
                "before proposing the next action.\n"
                f"Current parsed target path(s): {target_text}.\n"
                f"{facts}"
            ),
        },
        {"role": "user", "content": objective},
    ]

def normalize_model_messages(messages):
    """Keep llama.cpp Jinja conversations to one leading system message."""
    leading_system = []
    normalized = []
    seen_non_system = False
    for raw in messages or []:
        if not isinstance(raw, dict):
            continue
        role = str(raw.get("role") or "user").strip().lower()
        content = raw.get("content")
        if role == "system":
            text = str(content or "").strip()
            if not text:
                continue
            if not seen_non_system:
                leading_system.append(text)
            else:
                normalized.append({
                    "role": "user",
                    "content": "[RUNTIME INSTRUCTION]\n" + text,
                })
            continue
        seen_non_system = True
        item = dict(raw)
        item["role"] = role or "user"
        normalized.append(item)
    if leading_system:
        return [{
            "role": "system",
            "content": "\n\n".join(leading_system),
        }] + normalized
    return normalized

def pending_task_notice(pending):
    """Explain the checkpoint boundary without silently changing the request."""
    task_id = pending.get("task_id", "unknown")
    objective = _one_line(pending.get("objective", "unfinished task"), 100)
    return (
        f"\033[1;33m[ACTIVE TASK]\033[0m Checkpoint {task_id} remains preserved "
        f"for: {objective}. Use /resume (or llama --resume) to continue it, "
        "or /cancel before starting different work."
    )

def finish_task(state, conversation):
    state.status = "complete"
    state.record("completion", "all deterministic completion gates passed", True)
    payload = state.to_dict()
    payload["conversation"] = conversation
    payload["completed_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
    _atomic_write_json(TASK_HISTORY_DIR / f"{state.task_id}.json", payload)
    try:
        active = json.loads(ACTIVE_TASK_FILE.read_text())
        if active.get("task_id") == state.task_id:
            ACTIVE_TASK_FILE.unlink()
    except Exception:
        pass

def mark_current_task_interrupted(reason):
    if CURRENT_TASK_STATE is None or CURRENT_CONVERSATION is None:
        return
    try:
        CURRENT_TASK_STATE.status = "interrupted"
        CURRENT_TASK_STATE.record("interruption", reason, False)
        checkpoint_task(CURRENT_TASK_STATE, CURRENT_CONVERSATION)
    except Exception:
        pass

def _process_stats(pid):
    """Read truthful Linux process CPU and RAM without launching another command."""
    try:
        raw_stat = Path(f"/proc/{pid}/stat").read_text()
        # The process name is parenthesized and may contain spaces, so parse
        # fields only after the final ')' instead of splitting the whole line.
        stat = raw_stat[raw_stat.rfind(")") + 2:].split()
        ticks = os.sysconf(os.sysconf_names["SC_CLK_TCK"])
        cpu_s = (int(stat[11]) + int(stat[12])) / ticks
        rss_kb = 0
        for line in Path(f"/proc/{pid}/status").read_text().splitlines():
            if line.startswith("VmRSS:"):
                rss_kb = int(line.split()[1])
                break
        return cpu_s, rss_kb / 1024
    except Exception:
        return 0.0, 0.0

def _process_start_token(pid):
    try:
        raw = Path(f"/proc/{pid}/stat").read_text()
        fields = raw[raw.rfind(")") + 2:].split()
        return fields[19]
    except Exception:
        return ""

def _process_group_stats(root_pid):
    """Aggregate the shell plus every child in its isolated process group."""
    try:
        group_id = os.getpgid(root_pid)
    except Exception:
        return (*_process_stats(root_pid), "")
    total_cpu, total_ram = 0.0, 0.0
    busiest_name, busiest_ram = "", -1.0
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        pid = int(proc_dir.name)
        try:
            if os.getpgid(pid) != group_id:
                continue
            cpu_s, ram_mb = _process_stats(pid)
            total_cpu += cpu_s
            total_ram += ram_mb
            if ram_mb > busiest_ram:
                busiest_ram = ram_mb
                busiest_name = (proc_dir / "comm").read_text(errors="replace").strip()
        except Exception:
            continue
    return total_cpu, total_ram, busiest_name

def _process_io_stats(pid):
    """Read cumulative process I/O counters without running another command."""
    try:
        values = {}
        for line in Path(f"/proc/{pid}/io").read_text().splitlines():
            key, _, value = line.partition(":")
            if key in ("rchar", "syscr"):
                values[key] = int(value.strip())
        return values.get("rchar", 0), values.get("syscr", 0)
    except Exception:
        return 0, 0

def _process_group_io_stats(root_pid):
    """Aggregate read bytes and read syscalls for an isolated process group."""
    try:
        group_id = os.getpgid(root_pid)
    except Exception:
        return _process_io_stats(root_pid)
    total_bytes, total_reads = 0, 0
    for proc_dir in Path("/proc").iterdir():
        if not proc_dir.name.isdigit():
            continue
        try:
            if os.getpgid(int(proc_dir.name)) != group_id:
                continue
            read_bytes, read_calls = _process_io_stats(int(proc_dir.name))
            total_bytes += read_bytes
            total_reads += read_calls
        except Exception:
            continue
    return total_bytes, total_reads

def _progress_scope(current_path, drive):
    """Collapse a changing leaf path into a meaningful stable work area."""
    normalized = (current_path or "").replace("/", "\\").rstrip("\\")
    parts = [part for part in normalized.split("\\") if part]
    if not parts:
        return drive or "the requested location"
    depth = 3 if len(parts) >= 3 else len(parts)
    return "\\".join(parts[:depth])


def parse_live_progress_record(line):
    """Parse one structured tool checkpoint without discarding its counters."""
    text = _one_line(line)
    if not text.startswith("LLAMA_PROGRESS|"):
        return None
    parts = text.split("|", 6)
    if len(parts) != 7:
        return None
    _, operation, phase, drive, directories, files, remainder = parts
    matches, separator, current_path = remainder.partition("|")
    if not separator:
        return None
    try:
        directories = int(directories)
        files = int(files)
        matches = int(matches)
    except ValueError:
        return None
    operation_name = {
        "search": "Windows filename search",
        "files": "largest-file scan",
        "scan": "folder-size scan",
    }.get(operation, "Windows file operation")
    current_path = _one_line(current_path, 180) or f"{drive}\\"
    scope = _progress_scope(current_path, drive)
    key = (
        f"tool-progress:{operation}:{phase}:{drive}:"
        f"{scope if phase == 'scanning' else phase}"
    )
    if phase == "started":
        message = (
            f"Starting {operation_name} at {current_path}; "
            "live filesystem counts will follow."
        )
    elif phase == "match":
        message = (
            f"Match {matches:,}: {current_path}; "
            f"{files:,} file{'s' if files != 1 else ''}, "
            f"{directories:,} folder{'s' if directories != 1 else ''} checked."
        )
    elif phase in ("complete", "stopped-after-exact-match"):
        if operation == "search":
            message = (
                f"Finished: {files:,} file{'s' if files != 1 else ''} checked in "
                f"{directories:,} folder{'s' if directories != 1 else ''}; "
                f"{matches:,} match{'es' if matches != 1 else ''} found on {drive}."
            )
        else:
            message = (
                f"Finished: {files:,} file{'s' if files != 1 else ''} measured in "
                f"{directories:,} folder{'s' if directories != 1 else ''} "
                f"on {drive}. The ranking is ready."
            )
    elif operation == "search":
        message = (
            f"{files:,} file{'s' if files != 1 else ''}, "
            f"{directories:,} folder{'s' if directories != 1 else ''} checked; "
            f"{matches:,} match{'es' if matches != 1 else ''}; now {scope}."
        )
    elif operation == "files":
        message = (
            f"{files:,} file{'s' if files != 1 else ''}, "
            f"{directories:,} folder{'s' if directories != 1 else ''} measured; "
            f"now {scope}."
        )
    else:
        message = (
            f"{files:,} file{'s' if files != 1 else ''}, "
            f"{directories:,} folder{'s' if directories != 1 else ''} measured; "
            f"adding sizes at {scope}."
        )
    return {
        "key": key,
        "message": message,
        "operation": operation,
        "phase": phase,
        "drive": drive,
        "directories": directories,
        "files": files,
        "matches": matches,
        "current_path": current_path,
        "scope": scope,
    }


def parse_live_progress_line(line):
    """Translate structured tool checkpoints into evidence-based English."""
    record = parse_live_progress_record(line)
    if not record:
        return None
    return record["key"], record["message"]

class ProcessTelemetry:
    def __init__(self, label):
        self.label = _one_line(label, 90)
        self.subject = re.sub(
            r"^(?:Running command|Running Python):\s*",
            "",
            self.label,
            flags=re.IGNORECASE,
        ) or self.label
        self.pid = 0
        self.lines = 0
        self.characters = 0
        self.latest = ""
        self.latest_stream = ""
        self.last_output_at = None
        self.last_report_lines = 0
        self.last_report_characters = 0
        self.last_report_cpu = 0.0
        self.last_report_io_bytes = 0
        self.last_report_io_reads = 0
        self.structured_event = None
        self.last_report_structured_directories = 0
        self.last_report_structured_files = 0
        self.last_report_structured_matches = 0
        self._event_key = ""
        self._event_message = ""
        self.lock = threading.Lock()

    def _event(self, key, message):
        """Keep the last factual process state until new evidence changes it."""
        with self.lock:
            self._event_key = key
            self._event_message = message
            return self._event_key, self._event_message

    def update(self, line, stream_name):
        structured = parse_live_progress_record(line)
        with self.lock:
            self.lines += 1
            self.characters += len(line)
            if structured:
                self.structured_event = structured
            cleaned = _one_line(line)
            if cleaned:
                self.latest = cleaned
                self.latest_stream = stream_name
            self.last_output_at = time.monotonic()

    def report(self, elapsed):
        with self.lock:
            lines = self.lines
            characters = self.characters
            latest = self.latest
            stream_name = self.latest_stream
            last_output_at = self.last_output_at
            pid = self.pid
            structured_event = self.structured_event
        cpu_s, ram_mb, active_name = (
            _process_group_stats(pid) if pid else (0.0, 0.0, "")
        )
        io_bytes, io_reads = _process_group_io_stats(pid) if pid else (0, 0)
        with self.lock:
            new_lines = max(0, lines - self.last_report_lines)
            new_characters = max(0, characters - self.last_report_characters)
            cpu_delta = max(0.0, cpu_s - self.last_report_cpu)
            io_delta_bytes = max(0, io_bytes - self.last_report_io_bytes)
            io_delta_reads = max(0, io_reads - self.last_report_io_reads)
            self.last_report_lines = lines
            self.last_report_characters = characters
            self.last_report_cpu = cpu_s
            self.last_report_io_bytes = io_bytes
            self.last_report_io_reads = io_reads
            if structured_event:
                structured_key = structured_event["key"]
                structured_message = structured_event["message"]
                structured_directory_delta = max(
                    0,
                    structured_event["directories"]
                    - self.last_report_structured_directories,
                )
                structured_file_delta = max(
                    0,
                    structured_event["files"]
                    - self.last_report_structured_files,
                )
                structured_match_delta = max(
                    0,
                    structured_event["matches"]
                    - self.last_report_structured_matches,
                )
                self.last_report_structured_directories = structured_event["directories"]
                self.last_report_structured_files = structured_event["files"]
                self.last_report_structured_matches = structured_event["matches"]
            else:
                structured_key = structured_message = ""
                structured_directory_delta = structured_file_delta = 0
                structured_match_delta = 0
        age = (
            max(0.0, time.monotonic() - last_output_at)
            if last_output_at
            else float(elapsed)
        )
        worker = active_name or "The command process"
        if structured_key:
            return self._event(structured_key, structured_message)
        if new_lines:
            resumed = self._event_key.startswith("quiet:")
            prefix = "Output resumed" if resumed else "New output"
            output_identity = hashlib.sha1(
                (latest or "").encode("utf-8", "replace")
            ).hexdigest()[:12]
            return self._event(
                f"output:{output_identity}",
                (
                    f"{prefix}: {new_lines} new "
                    f"line{'s' if new_lines != 1 else ''}; "
                    f"{lines:,} total lines and {characters:,} characters. "
                    f"Latest {stream_name}: {latest or 'a blank line'}."
                ),
            )

        if io_delta_bytes >= 1024 * 1024 or io_delta_reads >= 512:
            return self._event(
                f"filesystem-io:{self.label}",
                (
                    f"{worker} is actively working on {self.subject}: "
                    f"{io_bytes / (1024 * 1024):.1f} MiB read across "
                    f"{io_reads:,} file operations; no new text for "
                    f"{age:.0f} seconds."
                ),
            )

        if cpu_delta >= 0.05:
            previous = f" Latest {stream_name}: {latest}." if latest else ""
            return self._event(
                f"processing:{self.label}:{worker}",
                (
                    f"{worker} is actively working on {self.subject}: "
                    f"{cpu_delta:.2f} CPU seconds since the prior check and "
                    f"{ram_mb:.0f} MB RAM in use.{previous}"
                ),
            )

        if age >= 8.0:
            quiet_stage = max(1, int(age // 8.0))
            observed_from = (quiet_stage - 1) * 8
            observed_to = quiet_stage * 8
            last_fact = (
                f" Last output: {latest}."
                if latest else " No output has arrived yet."
            )
            if quiet_stage == 1:
                quiet_message = (
                    f"No measurable output, CPU time, or file I/O appeared for "
                    f"{self.subject} during the {observed_from}-to-"
                    f"{observed_to}-second observation window.{last_fact} "
                    "I am checking for blocked input, a hidden window, a lock, "
                    "or external I/O."
                )
            elif quiet_stage == 2:
                quiet_message = (
                    f"The first wait-state check found no measurable activity "
                    f"for {self.subject} during the {observed_from}-to-"
                    f"{observed_to}-second window.{last_fact} Recovery is now "
                    "armed: only this subprocess will be stopped if evidence "
                    "does not resume, and the parent task will change strategy."
                )
            else:
                remaining = max(0, CMD_STALL_TIMEOUT - int(age))
                quiet_message = (
                    f"The watchdog measured no output, CPU progress, or file I/O "
                    f"for {self.subject} during the {observed_from}-to-"
                    f"{observed_to}-second window.{last_fact} This subprocess "
                    f"will be recovered in at most {remaining} seconds; the "
                    "parent task and its checkpoint remain active."
                )
            return self._event(
                f"quiet:{self.label}:{quiet_stage}",
                quiet_message,
            )

        if self._event_key:
            return self._event(self._event_key, self._event_message)
        return self._event(
            f"command-started:{self.label}",
            (
                f"Started {self.subject}; the process has not written output yet."
            ),
        )

class ProcessStalled(RuntimeError):
    pass

class ProcessInterrupted(RuntimeError):
    pass

def _terminate_process_group(proc):
    if proc.poll() is not None:
        return
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGTERM)
        proc.wait(timeout=5)
        return
    except Exception:
        pass
    try:
        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
    except Exception:
        try:
            proc.kill()
        except Exception:
            pass

def run_live_process(command, *, shell, timeout, env, label):
    """Run a process while continuously capturing output and exposing live facts."""
    telemetry = ProcessTelemetry(label)
    stdout_lines, stderr_lines = [], []
    proc = subprocess.Popen(
        command,
        shell=shell,
        executable="/bin/bash" if shell else None,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        errors="replace",
        bufsize=1,
        env=env,
        start_new_session=True,
    )
    telemetry.pid = proc.pid

    def consume(pipe, sink, stream_name):
        try:
            for line in iter(pipe.readline, ""):
                sink.append(line)
                telemetry.update(line, stream_name)
        finally:
            pipe.close()

    readers = [
        threading.Thread(target=consume, args=(proc.stdout, stdout_lines, "output"), daemon=True),
        threading.Thread(target=consume, args=(proc.stderr, stderr_lines, "error output"), daemon=True),
    ]
    for reader in readers:
        reader.start()
    started = time.monotonic()
    last_activity = started
    last_probe = started
    last_lines = 0
    last_cpu = 0.0
    last_io_bytes = 0
    last_io_reads = 0
    try:
        with working(
            (
                f"command-started:{telemetry.label}",
                f"Running: {telemetry.subject}. Waiting for its first real result.",
            ),
            reporter=telemetry.report,
        ):
            while proc.poll() is None:
                now = time.monotonic()
                if timeout and timeout > 0 and now - started > timeout:
                    try:
                        os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                    except Exception:
                        proc.kill()
                    raise subprocess.TimeoutExpired(
                        command, timeout,
                        output="".join(stdout_lines),
                        stderr="".join(stderr_lines),
                    )
                if now - last_probe >= 1.0:
                    with telemetry.lock:
                        current_lines = telemetry.lines
                    cpu_s, _, _ = _process_group_stats(proc.pid)
                    io_bytes, io_reads = _process_group_io_stats(proc.pid)
                    if (
                        current_lines != last_lines or
                        cpu_s > last_cpu + 0.05 or
                        io_bytes > last_io_bytes or
                        io_reads > last_io_reads
                    ):
                        last_activity = now
                    last_lines = current_lines
                    last_cpu = cpu_s
                    last_io_bytes = io_bytes
                    last_io_reads = io_reads
                    last_probe = now
                    if (
                        CMD_STALL_TIMEOUT > 0
                        and now - last_activity > CMD_STALL_TIMEOUT
                    ):
                        try:
                            os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                        except Exception:
                            proc.kill()
                        raise ProcessStalled(
                            f"No output or measurable CPU progress for "
                            f"{CMD_STALL_TIMEOUT} seconds while running: {label}"
                        )
                time.sleep(0.1)
    except KeyboardInterrupt as exc:
        _terminate_process_group(proc)
        raise ProcessInterrupted(
            f"The operator interrupted only this subprocess: {label}"
        ) from exc
    except BaseException:
        _terminate_process_group(proc)
        raise
    finally:
        for reader in readers:
            reader.join(timeout=2)
    visible_stdout = "".join(
        line for line in stdout_lines
        if parse_live_progress_line(line) is None
    )
    return proc.returncode, visible_stdout, "".join(stderr_lines)

class TaskPlan:
    """Internal completion milestones; live output comes from observed work only."""
    def __init__(self, objective):
        self.objective = " ".join(objective.split())
        self.steps = {}

    def render(self, title="PLAN"):
        return None

    def done(self, index, detail=None):
        self.steps[index] = ("done", _one_line(detail or "", 240))

    def fail(self, index, detail):
        self.steps[index] = ("failed", _one_line(detail or "", 240))

def find_binary(name):
    """Find an executable by name in the llama.cpp build tree."""
    for base in [LLAMA_DIR / "build" / "bin", LLAMA_DIR / "build" / "app" / "bin", LLAMA_DIR / "build"]:
        p = base / name
        if p.exists() and os.access(str(p), os.X_OK):
            return p
    try:
        r = subprocess.run(
            ["find", str(LLAMA_DIR / "build"), "-name", name, "-type", "f", "-executable"],
            capture_output=True, text=True, timeout=10
        )
        for line in r.stdout.strip().split("\n"):
            if line and Path(line).exists():
                return Path(line)
    except Exception:
        pass
    return None

def find_model():
    """Find the model to use: the installer-chosen one, else the largest .gguf."""
    if not MODEL_DIR.exists():
        return None
    marker = MODEL_DIR / ".chosen-model"
    if marker.exists():
        p = MODEL_DIR / marker.read_text().strip()
        if p.exists():
            return p
    models = sorted(
        (
            p for p in MODEL_DIR.glob("*.gguf")
            if not any(tag in p.name.lower() for tag in ("mmproj", "projector", "mtp", "draft"))
        ),
        key=lambda p: p.stat().st_size,
        reverse=True,
    )
    return models[0] if models else None

def detect_gpu_memory_mib():
    """Return the first NVIDIA GPU's total and currently free memory in MiB."""
    for binary in ("nvidia-smi", "/usr/lib/wsl/lib/nvidia-smi"):
        try:
            result = subprocess.run(
                [
                    binary,
                    "--query-gpu=memory.total,memory.free",
                    "--format=csv,noheader,nounits",
                ],
                capture_output=True,
                text=True,
                timeout=8,
            )
            if result.returncode != 0:
                continue
            fields = [part.strip() for part in result.stdout.splitlines()[0].split(",")]
            if len(fields) >= 2:
                total, free = int(fields[0]), int(fields[1])
                if total > 0 and free > 0:
                    return total, min(total, free)
        except Exception:
            continue
    return 0, 0


def detect_gpu_layers():
    """Retain the legacy capability answer for callers that only need yes/no."""
    total_mib, _ = detect_gpu_memory_mib()
    return 999 if total_mib else 0

def api_call(endpoint, data=None, timeout=API_TIMEOUT):
    """Make an HTTP request to the llama-server API."""
    url = f"http://{SERVER_HOST}:{SERVER_PORT}{endpoint}"
    if data is None:
        req = urllib.request.Request(url)
    else:
        payload = json.dumps(data).encode("utf-8")
        req = urllib.request.Request(url, data=payload,
                                     headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as resp:
            return json.loads(resp.read().decode("utf-8"))
    except Exception as e:
        return {"error": str(e)}

def merge_stream_fragment(existing, fragment, snapshot=False):
    """Append an SSE delta or replace with an authoritative snapshot."""
    existing = existing or ""
    fragment = fragment or ""
    if not fragment:
        return existing
    return fragment if snapshot else existing + fragment


def merge_tool_name_fragment(existing, fragment):
    """Tool names may arrive as cumulative parser snapshots."""
    existing = existing or ""
    fragment = fragment or ""
    if not fragment:
        return existing
    if fragment.startswith(existing) or existing.startswith(fragment):
        return fragment if len(fragment) >= len(existing) else existing
    return existing + fragment


def _progress_tail(text, limit=180):
    """Return the newest printable evidence without allowing terminal control."""
    text = _ANSI_RE.sub("", str(text or ""))
    text = "".join(ch if ch >= " " or ch in "\n\t" else " " for ch in text)
    lines = [" ".join(line.split()) for line in text.replace("\r", "\n").splitlines()]
    useful = [line for line in lines if line]
    flattened = " | ".join(useful[-3:]) if useful else " ".join(text.split())
    if len(flattened) <= limit:
        return flattened
    return "..." + flattened[-(limit - 3):]


def _safe_unicode_escape(codepoint):
    if 0xD800 <= codepoint <= 0xDFFF:
        return f"\\u{codepoint:04X}"
    try:
        return chr(codepoint)
    except ValueError:
        return "\uFFFD"


def _decode_partial_json_field(arguments, key):
    """Inspect one streamed JSON string without trusting malformed text."""
    arguments = arguments or ""
    try:
        parsed = json.loads(arguments)
        if isinstance(parsed, dict) and key in parsed:
            value = parsed.get(key)
            text = value if isinstance(value, str) else json.dumps(
                value, ensure_ascii=False
            )
            return {
                "text": text,
                "found": True,
                "complete": True,
                "status": "exact",
                "issue": "",
                "raw_consumed": len(arguments),
                "raw_length": len(arguments),
            }
    except (TypeError, ValueError, json.JSONDecodeError):
        pass

    match = re.search(r'"' + re.escape(key) + r'"\s*:\s*"', arguments)
    if not match:
        return {
            "text": "",
            "found": False,
            "complete": False,
            "status": "waiting_for_field",
            "issue": "",
            "raw_consumed": 0,
            "raw_length": len(arguments),
        }
    raw = arguments[match.end():]
    result = []
    index = 0
    status = "partial"
    issue = ""
    complete = False
    while index < len(raw):
        char = raw[index]
        if char == '"':
            suffix = raw[index + 1:]
            significant = suffix.lstrip()
            structurally_closed = (
                not significant
                or significant.startswith("}")
                or significant.startswith("]")
                or re.match(r',\s*"[^"]+"\s*:', significant) is not None
            )
            if structurally_closed:
                complete = True
                status = "exact" if not issue else status
                index += 1
                break
            result.append('"')
            if status == "partial":
                status = "ambiguous_quote"
                issue = (
                    "an unescaped quote appeared inside the streamed string; "
                    "display continued, but execution still requires strict JSON"
                )
            index += 1
            continue
        if char != "\\":
            result.append(char)
            index += 1
            continue
        escape_start = index
        index += 1
        if index >= len(raw):
            result.append("\\")
            status = "partial_escape"
            issue = "the stream ended immediately after a backslash"
            break
        escape = raw[index]
        translated = {
            '"': '"', "\\": "\\", "/": "/", "b": "\b",
            "f": "\f", "n": "\n", "r": "\r", "t": "\t",
        }.get(escape)
        if translated is not None:
            result.append(translated)
            index += 1
            continue
        if escape == "u":
            if index + 4 >= len(raw):
                result.append(raw[escape_start:])
                status = "partial_unicode"
                issue = "a Unicode escape is still arriving"
                index = len(raw)
                break
            digits = raw[index + 1:index + 5]
            if re.fullmatch(r"[0-9A-Fa-f]{4}", digits):
                codepoint = int(digits, 16)
                index += 5
                if 0xD800 <= codepoint <= 0xDBFF:
                    if (
                        raw[index:index + 2] == "\\u"
                        and index + 6 <= len(raw)
                        and re.fullmatch(
                            r"[0-9A-Fa-f]{4}", raw[index + 2:index + 6]
                        )
                    ):
                        low = int(raw[index + 2:index + 6], 16)
                        if 0xDC00 <= low <= 0xDFFF:
                            combined = (
                                0x10000
                                + ((codepoint - 0xD800) << 10)
                                + (low - 0xDC00)
                            )
                            result.append(chr(combined))
                            index += 6
                            continue
                    result.append(f"\\u{codepoint:04X}")
                    status = "unpaired_surrogate"
                    issue = "a high Unicode surrogate was not followed by a low surrogate"
                    continue
                if 0xDC00 <= codepoint <= 0xDFFF:
                    result.append(f"\\u{codepoint:04X}")
                    status = "unpaired_surrogate"
                    issue = "a low Unicode surrogate arrived without a high surrogate"
                    continue
                result.append(_safe_unicode_escape(codepoint))
                continue
            result.append("\\u" + digits)
            status = "invalid_unicode"
            issue = "the streamed Unicode escape contains non-hexadecimal digits"
            index += 5
            continue
        result.append("\\" + escape)
        status = "invalid_escape"
        issue = f"the streamed JSON contains the invalid escape \\{escape}"
        index += 1
    return {
        "text": "".join(result),
        "found": True,
        "complete": complete,
        "status": status,
        "issue": issue,
        "raw_consumed": match.end() + index,
        "raw_length": len(arguments),
    }


def _decode_partial_json_string(arguments, key):
    return _decode_partial_json_field(arguments, key)["text"]


def _plain_generated_line(line):
    """Turn one complete Markdown line into readable progress text."""
    value = (line or "").strip()
    if not value or re.fullmatch(
        r"\[/?(?:TASK_COMPLETE|TASK_BLOCKED|MEMORY)\]?",
        value,
        re.IGNORECASE,
    ):
        return ""
    if re.fullmatch(r"\|?(?:\s*:?-{3,}:?\s*\|)+", value):
        return ""
    if value.startswith("|") and value.endswith("|"):
        cells = [
            re.sub(r"[*_`]+", "", cell).strip()
            for cell in value.strip("|").split("|")
        ]
        cells = [cell for cell in cells if cell]
        value = ": ".join(cells)
    value = re.sub(r"^\s*(?:[-+*]\s+|#{1,6}\s*)", "", value)
    value = re.sub(r"[*_`]+", "", value).strip()
    if len(re.findall(r"[A-Za-z]{2,}", value)) < 2:
        return ""
    return _one_line(value, 140)

def _describe_generated_text(text, final=False):
    """Report complete readable lines plus the exact generated size."""
    raw = text or ""
    size_fact = (
        f"{len(raw):,} character{'s' if len(raw) != 1 else ''} generated"
    )
    split_lines = raw.splitlines()
    if raw and not final and not raw.endswith(("\n", "\r")):
        split_lines = split_lines[:-1]
    lines = [line.strip() for line in split_lines if line.strip()]
    readable = [(line, _plain_generated_line(line)) for line in lines]
    readable = [(raw_line, plain) for raw_line, plain in readable if plain]
    if not readable:
        return f"{size_fact}; the current line is still being generated."
    latest, latest_plain = readable[-1]
    class_match = re.match(r"class\s+([A-Za-z_][A-Za-z0-9_]*)", latest)
    if class_match:
        return (
            f"{len(readable):,} complete line{'s' if len(readable) != 1 else ''} "
            f"and {size_fact}; the latest completed line defines the "
            f"{class_match.group(1)} class."
        )
    function_match = re.match(
        r"(?:async\s+)?def\s+([A-Za-z_][A-Za-z0-9_]*)", latest
    )
    if function_match:
        return (
            f"{len(readable):,} complete line{'s' if len(readable) != 1 else ''} "
            f"and {size_fact}; the latest completed line defines the "
            f"{function_match.group(1)} function."
        )
    if latest.startswith(("import ", "from ")):
        return (
            f"{len(readable):,} complete line{'s' if len(readable) != 1 else ''} "
            f"and {size_fact}; latest completed import: {_one_line(latest, 120)}."
        )
    if latest.startswith("#"):
        return (
            f"{len(readable):,} complete line{'s' if len(readable) != 1 else ''} "
            f"and {size_fact}; latest completed section: "
            f"{_one_line(latest.lstrip('# '), 120)}."
        )
    assignment = re.match(r"([A-Za-z_][A-Za-z0-9_]*)\s*=", latest)
    if assignment:
        return (
            f"{len(readable):,} complete line{'s' if len(readable) != 1 else ''} "
            f"and {size_fact}; latest completed assignment: "
            f"{assignment.group(1)}."
        )
    return (
        f"{len(readable):,} complete readable line"
        f"{'s' if len(readable) != 1 else ''} and {size_fact}; "
        f"latest completed point: {latest_plain}."
    )


def _tool_progress_description(
    name, arguments, new_argument_chars, elapsed, quiet_run, previous_decoded=0
):
    """Describe the chosen tool from decoded fields, without transport jargon."""
    name = (name or "unnamed_tool").strip()
    target_info = _decode_partial_json_field(arguments, "path")
    target = target_info["text"]
    if name in ("write_file", "append_file"):
        content_info = _decode_partial_json_field(arguments, "content")
        content = content_info["text"]
        verb = "building" if name == "write_file" else "extending"
        if target_info["status"] != "exact":
            return (
                f"The model is selecting the exact file path: {len(arguments):,} "
                "tool-request characters have arrived."
            )
        destination = target or "the requested file"
        if content_info["status"] not in ("exact", "partial"):
            return (
                f"The model selected {destination} and is generating its first "
                f"file content now; {len(arguments):,} tool-request characters "
                "have arrived."
            )
        if content:
            return (
                f"The model is {verb} {destination} now: "
                f"{_describe_generated_text(content, final=content_info['status'] == 'exact')}"
            )
        return (
            f"The model selected {destination} and has started its file request; "
            "the first content character has not arrived yet."
        )

    if name == "apply_patch":
        patch_info = _decode_partial_json_field(arguments, "patch")
        patch = patch_info["text"]
        targets = re.findall(r"^\+\+\+\s+(?:b/)?(.+)$", patch, re.MULTILINE)
        destination = ", ".join(targets[-3:]) or "the requested file"
        hunks = sum(1 for line in patch.splitlines() if line.startswith("@@ "))
        additions = sum(
            1 for line in patch.splitlines()
            if line.startswith("+") and not line.startswith("+++")
        )
        removals = sum(
            1 for line in patch.splitlines()
            if line.startswith("-") and not line.startswith("---")
        )
        return (
            f"The model is building a patch for {destination}: {len(patch):,} "
            f"characters, {hunks} section"
            f"{'s' if hunks != 1 else ''}, {additions} added line"
            f"{'s' if additions != 1 else ''}, and {removals} removed line"
            f"{'s' if removals != 1 else ''} generated so far."
        )

    field_by_tool = {
        "run_command": "command",
        "run_python": "code",
        "read_file": "path",
        "browse": "url",
        "win_tools": "action",
        "mcp_call": "tool",
    }
    field = field_by_tool.get(name, "")
    field_info = (
        _decode_partial_json_field(arguments, field)
        if field else {
            "text": "", "status": "waiting_for_field", "raw_consumed": 0,
        }
    )
    subject = field_info["text"]
    if name == "win_tools":
        drive = _decode_partial_json_string(arguments, "drive")
        if drive:
            subject = f"{subject or 'Windows operation'} on {drive}"
    if name == "mcp_call":
        server = _decode_partial_json_string(arguments, "server")
        if server:
            subject = f"{server}.{subject or 'requested tool'}"
    evidence = _progress_tail(subject)
    descriptions = {
        "run_command": "The model is generating the exact command",
        "run_python": "The model is generating executable Python",
        "read_file": "The model is selecting the exact file to read",
        "browse": "The model is selecting the exact page to open",
        "win_tools": "The model is selecting the exact Windows operation",
        "mcp_call": "The model is selecting the exact connected tool",
    }
    description = descriptions.get(
        name, f"The model is generating the {name.replace('_', ' ')} request"
    )
    if field_info["status"] != "exact":
        return (
            f"{description}: {len(arguments):,} request characters have arrived; "
            "the request is still growing."
        )
    if evidence:
        return (
            f"{description}: {evidence}. The complete request currently contains "
            f"{len(arguments):,} characters."
        )
    return (
        f"{description}; {len(arguments):,} request characters have arrived and "
        "the exact target is still growing."
    )


class ModelTelemetry:
    def __init__(self, message_count, tool_count, attempt):
        self.message_count = message_count
        self.tool_count = tool_count
        self.attempt = attempt
        self.connected = False
        self.chunks = 0
        self.reasoning_chars = 0
        self.content_chars = 0
        self.reasoning_text = ""
        self.content_text = ""
        self.tool_argument_chars = 0
        self.tool_names = {}
        self.tool_arguments = {}
        self.raw_bytes = 0
        self.transport_events = 0
        self.malformed_events = 0
        self.prompt_progress = {}
        self.last_report_reasoning_chars = 0
        self.last_report_content_chars = 0
        self.last_report_tool_lengths = {}
        self.last_report_tool_decoded_lengths = {}
        self.last_report_raw_bytes = 0
        self.last_report_transport_events = 0
        self.last_report_malformed_events = 0
        self.quiet_run = 0
        self.last_event_at = None
        self.last_transport_at = None
        self.lock = threading.Lock()

    @staticmethod
    def _index(tool, position):
        try:
            value = tool.get("index", position)
            return position if value is None else int(value)
        except (TypeError, ValueError):
            return position

    def transport(self, raw_bytes=0, malformed=False):
        with self.lock:
            now = time.monotonic()
            self.raw_bytes += max(0, int(raw_bytes or 0))
            self.transport_events += 1
            self.malformed_events += int(bool(malformed))
            self.last_transport_at = now

    def update_prompt_progress(self, progress):
        with self.lock:
            self.prompt_progress = dict(progress or {})
            self.last_event_at = time.monotonic()

    def update(self, delta, snapshot=False):
        with self.lock:
            now = time.monotonic()
            self.chunks += 1
            self.last_transport_at = now
            reasoning = delta.get("reasoning_content") or ""
            content = delta.get("content") or ""
            self.reasoning_text = merge_stream_fragment(
                self.reasoning_text, reasoning, snapshot=snapshot
            )
            self.content_text = merge_stream_fragment(
                self.content_text, content, snapshot=snapshot
            )
            self.reasoning_chars = len(self.reasoning_text)
            self.content_chars = len(self.content_text)
            for position, tool in enumerate(delta.get("tool_calls") or []):
                function = tool.get("function") or {}
                if function.get("name"):
                    index = self._index(tool, position)
                    self.tool_names[index] = merge_tool_name_fragment(
                        self.tool_names.get(index, ""), function["name"]
                    )
                if function.get("arguments") is not None:
                    index = self._index(tool, position)
                    fragment = function.get("arguments")
                    if isinstance(fragment, dict):
                        fragment = json.dumps(fragment, ensure_ascii=False)
                    self.tool_arguments[index] = merge_stream_fragment(
                        self.tool_arguments.get(index, ""),
                        fragment or "",
                        snapshot=snapshot,
                    )
            self.tool_argument_chars = sum(
                len(arguments) for arguments in self.tool_arguments.values()
            )
            if reasoning or content or delta.get("tool_calls"):
                self.last_event_at = now

    def report(self, elapsed):
        with self.lock:
            connected = self.connected
            chunks = self.chunks
            reasoning_chars = self.reasoning_chars
            content_chars = self.content_chars
            reasoning_text = self.reasoning_text
            content_text = self.content_text
            tool_argument_chars = self.tool_argument_chars
            tool_names = dict(self.tool_names)
            tool_arguments = dict(self.tool_arguments)
            raw_bytes = self.raw_bytes
            transport_events = self.transport_events
            malformed_events = self.malformed_events
            prompt_progress = dict(self.prompt_progress)
            reasoning_delta = max(
                0, reasoning_chars - self.last_report_reasoning_chars
            )
            content_delta = max(0, content_chars - self.last_report_content_chars)
            tool_deltas = {
                index: max(
                    0,
                    len(arguments) - self.last_report_tool_lengths.get(index, 0),
                )
                for index, arguments in tool_arguments.items()
            }
            tool_decoded_lengths = {
                index: len(_decode_partial_json_field(arguments, "content")["text"])
                for index, arguments in tool_arguments.items()
            }
            raw_delta = max(0, raw_bytes - self.last_report_raw_bytes)
            transport_delta = max(
                0, transport_events - self.last_report_transport_events
            )
            malformed_delta = max(
                0, malformed_events - self.last_report_malformed_events
            )
            self.last_report_reasoning_chars = reasoning_chars
            self.last_report_content_chars = content_chars
            self.last_report_tool_lengths = {
                index: len(arguments)
                for index, arguments in tool_arguments.items()
            }
            previous_decoded_lengths = dict(
                self.last_report_tool_decoded_lengths
            )
            self.last_report_tool_decoded_lengths = tool_decoded_lengths
            self.last_report_raw_bytes = raw_bytes
            self.last_report_transport_events = transport_events
            self.last_report_malformed_events = malformed_events
            changed = bool(
                reasoning_delta or content_delta or any(tool_deltas.values())
                or raw_delta or transport_delta or malformed_delta
            )
            self.quiet_run = 0 if changed else self.quiet_run + 1
            quiet_run = self.quiet_run
            last_event_at = self.last_event_at
            last_transport_at = self.last_transport_at
        age = (time.monotonic() - last_event_at) if last_event_at else float(elapsed)
        transport_age = (
            time.monotonic() - last_transport_at
            if last_transport_at else float(elapsed)
        )
        elapsed = max(0, int(elapsed))
        event_age = max(0, int(age))
        transport_age = max(0, int(transport_age))
        if prompt_progress and not tool_names and not content_chars and not reasoning_chars:
            total = int(prompt_progress.get("total") or 0)
            processed = int(prompt_progress.get("processed") or 0)
            percent = min(100, int(processed * 100 / max(1, total)))
            return (
                f"model-prompt:{self.attempt}",
                (
                    f"Loading your request into the local model: {percent}% "
                    f"({processed:,} of {total:,} tokens)."
                ),
            )
        if tool_names:
            active_index = max(
                tool_names,
                key=lambda index: (
                    tool_deltas.get(index, 0),
                    len(tool_arguments.get(index, "")),
                ),
            )
            tool_name = tool_names.get(active_index) or "unnamed_tool"
            arguments = tool_arguments.get(active_index, "")
            description = _tool_progress_description(
                tool_name,
                arguments,
                tool_deltas.get(active_index, 0),
                elapsed,
                quiet_run,
                previous_decoded_lengths.get(active_index, 0),
            )
            return (
                f"model-tool:{active_index}:{tool_name}",
                description,
            )
        if content_chars:
            message = (
                "The model is writing the answer now: "
                f"{_describe_generated_text(content_text)}"
            )
            return (f"model-answer:{self.attempt}", message)
        if reasoning_chars:
            message = (
                f"The model is reasoning about the next concrete action: "
                f"{reasoning_chars:,} reasoning characters produced in "
                f"{elapsed} seconds; no tool request is complete yet."
            )
            return (f"model-planning:{self.attempt}", message)
        if connected:
            if malformed_delta:
                return (
                    f"model-protocol-malformed:{self.attempt}",
                    (
                        "The model sent an invalid partial response. It was ignored; "
                        "waiting for a complete valid action."
                    ),
                )
            if elapsed >= 12:
                return (
                    f"model-response-open:{self.attempt}",
                    f"The server accepted the request {elapsed} seconds ago; it "
                    "has not produced its first answer or action character yet.",
                )
            return (
                f"model-response-open:{self.attempt}",
                f"The server accepted the request {elapsed} seconds ago and is "
                "starting the first concrete response.",
            )
        if elapsed >= 12:
            return (
                f"model-opening:{self.attempt}",
                f"The client has waited {elapsed} seconds for the local model "
                "connection; the server has not accepted it yet.",
            )
        return (
            f"model-opening:{self.attempt}",
            "Connecting to the local model for this task.",
        )

def _prepare_stream_body(body):
    stream_body = dict(body)
    stream_body.update({
        "stream": True,
        "return_progress": True,
        "sse_ping_interval": 1,
        "parse_tool_calls": True,
        "parallel_tool_calls": False,
    })
    return stream_body


def _tool_index(tool, position):
    try:
        value = tool.get("index", position)
        return position if value is None else int(value)
    except (TypeError, ValueError):
        return position


def _json_argument_text(value):
    if isinstance(value, str):
        return value
    if isinstance(value, dict):
        return json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    if value is None:
        return ""
    return json.dumps(value, ensure_ascii=False)


def api_chat_stream(body, attempt):
    """Stream one model response and reconstruct the normal response object."""
    stream_body = _prepare_stream_body(body)
    telemetry = ModelTelemetry(
        len(stream_body.get("messages") or []),
        len(stream_body.get("tools") or []),
        attempt,
    )
    content_text, reasoning_text = "", ""
    tool_parts = {}
    finish_reason = ""
    saw_finish = False
    saw_done = False
    stream_started_at = time.monotonic()
    last_semantic_at = stream_started_at
    url = f"http://{SERVER_HOST}:{SERVER_PORT}/v1/chat/completions"
    payload = json.dumps(stream_body).encode("utf-8")
    req = urllib.request.Request(
        url, data=payload, headers={"Content-Type": "application/json"}
    )
    try:
        def process_sse_payload(payload):
            nonlocal content_text, reasoning_text, finish_reason
            nonlocal saw_finish, saw_done, last_semantic_at
            if payload == "[DONE]":
                saw_done = True
                last_semantic_at = time.monotonic()
                return
            try:
                event = json.loads(payload)
            except json.JSONDecodeError as exc:
                telemetry.transport(malformed=True)
                raise RuntimeError(
                    "Malformed SSE JSON was preserved and rejected at "
                    f"line {exc.lineno}, column {exc.colno}: "
                    f"{_one_line(payload, 240)}"
                )
            if event.get("error"):
                detail = event["error"]
                if isinstance(detail, dict):
                    detail = detail.get("message") or json.dumps(
                        detail, ensure_ascii=False
                    )
                raise RuntimeError(
                    "The model stream ended with a server error: "
                    + _one_line(str(detail), 800)
                )
            progress = event.get("prompt_progress")
            if isinstance(progress, dict):
                telemetry.update_prompt_progress(progress)
                last_semantic_at = time.monotonic()
            choices = event.get("choices") or []
            if not choices:
                return
            last_semantic_at = time.monotonic()
            choice = choices[0]
            if choice.get("finish_reason") is not None:
                finish_reason = choice.get("finish_reason") or ""
                saw_finish = True
            snapshot = "delta" not in choice and "message" in choice
            delta = (
                choice.get("message") or {}
                if snapshot else choice.get("delta") or {}
            )
            telemetry.update(delta, snapshot=snapshot)
            content_text = merge_stream_fragment(
                content_text, delta.get("content") or "", snapshot=snapshot
            )
            reasoning_text = merge_stream_fragment(
                reasoning_text,
                delta.get("reasoning_content") or "",
                snapshot=snapshot,
            )
            for position, tool in enumerate(delta.get("tool_calls") or []):
                index = _tool_index(tool, position)
                current = tool_parts.setdefault(index, {
                    "id": "", "type": "function",
                    "function": {"name": "", "arguments": ""},
                })
                incoming_id = str(tool.get("id") or "")
                if incoming_id:
                    if current["id"] and current["id"] != incoming_id:
                        raise RuntimeError(
                            f"Conflicting IDs arrived for tool call {index}: "
                            f"{current['id']} versus {incoming_id}"
                        )
                    current["id"] = incoming_id
                if tool.get("type"):
                    current["type"] = tool["type"]
                function = tool.get("function") or {}
                current["function"]["name"] = merge_tool_name_fragment(
                    current["function"]["name"], function.get("name") or ""
                )
                argument_fragment = _json_argument_text(
                    function.get("arguments")
                )
                current["function"]["arguments"] = merge_stream_fragment(
                    current["function"]["arguments"],
                    argument_fragment,
                    snapshot=snapshot,
                )
                current_name = current["function"]["name"].lower()
                current_arguments = current["function"]["arguments"]
                current_size = len(current_arguments)
                if current_name in ("write_file", "append_file"):
                    content_info = _decode_partial_json_field(
                        current_arguments, "content"
                    )
                    if len(content_info["text"]) > MAX_WHOLE_FILE_CHARS:
                        raise RuntimeError(
                            "oversized_write: the streamed "
                            f"{current_name} content reached "
                            f"{len(content_info['text']):,} decoded characters "
                            f"(limit {MAX_WHOLE_FILE_CHARS:,}); use apply_patch "
                            "or bounded append chunks"
                        )
                    if current_size > MAX_WHOLE_FILE_CHARS * 4:
                        raise RuntimeError(
                            "oversized_write: malformed raw tool arguments grew "
                            f"to {current_size:,} characters without a safe bounded "
                            "file payload"
                        )
            if (
                MODEL_ACTION_TIMEOUT > 0
                and time.monotonic() - stream_started_at >= MODEL_ACTION_TIMEOUT
                and reasoning_text
                and not content_text
                and not any(
                    part["function"]["arguments"] for part in tool_parts.values()
                )
            ):
                raise RuntimeError(
                    "usable action deadline exceeded: the model spent "
                    f"{MODEL_ACTION_TIMEOUT}s reasoning without producing "
                    "visible content or tool arguments"
                )

        with working("Opening the live model response stream", reporter=telemetry.report):
            with urllib.request.urlopen(req, timeout=API_TIMEOUT) as resp:
                telemetry.connected = True
                decoder = codecs.getincrementaldecoder("utf-8")("strict")
                data_lines = []
                for raw_line in resp:
                    telemetry.transport(len(raw_line))
                    try:
                        line = decoder.decode(raw_line, final=False)
                    except UnicodeDecodeError as exc:
                        telemetry.transport(malformed=True)
                        raise RuntimeError(
                            "Invalid UTF-8 in the SSE stream at byte "
                            f"{exc.start}: {raw_line[max(0, exc.start - 8):exc.end + 8].hex()}"
                        )
                    line = line.rstrip("\r\n")
                    if not line:
                        if data_lines:
                            process_sse_payload("\n".join(data_lines))
                            data_lines = []
                        if (
                            MODEL_STREAM_IDLE_TIMEOUT > 0
                            and time.monotonic() - last_semantic_at
                            >= MODEL_STREAM_IDLE_TIMEOUT
                        ):
                            raise RuntimeError(
                                "model stream idle deadline exceeded: the server "
                                f"kept the connection open for "
                                f"{MODEL_STREAM_IDLE_TIMEOUT}s without prompt "
                                "progress, answer text, reasoning progress, or "
                                "tool arguments"
                            )
                        continue
                    if line.startswith(":"):
                        continue
                    if line.startswith("data:"):
                        value = line[5:]
                        if value.startswith(" "):
                            value = value[1:]
                        data_lines.append(value)
                        continue
                    if line.startswith(("event:", "id:", "retry:")):
                        continue
                    telemetry.transport(malformed=True)
                    raise RuntimeError(
                        "Unexpected SSE field was preserved and rejected: "
                        + _one_line(line, 240)
                    )
                decoder.decode(b"", final=True)
                if data_lines:
                    process_sse_payload("\n".join(data_lines))
        if not saw_done:
            raise RuntimeError(
                "The model stream ended before the required [DONE] marker"
            )
        if not saw_finish:
            raise RuntimeError(
                "The model stream ended without a completion finish state"
            )
        message = {
            "role": "assistant",
            "content": content_text,
            "reasoning_content": reasoning_text,
            "tool_calls": [tool_parts[i] for i in sorted(tool_parts)],
        }
        for index, tool in enumerate(message["tool_calls"]):
            if not tool.get("id"):
                tool["id"] = f"call_local_{attempt}_{index}_{uuid.uuid4().hex[:8]}"
            arguments = tool.get("function", {}).get("arguments", "")
            try:
                parsed_arguments = json.loads(arguments)
            except (TypeError, ValueError, json.JSONDecodeError) as exc:
                raise RuntimeError(
                    "Failed to parse tool call arguments as JSON: "
                    f"{type(exc).__name__}: {exc}; "
                    f"raw arguments: {_one_line(str(arguments), 600)}"
                )
            if not isinstance(parsed_arguments, dict):
                raise RuntimeError(
                    "Failed to parse tool call arguments as JSON object: "
                    f"received {type(parsed_arguments).__name__}"
                )
        return {"choices": [{"message": message, "finish_reason": finish_reason}]}
    except urllib.error.HTTPError as exc:
        try:
            detail = exc.read().decode("utf-8", errors="replace")
        except Exception:
            detail = ""
        return {
            "error": (
                f"HTTPError: HTTP {exc.code}: "
                f"{_one_line(detail, 1200) or exc.reason}"
            )
        }
    except Exception as exc:
        return {"error": f"{type(exc).__name__}: {exc}"}

def extract_tool_calls(text):
    """Extract executable tool calls from the model's response."""
    text = clean_artifacts(text or "")
    calls = []
    # Triple-backtick code blocks (preferred format)
    for match in re.finditer(r'```(?:bash|sh|shell)\n(.*?)```', text, re.DOTALL):
        cmd = clean_artifacts(match.group(1)).strip()
        if cmd and not cmd.strip().startswith('#'):
            calls.append({"type": "command", "cmd": cmd})
    for match in re.finditer(r'```python\n(.*?)```', text, re.DOTALL):
        code = clean_artifacts(match.group(1)).strip()
        if code:
            calls.append({"type": "python", "code": code})
    # Fallback: <tool> tags
    if not calls:
        for match in re.finditer(
            r'<tool>\s*(command|write|read|python)\s*:\s*(.*?)</tool>', text, re.DOTALL
        ):
            tt = match.group(1).strip()
            ct = match.group(2).strip()
            if tt == "command":
                calls.append({"type": "command", "cmd": ct})
            elif tt == "write":
                lines = ct.split('\n', 1)
                calls.append({"type": "write", "path": lines[0].strip(),
                              "content": lines[1].strip() if len(lines) > 1 else ""})
            elif tt == "read":
                calls.append({"type": "read", "path": ct})
            elif tt == "python":
                calls.append({"type": "python", "code": ct})
    return calls

def windows_filename_query(text):
    """Return a safe Windows executable basename for a direct locate request."""
    raw = text or ""
    if not re.search(r"\b(find|search|locate|where|path)\b", raw, re.IGNORECASE):
        return ""
    direct = re.search(
        r"\b([A-Za-z0-9][A-Za-z0-9_.-]{0,120}\.exe)\b",
        raw, re.IGNORECASE,
    )
    if direct:
        return direct.group(1)
    spaced = re.search(
        r"\b([A-Za-z0-9][A-Za-z0-9_.-]{0,120})\s+\.?exe\b",
        raw, re.IGNORECASE,
    )
    return (spaced.group(1) + ".exe") if spaced else ""

def is_direct_windows_filename_request(text):
    """Recognize a locate-only executable request without filename collisions."""
    filename = windows_filename_query(text)
    if not filename:
        return False
    without_filename = re.sub(
        re.escape(filename), " ", text or "", flags=re.IGNORECASE
    )
    return not objective_requires_action(without_filename)

def dependency_preflight_command(command):
    """Replace compound model installs with the exact executable capability probe."""
    text = command or ""
    if not re.search(
        r"(?i)(?:^|[;&|]\s*)(?:sudo\s+)?apt(?:-get)?\s+"
        r"(?:update|install)\b",
        text,
    ):
        return ""
    if re.search(r"(?i)\bdotnet(?:-sdk)?\b", text):
        return "dotnet --info"
    return ""

COMMAND_REJECTION_PREFIX = "__NATURE_COMMAND_REJECT__:"

def compact_project_toolchain_survey(command, user_message):
    """Replace broad environment surveys with one relevant, bounded probe."""
    if not objective_requires_action(user_message):
        return ""
    text = command or ""
    low = text.lower()
    survey_markers = (
        "get-childitem",
        "get-command",
        "where.exe",
        "write-host",
        "program files\\dotnet",
        "pipx",
        "py launcher",
    )
    if sum(marker in low for marker in survey_markers) < 3:
        return ""
    if "dotnet" not in low:
        return ""
    return "dotnet --info"

def active_task_has_nonempty_requested_target(user_message):
    """Use checkpoint evidence, not a fresh parent-side mount probe."""
    state = CURRENT_TASK_STATE
    if state is None:
        return False
    requested = extract_target_paths(user_message)
    targets = requested or list(getattr(state, "target_paths", []) or [])
    for target in targets:
        observed = (getattr(state, "target_checks", {}) or {}).get(target)
        if observed and observed.get("exists") and observed.get("nonempty"):
            return True
    return False

def divergent_windows_gui_scaffold_rejection(command, user_message):
    """Block a second GUI scaffold after verified evidence shows one already exists."""
    if not objective_requests_windows_gui(user_message):
        return ""
    if not active_task_has_nonempty_requested_target(user_message):
        return ""
    if not re.search(
        r"(?is)\bdotnet\s+new\b|(?:^|&&|\|\||[;|])\s*(?:"
        r"tee\b[^;\n|]*\bapp_gui\.(?:py|ps1)\b|"
        r"cat\b.*?(?<![>&])>(?![>&])\s*['\"]?"
        r"[^\s'\";|]*app_gui\.(?:py|ps1)\b"
        r")",
        command or "",
    ):
        return ""
    return (
        COMMAND_REJECTION_PREFIX
        + "A verified nonempty Windows project already exists at the requested "
        + "target. Creating a second GUI scaffold was rejected before execution. "
        + "Read and repair the existing project files, then run its actual "
        + "Windows-host verification."
    )

def verified_project_raw_overwrite_rejection(command, user_message):
    """Protect a verified nonempty project from raw shell whole-file replacement."""
    if not active_task_has_nonempty_requested_target(user_message):
        return ""
    text = command or ""
    targets = extract_target_paths(user_message) or list(
        getattr(CURRENT_TASK_STATE, "target_paths", []) or []
    )
    target_mentioned = False
    for target in targets:
        normalized = normalize_user_path(target)
        variants = {
            normalized,
            normalized.replace(" ", r"\ "),
        }
        if re.match(r"(?i)^/mnt/[a-z](?:/|$)", normalized):
            drive = normalized[5:6].upper()
            tail = normalized[6:].replace("/", "\\")
            variants.add(f"{drive}:{tail}")
        if any(variant and variant in text for variant in variants):
            target_mentioned = True
            break
    if not target_mentioned:
        return ""
    raw_file_replacement = any((
        re.search(
            r"(?is)(?:^|&&|\|\||[;|])\s*cat\b.*?"
            r"(?<![>&])>(?![>&])\s*(?!/dev/(?:null|stdout|stderr)\b)"
            r"(?:['\"]?)[^\s'\";|]+",
            text,
        ),
        re.search(
            r"(?is)(?:^|&&|\|\||[;|])\s*tee\b"
            r"(?:\s+-(?:a|append)|\s+--append)*\s+"
            r"(?!-)(?:['\"]?)[^\s'\";|]+",
            text,
        ),
        re.search(
            r"(?i)\b(?:set-content|add-content|out-file|"
            r"\[io\.file\]::writeall(?:text|bytes))\b",
            text,
        ),
        re.search(
            r"(?i)\b(?:write_text|write_bytes)\s*\(|"
            r"\bopen\s*\([^)]*,\s*['\"][wa]",
            text,
        ),
    ))
    if not raw_file_replacement:
        return ""
    return (
        COMMAND_REJECTION_PREFIX
        + "The requested target is a verified nonempty project. Raw shell, "
        + "PowerShell, or script file replacement was rejected before execution "
        + "to preserve the existing application. Read the file and use one "
        + "focused apply_patch instead; create new files only through the "
        + "structured write tool."
    )

def verified_project_existing_file_write_rejection(raw_path, user_message):
    """Require a focused patch before changing an existing verified project file."""
    if not active_task_has_nonempty_requested_target(user_message):
        return ""
    if not isinstance(raw_path, str) or not raw_path.strip():
        return ""
    try:
        candidate = Path(normalize_user_path(raw_path)).expanduser().resolve()
    except (OSError, RuntimeError):
        return ""
    targets = extract_target_paths(user_message) or list(
        getattr(CURRENT_TASK_STATE, "target_paths", []) or []
    )
    for target in targets:
        try:
            root = Path(normalize_user_path(target)).expanduser().resolve()
        except (OSError, RuntimeError):
            continue
        if candidate == root or root not in candidate.parents:
            continue
        if candidate.is_file():
            return (
                COMMAND_REJECTION_PREFIX
                + "The requested target is a verified nonempty project. Structured "
                + "write_file/append_file replacement of an existing file was "
                + "rejected before execution to preserve the application. Read the "
                + "file and use one focused apply_patch instead."
            )
    return ""

def intercept_command(cmd, user_message=""):
    """
    Intercept and redirect commands that the model gets wrong.
    This is the safety net: even if the model produces wrong commands,
    we fix them before execution. Order matters:
    (1) specific broken-command fixes first (win-tools / PowerShell / /mnt / chrome),
    (2) generic intent-based routing last.
    """
    cmd = align_call_to_requested_targets(
        {"type": "command", "cmd": cmd},
        user_message,
    ).get("cmd", cmd)
    cmd = normalize_windows_paths_in_bash(cmd)
    cmd = normalize_direct_windows_powershell(cmd)
    raw_overwrite_rejection = verified_project_raw_overwrite_rejection(
        cmd, user_message
    )
    if raw_overwrite_rejection:
        return raw_overwrite_rejection
    scaffold_rejection = divergent_windows_gui_scaffold_rejection(
        cmd, user_message
    )
    if scaffold_rejection:
        return scaffold_rejection
    dependency_preflight = dependency_preflight_command(cmd)
    if dependency_preflight:
        return dependency_preflight
    compact_survey = compact_project_toolchain_survey(cmd, user_message)
    if compact_survey:
        return compact_survey
    msg = user_message.lower() if user_message else ""
    windows_find = re.search(
        r"^\s*find\s+/mnt/c/Users(?:/\S*)?\s+.*?-(?:i)?name\s+"
        r"(?P<quote>['\"]?)(?P<name>[^'\"\s;|]+)(?P=quote)",
        cmd,
        re.IGNORECASE,
    )
    if windows_find and objective_requires_action(user_message):
        filename = windows_find.group("name")
        local_matches = [
            path for path in Path.cwd().rglob(filename)
            if path.is_file()
        ]
        if len(local_matches) == 1:
            relative = local_matches[0].relative_to(Path.cwd()).as_posix()
            return f"find . -maxdepth 8 -type f -path './{relative}' -print"
    if re.search(
        r"^\s*find\s+/\s+(?:-[^\n|;]+\s+)*-(?:i)?name\b",
        cmd,
        re.IGNORECASE,
    ):
        cmd = re.sub(
            r"^\s*find\s+/\s+",
            "find . -maxdepth 5 ",
            cmd,
            count=1,
            flags=re.IGNORECASE,
        )

    # A whole-drive Linux find on /mnt is both slow and opaque. Route direct,
    # read-only filename searches through the Windows scanner, which emits
    # factual traversal checkpoints and searches every named fixed drive.
    find_name = re.search(
        r"\bfind\b.*?\s-(?:i)?name\s+(?P<quote>['\"]?)(?P<name>[^'\"\s;|]+)(?P=quote)",
        cmd,
        re.IGNORECASE,
    )
    mounted_drives = sorted(set(re.findall(
        r"/mnt/([a-z])(?=\s|/|$)", cmd, re.IGNORECASE
    )))
    requested_filename = (
        find_name.group("name") if find_name else windows_filename_query(user_message)
    )
    if (
        requested_filename and mounted_drives and
        re.search(r"(^|[;&|]\s*)find\s", cmd, re.IGNORECASE) and
        not objective_requires_action(user_message)
    ):
        drive = "ALL" if len(mounted_drives) > 1 else mounted_drives[0].upper()
        return f"win-tools search {drive} {shlex.quote(requested_filename)} FIRST"

    # Intent shortcuts are allowed only for a direct read-only inventory request.
    # A project such as "build a startup app manager" must retain its literal task.
    boot_intent = is_direct_boot_inventory_request(user_message)
    ranked_intent = any(w in msg for w in ["rank", "cpu", "memory", "ram", "usage", "top "])
    drive_in_msg = re.search(r'([A-Za-z])\s*(?::|\s+drive)', msg)
    largest_files_intent = "file" in msg and any(
        word in msg for word in ("largest", "biggest", "heaviest", "top ")
    )
    file_count_match = re.search(r'\btop\s+(\d+)\b', msg)
    largest_file_count = (
        max(1, min(200, int(file_count_match.group(1))))
        if file_count_match else 50
    )

    # Use the same launch classifier as execution. A path mention inside a
    # Bash probe is data, not a PowerShell invocation.
    if command_uses_direct_windows_powershell(cmd) and "win-tools" not in cmd:
        low = cmd.lower()
        if "get-childitem" in low or "get-child" in low or "measure-object" in low:
            dm = re.search(r'([A-Za-z])\s*:', cmd)
            if dm:
                return f'win-tools dir {dm.group(1).upper()}:'
            if drive_in_msg:
                return f'win-tools dir {drive_in_msg.group(1).upper()}:'
            return "win-tools dir C"
        if "get-process" in low or "tasklist" in low:
            if boot_intent and ranked_intent:
                return "win-tools boot"
            return "win-tools processes"
        if "get-service" in low:
            if boot_intent and ranked_intent:
                return "win-tools boot"
            return "win-tools services"
        if "get-scheduledtask" in low or "taskschd" in low:
            if boot_intent or ranked_intent:
                return "win-tools boot"
            return "win-tools scheduled"
        return cmd

    # ── Fix google-chrome → browse ──
    if "google-chrome" in cmd or cmd.strip().lower().startswith("google-chrome"):
        um = re.search(r'https?://[^\s]+', cmd)
        url = um.group(0) if um else "about:blank"
        if "--new-window" in cmd:
            return f"browse newwindow {url}"
        return f"browse open {url}"

    # ── Fix xdotool (no X display in WSL2) ──
    if "xdotool" in cmd:
        return "echo 'xdotool is not available in WSL2 - use browse for Chrome operations'"

    # ── Fix read-only taskschd.msc / schtasks inventory commands ──
    if "taskschd" in cmd.lower() or "schtasks" in cmd.lower():
        low = cmd.lower()
        if any(flag in low for flag in (
            "/create", "/change", "/delete", "/run", "/end",
            "register-scheduledtask", "set-scheduledtask",
            "unregister-scheduledtask", "start-scheduledtask",
        )):
            return cmd
        return "win-tools boot" if is_direct_boot_inventory_request(user_message) else cmd

    # ── Fix du/find/ls on Windows mount points ──
    mnt = re.search(r'/mnt/([a-z])(?=\s|/|$)', cmd, re.IGNORECASE)
    if mnt:
        # The canonical executable path can be a direct invocation or a
        # Linux-side interop probe. In both cases, keep the compound command
        # intact instead of collapsing its trailing `ls` into a drive listing.
        if str(WINDOWS_POWERSHELL) in cmd:
            return cmd
        if objective_requires_action(user_message):
            return cmd
        drive = mnt.group(1).upper()
        if re.search(r'(^|[;&|]\s*)(du|find|tree|df)\s', cmd):
            if requested_filename:
                scope = "ALL" if len(mounted_drives) > 1 else drive
                return f"win-tools search {scope} {shlex.quote(requested_filename)} FIRST"
            if largest_files_intent:
                return f"win-tools files {drive} {largest_file_count}"
            return f"win-tools scan {drive}"
        if re.search(r'(^|[;&|]\s*)(ls|dir)\s', cmd):
            return f'win-tools dir {mnt.group(1).upper()}:'
        # Creation, editing, testing, Git, and all other commands must keep the
        # user's exact destination. Never rewrite a mutation into a drive scan.
        return cmd

    # ── Route win-tools commands (also honors the user's intent) ──
    if "win-tools" in cmd:
        low = cmd.lower()
        try:
            win_parts = shlex.split(cmd)
        except ValueError:
            win_parts = []
        win_action = (
            win_parts[1].lower()
            if len(win_parts) >= 2 and win_parts[0].lower() == "win-tools"
            else ""
        )
        supplied_drive = (
            normalize_windows_drive(win_parts[2], allow_all=win_action == "search")
            if len(win_parts) >= 3 else None
        )
        folders_only = (
            win_action == "dir"
            and any(str(part).upper() == "FOLDERS" for part in win_parts[3:])
        )
        if re.search(r'win-tools\s+help\s+', low):
            hm = re.search(r'win-tools\s+help\s+(\S+)', low)
            if hm:
                act = hm.group(1).lower()
                if act in ("dir", "folder", "folders", "ls"):
                    dm3 = re.search(r'help\s+\S+\s+([A-Za-z])\s*:', low)
                    if dm3:
                        return f'win-tools dir {dm3.group(1).upper()}:'
                    if drive_in_msg:
                        return f'win-tools dir {drive_in_msg.group(1).upper()}:'
                    return "win-tools dir C"
                if act in ("startup", "start", "boot"):
                    return "win-tools boot" if ranked_intent else "win-tools startup"
                return cmd
        if win_action == "search":
            if len(win_parts) >= 4:
                scope = win_parts[2].upper()
                scope = scope if scope == "ALL" else scope[0]
                mode = win_parts[4].upper() if len(win_parts) >= 5 else "ALL"
                mode = mode if mode in ("FIRST", "ALL") else "ALL"
                if is_direct_windows_filename_request(user_message):
                    mode = "FIRST"
                return (
                    f"win-tools search {scope} {shlex.quote(win_parts[3])} {mode}"
                )
            return "win-tools search C test ALL"
        # Boot/startup with ranking -> the full correlated report
        if boot_intent and ranked_intent:
            return "win-tools boot"
        if boot_intent or "boot" in low or re.search(r'win-tools\s+start\b', low):
            return "win-tools startup"
        if "scheduled" in low or "task scheduler" in low:
            return "win-tools scheduled"
        # Pass-through for the new automation/system actions
        for keep in ("gui", "clip", "notify", "shot", "net", "gpu", "battery"):
            if keep in low:
                return cmd
        if "files" in low:
            count_match = re.search(r'win-tools\s+files(?:\s+[A-Za-z]:?)?\s+(\d+)', cmd)
            count = max(1, min(200, int(count_match.group(1)))) if count_match else largest_file_count
            return f'win-tools files {supplied_drive or "C"} {count}'
        if "scan" in low:
            if largest_files_intent:
                return f'win-tools files {supplied_drive or "C"} {largest_file_count}'
            return f'win-tools scan {supplied_drive or "C"}'
        if "disk" in low:
            return f'win-tools disk {supplied_drive or "C"}'
        if "dir" in low or "folder" in low or " ls " in low or low.strip().endswith("ls"):
            if supplied_drive:
                suffix = " FOLDERS" if folders_only else ""
                return f'win-tools dir {supplied_drive}:{suffix}'
            dm4 = re.search(r'dir\s+([A-Za-z])\s*:', low)
            if dm4:
                return f'win-tools dir {dm4.group(1).upper()}:'
            if drive_in_msg:
                return f'win-tools dir {drive_in_msg.group(1).upper()}:'
            return "win-tools dir C"
        if "process" in low:
            return "win-tools processes"
        if "service" in low:
            return "win-tools services"
        return cmd

    # Generic intent routing is only a fallback for an empty/placeholder model
    # command. Replacing a concrete build command based on one user keyword is
    # what previously converted project creation into a startup inventory.
    if cmd.strip() and cmd.strip().lower() not in ("help", "true", ":"):
        return cmd

    # ── Intent-based routing (only when no concrete command was supplied) ──
    if largest_files_intent:
        return f"win-tools files C {largest_file_count}"

    c_drive_keywords = [
        "scan", "heaviest", "biggest folder", "largest folder", "disk usage",
        "top 10", "top 5", "top 20", "folder size", "how big", "space used",
        "largest directories", "biggest directories", "what's taking space",
    ]
    if any(w in msg for w in c_drive_keywords):
        return "win-tools scan C"

    disk_space_keywords = ["disk space", "free space", "how much space", "storage left", "disk full"]
    if any(w in msg for w in disk_space_keywords):
        return "win-tools disk C"

    process_keywords = ["running process", "what process", "task manager", "top processes"]
    if any(w in msg for w in process_keywords):
        return "win-tools processes"

    service_keywords = ["running service", "what service", "service status"]
    if any(w in msg for w in service_keywords):
        return "win-tools services"

    if boot_intent:
        return "win-tools boot" if ranked_intent else "win-tools startup"

    scheduled_keywords = ["scheduled task", "task scheduler", "schtasks", "taskschd"]
    if any(w in msg for w in scheduled_keywords):
        return "win-tools scheduled"

    if "clipboard" in msg or "copy to clipboard" in msg or "paste" in msg:
        return "win-tools clip"
    if "notification" in msg or "notify" in msg:
        return "win-tools notify"
    if "screenshot" in msg or "screen shot" in msg or "capture screen" in msg:
        return "win-tools shot"
    if "wifi" in msg or "network" in msg or "ip address" in msg or "internet connection" in msg:
        return "win-tools net"
    if "gpu" in msg and ("info" in msg or "what gpu" in msg or "graphics card" in msg):
        return "win-tools gpu"

    fm = re.search(r'folders?\s+(?:under|in|on)\s+([A-Za-z])\s*(?::|\s+drive|\s*folder)', msg)
    if fm:
        return f'win-tools dir {fm.group(1).upper()}:'
    if ("list" in msg or "show" in msg) and ("folder" in msg or "drive" in msg or "directory" in msg):
        dm = re.search(r'([A-Za-z])\s*(?::|\s+drive)', msg)
        return f'win-tools dir {dm.group(1).upper()}:' if dm else "win-tools dir C"

    return cmd

def harden_local_tool_launchers(command):
    """Run installed shell helpers directly when /usr/bin/env shebang lookup fails."""
    return re.sub(
        r"(?<![\w/.-])win-tools(?=\s|$)",
        '/bin/bash "$HOME/.local/bin/win-tools"',
        command or "",
    )

def recover_missing_command_dependency(command_name):
    """Install one curated missing toolchain, verify it, and report exact evidence."""
    recovery = missing_command_recovery(command_name)
    if recovery is None:
        return False, ""
    package, verification = recovery
    if package == "rustup":
        install_command = (
            "curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | "
            "sh -s -- -y --profile default && "
            "$HOME/.cargo/bin/rustup default stable && "
            "$HOME/.cargo/bin/rustup component add clippy rustfmt"
        )
    elif package.startswith("mise:"):
        tool_name = package.split(":", 1)[1]
        install_command = (
            "command -v mise >/dev/null 2>&1 || "
            "(curl https://mise.run | sh); "
            f"$HOME/.local/bin/mise use --global {shlex.quote(tool_name)}@latest"
        )
    else:
        install_command = (
            "sudo apt-get -o DPkg::Lock::Timeout=600 update && "
            "sudo apt-get -o DPkg::Lock::Timeout=600 install -y "
            f"{shlex.quote(package)}"
        )
    try:
        returncode, stdout, stderr = run_live_process(
            "set -o pipefail\n" + install_command,
            shell=True,
            timeout=CMD_TIMEOUT_LONG,
            label=f"Installing missing dependency for {command_name}",
            env={
                **os.environ,
                "TERM": "dumb",
                "DEBIAN_FRONTEND": "noninteractive",
                "PATH": AGENT_PATH,
            },
        )
    except Exception as exc:
        return False, (
            f"dependency installation for {command_name} raised "
            f"{type(exc).__name__}: {exc}"
        )
    install_evidence = "\n".join(
        part.strip() for part in (stdout, stderr) if part and part.strip()
    )
    if returncode != 0:
        return False, (
            f"dependency package {package} exited with code {returncode}: "
            f"{_one_line(install_evidence, 1200)}"
        )
    verify_env = {
        **os.environ,
        "PATH": AGENT_PATH,
    }
    try:
        checked = subprocess.run(
            verification,
            shell=True,
            executable="/bin/bash",
            text=True,
            capture_output=True,
            timeout=60,
            env=verify_env,
        )
    except Exception as exc:
        return False, (
            f"dependency package {package} installed, but verification raised "
            f"{type(exc).__name__}: {exc}"
        )
    verification_evidence = _one_line(
        checked.stdout or checked.stderr or "verification produced no text",
        1200,
    )
    if checked.returncode != 0:
        return False, (
            f"dependency package {package} installed, but {verification!r} "
            f"failed with code {checked.returncode}: {verification_evidence}"
        )
    return True, (
        f"installed {package} for missing command {command_name}; "
        f"verified with {verification!r}: {verification_evidence}"
    )

def execute_tool_call(call, user_message=""):
    """Execute a single tool call and return its output as a string."""
    try:
        ct = call.get("type", "command")

        if ct == "command":
            cmd = intercept_command(call.get("cmd", ""), user_message)
            if cmd.startswith(COMMAND_REJECTION_PREFIX):
                return "[RECOVERY REQUIRED: " + cmd[len(
                    COMMAND_REJECTION_PREFIX
                ):] + "]"
            uses_windows_powershell = command_uses_direct_windows_powershell(cmd)
            if uses_windows_powershell:
                _ensure_windows_interop_runtime()
            if (
                objective_requests_windows_gui(user_message)
                and is_foreground_gui_command(cmd)
                and re.search(r"\bpython(?:3(?:\.\d+)?)?\b", cmd, re.IGNORECASE)
            ):
                return (
                    "[ERROR: A foreground Linux Python GUI launch was rejected "
                    "because the requested deliverable is a Windows desktop GUI at "
                    "a Windows drive path. Build and run it with the installed "
                    "Windows Python or Windows .NET runtime through powershell.exe, "
                    "then verify the actual Windows process/window. Do not use "
                    "Xvfb as Windows GUI acceptance.]"
                )
            cmd = harden_local_tool_launchers(cmd)
            incomplete_heredoc = incomplete_shell_heredoc_marker(cmd)
            if incomplete_heredoc:
                return (
                    "[RECOVERY REQUIRED: shell heredoc marker "
                    f"{incomplete_heredoc!r} has no closing line. No command "
                    "was executed and no file was changed. Use write_file or "
                    "apply_patch, or include the complete heredoc terminator.]"
                )
            identical_sed = _identical_sed_substitution(cmd)
            if identical_sed is not None:
                old, new = identical_sed
                return (
                    "[NO CHANGE: The sed search and replacement are identical "
                    f"({old!r} -> {new!r}), so this command cannot alter a file. "
                    "Emit a materially different destination value. No command "
                    "was executed and no reconciliation is required.]"
                )
            if (
                re.search(
                    r"\b(pytest|unittest|npm\s+(?:run\s+)?test|cargo\s+test|"
                    r"go\s+test|dotnet\s+test|mvn\s+test|gradle\s+test)\b",
                    cmd,
                    re.IGNORECASE,
                )
                and re.search(r"\|\s*(?:head|tail)\b", cmd, re.IGNORECASE)
            ):
                return (
                    "[ERROR: Verification output truncation was rejected. Run "
                    "the complete test command without piping through head or "
                    "tail so every failure remains visible.]"
                )
            is_long = any(s in cmd for s in ["win-tools", "powershell", "du ", "find "])
            timeout = CMD_TIMEOUT_LONG if is_long else CMD_TIMEOUT_DEFAULT
            before_snapshot = (
                project_file_snapshot()
                if _command_edits_project_files(cmd)
                else None
            )
            python_transaction = (
                project_python_backup()
                if before_snapshot is not None
                else None
            )

            returncode, stdout, stderr = run_live_process(
                "set -o pipefail\n" + cmd, shell=True, timeout=timeout,
                label=f"Running command: {_one_line(cmd, 90)}",
                env={
                    **os.environ,
                    "TERM": "dumb",
                    "DEBIAN_FRONTEND": "noninteractive",
                    "PATH": AGENT_PATH,
                    "LD_LIBRARY_PATH": ":".join([
                        str(LLAMA_DIR / "build" / "bin"),
                        "/usr/local/cuda/lib64",
                        os.environ.get("LD_LIBRARY_PATH", ""),
                    ]),
                },
            )
            dependency_note = ""
            if returncode == 127:
                missing_command = extract_missing_command(
                    "\n".join(part for part in (stdout, stderr) if part)
                )
                if missing_command and missing_command_recovery(missing_command):
                    recovered, dependency_note = recover_missing_command_dependency(
                        missing_command
                    )
                    if recovered:
                        returncode, stdout, stderr = run_live_process(
                            "set -o pipefail\n" + cmd,
                            shell=True,
                            timeout=timeout,
                            label=(
                                "Retrying after verified dependency recovery: "
                                f"{_one_line(cmd, 72)}"
                            ),
                            env={
                                **os.environ,
                                "TERM": "dumb",
                                "DEBIAN_FRONTEND": "noninteractive",
                                "PATH": (
                                    AGENT_PATH + ":" +
                                    str(HOME / ".cargo" / "bin")
                                ),
                                "LD_LIBRARY_PATH": ":".join([
                                    str(LLAMA_DIR / "build" / "bin"),
                                    "/usr/local/cuda/lib64",
                                    os.environ.get("LD_LIBRARY_PATH", ""),
                                ]),
                            },
                        )
            output = ""
            if dependency_note:
                output += f"[DEPENDENCY RECOVERY] {dependency_note}\n"
            if stdout:
                output += stdout
            if stderr:
                output += ("\n[STDERR]\n" + stderr) if output else stderr
            if returncode != 0:
                output += f"\n[EXIT CODE: {returncode}]"
            if python_transaction is not None:
                transaction_root, python_backup = python_transaction
                syntax_error = project_python_syntax_error(transaction_root)
                if syntax_error:
                    restore_project_python_backup(
                        transaction_root, python_backup
                    )
                    return (
                        "[ROLLED BACK: The shell edit left project Python code "
                        "syntactically invalid, so every Python-file byte was "
                        "restored to its pre-command state. Fresh compiler "
                        f"evidence: {syntax_error}]"
                    )
            if (
                returncode == 0
                and before_snapshot is not None
                and project_file_snapshot() == before_snapshot
            ):
                return (
                    "[NO CHANGE: The shell command was classified as a project "
                    "file edit, but every bounded project-file hash is unchanged. "
                    "The action does not count as progress.]"
                )
            return output.strip() or "[Command completed with no output]"

        elif ct in ("write", "append"):
            content = call.get("content", "")
            if not isinstance(content, str):
                return (
                    f"[ERROR: {ct} content must be a string. No directory or "
                    "file was created.]"
                )
            if len(content) > MAX_WHOLE_FILE_CHARS:
                return (
                    f"[RECOVERY REQUIRED: oversized_write type={ct} "
                    f"chars={len(content):,} limit={MAX_WHOLE_FILE_CHARS:,}; the "
                    f"safe per-call limit is {MAX_WHOLE_FILE_CHARS:,}. Use "
                    "apply_patch for an existing file or append_file in smaller "
                    "chunks. No directory or file was changed.]"
                )
            raw_path = call.get("path", "")
            if not isinstance(raw_path, str) or not raw_path.strip():
                return (
                    f"[ERROR: {ct} requires a nonempty string path. No directory "
                    "or file was created.]"
                )
            existing_file_rejection = (
                verified_project_existing_file_write_rejection(
                    raw_path, user_message
                )
            )
            if existing_file_rejection:
                return "[RECOVERY REQUIRED: " + existing_file_rejection[len(
                    COMMAND_REJECTION_PREFIX
                ):] + "]"
            p = Path(normalize_user_path(raw_path)).expanduser().resolve()
            if ct == "write" and p.is_file():
                try:
                    if p.read_text(encoding="utf-8") == content:
                        return (
                            f"[NO CHANGE: {p} already contains these exact "
                            "characters. The file was not rewritten. Inspect the "
                            "current failure evidence and choose a materially "
                            "different action.]"
                        )
                except (OSError, UnicodeError):
                    pass
            started = time.monotonic()
            p.parent.mkdir(parents=True, exist_ok=True)
            if ct == "append":
                with open(p, "a", encoding="utf-8") as handle:
                    handle.write(content)
                verb = "appended"
            else:
                temp = p.with_name(p.name + ".nature-tmp")
                try:
                    temp.write_text(content, encoding="utf-8")
                    os.replace(temp, p)
                finally:
                    try:
                        temp.unlink(missing_ok=True)
                    except OSError:
                        pass
                verb = "written atomically"
            duration_ms = int((time.monotonic() - started) * 1000)
            emit_event(
                "file-" + ct, "completed", f"{verb}: {p}",
                path=str(p), characters=len(content), duration_ms=duration_ms,
            )
            return (
                f"[File {verb}: {p} ({len(content):,} characters, "
                f"{duration_ms} ms)]"
            )

        elif ct == "patch":
            patch = normalize_unified_diff_hunks(call.get("patch", ""))
            patch = rebase_patch_paths(patch)
            project_before = project_file_snapshot()
            if not patch.strip():
                return "[ERROR: The patch was empty. No file was changed.]"
            hunk_count = sum(
                1 for line in patch.splitlines() if line.startswith("@@ ")
            )
            file_count = sum(
                1 for line in patch.splitlines() if line.startswith("--- ")
            )
            if not 1 <= file_count <= 24 or not 1 <= hunk_count <= 64:
                return (
                    "[ERROR: An atomic patch must contain between 1 and 24 files "
                    f"and between 1 and 64 hunks; received {file_count} file "
                    f"header(s) and {hunk_count} hunk(s). Split only oversized "
                    "work and retry the first unresolved transaction.]"
                )
            if len(patch) > MAX_PATCH_CHARS:
                return (
                    f"[ERROR: Patch is {len(patch):,} characters; limit is "
                    f"{MAX_PATCH_CHARS:,}. Split it into focused patches.]"
                )
            if not shutil.which("git"):
                if not shutil.which("patch"):
                    return "[ERROR: git or patch is required to validate and apply patches.]"
            for line in patch.splitlines():
                if not line.startswith(("--- ", "+++ ")):
                    continue
                raw_path = line[4:].split("\t", 1)[0].strip()
                if raw_path == "/dev/null":
                    continue
                normalized = raw_path[2:] if raw_path.startswith(("a/", "b/")) else raw_path
                parts = Path(normalized).parts
                if Path(normalized).is_absolute() or ".." in parts:
                    return (
                        f"[ERROR: Unsafe patch path rejected: {raw_path}. "
                        "Only relative paths below the current directory are allowed.]"
                    )
            with tempfile.NamedTemporaryFile(
                mode="w", suffix=".diff", delete=False, encoding="utf-8"
            ) as handle:
                handle.write(patch)
                patch_path = handle.name
            started = time.monotonic()
            try:
                engine = "git"
                check = subprocess.run(
                    ["git", "apply", "--check", "--whitespace=nowarn", patch_path],
                    text=True, capture_output=True, timeout=30,
                ) if shutil.which("git") else None
                if check is None or check.returncode != 0:
                    if not shutil.which("patch"):
                        detail = "" if check is None else (check.stderr or check.stdout)
                        return (
                            "[ERROR: Patch validation failed; no file was changed. "
                            + _one_line(detail, 1200) + "]"
                        )
                    engine = "patch"
                    check = subprocess.run(
                        ["patch", "--batch", "--forward", "--dry-run", "-p1"],
                        input=patch, text=True, capture_output=True, timeout=30,
                    )
                    if check.returncode != 0:
                        recovered = apply_unique_single_line_patch(patch)
                        if recovered is not None:
                            if (
                                recovered.startswith("[PATCH APPLIED:")
                                and project_file_snapshot() == project_before
                            ):
                                return (
                                    "[NO CHANGE: The patch engine reported success "
                                    "but no project file bytes changed.]"
                                )
                            return recovered
                        return (
                            "[ERROR: Patch validation failed in both available "
                            "engines; no file was changed. "
                            + _one_line(check.stderr or check.stdout, 1200) + "]"
                            + patch_refresh_evidence(patch)
                        )
                command = (
                    ["git", "apply", "--whitespace=nowarn", patch_path]
                    if engine == "git" else
                    ["patch", "--batch", "--forward", "-p1"]
                )
                applied = subprocess.run(
                    command,
                    input=None if engine == "git" else patch,
                    text=True, capture_output=True, timeout=60,
                )
                if applied.returncode != 0:
                    return (
                        "[ERROR: Patch application failed after validation. "
                        + _one_line(applied.stderr or applied.stdout, 1200) + "]"
                    )
            finally:
                try:
                    os.unlink(patch_path)
                except OSError:
                    pass
            if project_file_snapshot() == project_before:
                return (
                    "[NO CHANGE: The patch engine reported success but no "
                    "project file bytes changed.]"
                )
            duration_ms = int((time.monotonic() - started) * 1000)
            emit_event(
                "file-patch", "completed", "validated and applied a patch",
                characters=len(patch), duration_ms=duration_ms, engine=engine,
            )
            return (
                f"[Patch validated and applied with {engine} "
                f"({len(patch):,} characters, {duration_ms} ms)]"
            )

        elif ct == "mcp":
            server = call.get("server", "")
            tool = call.get("tool", "")
            arguments = call.get("arguments") or {}
            started = time.monotonic()
            result = _mcp_exchange(
                server, "tools/call",
                {"name": tool, "arguments": arguments},
                timeout=60,
            )
            duration_ms = int((time.monotonic() - started) * 1000)
            status = "failed" if result.get("error") else "completed"
            emit_event(
                "mcp-call", status, f"{server}:{tool}",
                duration_ms=duration_ms,
            )
            return json.dumps(result, ensure_ascii=True, indent=2)[:MAX_TOOL_OUTPUT_CHARS]

        elif ct == "read":
            p = Path(normalize_user_path(call.get("path", ""))).expanduser().resolve()
            if not p.exists():
                return f"[File not found: {p}]"
            c = p.read_text(errors="replace")
            if len(c) > MAX_TOOL_OUTPUT_CHARS:
                c = c[:MAX_TOOL_OUTPUT_CHARS] + (
                    f"\n... [truncated at {MAX_TOOL_OUTPUT_CHARS:,} characters; "
                    "read a narrower range to continue]"
                )
            return c

        elif ct == "python":
            code = call.get("code", "")
            direct_file_write = bool(re.search(
                r"\b(write_text|write_bytes|open\s*\([^)]*,\s*['\"](?:w|a|x)|"
                r"os\.replace|shutil\.(?:copy|copy2|move))\b",
                code,
                re.IGNORECASE,
            ))
            before_snapshot = project_file_snapshot() if direct_file_write else None
            with tempfile.NamedTemporaryFile(mode='w', suffix='.py', delete=False) as f:
                f.write(code)
                f.flush()
                tmp = f.name
            try:
                returncode, stdout, stderr = run_live_process(
                    [sys.executable, tmp],
                    shell=False,
                    timeout=CMD_TIMEOUT_DEFAULT,
                    env={**os.environ, "PATH": AGENT_PATH},
                    label=f"Running generated Python task from {tmp}",
                )
            finally:
                try:
                    os.unlink(tmp)
                except Exception:
                    pass
            output = ""
            if stdout:
                output += stdout
            if stderr:
                output += ("\n[STDERR]\n" + stderr) if output else stderr
            if returncode != 0:
                output += f"\n[EXIT CODE: {returncode}]"
            if (
                returncode == 0
                and before_snapshot is not None
                and project_file_snapshot() == before_snapshot
            ):
                return (
                    "[NO CHANGE: The Python script claimed a file-editing action, "
                    "but every bounded project-file hash is unchanged. The action "
                    "does not count as progress.]"
                )
            return output.strip() or "[Python script completed with no output]"

        elif ct == "invalid":
            return f"[ERROR: {call.get('error', 'Malformed tool call')}]"

        return f"[Unknown tool type: {ct}]"

    except ProcessInterrupted as exc:
        return (
            "[INTERRUPTED SUBPROCESS: "
            f"{exc} The exact action is now blocked from automatic replay. "
            "The parent task will continue from its durable checkpoint and must "
            "choose a materially different strategy.]"
        )
    except ProcessStalled as exc:
        return (
            "[STALLED SUBPROCESS: "
            f"{exc} The process group was terminated after measured inactivity. "
            "The exact action is now blocked from automatic replay, and the "
            "parent task must continue with a materially different strategy.]"
        )
    except subprocess.TimeoutExpired as exc:
        return (
            f"[ERROR: This operation exceeded its configured {exc.timeout}-second "
            "watchdog. The task is still active and must continue with a resumable "
            "or smaller-step approach.]"
        )
    except Exception as e:
        return f"[ERROR: {type(e).__name__}: {e}]"

# ─── Server management ──────────────────────────────────────────────────────

server_process = None  # Track if WE started the server (so we clean up)

def find_draft_model():
    """Find the MTP draft model (speculative decoding), if present."""
    marker = MODEL_DIR / ".chosen-draft"
    if marker.exists():
        p = MODEL_DIR / "MTP" / marker.read_text().strip()
        if p.exists():
            return p
    # Fallback: any mtp-*.gguf under MODEL_DIR/MTP
    mtp = sorted((MODEL_DIR / "MTP").glob("*.gguf")) if (MODEL_DIR / "MTP").exists() else []
    return mtp[0] if mtp else None

def find_mmproj():
    """Find the vision encoder (mmproj), if present - enables image input."""
    marker = MODEL_DIR / ".chosen-mmproj"
    if marker.exists():
        p = MODEL_DIR / marker.read_text().strip()
        if p.exists():
            return p
    for p in sorted(MODEL_DIR.glob("mmproj*.gguf")):
        return p
    return None

_server_help_cache = {}

def server_help(binary):
    """Cached --help output of the llama-server binary.

    llama.cpp renames/removes flags between releases, and the installer always
    builds from upstream HEAD, so the agent adapts its flags to the ACTUAL
    build instead of assuming a fixed flag set.
    """
    if binary not in _server_help_cache:
        try:
            r = subprocess.run([str(binary), "--help"], capture_output=True,
                               text=True, timeout=15)
            _server_help_cache[binary] = (r.stdout or "") + "\n" + (r.stderr or "")
        except Exception:
            _server_help_cache[binary] = ""
    return _server_help_cache[binary]

def flash_attn_flags(binary):
    """Return the correct --flash-attn args for THIS build.

    In llama.cpp >= 0.17 the bare boolean flag became
    `--flash-attn [on|off|auto]`. Passing the bare flag now makes the server
    swallow the NEXT argument as its value and exit with code 1 - which is
    exactly the "Server process exited unexpectedly" crash seen in the field.
    """
    h = server_help(binary)
    if "--flash-attn [on" in h:
        return ["--flash-attn", "on"]
    return ["--flash-attn"]

def get_server_command(model_path, use_draft=True):
    """Build the llama-server command line with maximum-performance flags.

    Flags are feature-detected from the installed build. Fast, balanced, and
    quality profiles make explicit throughput/context/quality tradeoffs; no
    fixed speedup is claimed without a benchmark on this machine.
      --jinja                      use the model's native chat template
      --model-draft + --spec-draft-n-max / --spec-draft-n-min / --spec-draft-p-min
                                   speculative decoding via the model's MTP head
                                   (--draft-max/--draft-min were REMOVED upstream)
    """
    profile = _load_runtime_config().get("profile", "balanced")
    threads = max(1, min(12, (os.cpu_count() or 4) // 2))
    size_gb = model_path.stat().st_size / (1024 ** 3) if model_path.exists() else 0
    model_name = model_path.name.lower()
    # Preserve enough room for long, stateful agent work. A 16 GB GPU uses
    # quantized KV at 32K for larger models and 64K for compact models.
    total_vram_mib, free_vram_mib = detect_gpu_memory_mib()
    if "rnj-1" in model_name:
        # RNJ-1's published native context is 32K. Asking for more only spends
        # memory and can reduce quality; the durable task journal carries work
        # across bounded model calls.
        ctx_size = "32768"
    elif total_vram_mib > 0:
        ctx_size = "32768" if size_gb > 14 else ("65536" if size_gb > 8 else "131072")
    else:
        ctx_size = "32768" if size_gb < 8 else "16384"
    if profile == "fast":
        ctx_size = str(min(int(ctx_size), 32768))
        batch_size, ubatch_size, cache_type = "2048", "512", "q4_0"
    elif profile == "quality":
        batch_size, ubatch_size, cache_type = "512", "256", "f16"
    else:
        batch_size, ubatch_size, cache_type = "1024", "512", "q8_0"

    # Try llama-server binary first (preferred), else `llama server` subcommand
    sb = find_binary("llama-server")
    lm = find_binary("llama") if sb is None else None
    binary = sb if sb is not None else lm
    if binary is None:
        return None

    help_text = server_help(binary)
    gpu_layers = 0
    fit_target_mib = 0
    if total_vram_mib > 0:
        # Protect real free VRAM, not just nominal capacity. Full offload wins
        # when the model, a context/work allowance, and the protected margin all
        # fit. Automatic fitting is only the fallback because some hybrid
        # architectures can allocate far beyond the requested fit target.
        fit_target_mib = max(3072, min(4096, int(total_vram_mib * 0.22)))
        fit_target_mib = min(fit_target_mib, max(1024, free_vram_mib // 2))
        supports_auto = "'auto'" in help_text and "--fit-target" in help_text
        model_mib = int(math.ceil(model_path.stat().st_size / (1024 ** 2)))
        context_work_mib = 1024 if int(ctx_size) <= 32768 else 2048
        if model_mib + context_work_mib + fit_target_mib <= free_vram_mib:
            gpu_layers = 999
        elif supports_auto:
            gpu_layers = "auto"

    base_args = [
        "--model", str(model_path),
        "--threads", str(threads),
        "--ctx-size", ctx_size,
        "--host", SERVER_HOST,
        "--port", str(SERVER_PORT),
    ] + flash_attn_flags(binary) + [
        "-b", batch_size,
        "--jinja",
        "--n-gpu-layers", str(gpu_layers),
    ]
    if gpu_layers == "auto":
        base_args += ["--fit", "on", "--fit-target", str(fit_target_mib)]

    h = help_text
    if "--ubatch-size" in h:
        base_args += ["--ubatch-size", ubatch_size]
    if "--threads-batch" in h:
        base_args += ["--threads-batch", str(threads)]
    if "--cache-type-k" in h and "--cache-type-v" in h:
        # Balanced defaults to q8 for quality; fast deliberately trades some
        # cache precision for capacity. Gemma stays at the server default.
        if "gemma" not in model_name:
            base_args += [
                "--cache-type-k", cache_type,
                "--cache-type-v", cache_type,
            ]
    if "--context-shift" in h:
        base_args += ["--context-shift"]
    if "--cache-ram" in h:
        base_args += ["--cache-ram", "8192"]
    if "--cache-reuse" in h:
        # Reuse a meaningful conversation prefix after context shifting. The
        # current llama.cpp server defaults to disabled cache reuse; retain an
        # explicit, bounded override for hosts that need a different tradeoff.
        cache_reuse = os.environ.get("LLAMA_CACHE_REUSE_TOKENS", "512")
        if not re.fullmatch(r"[0-9]+", cache_reuse) or not 64 <= int(cache_reuse) <= 4096:
            cache_reuse = "512"
        base_args += ["--cache-reuse", cache_reuse]
    if "--metrics" in h:
        base_args += ["--metrics"]
    if "--slots" in h:
        base_args += ["--slots"]

    # Attach a projector only when the selected model is explicitly a vision
    # family. A stale projector from another model can otherwise make an
    # entirely valid text model fail during startup with an embedding mismatch.
    vision_markers = ("vision", "llava", "minicpm-v", "qwen-vl", "qwen2-vl",
                      "qwen2.5-vl", "qwen3.6", "qwen3.8", "gemma-3",
                      "gemma-4", "nemotron", "pixtral")
    mmproj = find_mmproj()
    if mmproj is not None and any(marker in model_name for marker in vision_markers):
        base_args += ["--mmproj", str(mmproj)]

    # A compatible draft can help, but the actual gain must be benchmarked.
    # NOTE: upstream REMOVED --draft-max/--draft-min; the current names are
    # --spec-draft-n-max/--spec-draft-n-min. Old names make the server exit
    # immediately with "the argument has been removed".
    if use_draft:
        draft = find_draft_model()
        if draft is not None:
            base_args += [
                "--model-draft", str(draft),
                "--spec-draft-n-max", "5",
                "--spec-draft-n-min", "2",
                "--spec-draft-p-min", "0.75",
            ]

    if sb is not None:
        return [str(sb)] + base_args + ["--cont-batching"]
    return [str(lm), "server"] + base_args + ["--cont-batching"]

def _wait_ready(proc, timeout_s=None):
    """Wait for /health without abandoning a model merely because loading is slow."""
    if timeout_s is None:
        timeout_s = int(os.environ.get("LLAMA_SERVER_START_TIMEOUT", "900"))
    started = time.monotonic()
    sample = {
        "cpu_s": 0.0,
        "ram_mb": 0.0,
        "io_bytes": 0,
        "io_reads": 0,
        "log_event": "",
    }
    sample_lock = threading.Lock()

    def startup_report(elapsed):
        with sample_lock:
            cpu_s, ram_mb = _process_stats(proc.pid)
            io_bytes, io_reads = _process_io_stats(proc.pid)
            latest_event = ""
            try:
                log_lines = [
                    _one_line(line, 150)
                    for line in (LOG_DIR / "server.log").read_text(
                        errors="replace"
                    ).splitlines()
                    if _one_line(line)
                ]
                if log_lines:
                    latest_event = log_lines[-1]
            except Exception:
                pass
            cpu_delta = max(0.0, cpu_s - sample["cpu_s"])
            ram_delta = ram_mb - sample["ram_mb"]
            io_delta_bytes = max(0, io_bytes - sample["io_bytes"])
            io_delta_reads = max(0, io_reads - sample["io_reads"])
            event_changed = bool(latest_event and latest_event != sample["log_event"])
            sample.update({
                "cpu_s": cpu_s,
                "ram_mb": ram_mb,
                "io_bytes": io_bytes,
                "io_reads": io_reads,
                "log_event": latest_event or sample["log_event"],
            })
        if event_changed:
            message = (
                f"Loading model: {ram_mb:.0f} MB in memory; "
                "the server reached a new loading step."
            )
        elif cpu_delta >= 0.01 or abs(ram_delta) >= 1 or io_delta_reads:
            message = (
                f"Loading model: {ram_mb:.0f} MB in memory; "
                f"{io_delta_bytes / (1024 * 1024):.1f} MiB read in the latest check."
            )
        else:
            message = (
                f"Model server is alive with {ram_mb:.0f} MB loaded; "
                "the health check is not ready."
            )
        return "server-startup-loading", message

    startup_progress = LiveProgress()
    startup_progress.start((
        "server-startup-loading",
        "Starting the local model server and waiting until it can answer.",
    ), reporter=startup_report)
    outcome = "timeout"
    elapsed = 0
    try:
        while True:
            time.sleep(1)
            elapsed = int(time.monotonic() - started)
            if proc.poll() is not None:
                outcome = "exited"
                break
            try:
                resp = urllib.request.urlopen(
                    f"http://{SERVER_HOST}:{SERVER_PORT}/health",
                    timeout=3,
                )
                if b"ok" in resp.read():
                    outcome = "ready"
                    break
            except Exception:
                pass
            if timeout_s and elapsed >= timeout_s:
                break
    finally:
        startup_progress.stop()
    if outcome == "ready":
        log(f"Server ready after {elapsed}s")
        return True
    if outcome == "exited":
        log("Server process exited unexpectedly")
        return False
    log(
        f"Server readiness watchdog reached {timeout_s}s; "
        "the task remains checkpointed for recovery"
    )
    return False

_PERF_VAL_FLAGS = {"--cache-type-k", "-ctk", "--cache-type-v", "-ctv",
                   "-b", "--batch-size", "--ubatch-size", "--threads-batch",
                   "--cache-reuse", "--spec-draft-n-max",
                   "--spec-draft-n-min", "--spec-draft-p-min",
                   "--draft-max", "--draft-min", "--model-draft", "-md",
                   "--mmproj", "--cache-ram"}
_PERF_BARE_FLAGS = {"--flash-attn", "-fa", "--cont-batching", "-cb",
                    "--context-shift", "--metrics", "--slots"}

def _strip_perf_flags(args):
    """Remove performance flags (with their values) for the minimal fallback."""
    out, i = [], 0
    while i < len(args):
        a = args[i]
        if a in _PERF_BARE_FLAGS:
            i += 1
            if a in ("--flash-attn", "-fa") and i < len(args) and args[i] in ("on", "off", "auto"):
                i += 1
            continue
        if a in _PERF_VAL_FLAGS:
            i += 2
            continue
        out.append(a)
        i += 1
    return out

def _set_gpu_layers(args, layers):
    """Return a command with an explicit, replacement GPU-layer strategy."""
    out = list(args)
    for flag in ("--n-gpu-layers", "-ngl"):
        if flag in out:
            index = out.index(flag)
            if layers is None:
                del out[index:index + 2]
            else:
                out[index + 1] = str(layers)
            return out
    if layers is not None:
        out += ["--n-gpu-layers", str(layers)]
    return out


def _gpu_layer_value(args):
    """Read the effective explicit GPU-layer value from one server command."""
    for flag in ("--n-gpu-layers", "--gpu-layers", "-ngl"):
        if flag in args:
            index = args.index(flag)
            return str(args[index + 1]) if index + 1 < len(args) else None
    return None


def start_server(model_path):
    """Start the llama-server (or detect it's already running).

    Tries progressively simpler flag sets so compatible builds have multiple
    verified startup paths:
      1. full flags + MTP draft
      2. full flags without draft
      3. minimal flags (no flash-attn / KV quant / batch / jinja)
    """
    global server_process

    # Check if a compatible server is already running. Never silently reuse a
    # stale CPU-only or different-model server from an interrupted session.
    try:
        resp = urllib.request.urlopen(f"http://{SERVER_HOST}:{SERVER_PORT}/health", timeout=3)
        data = resp.read()
        if b"ok" in data:
            props = api_call("/props", timeout=5)
            model_alias = json.dumps(props).lower()
            if model_path.name.lower() in model_alias:
                log("Compatible server already running on port " + str(SERVER_PORT))
                server_process = None
                _read_context_size()
                _report_tool_template_state()
                return True
            log("A stale or different server owns the agent port; refusing to reuse it")
            return False
    except Exception:
        pass

    candidates = []
    c1 = get_server_command(model_path, use_draft=True)
    if c1:
        auto_fit = _gpu_layer_value(c1) == "auto"
        if auto_fit:
            label = (
                "VRAM-aware GPU fitting + MTP draft"
                if "--model-draft" in c1
                else "VRAM-aware GPU fitting"
            )
        else:
            label = "full + MTP draft" if "--model-draft" in c1 else "full flags"
        candidates.append((c1, label))
    c2 = get_server_command(model_path, use_draft=False)
    if c2 and c2 != c1:
        candidates.append((
            c2,
            "VRAM-aware GPU fitting without draft"
            if _gpu_layer_value(c2) == "auto"
            else "full flags without draft",
        ))
    # Minimal fallback: strip perf flags that could fail on old builds
    if c2:
        minimal = _strip_perf_flags(c2)
        if minimal != c2:
            candidates.append((
                minimal,
                "minimal flags with VRAM-aware GPU fitting"
                if _gpu_layer_value(minimal) == "auto"
                else "minimal flags",
            ))
        cpu_ram = _set_gpu_layers(minimal, 0)
        if cpu_ram != minimal:
            candidates.append((cpu_ram, "CPU and system RAM fallback"))

    unique_candidates = []
    seen_commands = set()
    for command, label in candidates:
        fingerprint = tuple(str(part) for part in command)
        if fingerprint not in seen_commands:
            seen_commands.add(fingerprint)
            unique_candidates.append((command, label))
    candidates = unique_candidates

    server_env = os.environ.copy()
    build_bin = str(LLAMA_DIR / "build" / "bin")
    server_env["LD_LIBRARY_PATH"] = ":".join([
        build_bin, "/usr/local/cuda/lib64",
        server_env.get("LD_LIBRARY_PATH", ""),
    ])
    server_env["PATH"] = build_bin + ":" + server_env.get("PATH", "")

    last_err = "unknown error"
    cuda_allocation_failed = False
    for cmd, label in candidates:
        layer_value = _gpu_layer_value(cmd)
        if cuda_allocation_failed and layer_value not in ("0", None):
            log(
                f"Skipping {label} because the prior distinct GPU-fit attempt "
                "already proved the current VRAM allocation cannot load"
            )
            continue
        log(f"Starting server with {label}")
        if DEBUG_TO_CONSOLE:
            log("Server command: " + " ".join(str(c) for c in cmd))
        try:
            log_fh = open(LOG_DIR / "server.log", "w")
            server_process = subprocess.Popen(
                cmd, stdout=log_fh, stderr=subprocess.STDOUT,
                env=server_env,
                preexec_fn=os.setsid if hasattr(os, "setsid") else None,
            )
            if _wait_ready(server_process):
                _read_context_size()
                _report_tool_template_state()
                return True
        except Exception as e:
            last_err = f"{type(e).__name__}: {e}"
            log(f"Attempt ({label}) raised: {last_err}")
        # Capture WHY it failed (last lines of server.log) for diagnostics
        try:
            tail = [l for l in (LOG_DIR / "server.log").read_text(errors="replace").splitlines() if l.strip()][-6:]
            if tail:
                last_err = " // ".join(tail)
                log(f"Attempt ({label}) failed - server log: {' // '.join(tail)}")
        except Exception:
            pass
        if "unable to allocate cuda" in last_err.lower():
            cuda_allocation_failed = True
        # Not ready - kill this attempt and try the next simpler config
        try:
            os.killpg(os.getpgid(server_process.pid), signal.SIGKILL)
        except Exception:
            pass
        print(
            f"  \033[1;33m[RECOVERY]\033[0m The {label} server attempt did not "
            "become healthy. Its process is stopped, and the next materially "
            "different configuration will start immediately."
        )

    log(f"Server failed to start after all attempts. Last error: {last_err}")
    server_process = None
    return False

def stop_server():
    """Kill the server only if WE started it."""
    global server_process
    if server_process is None:
        return  # Server was already running when we arrived — don't touch it
    try:
        os.killpg(os.getpgid(server_process.pid), signal.SIGTERM)
    except Exception:
        pass
    try:
        server_process.wait(timeout=5)
    except Exception:
        try:
            os.killpg(os.getpgid(server_process.pid), signal.SIGKILL)
        except Exception:
            pass
    server_process = None

def model_server_healthy():
    try:
        response = urllib.request.urlopen(
            f"http://{SERVER_HOST}:{SERVER_PORT}/health", timeout=5
        )
        return b"ok" in response.read()
    except Exception:
        return False

def stop_reused_compatible_server(model_path):
    """Stop only the exact compatible llama-server inherited after a crash."""
    expected_model = str(model_path.resolve())
    expected_port = str(SERVER_PORT)
    for proc_dir in Path("/proc").glob("[0-9]*"):
        try:
            parts = (proc_dir / "cmdline").read_bytes().split(b"\0")
            args = [part.decode("utf-8", "replace") for part in parts if part]
        except (OSError, PermissionError):
            continue
        executable = Path(args[0]).name if args else ""
        if executable != "llama-server":
            continue
        if "--port" not in args or "--model" not in args:
            continue
        try:
            port = args[args.index("--port") + 1]
            model = str(Path(args[args.index("--model") + 1]).resolve())
        except (ValueError, IndexError, OSError):
            continue
        if port != expected_port or model != expected_model:
            continue
        pid = int(proc_dir.name)
        log(f"Stopping inherited compatible model server process {pid}")
        try:
            os.killpg(os.getpgid(pid), signal.SIGTERM)
        except (OSError, ProcessLookupError):
            return not model_server_healthy()
        for _ in range(50):
            if not model_server_healthy():
                return True
            time.sleep(0.1)
        try:
            os.killpg(os.getpgid(pid), signal.SIGKILL)
        except (OSError, ProcessLookupError):
            pass
        return not model_server_healthy()
    return not model_server_healthy()

def recover_model_server(force=False):
    """Restore the local inference endpoint without abandoning active work."""
    if not force and model_server_healthy():
        return True
    if force:
        log("Clearing a poisoned model cache by restarting the owned server")
    else:
        log("The model endpoint is unavailable; restarting the owned server")
    model = find_model()
    if force and server_process is None and model_server_healthy():
        if not model or not stop_reused_compatible_server(model):
            log("Refusing to stop an unverified process that owns the model port")
            return False
    else:
        stop_server()
    return bool(model and start_server(model))

def ensure_model_server_until_ready(state, conversation):
    """Keep the submitted task active until inference is usable or user interrupts."""
    attempt = 0
    while not model_server_healthy():
        attempt += 1
        state.status = "recovering"
        state.record(
            "model-start-recovery",
            f"starting model-server recovery attempt {attempt}",
            False,
        )
        checkpoint_task(state, conversation)
        model = find_model()
        recovered = bool(model and start_server(model))
        if recovered and model_server_healthy():
            state.status = "running"
            state.record(
                "model-start-recovery",
                f"model server became healthy on recovery attempt {attempt}",
                True,
            )
            checkpoint_task(state, conversation)
            return
        delay = min(5 + (attempt - 1) * 5, 30)
        state.record(
            "model-start-recovery",
            (
                f"attempt {attempt} did not produce a healthy server; "
                f"the task remains active and retries in {delay} seconds"
            ),
            False,
        )
        checkpoint_task(state, conversation)
        wait_with_progress(
            delay,
            (
                f"Model-server recovery attempt {attempt} did not become healthy; "
                "the task remains active with all evidence checkpointed"
            ),
        )

def ensure_initial_server_until_ready(model_path):
    """Keep startup alive with factual retries until the model is ready."""
    attempt = 0
    while not model_server_healthy():
        attempt += 1
        if start_server(model_path) and model_server_healthy():
            return
        delay = min(5 + (attempt - 1) * 5, 30)
        wait_with_progress(
            delay,
            (
                f"Model startup attempt {attempt} did not become healthy; "
                "the launcher remains active and will retry automatically"
            ),
        )

class _RetryActiveTask:
    def __init__(self, payload):
        self.payload = payload

# ─── Conversation management ────────────────────────────────────────────────

_ARTIFACT_RE = re.compile(
    r"</?(?:arg_value|tool_call|tool_name|parameters|parameter|arguments|value|result|data|name)>"
    r"|<\|[^|]*\|>"
)

def clean_artifacts(text):
    """Strip tool-call XML / special-token leftovers that reasoning models leak
    into their visible content (e.g. '</arg_value></tool_call>' glued onto a
    code block). These fragments are never legitimate user-facing text."""
    if not text:
        return text
    return _ARTIFACT_RE.sub("", text).strip()

def recover_malformed_read_call(error):
    """Recover only an unambiguous read-only `cat ABSOLUTE_PATH` tool intent."""
    if "Failed to parse tool call arguments as JSON" not in (error or ""):
        return None
    match = re.search(r"last read:.*?\bcat\s+([^\s\"'\\}]+)", error)
    if not match:
        return None
    path = match.group(1).strip()
    if not path.startswith("/") or any(token in path for token in ("\n", "\r", "\x00")):
        return None
    return {"type": "read", "path": path}

def _model_error_is_request_local(error):
    low = (error or "").lower()
    return any(marker in low for marker in (
        "failed to parse tool call arguments",
        "malformed sse",
        "invalid utf-8",
        "unexpected sse",
        "oversized_write",
        "usable action deadline exceeded",
        "token limit",
        "before the required [done]",
        "without a completion finish state",
        "conflicting ids",
        "json object",
        "prompt is too long",
        "context",
    ))


def _build_retry_body(body, messages, error, repeated_count=1):
    """Build a materially different, capability-preserving retry request."""
    retry = dict(body)
    retry["cache_prompt"] = False
    retry["temperature"] = 0.1
    retry["top_p"] = 0.9
    retry["top_k"] = 20
    retry["reasoning_effort"] = "none"
    retry["parallel_tool_calls"] = False
    retry_messages = list(messages)
    low = (error or "").lower()

    if "oversized_write" in low:
        retry["tools"] = [
            tool for tool in (retry.get("tools") or [])
            if tool.get("function", {}).get("name")
            not in ("write_file", "append_file")
        ]
        instruction = (
            "[OVERSIZED WRITE RECOVERY]\n"
            "The previous whole-file payload exceeded the safe limit and was "
            "stopped before any file mutation. Keep the full task objective, "
            "but use apply_patch for an existing file or run_command/Python to "
            "generate a new large file in bounded chunks. Do not resend the "
            "rejected write_file or append_file payload."
        )
    elif "failed to parse tool call arguments" in low or "malformed" in low:
        retry_messages = sanitize_native_tool_history(retry_messages)
        instruction = (
            "[MALFORMED TOOL RECOVERY]\n"
            "The previous tool arguments were invalid and were not executed. "
            "Use the preserved evidence, then emit exactly one complete native "
            "tool call whose arguments are a strict JSON object. Keep the same "
            "task and choose the smallest operation that advances it."
        )
    elif "usable action deadline exceeded" in low:
        instruction = (
            "[ACTION DEADLINE RECOVERY]\n"
            "Use the evidence already collected and emit one concrete tool call "
            "now. Do not repeat analysis or the plan."
        )
    elif "token limit" in low or "before the required [done]" in low:
        instruction = (
            "[INCOMPLETE STREAM RECOVERY]\n"
            "Regenerate only the next complete, bounded answer or tool call. "
            "Do not repeat partial output and do not claim completion."
        )
    elif "context" in low or "prompt is too long" in low:
        retry_messages = trim_conversation(
            sanitize_native_tool_history(retry_messages), CURRENT_TASK_STATE
        )
        instruction = (
            "[CONTEXT RECOVERY]\n"
            "Continue from the compacted objective and newest verified evidence. "
            "Emit one useful next action without repeating old tool output."
        )
    else:
        instruction = (
            "[CLEAN RETRY]\n"
            "The prior stream did not complete. Continue the same task using a "
            "different, strictly valid next response."
        )
    if repeated_count >= 2:
        instruction += (
            "\nThis failure repeated; change the operation shape rather than "
            "resending the same payload."
        )
    retry["messages"] = normalize_model_messages(retry_messages + [{
        "role": "user",
        "content": instruction,
    }])
    return retry


def send_message(messages, tools=None, max_tokens=None):
    """Send one recoverable chat request.

    Handles reasoning models (GLM-4.7-Flash, Qwen3, ...): those models think
    first - llama-server reports the thinking as `reasoning_content` and the
    visible answer arrives in `content` only afterwards. Connection failures
    and thought-only responses are retried, but never converted into a final
    user answer.
    """
    messages = normalize_model_messages(messages)
    body = {
        "model": "local",
        "messages": messages,
        "max_tokens": max_tokens or RESPONSE_MAX_TOKENS,
        "temperature": 0.6,
        "top_p": 0.95,
        "top_k": 20,
        "repeat_penalty": 1.08,
        "cache_prompt": True,  # KV-cache reuse: much faster repeated agent rounds
    }
    if DISABLE_MODEL_THINKING:
        # Qwen chat templates honor this llama-server request and skip private
        # chain-of-thought before the first actionable tool call.
        body["chat_template_kwargs"] = {"enable_thinking": False}
    if tools:
        body["tools"] = tools
    last_error = ""
    repeated_error_count = 0
    for attempt in range(4):
        response = api_chat_stream(body, attempt + 1)
        if "error" in response:
            current_error = response["error"]
            if recover_malformed_read_call(current_error):
                return {
                    "content": "", "tool_calls": [], "message": None,
                    "finish_reason": "recoverable_malformed_read",
                    "error": current_error,
                }
            repeated_error_count = (
                repeated_error_count + 1 if current_error == last_error else 1
            )
            last_error = current_error
            log(f"Model stream attempt {attempt + 1} failed: {last_error}")
            if attempt < 3:
                body = _build_retry_body(
                    body, messages, last_error, repeated_error_count
                )
                print(
                    f"  \033[1;33m[RETRY {attempt + 2}/4]\033[0m "
                    f"The model stream failed: {_one_line(last_error, 180)}"
                )
                continue
            return {
                "content": "", "tool_calls": [], "message": None,
                "finish_reason": "error", "error": last_error,
            }
        try:
            msg = response["choices"][0]["message"]
            finish = response["choices"][0].get("finish_reason", "")
        except (KeyError, IndexError):
            last_error = "Could not parse the model response"
            continue
        content = clean_artifacts(msg.get("content") or "")
        tool_calls = msg.get("tool_calls") or []
        reasoning = (msg.get("reasoning_content") or "").strip()
        if finish in ("length", "max_tokens") and tool_calls:
            last_error = "A tool call was cut off by the model token limit"
            body = _build_retry_body(body, messages, last_error, 1)
            continue
        if content or tool_calls:
            return {
                "content": content,
                "tool_calls": tool_calls,
                "message": msg,
                "finish_reason": finish,
                "error": None,
            }
        # No visible answer yet: reasoning model either ran out of tokens while
        # thinking or finished with a thought-only reply. Keep nudging within
        # this request; the outer task loop remains active after these retries.
        if reasoning and attempt < 3:
            log(f"Model produced only reasoning ({len(reasoning)} chars) - asking for its final answer")
            body = _build_retry_body(
                body,
                messages,
                "usable action deadline exceeded: reasoning-only response",
                1,
            )
            body["max_tokens"] = RESPONSE_MAX_TOKENS
            continue
        last_error = "The model returned neither visible content nor a complete tool call"
    return {
        "content": "", "tool_calls": [], "message": None,
        "finish_reason": "error", "error": last_error or "Unknown model response failure",
    }

TOOL_ALIASES = {
    "shell": "run_command", "bash": "run_command", "sh": "run_command",
    "terminal": "run_command", "exec": "run_command", "execute": "run_command",
    "python": "run_python", "python_code": "run_python",
    "execute_python": "run_python",
    "read": "read_file", "cat": "read_file", "file_read": "read_file",
    "write": "write_file", "file_write": "write_file",
    "append": "append_file", "file_append": "append_file",
    "patch": "apply_patch", "diff": "apply_patch",
}


def _native_args(raw):
    raw_text = (
        raw if isinstance(raw, str)
        else json.dumps(raw, ensure_ascii=False, default=repr)
    )
    try:
        value = raw if isinstance(raw, dict) else json.loads(raw_text or "{}")
    except (TypeError, ValueError, json.JSONDecodeError) as exc:
        return None, raw_text[:4000], f"{type(exc).__name__}: {exc}"
    if not isinstance(value, dict):
        return (
            None,
            raw_text[:4000],
            f"arguments must be a JSON object, not {type(value).__name__}",
        )
    return value, raw_text[:4000], ""


def _string_arg(args, *names):
    for name in names:
        value = args.get(name)
        if isinstance(value, str) and value.strip():
            return value
    return ""


def tool_calls_to_calls(tool_calls):
    """Normalize native tool calls without guessing past malformed input."""
    calls = []
    for tc in tool_calls or []:
        fn = tc.get("function", {})
        original_name = (fn.get("name") or "").strip().lower()
        name = TOOL_ALIASES.get(original_name, original_name)
        args, raw_arguments, parse_error = _native_args(
            fn.get("arguments", "{}")
        )
        tid = tc.get("id") or f"call_local_{uuid.uuid4().hex[:12]}"
        tc["id"] = tid
        if parse_error:
            calls.append({
                "type": "invalid",
                "tool_call_id": tid,
                "raw_arguments": raw_arguments,
                "error": (
                    f"Native tool call {original_name or 'unnamed'} was rejected "
                    f"before execution because its arguments are invalid: {parse_error}"
                ),
            })
            continue
        if name == "win_tools":
            action = _string_arg(args, "action") or "help"
            drive = _string_arg(args, "drive") or "C"
            extra = args.get("args") or []
            if not isinstance(extra, list):
                extra = [extra]
            command_parts = ["win-tools", action]
            if action in ("scan", "files", "dir", "disk", "search"):
                command_parts.append(drive)
            if extra:
                command_parts.extend(str(item) for item in extra)
            calls.append({
                "type": "command",
                "cmd": shlex.join(command_parts),
                "tool_call_id": tid,
            })
        elif name == "browse":
            action = _string_arg(args, "action") or "open"
            url = _string_arg(args, "url") or "about:blank"
            command_parts = (
                ["browse", "newtab"]
                if action == "newtab" else ["browse", action, url]
            )
            cmd = shlex.join(command_parts)
            calls.append({"type": "command", "cmd": cmd, "tool_call_id": tid})
        elif name == "run_command":
            command = _string_arg(args, "command", "cmd", "code")
            calls.append({
                "type": "command" if command else "invalid",
                "cmd": command,
                "tool_call_id": tid,
                "error": "The model emitted an empty command.",
            })
        elif name == "run_python":
            code = _string_arg(args, "code", "script")
            command = _string_arg(args, "command", "cmd")
            if not code and command:
                calls.append({
                    "type": "command",
                    "cmd": command,
                    "tool_call_id": tid,
                })
                continue
            calls.append({
                "type": "python" if code else "invalid",
                "code": code,
                "tool_call_id": tid,
                "error": "The model emitted empty Python code.",
            })
        elif name == "write_file":
            path = _string_arg(args, "path", "file", "file_path")
            content = args.get("content", "")
            calls.append({
                "type": "write"
                if path and isinstance(content, str) else "invalid",
                "path": path, "content": content if isinstance(content, str) else "",
                "tool_call_id": tid,
                "error": "The file write requires string path and content fields.",
            })
        elif name == "append_file":
            path = _string_arg(args, "path", "file", "file_path")
            content = args.get("content", "")
            calls.append({
                "type": "append"
                if path and isinstance(content, str) else "invalid",
                "path": path, "content": content if isinstance(content, str) else "",
                "tool_call_id": tid,
                "error": "The file append requires string path and content fields.",
            })
        elif name == "apply_patch":
            patch = _string_arg(args, "patch", "diff")
            calls.append({
                "type": "patch" if patch else "invalid",
                "patch": patch,
                "tool_call_id": tid,
                "error": "The model emitted an empty patch.",
            })
        elif name == "mcp_call":
            server = _string_arg(args, "server")
            tool = _string_arg(args, "tool")
            mcp_arguments = args.get("arguments") or {}
            calls.append({
                "type": "mcp"
                if server and tool and isinstance(mcp_arguments, dict)
                else "invalid",
                "server": server,
                "tool": tool,
                "arguments": mcp_arguments if isinstance(mcp_arguments, dict) else {},
                "tool_call_id": tid,
                "error": (
                    "The MCP call requires a server, tool, and object-valued arguments."
                ),
            })
        elif name == "read_file":
            path = _string_arg(args, "path", "file", "file_path")
            calls.append({
                "type": "read" if path else "invalid",
                "path": path,
                "tool_call_id": tid,
                "error": "The model emitted a file read without a path.",
            })
        else:
            calls.append({
                "type": "invalid",
                "tool_call_id": tid,
                "raw_arguments": raw_arguments,
                "error": (
                    f"Unsupported native tool call {original_name or 'unnamed'} "
                    "was rejected before execution."
                ),
            })
    return calls

def narrate(call):
    """Deterministic plain-English sentence describing what is about to happen.
    This guarantees real-time English progress narration even if the model
    forgets to narrate on its own."""
    ct = call.get("type", "command")
    if ct == "command":
        cmd = call.get("cmd", "").strip()
        low = cmd.lower()
        try:
            command_parts = shlex.split(cmd)
        except ValueError:
            command_parts = cmd.split()

        def useful_arguments():
            return [
                part for part in command_parts[1:]
                if not part.startswith("-")
                and part not in ("&&", "||", ";", "|")
            ]

        arguments = useful_arguments()
        target = arguments[-1] if arguments else "the requested target"
        if low.startswith("win-tools boot"):
            return "Scanning everything that runs when Windows boots - startup programs, scheduled tasks, and auto-start services - and ranking them by CPU and memory usage."
        if low.startswith("win-tools files"):
            return "Scanning the Windows drive and ranking the requested largest files by their actual byte size."
        if low.startswith("win-tools scan"):
            return "Scanning the Windows drive to find the heaviest folders, so I can show you exactly what is using the most space."
        if low.startswith("win-tools dir"):
            if re.search(r"\bfolders\b", low):
                return "Listing every top-level folder on the Windows drive you asked about."
            return "Listing the top-level folders and files on the Windows drive you asked about."
        if low.startswith("win-tools disk"):
            return "Checking how much space is used and how much is free on that Windows drive."
        if low.startswith("win-tools search"):
            return (
                "Searching the requested fixed Windows drive or drives by file "
                "name, with live counts of folders and files checked."
            )
        if low.startswith("win-tools startup") or low.startswith("win-tools scheduled"):
            return "Looking up everything configured to start with Windows, including scheduled tasks."
        if low.startswith("win-tools processes"):
            return "Listing the processes running on Windows, sorted by memory usage."
        if low.startswith("win-tools services"):
            return "Listing the services currently running on Windows."
        if low.startswith("win-tools gui"):
            return "Automating a Windows window by activating it and sending keystrokes."
        if low.startswith("win-tools clip"):
            return "Working with the Windows clipboard for you."
        if low.startswith("win-tools notify"):
            return "Sending a Windows notification so you can see the result right away."
        if low.startswith("win-tools shot"):
            return "Taking a screenshot of the Windows screen and reading any text on it."
        if low.startswith("win-tools net"):
            return "Checking the Windows network adapters, IP addresses, and Wi-Fi status."
        if low.startswith("win-tools gpu"):
            return "Reading the GPU information from Windows."
        if low.startswith("win-tools battery"):
            return "Checking the laptop battery status."
        if low.startswith("win-tools"):
            return "Running a Windows system operation via the win-tools bridge."
        if low.startswith("browse"):
            return "Opening that URL in the verified Chrome Profile 2 window."
        if re.match(r"^(?:sudo\s+)?apt(?:-get)?\s+update\b", low):
            return (
                "Refreshing Ubuntu's package index so dependency decisions use "
                "the repositories available right now."
            )
        if re.match(r"^(?:sudo\s+)?apt(?:-get)?\s+install\b", low):
            packages = [
                part for part in command_parts
                if not part.startswith("-")
                and part not in ("sudo", "apt", "apt-get", "install")
                and not re.match(r"^[;&|]+$", part)
            ]
            package_text = ", ".join(packages[:8]) or "the required dependency"
            if len(packages) > 8:
                package_text += f", and {len(packages) - 8} more"
            return f"Installing the missing system dependencies: {package_text}."
        if low.startswith("mkdir "):
            return f"Creating the requested directory structure at {target}."
        if low.startswith("chmod "):
            return f"Applying the requested executable permissions to {target}."
        if low.startswith("cd "):
            return f"Changing the working directory to {target}."
        if re.match(r"^dotnet\s+build\b", low):
            return f"Building {target} with the .NET SDK and collecting every compiler diagnostic."
        if re.match(r"^dotnet\s+test\b", low):
            return f"Running the complete .NET test suite for {target}."
        if re.match(r"^dotnet\s+new\b", low):
            return f"Creating the requested .NET project structure at {target}."
        if re.match(r"^dotnet\s+run\b", low):
            return f"Launching the .NET project at {target} for a real runtime check."
        if low.startswith("git "):
            action = command_parts[1] if len(command_parts) > 1 else "operation"
            return f"Running Git {action} against {target} and preserving its exact result."
        if low.startswith("docker"):
            action = command_parts[1] if len(command_parts) > 1 else "operation"
            return f"Running Docker {action} for {target} and monitoring the real process."
        if low.startswith("ffmpeg"):
            return "Processing audio or video with ffmpeg."
        if low.startswith("tesseract"):
            return "Reading text out of an image using OCR."
        if low.startswith("pdftotext"):
            return "Extracting text from a PDF document."
        if low.startswith("pandoc"):
            return "Converting a document between formats."
        if low.startswith("curl ") or low.startswith("wget "):
            return "Fetching data from the internet."
        if low.startswith("python3 ") or low.startswith("python "):
            if re.search(r"\s-m\s+(?:py_compile|compileall)\b", low):
                return f"Checking Python syntax for {target} without launching the application."
            if re.search(r"\s-m\s+(?:unittest|pytest)\b|\bpytest\b", low):
                return f"Running the Python test suite rooted at {target} and keeping every failure visible."
            if re.search(r"\s-c\s+", low):
                return (
                    "Running one bounded inline Python capability check and "
                    "reading its exact result."
                )
            return f"Running the Python program at {target} and monitoring its real output."
        if low.startswith("cargo "):
            action = command_parts[1] if len(command_parts) > 1 else "command"
            return f"Running Cargo {action} for the Rust project at {target}."
        if low.startswith("go "):
            action = command_parts[1] if len(command_parts) > 1 else "command"
            return f"Running Go {action} for {target}."
        if low.startswith(("npm ", "pnpm ", "yarn ")):
            manager = command_parts[0]
            action = command_parts[1] if len(command_parts) > 1 else "command"
            return f"Running {manager} {action} for the JavaScript project at {target}."
        executable = command_parts[0] if command_parts else "the requested command"
        return (
            f"Executing {executable} for {target}; this exact subprocess is being "
            "monitored for output, CPU work, file activity, and exit status."
        )
    if ct == "python":
        return "Running a Python script to handle the calculation or data processing."
    if ct == "write":
        return f"Writing the file {call.get('path', '')} for you."
    if ct == "append":
        return f"Appending a bounded chunk to {call.get('path', '')}."
    if ct == "patch":
        return "Validating and applying a focused code patch."
    if ct == "mcp":
        return f"Calling {call.get('tool', '')} on trusted MCP server {call.get('server', '')}."
    if ct == "read":
        return f"Reading the file {call.get('path', '')}."
    if ct == "invalid":
        return (
            "Rejecting an invalid tool request before execution; its bounded "
            "arguments are being retained only as diagnostic evidence."
        )
    return f"Executing the requested {ct} operation with its supplied arguments."

def interpret_result(call, output):
    """Deterministic plain-English sentence interpreting what a tool returned.
    This guarantees real-time English progress narration AFTER every action,
    exactly like a human would narrate while working."""
    out = (output or "").strip()
    lines = [l for l in out.splitlines() if l.strip()]
    ct = call.get("type", "command")
    evidence = re.sub(r"\s+", " ", _ANSI_RE.sub("", out)).strip()
    if len(evidence) > 180:
        evidence = evidence[:177].rstrip() + "..."
    if _tool_failed(out):
        if out.lower().startswith("[no change:"):
            return (
                f"No bytes changed for {call.get('path', 'the requested target')}: "
                f"{evidence}"
            )
        if out.lower().startswith("[loop guard:"):
            return f"The duplicate action was blocked before execution: {evidence}"
        return f"The {ct} action failed with this reported evidence: {evidence or 'no diagnostic text was returned'}"
    if ct == "command":
        low = call.get("cmd", "").lower()
        if low.startswith("win-tools boot"):
            rows = [l for l in lines if "|" in l and not l.startswith("Format")]
            return f"Got the boot inventory back with {len(rows)} startup items - I can now rank them by CPU and RAM usage for you."
        if low.startswith("win-tools files"):
            rows = [
                line for line in lines
                if re.match(r"^[A-Za-z]:\\.*\|\d+\|", line)
            ]
            return f"Largest-file scan finished - {len(rows)} files were measured and ranked by byte size."
        if low.startswith("win-tools scan"):
            rows = [
                line for line in lines
                if "|" in line and not line.startswith(("SUMMARY|", "LLAMA_PROGRESS|"))
            ]
            return f"Folder scan finished - {len(rows)} folders measured, sorted from heaviest to lightest."
        if low.startswith("win-tools dir"):
            folders = [line for line in lines if line.startswith("FOLDER|")]
            if re.search(r"\bfolders\b", low):
                return (
                    f"Folder listing finished with {len(folders)} verified "
                    f"top-level folders."
                )
            return f"Drive listing returned {len(lines)} entries - here is what is stored there."
        if low.startswith("win-tools disk"):
            return "Disk space checked - I can see used, free, and total space now."
        if low.startswith("win-tools search"):
            matches = [line for line in lines if line.startswith("MATCH|")]
            if not matches:
                return "Filename search completed - no matching file was found in the scanned fixed Windows drives."
            return (
                f"Filename search completed - {len(matches)} matching file"
                f"{'s' if len(matches) != 1 else ''} found with full paths."
            )
        if low.startswith("win-tools processes"):
            return "Process list received - these are the top memory consumers right now."
        if low.startswith("win-tools services"):
            return "Service list received - here are the services currently running."
        if low.startswith("win-tools startup") or low.startswith("win-tools scheduled"):
            return "Startup configuration retrieved - I can see what is configured to launch."
        if low.startswith("win-tools"):
            return "The Windows operation completed - processing the results now."
        if low.startswith("browse"):
            return "Chrome accepted the profile-targeted open request; interactive tab control remains a separate capability."
        command = re.sub(r"\s+", " ", call.get("cmd", "")).strip()
        if len(command) > 120:
            command = command[:117].rstrip() + "..."
        return (
            f"Finished {command or 'the requested command'}: "
            f"{len(lines)} non-empty output line(s), {len(out)} characters returned."
        )
    if ct == "python":
        return (
            f"The Python script finished with {len(lines)} non-empty output "
            f"line(s) and {len(out)} returned characters."
        )
    if ct == "write":
        match = re.search(
            r"\[File written atomically:\s*(.*?)\s*"
            r"\((\d+) characters,\s*(\d+) ms\)\]",
            out,
        )
        if match:
            return (
                f"Saved {match.group(1)} atomically: {match.group(2)} "
                f"characters written in {match.group(3)} ms."
            )
        return (
            f"Saved {call.get('path', 'the requested file')}; "
            f"the write tool returned: {evidence or 'success with no detail'}"
        )
    if ct == "append":
        return (
            f"Appended the bounded chunk to {call.get('path', 'the requested file')}; "
            f"the tool returned: {evidence or 'success with no detail'}"
        )
    if ct == "patch":
        return f"Applied the validated patch; the tool returned: {evidence or 'success with no detail'}"
    if ct == "mcp":
        return (
            f"{call.get('server', 'The MCP server')}.{call.get('tool', 'tool')} "
            f"returned {len(lines)} non-empty line(s) and {len(out)} characters."
        )
    if ct == "read":
        return (
            f"Read {call.get('path', 'the requested file')}: "
            f"{len(lines)} non-empty line(s), {len(out)} characters loaded."
        )
    return (
        f"Completed the {ct} action with {len(lines)} non-empty result "
        f"line(s) and {len(out)} returned characters."
    )

def _read_context_size():
    """Fetch the real context size from the running server and remember it.

    The conversation/response budgets must fit inside the model's context or
    every request fails with a prompt-too-long error mid-conversation.
    """
    global CONTEXT_TOKENS
    try:
        d = api_call("/props", timeout=10)
        n = d.get("default_generation_settings", {}).get("n_ctx")
        if isinstance(n, int) and n > 0:
            CONTEXT_TOKENS = n
            log(f"Server context: {CONTEXT_TOKENS} tokens")
    except Exception:
        pass

def _report_tool_template_state():
    """Report whether the server advertises a tool-aware chat template."""
    try:
        props = api_call("/props", timeout=10)
        tool_template = props.get("chat_template_tool_use")
        base_template = props.get("chat_template")
        selected = tool_template or base_template or ""
        selected_text = (
            selected if isinstance(selected, str)
            else json.dumps(selected, ensure_ascii=False)
        ).lower()
        if tool_template or "tool" in selected_text or "function" in selected_text:
            log("Server tool template: ready for native function calls")
        elif selected:
            log(
                "Server tool template: base template loaded, but /props did not "
                "advertise an explicit tool-use template"
            )
        else:
            log(
                "Server tool template: /props exposed no chat template; native "
                "tool calls may require a different model template"
            )
    except Exception as exc:
        log(
            "Server tool template check unavailable: "
            + _one_line(str(exc), 240)
        )

def context_char_budget():
    """Max conversation chars so system prompt + conversation + response all
    fit in the model's context (keeps long chats working flawlessly)."""
    reserve = 2300  # tokens for the system prompt + persistent memory + margin
    per_token = 3.5  # conservative chars per token
    calculated = max(
        8000,
        int((CONTEXT_TOKENS - reserve - RESPONSE_MAX_TOKENS) * per_token),
    )
    # Capacity is not the same as usable interactive latency. Keep the default
    # working set compact for large local models while allowing an explicit
    # override on machines that have measured faster prompt ingestion.
    practical = max(
        8000,
        int(os.environ.get("LLAMA_CONTEXT_CHAR_BUDGET", "32000")),
    )
    return min(calculated, practical)

def compact_message(m, limit=5000):
    """Deterministically preserve task evidence without asking the model to
    summarize itself. This cannot burn the response budget or invent facts."""
    content = m.get("content", "")
    if len(content) <= limit:
        return dict(m)
    head = content[:limit // 2]
    tail = content[-limit // 2:]
    out = dict(m)
    out["content"] = head + "\n...[middle omitted by context manager]...\n" + tail
    return out

def compact_text(text, limit=6000):
    text = text or ""
    if len(text) <= limit:
        return text
    half = max(1, limit // 2)
    return (
        text[:half]
        + "\n...[middle preserved in the durable task checkpoint]...\n"
        + text[-half:]
    )

def normalize_unified_diff_hunks(patch):
    """Correct only hunk line counts; paths and edited content stay unchanged."""
    lines = patch.splitlines(keepends=True)
    cwd_prefix = Path.cwd().name + "/"
    for index, line in enumerate(lines):
        if line.startswith(("--- ", "+++ ")):
            marker, raw = line[:4], line[4:]
            newline = "\n" if raw.endswith("\n") else ""
            path = raw.rstrip("\r\n").split("\t", 1)[0]
            git_prefix = path[:2] if path.startswith(("a/", "b/")) else ""
            relative = path[2:] if git_prefix else path
            if relative.startswith(cwd_prefix):
                candidate = relative[len(cwd_prefix):]
                if Path(candidate).exists():
                    lines[index] = marker + git_prefix + candidate + newline
        elif line.startswith("diff --git "):
            parts = line.rstrip("\r\n").split()
            if len(parts) == 4:
                rewritten = []
                for path in parts[2:]:
                    git_prefix = path[:2] if path.startswith(("a/", "b/")) else ""
                    relative = path[2:] if git_prefix else path
                    candidate = (
                        relative[len(cwd_prefix):]
                        if relative.startswith(cwd_prefix) else relative
                    )
                    rewritten.append(
                        git_prefix + candidate if Path(candidate).exists() else path
                    )
                newline = "\n" if line.endswith("\n") else ""
                lines[index] = f"diff --git {rewritten[0]} {rewritten[1]}{newline}"
    header_re = re.compile(
        r"^@@ -(?P<old_start>\d+)(?:,(?P<old_count>\d+))? "
        r"\+(?P<new_start>\d+)(?:,(?P<new_count>\d+))? @@(?P<label>.*)"
    )
    index = 0
    while index < len(lines):
        match = header_re.match(lines[index].rstrip("\r\n"))
        if not match:
            index += 1
            continue
        end = index + 1
        declared_old = int(match.group("old_count") or 1)
        declared_new = int(match.group("new_count") or 1)
        bare_indexes = []
        known_old = 0
        known_new = 0
        while end < len(lines):
            line = lines[end]
            if line.startswith(("@@ ", "diff --git ", "--- ")):
                break
            if line.startswith("\\ No newline at end of file"):
                end += 1
                continue
            if line.startswith((" ", "-")):
                known_old += 1
            if line.startswith((" ", "+")):
                known_new += 1
            if not line.startswith((" ", "-", "+", "\\")):
                bare_indexes.append(end)
            end += 1
        old_needed = declared_old - known_old
        new_needed = declared_new - known_new
        bare_count = len(bare_indexes)
        inferred_prefix = None
        if bare_count and old_needed == bare_count and new_needed == bare_count:
            inferred_prefix = " "
        elif bare_count and old_needed == 0 and new_needed == bare_count:
            inferred_prefix = "+"
        elif bare_count and new_needed == 0 and old_needed == bare_count:
            inferred_prefix = "-"
        elif bare_count:
            # A bare line is never valid inside a unified-diff hunk. Models
            # commonly omit the single context-space while preserving +/-.
            inferred_prefix = " "
        if inferred_prefix:
            for bare_index in bare_indexes:
                lines[bare_index] = inferred_prefix + lines[bare_index]
        old_count = 0
        new_count = 0
        for line in lines[index + 1:end]:
            if line.startswith("\\ No newline at end of file"):
                continue
            if line.startswith((" ", "-")):
                old_count += 1
            if line.startswith((" ", "+")):
                new_count += 1
        old_part = (
            match.group("old_start") if old_count == 1
            else f"{match.group('old_start')},{old_count}"
        )
        new_part = (
            match.group("new_start") if new_count == 1
            else f"{match.group('new_start')},{new_count}"
        )
        newline = "\n" if lines[index].endswith("\n") else ""
        lines[index] = (
            f"@@ -{old_part} +{new_part} @@{match.group('label')}{newline}"
        )
        index = end
    return "".join(lines)

def sanitize_native_tool_history(conv):
    """Demote malformed native calls to bounded non-executable evidence."""
    cleaned = []
    invalid_ids = set()
    for message in conv:
        if message.get("role") == "assistant" and message.get("tool_calls"):
            valid_calls = []
            invalid_evidence = []
            for tool_call in message.get("tool_calls") or []:
                tool_id = tool_call.get("id")
                function = tool_call.get("function") or {}
                arguments = function.get("arguments", "{}")
                try:
                    parsed = (
                        json.loads(arguments)
                        if isinstance(arguments, str) else arguments
                    )
                    valid = (
                        isinstance(parsed, dict)
                        and bool(function.get("name"))
                    )
                except (TypeError, ValueError, json.JSONDecodeError):
                    valid = False
                if valid:
                    valid_calls.append(tool_call)
                else:
                    if tool_id:
                        invalid_ids.add(tool_id)
                    invalid_evidence.append(
                        "[INVALID TOOL CALL PRESERVED AS DATA] "
                        f"name={_one_line(str(function.get('name') or 'unnamed'), 80)} "
                        f"id={_one_line(str(tool_id or 'missing'), 80)} "
                        f"arguments={_one_line(str(arguments), 500)}"
                    )
            repaired = dict(message)
            if valid_calls:
                repaired["tool_calls"] = valid_calls
            else:
                repaired.pop("tool_calls", None)
            if invalid_evidence:
                existing_content = (repaired.get("content") or "").strip()
                repaired["content"] = "\n".join(
                    ([existing_content] if existing_content else [])
                    + invalid_evidence
                )
            if repaired.get("content") or valid_calls:
                cleaned.append(repaired)
            continue
        if (
            message.get("role") == "tool"
            and message.get("tool_call_id") in invalid_ids
        ):
            continue
        cleaned.append(message)
    return cleaned

def trim_conversation(conv, task_state=None):
    """Keep the conversation under the context budget.

    Keep the original user objective, recent tool evidence and latest turns.
    Never recursively call the model during compaction.
    """
    synthetic_failure_notice = (
        "The previous model stream failed before producing a usable action"
    )
    conv = sanitize_native_tool_history(conv)
    conv = [
        message for message in conv
        if synthetic_failure_notice not in (message.get("content") or "")
    ]
    deduplicated = []
    for message in conv:
        fingerprint = (
            message.get("role"),
            message.get("content") or "",
            json.dumps(message.get("tool_calls") or [], sort_keys=True),
        )
        if deduplicated and fingerprint == deduplicated[-1][0]:
            continue
        deduplicated.append((fingerprint, message))
    conv = [message for _, message in deduplicated]
    total = sum(len(m.get("content", "")) for m in conv)
    if total <= context_char_budget() and len(conv) <= 24:
        return conv
    log(f"Context over budget ({total} chars) - compacting evidence deterministically")
    budget = context_char_budget()
    system = conv[:1]
    first_user = next((m for m in conv[1:] if m.get("role") == "user"), None)
    recent_source = conv[max(1, len(conv) - 12):]
    if task_state is not None and first_user is not None:
        recent_source = [m for m in recent_source if m is not first_user]
    while recent_source and recent_source[0].get("role") == "tool":
        recent_source.pop(0)
    recent = [compact_message(m) for m in recent_source]
    kept = system
    if task_state is not None:
        kept.append({"role": "system", "content": task_state.context_summary()})
    elif first_user and first_user not in conv[-24:]:
        kept.append(compact_message(first_user, 8000))
    kept += recent
    protected = 2 if task_state is not None else 1
    if task_state is not None and sum(
        len(m.get("content", "")) for m in kept[:protected]
    ) > budget:
        room = max(2000, budget - len(system[0].get("content", "")) - 500)
        kept[1]["content"] = compact_text(kept[1]["content"], room)
    while sum(len(m.get("content", "")) for m in kept) > budget and len(kept) > protected:
        # Remove the oldest complete interaction block. Never leave a native
        # assistant tool call without its following tool-result messages.
        index = protected
        if index >= len(kept):
            break
        if kept[index].get("role") == "assistant" and kept[index].get("tool_calls"):
            kept.pop(index)
            while index < len(kept) and kept[index].get("role") == "tool":
                kept.pop(index)
        elif kept[index].get("role") == "tool":
            while index < len(kept) and kept[index].get("role") == "tool":
                kept.pop(index)
        else:
            kept.pop(index)
    return kept

# ─── Persistent memory (cross-session) ─────────────────────────────────────

def load_memory():
    """Return the persistent memory file contents, or empty string."""
    p = LOG_DIR / "memory.md"
    if p.exists():
        try:
            text = p.read_text(errors="replace")
            return text[-3000:]  # keep the most recent 3K chars (fits the context)
        except Exception:
            return ""
    return ""

def save_memory(entry):
    """Append one fact to persistent memory, keeping the file bounded."""
    if not entry:
        return
    p = LOG_DIR / "memory.md"
    try:
        lines = p.read_text(errors="replace").splitlines() if p.exists() else []
        lines.append(entry)
        if len(lines) > 400:
            lines = lines[-400:]
        p.write_text("\n".join(lines) + "\n")
    except Exception:
        pass

def extract_memory_entries(text):
    """Pull [MEMORY]...[/MEMORY] blocks the model wrote into its answer."""
    entries = []
    for m in re.finditer(r'\[MEMORY\](.*?)\[/MEMORY\]', text, re.DOTALL):
        e = m.group(1).strip()
        if e and len(e) < 600:
            entries.append(e)
    return entries

def direct_largest_files_request(user_message):
    """Return (drive, count) for an unambiguous read-only largest-file request."""
    text = " ".join((user_message or "").split())
    low = text.lower()
    if "file" not in low or not any(
        word in low for word in ("largest", "biggest", "heaviest")
    ):
        return None
    if any(
        re.search(rf"\b{verb}\b", low)
        for verb in (
            "delete", "remove", "move", "rename", "compress", "archive",
            "change", "edit", "modify", "replace",
        )
    ):
        return None
    drive_match = re.search(
        r"\b([A-Za-z])\s*(?::|[-\s]?drive)\b",
        text,
        re.IGNORECASE,
    )
    drive = drive_match.group(1).upper() if drive_match else "C"
    count_match = re.search(r"\btop(?:\s+of)?\s+(\d+)\b", low)
    if not count_match:
        count_match = re.search(
            r"\b(\d+)\s+(?:largest|biggest|heaviest)\s+files?\b",
            low,
        )
    count = int(count_match.group(1)) if count_match else 50
    return drive, max(1, min(200, count))


_SPOKEN_WINDOWS_DRIVES = {
    "see": "C", "sea": "C", "dee": "D", "ee": "E", "eff": "F",
    "gee": "G", "aitch": "H", "eye": "I", "jay": "J", "kay": "K",
    "el": "L", "em": "M", "en": "N", "oh": "O", "pee": "P",
    "cue": "Q", "queue": "Q", "are": "R", "air": "R", "ess": "S",
    "tee": "T", "tea": "T", "you": "U", "vee": "V",
    "doubleyou": "W", "double-u": "W", "ex": "X", "why": "Y",
    "zee": "Z", "zed": "Z",
}


def normalize_windows_drive(value, allow_all=False):
    """Normalize one literal or speech-to-text Windows drive token."""
    token = re.sub(r"\s+", "", str(value or "")).strip().rstrip(":").lower()
    if allow_all and token == "all":
        return "ALL"
    if re.fullmatch(r"[a-z]", token):
        return token.upper()
    return _SPOKEN_WINDOWS_DRIVES.get(token)


def extract_windows_drive(user_message, default=None, allow_all=False):
    """Extract the complete token before 'drive'; never take one letter from a word."""
    text = " ".join((user_message or "").split())
    literal = re.search(r"\b([A-Za-z])\s*:\s*(?:\\|/)?", text)
    if literal:
        return literal.group(1).upper()
    named = re.search(
        r"\b([A-Za-z]+(?:-[A-Za-z]+)?)\s+(?:disk|drive)\b",
        text,
        re.IGNORECASE,
    )
    if named:
        return normalize_windows_drive(named.group(1), allow_all=allow_all)
    return default


def direct_drive_listing_request(user_message):
    """Return a drive for an unambiguous read-only top-level folder listing."""
    text = " ".join((user_message or "").split())
    low = text.lower()
    if not any(word in low for word in ("folder", "folders", "director", "directories")):
        return None
    if not any(word in low for word in ("list", "show", "output", "display", "what")):
        return None
    if any(
        re.search(rf"\b{verb}\b", low)
        for verb in (
            "delete", "remove", "move", "rename", "create", "write", "edit",
            "modify", "replace", "compress", "archive",
        )
    ):
        return None
    return extract_windows_drive(text)


def response_delegates_action_to_user(content):
    """Reject permission-seeking or instructional handoffs for executable work."""
    low = " ".join((content or "").lower().split())
    return any(re.search(pattern, low) for pattern in (
        r"\bwould you like me to\b",
        r"\bdo you want me to\b",
        r"\bshall i\b",
        r"\byou can (?:run|execute|try|open|install|create|edit|delete)\b",
        r"\bplease (?:run|execute|try|open|install|create|edit|delete)\b",
        r"\btry running\b",
        r"\brun the following\b",
        r"\byou(?:'ll| will) need to\b",
        r"\bexecute these commands\b",
    ))


def direct_exact_file_request(user_message):
    """Extract an unambiguous exact-content write/read/verify request."""
    text = user_message or ""
    low = text.lower()
    if not (
        any(word in low for word in ("create", "write", "make"))
        and "exactly" in low
        and "read" in low
        and "verif" in low
    ):
        return None
    match = re.search(
        r"\b(?:create|write|make)\s+(?:the\s+)?(?:file\s+)?(?:at\s+)?"
        r"(?P<path>.+?)\s+"
        r"(?:containing|with(?:\s+(?:the\s+)?content)?)\s+exactly\s+"
        r"(?P<content>`[^`]*`|'[^']*'|\"[^\"]*\"|.+?)"
        r"(?=,\s*(?:then\s+)?(?:read|verify|report)\b|"
        r"\s+and\s+(?:then\s+)?(?:read|verify|report)\b|$)",
        text,
        re.IGNORECASE | re.DOTALL,
    )
    if not match:
        return None
    raw_path = match.group("path").strip().strip("`\"'")
    content = match.group("content").strip()
    if (
        len(content) >= 2
        and content[0] == content[-1]
        and content[0] in "`\"'"
    ):
        content = content[1:-1]
    if not re.match(r"^(?:[A-Za-z]:[\\/]|~?/)", raw_path):
        return None
    if len(content) > MAX_WHOLE_FILE_CHARS:
        return None
    return normalize_user_path(raw_path), content


def plan_hint(user_message):
    """Return (understood_sentence, task_hint) when the request maps cleanly to a
    known tool, so the model picks the right command on the FIRST try."""
    msg = user_message.lower()
    filename = windows_filename_query(user_message)
    direct_filename_request = is_direct_windows_filename_request(user_message)
    # Never reduce a multi-step implementation request to a read-only shortcut.
    if not direct_filename_request and (
        objective_requires_verification(user_message) or (
            objective_requires_action(user_message)
            and (
                any(word in msg for word in _PROJECT_WORDS)
                or re.search(r"[A-Za-z]:\\", user_message) is not None
            )
        )
    ):
        return (None, None)
    boot_intent = is_direct_boot_inventory_request(user_message)
    ranked_intent = any(w in msg for w in ["rank", "cpu", "memory", "ram", "usage"])
    if boot_intent and ranked_intent:
        return ("Understood - you want the complete boot inventory ranked by CPU and RAM.",
                "[TASK HINT: the user wants EVERYTHING that runs at boot, ranked by CPU and RAM. Run exactly: win-tools boot. That single command already returns the full ranked report - do NOT run startup, scheduled, or services separately.]")
    if boot_intent:
        return ("Understood - you want everything configured to start with Windows.",
                "[TASK HINT: run exactly: win-tools boot - it returns the full boot inventory.]")
    if direct_filename_request:
        dm = re.search(r'([A-Za-z])\s*(?::|\s+drive)', msg)
        scope = dm.group(1).upper() if dm else "ALL"
        return (
            f"Understood - you want the full Windows path for {filename}.",
            f"[TASK HINT: run exactly: win-tools search {scope} {filename} FIRST - it emits factual live traversal checkpoints and stops as soon as that exact filename is found.]",
        )
    largest_request = direct_largest_files_request(user_message)
    if largest_request:
        drv, count = largest_request
        return (
            f"Understood - you want the {count} largest files on drive {drv}.",
            f"[TASK HINT: run exactly: win-tools files {drv} {count} - it returns files ranked by byte size.]",
        )
    listing_drive = direct_drive_listing_request(user_message)
    if listing_drive:
        return (
            f"Understood - you want the top-level folders on drive {listing_drive}.",
            f"[TASK HINT: run exactly: win-tools dir {listing_drive} FOLDERS - it lists only the live top-level folders.]",
        )
    if any(w in msg for w in ["scan", "heaviest", "biggest folder", "largest folder",
                              "disk usage", "folder size", "how big", "space used",
                              "what's taking space", "top 10", "top 5"]):
        dm = re.search(r'([A-Za-z])\s*(?::|\s+drive)', msg)
        drv = dm.group(1).upper() if dm else "C"
        return (f"Understood - you want the heaviest folders on drive {drv}.",
                f"[TASK HINT: run exactly: win-tools scan {drv} - it returns ranked folder sizes.]")
    if any(w in msg for w in ["disk space", "free space", "how much space", "storage left", "disk full"]):
        dm = re.search(r'([A-Za-z])\s*(?::|\s+drive)', msg)
        drv = dm.group(1).upper() if dm else "C"
        return (f"Understood - you want the disk space situation on drive {drv}.",
                f"[TASK HINT: run exactly: win-tools disk {drv} - it returns used/free/total.]")
    fm = re.search(r'(?:under|in|on)\s+(?:my\s+|the\s+)?([A-Za-z])\s*(?::|\s+drive)', msg)
    if fm and ("folder" in msg or "drive" in msg or "director" in msg or "ls" in msg):
        drv = fm.group(1).upper()
        return (f"Understood - you want the folders on drive {drv}.",
                f"[TASK HINT: run exactly: win-tools dir {drv}: - it lists top-level folders and files.]")
    if any(w in msg for w in ["running process", "task manager", "top processes", "processes"]):
        return ("Understood - you want the top processes by resource use.",
                "[TASK HINT: run exactly: win-tools processes - it returns top memory consumers.]")
    if any(w in msg for w in ["scheduled task", "task scheduler"]):
        return ("Understood - you want the scheduled tasks.",
                "[TASK HINT: run exactly: win-tools scheduled.]")
    if any(w in msg for w in ["clipboard", "copy to clipboard", "paste"]):
        return ("Understood - you want me to work with the Windows clipboard.",
                "[TASK HINT: run exactly: win-tools clip ...]")
    if any(w in msg for w in ["screenshot", "capture screen"]):
        return ("Understood - you want a screenshot of the Windows screen.",
                "[TASK HINT: run exactly: win-tools shot - it captures and OCRs the screen.]")
    if any(w in msg for w in ["wifi", "network", "ip address", "internet connection"]):
        return ("Understood - you want the network status.",
                "[TASK HINT: run exactly: win-tools net.]")
    if any(w in msg for w in ["gpu"]):
        return ("Understood - you want GPU information.",
                "[TASK HINT: run exactly: win-tools gpu.]")
    return (None, None)

def deterministic_boot_answer(output, user_message):
    """Render boot inventory directly from evidence for safety-sensitive
    disable/ranking requests. The model never gets a chance to invent rows."""
    rows = []
    for line in (output or "").splitlines():
        parts = line.strip().split("|")
        if len(parts) != 5 or parts[0] == "ITEM":
            continue
        try:
            cpu = float(parts[3])
            ram = float(parts[4])
        except ValueError:
            continue
        rows.append({
            "item": parts[0], "source": parts[1], "process": parts[2],
            "cpu": cpu, "ram": ram,
        })
    if not rows:
        return ("The boot scan returned no parseable inventory rows, so I am "
                "not going to guess which items are safe to disable.")
    low = user_message.lower()
    safety_filter = any(x in low for x in [
        "non-essential", "nonessential", "safe", "break something important",
        "can disable", "disable",
    ])
    shown = rows
    note = ""
    if safety_filter:
        # Resource data cannot prove disable-safety. Even third-party startup
        # apps may provide networking, security, accessibility, backup, input,
        # or automation that the user depends on. Fail closed instead of
        # presenting a plausible-looking but dangerous recommendation.
        shown = []
        note = (
            f"\n\nScanned {len(rows)} boot entries. I excluded every service "
            "and startup entry because resource usage alone cannot prove that "
            "disabling it would not break an important system or user workflow."
        )
    if not shown:
        return (
            "No boot item can be confidently recommended for disabling from "
            "the verified scan. All returned entries are Windows services or "
            "otherwise lack enough evidence to prove disabling them would not "
            f"break something important.{note}"
        )
    shown.sort(key=lambda r: (-r["cpu"], -r["ram"], r["item"].lower()))
    lines = ["Verified boot items ranked by current CPU, then RAM:", ""]
    for i, r in enumerate(shown, 1):
        cpu = int(r["cpu"]) if r["cpu"].is_integer() else r["cpu"]
        ram = int(r["ram"]) if r["ram"].is_integer() else r["ram"]
        lines.append(
            f"{i}. {r['item']} | {r['source']} | {r['process']} | "
            f"{cpu} CPU seconds | {ram} MB RAM"
        )
    lines.append(
        "\nCPU is cumulative since boot. RAM is current. Values are reported "
        "only from the live Windows scan."
    )
    return "\n".join(lines) + note

def deterministic_filename_answer(output, requested_filename):
    """Return only verified exact paths from the Windows scanner."""
    paths = []
    for line in (output or "").splitlines():
        if not line.startswith("MATCH|"):
            continue
        parts = line.split("|", 2)
        if len(parts) >= 2 and parts[1].strip():
            paths.append(parts[1].strip())
    paths = list(dict.fromkeys(paths))
    if not paths:
        return (
            f"No exact Windows filename match was found for "
            f"{requested_filename} in the scanned scope."
        )
    if len(paths) == 1:
        return f"The full path is:\n{paths[0]}"
    return "The verified full paths are:\n" + "\n".join(paths)


def deterministic_largest_files_answer(output, drive, requested_count):
    """Render the measured Windows file ranking without another model round."""
    rows = []
    for line in (output or "").splitlines():
        parts = line.strip().rsplit("|", 2)
        if len(parts) != 3:
            continue
        path, byte_text, human_size = parts
        try:
            byte_size = int(byte_text)
        except ValueError:
            continue
        if not re.match(r"^[A-Za-z]:\\", path):
            continue
        rows.append((path, byte_size, human_size))
    rows.sort(key=lambda item: (-item[1], item[0].lower()))
    rows = rows[:max(1, int(requested_count))]
    if not rows:
        return (
            f"The scan of drive {drive} did not return any measurable file rows, "
            "so no ranking can be reported."
        )
    lines = [
        f"Verified {len(rows)} largest files on drive {drive}, ranked by actual byte size:",
        "",
    ]
    for index, (path, byte_size, human_size) in enumerate(rows, 1):
        lines.append(
            f"{index}. {human_size} ({byte_size:,} bytes) | {path}"
        )
    return "\n".join(lines)


def deterministic_drive_listing_answer(output, drive):
    """Render only verified folder rows for a direct folder-list request."""
    folders = []
    for line in (output or "").splitlines():
        parts = line.strip().split("|", 2)
        if len(parts) == 3 and parts[0] == "FOLDER" and parts[1].strip():
            folders.append((parts[1].strip(), parts[2].strip()))
    if not folders:
        return f"Drive {drive}: is available, but no top-level folders were returned."
    lines = [f"Top-level folders on drive {drive}:", ""]
    for index, (name, last_write) in enumerate(folders, 1):
        lines.append(f"{index}. {name} | last changed {last_write}")
    return "\n".join(lines)


def deterministic_exact_file_answer(path, content):
    """Report only the exact read-back facts, without model-added claims."""
    return (
        "Verified the file by reading it back after the write.\n"
        f"Full path: {path}\n"
        f"Content: {content}"
    )


def _without_task_markers(text):
    return re.sub(
        r"(?im)^\s*\[(?:TASK_COMPLETE|TASK_BLOCKED)\]\s*$", "", text or ""
    ).strip()

def accept_marker_only_completion(state, content, gaps):
    """Do not spend another model round repeating an otherwise complete answer."""
    marker_gap = "the final completion marker is missing"
    if content.strip() and gaps == [marker_gap]:
        state.record(
            "completion-marker-repaired",
            "the harness supplied the internal completion marker without regenerating the answer",
        )
        return []
    return gaps

def register_completion_rejection(state, gaps):
    """Count one no-action response and produce a unique factual recovery status."""
    signature = "\n".join(gaps)
    if signature == state.last_completion_rejection:
        state.completion_rejection_repeats += 1
    else:
        state.last_completion_rejection = signature
        state.completion_rejection_repeats = 1
    state.total_completion_rejections += 1
    repeat = state.completion_rejection_repeats
    return repeat, (
        f"No-action recovery {state.total_completion_rejections}, occurrence "
        f"{repeat} for these unchanged unfinished requirements: "
        f"{'; '.join(gaps)}. The checkpoint currently records "
        f"{state.mutations} modification(s) and {state.verifications} "
        f"verification(s)."
    )

def _agent_turn_active(user_message, conversation, resume_payload=None):
    """Run until the objective passes deterministic completion gates."""
    global CURRENT_TASK_STATE, CURRENT_CONVERSATION
    original_objective = (
        resume_payload.get("objective") if resume_payload else user_message
    )
    state = TaskState(original_objective, restored=resume_payload)
    state.status = "running"
    plan = TaskPlan(original_objective)
    CURRENT_TASK_STATE = state
    CURRENT_CONVERSATION = conversation

    try:
        if resume_payload:
            print(
                f"  \033[1;35m[RESUMING]\033[0m Restoring task {state.task_id} "
                f"from round {state.round} with {state.successful_actions} successful action(s)."
            )
            state.record("resume", "restored the unfinished task from its durable checkpoint")
        else:
            understood, hint = plan_hint(original_objective)
            model_message = original_objective
            if understood:
                print(f"  \033[1;35m{understood}\033[0m")
                model_message += "\n\n" + hint
            conversation.append({"role": "user", "content": model_message})
            state.record("start", "accepted the complete user objective")
            checkpoint_task(state, conversation)

            exact_file_request = direct_exact_file_request(original_objective)
            if exact_file_request:
                requested_path, requested_content = exact_file_request
                resolved_path = str(Path(requested_path).expanduser().resolve())
                print(
                    "  \033[1;35mUnderstood - writing the exact requested "
                    f"content to {resolved_path}, then reading it back.\033[0m"
                )
                write_call = {
                    "type": "write",
                    "path": resolved_path,
                    "content": requested_content,
                }
                print(f"  \033[0;36m{narrate(write_call)}\033[0m")
                state.begin_tool(write_call, original_objective)
                checkpoint_task(state, conversation)
                write_result = execute_tool_call(write_call, original_objective)
                write_success, _ = state.observe_tool(
                    write_call, write_result, original_objective
                )
                checkpoint_task(state, conversation)
                print(
                    f"    \033[0;36m"
                    f"{interpret_result(write_call, write_result)}\033[0m"
                )
                exact_already_present = write_result.lower().startswith(
                    "[no change:"
                )
                if write_success or exact_already_present:
                    read_call = {"type": "read", "path": resolved_path}
                    print(f"  \033[0;36m{narrate(read_call)}\033[0m")
                    state.begin_tool(read_call, original_objective)
                    checkpoint_task(state, conversation)
                    read_result = execute_tool_call(
                        read_call, original_objective
                    )
                    read_success, _ = state.observe_tool(
                        read_call, read_result, original_objective
                    )
                    checkpoint_task(state, conversation)
                    print(
                        f"    \033[0;36m"
                        f"{interpret_result(read_call, read_result)}\033[0m"
                    )
                    if read_success and read_result == requested_content:
                        state.record(
                            "exact-content-verification",
                            (
                                f"read-back matched {len(requested_content)} "
                                f"characters at {resolved_path}"
                            ),
                            True,
                        )
                        plan.done(1, "the exact destination was resolved")
                        plan.done(2, "the requested content is in place")
                        plan.done(3, "the file was read back byte-for-byte")
                        plan.done(4, "the verified path and content are ready")
                        answer = deterministic_exact_file_answer(
                            resolved_path, requested_content
                        )
                        conversation.append(
                            {"role": "assistant", "content": answer}
                        )
                        finish_task(state, conversation)
                        CURRENT_TASK_STATE = None
                        CURRENT_CONVERSATION = None
                        return answer
                conversation.append({
                    "role": "system",
                    "content": (
                        "[DETERMINISTIC EXACT-CONTENT ATTEMPT FAILED]\n"
                        f"Write result: {_one_line(write_result, 1000)}\n"
                        "Continue with the full tool loop, diagnose the concrete "
                        "failure, and verify the exact requested bytes."
                    ),
                })
                checkpoint_task(state, conversation)

            for call in objective_exact_line_patch_calls(original_objective):
                detail = call.get("objective_literal_repair", "explicit line repair")
                print(
                    "  \033[1;35m[EXACT INTENT]\033[0m "
                    f"Applying the uniquely verified objective repair: {detail}"
                )
                print(f"  \033[0;36m{narrate(call)}\033[0m")
                seeded = execute_tool_call(call, original_objective)
                success, _ = state.observe_tool(
                    call, seeded, original_objective
                )
                conversation.append({
                    "role": "system",
                    "content": (
                        "[EXACT OBJECTIVE REPAIR RESULT]\n"
                        f"Requested repair: {detail}\n"
                        f"Execution result: {_one_line(seeded, 1200)}\n"
                        "This exact repair is already reconciled. Do not repeat "
                        "it; run the next requested verification against current bytes."
                    ),
                })
                checkpoint_task(state, conversation)
                print(f"    \033[0;36m{interpret_result(call, seeded)}\033[0m")
                if success:
                    plan.done(2, "an explicit exact-line objective repair completed")

            requested_filename = windows_filename_query(original_objective)
            if (
                requested_filename
                and hint
                and is_direct_windows_filename_request(original_objective)
            ):
                dm = re.search(
                    r"([A-Za-z])\s*(?::|\s+drive)",
                    original_objective,
                    re.IGNORECASE,
                )
                scope = dm.group(1).upper() if dm else "ALL"
                exact = (
                    f"win-tools search {scope} "
                    f"{shlex.quote(requested_filename)} FIRST"
                )
                call = {"type": "command", "cmd": exact}
                print(f"  \033[0;36m{narrate(call)}\033[0m")
                print(f"  \033[0;33m$ {exact}\033[0m")
                state.begin_tool(call, original_objective)
                checkpoint_task(state, conversation)
                seeded = execute_tool_call(call, original_objective)
                success, _ = state.observe_tool(call, seeded, original_objective)
                checkpoint_task(state, conversation)
                print(f"    \033[0;36m{interpret_result(call, seeded)}\033[0m")
                if success:
                    answer = deterministic_filename_answer(
                        seeded,
                        requested_filename,
                    )
                    plan.done(1, "the exact filename search completed")
                    plan.done(2, "the requested read-only lookup completed")
                    plan.done(3, "the returned path was parsed directly from live evidence")
                    plan.done(4, "the verified exact path is ready")
                    conversation.append({"role": "assistant", "content": answer})
                    finish_task(state, conversation)
                    CURRENT_TASK_STATE = None
                    CURRENT_CONVERSATION = None
                    return answer
                conversation.append({
                    "role": "user",
                    "content": (
                        "[The deterministic exact-filename lookup failed. Diagnose "
                        "that concrete failure and continue with a materially different "
                        "read-only search method.]\n" + seeded
                    ),
                })
                checkpoint_task(state, conversation)

            largest_request = direct_largest_files_request(original_objective)
            if largest_request:
                drive, count = largest_request
                exact = f"win-tools files {drive} {count}"
                call = {"type": "command", "cmd": exact}
                print(f"  \033[0;36m{narrate(call)}\033[0m")
                print(f"  \033[0;33m$ {exact}\033[0m")
                state.begin_tool(call, original_objective)
                checkpoint_task(state, conversation)
                seeded = execute_tool_call(call, original_objective)
                success, _ = state.observe_tool(
                    call, seeded, original_objective
                )
                checkpoint_task(state, conversation)
                print(f"    \033[0;36m{interpret_result(call, seeded)}\033[0m")
                if success:
                    answer = deterministic_largest_files_answer(
                        seeded, drive, count
                    )
                    conversation.append({"role": "assistant", "content": answer})
                    finish_task(state, conversation)
                    CURRENT_TASK_STATE = None
                    CURRENT_CONVERSATION = None
                    return answer
                conversation.append({
                    "role": "user",
                    "content": (
                        "[The direct largest-file scan failed. Diagnose that exact "
                        "failure and continue with a materially different read-only "
                        "method.]\n" + seeded
                    ),
                })
                checkpoint_task(state, conversation)

            listing_drive = direct_drive_listing_request(original_objective)
            if listing_drive:
                exact = f"win-tools dir {listing_drive} FOLDERS"
                call = {"type": "command", "cmd": exact}
                print(f"  \033[0;36m{narrate(call)}\033[0m")
                print(f"  \033[0;33m$ {exact}\033[0m")
                state.begin_tool(call, original_objective)
                checkpoint_task(state, conversation)
                seeded = execute_tool_call(call, original_objective)
                success, _ = state.observe_tool(
                    call, seeded, original_objective
                )
                checkpoint_task(state, conversation)
                if success:
                    print(f"    \033[0;36m{interpret_result(call, seeded)}\033[0m")
                    answer = deterministic_drive_listing_answer(
                        seeded, listing_drive
                    )
                    plan.done(1, "the requested live drive listing was collected")
                    plan.done(2, "the read-only folder inspection completed")
                    plan.done(3, "the folder rows were parsed from live evidence")
                    plan.done(4, "the verified folder list is ready")
                    conversation.append({"role": "assistant", "content": answer})
                    finish_task(state, conversation)
                    CURRENT_TASK_STATE = None
                    CURRENT_CONVERSATION = None
                    return answer
                answer = f"Drive {listing_drive}: is not available to list."
                conversation.append({"role": "assistant", "content": answer})
                finish_task(state, conversation)
                CURRENT_TASK_STATE = None
                CURRENT_CONVERSATION = None
                return answer

            # Only a direct read-only inventory request may use deterministic
            # pre-execution. Project/build requests always go through the full loop.
            exact_match = re.search(
                r"run exactly:\s*(win-tools\s+[a-z]+(?:\s+[A-Za-z]:?)?)",
                hint or "", re.IGNORECASE,
            )
            if exact_match and is_direct_boot_inventory_request(original_objective):
                exact = exact_match.group(1).strip()
                call = {"type": "command", "cmd": exact}
                print(f"  \033[0;36m{narrate(call)}\033[0m")
                print(f"  \033[0;33m$ {exact}\033[0m")
                seeded = execute_tool_call(call, original_objective)
                state.observe_tool(call, seeded, original_objective)
                checkpoint_task(state, conversation)
                if len(seeded) > 40000:
                    seeded = seeded[:20000] + "\n... [middle omitted] ...\n" + seeded[-20000:]
                print(f"    \033[0;36m{interpret_result(call, seeded)}\033[0m")
                plan.done(1, "the requested live inventory was collected")
                plan.done(2, "the read-only inspection completed")
                if exact.lower() == "win-tools boot" and not _tool_failed(seeded):
                    answer = deterministic_boot_answer(seeded, original_objective)
                    plan.done(3, "the returned rows were parsed directly")
                    plan.done(4, "the verified inventory answer is ready")
                    conversation.append({"role": "assistant", "content": answer})
                    finish_task(state, conversation)
                    CURRENT_TASK_STATE = None
                    CURRENT_CONVERSATION = None
                    return answer
                conversation.append({
                    "role": "user",
                    "content": (
                        "[Verified tool result already collected. Use this evidence; "
                        "do not rerun the command.]\n" + seeded
                    ),
                })
                checkpoint_task(state, conversation)

        if not model_server_healthy():
            ensure_model_server_until_ready(state, conversation)

        while True:
            # Reconcile interrupted mutations and verification pressure before
            # asking the model. Both need fresh target-specific evidence; model
            # prose alone cannot clear either durable guard.
            checkpoint_kind = ""
            if state.pending_reconciliation:
                checkpoint_kind = "reconciliation"
            elif state.verification_due():
                checkpoint_kind = "verification"
            if checkpoint_kind:
                checkpoint_call = automatic_verification_checkpoint_call(
                    original_objective
                )
                checkpoint_label = (
                    "Reconciling the interrupted action against the actual "
                    "target before any new write."
                    if checkpoint_kind == "reconciliation" else
                    "Verification pressure is active; Nature is collecting a "
                    "read-only workspace checkpoint before the next action."
                )
                print(
                    "  \033[1;33m[RECONCILING]\033[0m "
                    + checkpoint_label
                )
                state.begin_tool(checkpoint_call, original_objective)
                checkpoint_task(state, conversation)
                checkpoint_result = execute_tool_call(
                    checkpoint_call, original_objective
                )
                checkpoint_success, _ = state.observe_tool(
                    checkpoint_call, checkpoint_result, original_objective
                )
                state.record(
                    f"automatic-{checkpoint_kind}-checkpoint",
                    (
                        "fresh bounded target evidence collected before "
                        "requesting another action"
                        if checkpoint_success else
                        "the automatic target checkpoint failed"
                    ),
                    checkpoint_success,
                )
                checkpoint_task(state, conversation)
                if checkpoint_success:
                    plan.done(1, "fresh target evidence was collected")
                    conversation.append({
                        "role": "system",
                        "content": (
                            (
                                "[AUTOMATIC RECONCILIATION CHECKPOINT]\n"
                                "Nature reconciled an interrupted action against "
                                "the requested target. Do not replay its exact "
                                "write; use this evidence to repair or verify the "
                                "existing project."
                                if checkpoint_kind == "reconciliation" else
                                "[AUTOMATIC VERIFICATION CHECKPOINT]\n"
                                "Nature collected a bounded read-only target "
                                "snapshot because prior modifications required "
                                "fresh evidence. Use it to choose the next "
                                "concrete action. After the next mutation, run a "
                                "target-specific test or readback before completion."
                            )
                            + "\n\n"
                            f"{checkpoint_result}"
                        ),
                    })
                    # Start the next round with the durable uncertainty cleared
                    # and the reconciliation result compacted into context.
                    if checkpoint_kind == "reconciliation":
                        continue
                else:
                    conversation.append({
                        "role": "system",
                        "content": (
                            "[TARGET CHECKPOINT FAILED]\n"
                            "The automatic read-only target checkpoint failed. "
                            "Diagnose and repair this environment before "
                            "attempting any modifying action.\n\n"
                            f"{checkpoint_result}"
                        ),
                    })
                    wait_with_progress(
                        2,
                        "The automatic target checkpoint failed; preserving the task before retrying it",
                    )
                    continue
            if (
                state.verification_due()
                and state.verification_pressure_at_mutation != state.mutations
            ):
                pending = state.mutations - state.verified_mutation_count
                state.verification_pressure_at_mutation = state.mutations
                state.record(
                    "verification-pressure",
                    (
                        f"{pending} modifications accumulated since the last "
                        "verification; require a test or readback before more writes"
                    ),
                    False,
                )
                conversation.append({
                    "role": "system",
                    "content": (
                        f"[VERIFY NOW] {pending} successful modifications have "
                        "accumulated since the last verification. The next tool "
                        "must be a read-only file read or a non-mutating test, "
                        "syntax check, build check, hash, diff, or status command. "
                        "Do not write, append, patch, install, or modify anything "
                        "until that verification succeeds."
                    ),
                })
            if (
                state.requires_action
                and state.mutations == 0
                and state.verifications >= 12
                and not any(
                    event.get("kind") == "action-pressure"
                    for event in state.events
                )
            ):
                state.record(
                    "action-pressure",
                    "read-only evidence threshold reached; require a focused mutation next",
                    False,
                )
                conversation.append({
                    "role": "system",
                    "content": (
                        "[ACTION REQUIRED NOW] You have already collected ample "
                        "read-only evidence. Do not inspect or reread another file. "
                        "Use apply_patch for one focused root-cause repair now. If "
                        "a mutation is genuinely impossible, run only the single "
                        "command needed to prove the exact blocker."
                    ),
                })
            # Compact before every request, especially the first request after
            # restoring a durable checkpoint created by an older runtime.
            conversation = trim_conversation(conversation, state)
            checkpoint_task(state, conversation)
            state.round += 1
            state.record("round", f"starting action round {state.round}")
            checkpoint_task(state, conversation)
            selected_tools = select_tools(original_objective)
            verification_pressure_active = state.verification_due()
            if verification_pressure_active:
                selected_tools = [
                    tool for tool in selected_tools
                    if tool["function"]["name"] in {
                        "run_command", "read_file",
                    }
                ]
            elif (
                state.requires_action
                and (
                    (state.mutations == 0 and state.verifications >= 12)
                    or (
                        state.mutations > 0
                        and state.sequence - state.last_mutation_sequence >= 12
                    )
                )
                and state.no_progress_rounds < 3
            ):
                selected_tools = [
                    tool for tool in selected_tools
                    if tool["function"]["name"] in {
                        "run_command", "run_python", "write_file",
                        "append_file", "apply_patch",
                    }
                ]
            state.record(
                "tool-routing",
                "exposed " + ", ".join(
                    item["function"]["name"] for item in selected_tools
                ),
            )
            action_pressure_active = (
                verification_pressure_active
                or (
                state.requires_action
                and (
                    (state.mutations == 0 and state.verifications >= 12)
                    or (
                        state.mutations > 0
                        and state.sequence - state.last_mutation_sequence >= 12
                    )
                )
                and state.no_progress_rounds < 3
                )
            )
            result = send_message(
                conversation,
                tools=selected_tools,
                max_tokens=FOCUSED_ACTION_MAX_TOKENS if action_pressure_active else None,
            )

            if result.get("error"):
                recovered_call = recover_malformed_read_call(result["error"])
                if recovered_call:
                    print(
                        "  \033[1;33m[RECOVERING]\033[0m The model encoded a read "
                        "request as malformed JSON. Nature recovered the exact "
                        "read-only path and is executing it through the guarded tool."
                    )
                    print(f"  \033[0;36m{narrate(recovered_call)}\033[0m")
                    recovered_result = execute_tool_call(
                        recovered_call, original_objective
                    )
                    state.observe_tool(
                        recovered_call, recovered_result, original_objective
                    )
                    state.record(
                        "malformed-tool-recovery",
                        f"recovered guarded read of {recovered_call['path']}",
                        not _tool_failed(recovered_result),
                    )
                    conversation.append({
                        "role": "user",
                        "content": (
                            "[RECOVERED READ-ONLY TOOL RESULT]\n"
                            "Your malformed JSON was not executed. Nature safely "
                            "recovered the unambiguous read request below. Use this "
                            "result and continue with a valid tool call.\n\n"
                            f"Path: {recovered_call['path']}\n"
                            f"Result:\n{recovered_result}"
                        ),
                    })
                    state.model_failures = 0
                    state.status = "running"
                    conversation = trim_conversation(conversation, state)
                    checkpoint_task(state, conversation)
                    continue
                state.model_failures += 1
                state.status = "recovering"
                state.record(
                    "model-error",
                    f"model stream failed: {result['error']}",
                    False,
                )
                checkpoint_task(state, conversation)
                print(
                    f"  \033[1;33m[RECOVERING]\033[0m The model response failed "
                    f"validation ({result['error']}). The task remains checkpointed."
                )
                request_local = _model_error_is_request_local(result["error"])
                recovered = (
                    model_server_healthy()
                    if request_local else recover_model_server()
                )
                state.record(
                    "model-recovery",
                    (
                        "request-local failure; healthy server preserved"
                        if request_local and recovered else
                        "local model server is healthy again" if recovered else
                        "local model server has not recovered yet"
                    ),
                    recovered,
                )
                checkpoint_task(state, conversation)
                if not recovered:
                    wait_with_progress(
                        min(5 * state.model_failures, 30),
                        "The model server is still unavailable; keeping the task checkpoint safe",
                    )
                else:
                    state.status = "running"
                conversation.append({
                    "role": "system",
                    "content": (
                        "The previous model stream failed validation before producing "
                        "a usable action. The durable task remains active. Continue "
                        "from recorded evidence with a materially different valid "
                        "response and do not claim completion."
                    ),
                })
                conversation = trim_conversation(conversation, state)
                checkpoint_task(state, conversation)
                continue

            content = result.get("content") or ""
            finish_reason = result.get("finish_reason") or ""
            native_calls = tool_calls_to_calls(result.get("tool_calls"))
            tcalls = native_calls if native_calls else extract_tool_calls(content)
            tcalls = [
                call for call in tcalls
                if (
                    call.get("type") != "command"
                    or (call.get("cmd") or "").strip()
                )
                and (
                    call.get("type") != "write"
                    or (call.get("path") or "").strip()
                )
                and (
                    call.get("type") != "append"
                    or (call.get("path") or "").strip()
                )
                and (
                    call.get("type") != "patch"
                    or (call.get("patch") or "").strip()
                )
                and (
                    call.get("type") != "read"
                    or (call.get("path") or "").strip()
                )
                and (
                    call.get("type") != "python"
                    or (call.get("code") or "").strip()
                )
            ]

            if not tcalls:
                gaps = state.completion_gaps(content, finish_reason)
                gaps = accept_marker_only_completion(state, content, gaps)
                if not gaps:
                    final = _without_task_markers(content)
                    conversation.append({"role": "assistant", "content": final})
                    if state.successful_actions:
                        plan.done(1, "live tool evidence was collected")
                    else:
                        plan.done(1, "the response required no external evidence")
                    if state.requires_action:
                        plan.done(2, f"{state.mutations} modifying action(s) completed")
                    else:
                        plan.done(2, "the requested response is complete")
                    plan.done(3, "all deterministic completion gates passed")
                    plan.done(4, "the complete verified response is ready")
                    finish_task(state, conversation)
                    CURRENT_TASK_STATE = None
                    CURRENT_CONVERSATION = None
                    return final

                state.no_progress_rounds += 1
                rejection_repeat, rejection_status = register_completion_rejection(
                    state, gaps
                )
                state.record(
                    "completion-rejected",
                    rejection_status,
                    False,
                )
                if content.strip():
                    conversation.append({"role": "assistant", "content": content})
                print(
                    "  \033[1;33m[CONTINUING]\033[0m " + rejection_status
                )
                recovery_instruction = (
                    "[COMPLETION GATE: TASK STILL ACTIVE]\n"
                    f"No-action recovery attempt: {state.total_completion_rejections}\n"
                    f"Original objective: {state.objective}\n"
                    "Unfinished requirements:\n- " + "\n- ".join(gaps) + "\n"
                    "Continue with the next concrete tool action. Do not summarize, "
                    "stop, or repeat the same unchanged approach. After the final "
                    "modification, run a separate verification. Emit [TASK_COMPLETE] "
                    "only when every item above is actually resolved."
                )
                conversation.append({"role": "user", "content": recovery_instruction})
                if rejection_repeat % 3 == 0:
                    state.record(
                        "strategy-reset",
                        (
                            f"{rejection_repeat} identical no-action responses "
                            "triggered a compacted strategy reset"
                        ),
                        False,
                    )
                    conversation.append({
                        "role": "system",
                        "content": (
                            "[STRATEGY RESET] The prior replies produced no executable "
                            "action for the same unfinished requirements. Ignore their "
                            "wording. Select one smallest concrete tool action that "
                            "changes or verifies the requested target now."
                        ),
                    })
                if rejection_repeat % 6 == 0:
                    recover_model_server(force=True)
                conversation = trim_conversation(conversation, state)
                checkpoint_task(state, conversation)
                if rejection_repeat > 1:
                    wait_with_progress(
                        min(2 * rejection_repeat, 8),
                        (
                            f"No-action recovery {state.total_completion_rejections} "
                            "is preserving the task while the next materially "
                            "different model attempt is prepared"
                        ),
                    )
                continue

            tresults = []
            for call in tcalls:
                call = align_call_to_requested_targets(call, original_objective)
                call = repair_identical_numeric_sed_from_message(call, content)
                call = repair_missing_python_loop_variable(call, content)
                if call.get("intent_repaired"):
                    print(
                        "  \033[1;35m[INTENT CHECK]\033[0m "
                        + call["intent_repaired"]
                    )
                call_type = call.get("type", "command")
                if call_type == "command":
                    desc = "$ " + call.get("cmd", str(call))[:120]
                elif call_type == "write":
                    desc = "write -> " + call.get("path", "?")
                elif call_type == "append":
                    desc = "append -> " + call.get("path", "?")
                elif call_type == "patch":
                    desc = "apply validated patch"
                elif call_type == "read":
                    desc = "read -> " + call.get("path", "?")
                elif call_type == "mcp":
                    desc = (
                        f"mcp {call.get('server', '?')} -> "
                        f"{call.get('tool', '?')}"
                    )
                elif call_type == "invalid":
                    desc = "validation rejected this tool request; nothing will execute"
                else:
                    desc = "python script"

                print(f"  \033[0;36m{narrate(call)}\033[0m")
                print(f"  \033[0;33m{desc}\033[0m")
                if (
                    state.verification_due()
                    and not _is_verification_call(call)
                ):
                    pending = state.mutations - state.verified_mutation_count
                    result_str = (
                        "[VERIFICATION REQUIRED: "
                        f"{pending} successful modifications have accumulated "
                        "since the last verification. This non-verification action "
                        "was blocked before execution. Run a file read, test, "
                        "syntax check, hash, diff, or status command now.]"
                    )
                    state.record(
                        "verification-guard",
                        "blocked a mutation or unrelated action until fresh verification",
                        False,
                    )
                    success, repeats = False, 1
                elif state.requires_reconciliation_before(
                    call, original_objective
                ):
                    result_str = (
                        "[RECOVERY REQUIRED: A modifying action was interrupted "
                        "with an unknown outcome. Run a read-only existence, "
                        "content, status, or test check before any further "
                        "modification so the action is not duplicated.]"
                    )
                    state.record(
                        "recovery-guard",
                        "blocked a new action until the interrupted mutation is reconciled",
                        False,
                    )
                    success, repeats = False, 1
                elif state.action_was_interrupted(
                    call, original_objective
                ):
                    blocked_action = state.interrupted_action_reason(
                        call, original_objective
                    )
                    result_str = (
                        "[INTERRUPTED ACTION BLOCKED: This exact action was "
                        "interrupted or stalled earlier and was not executed "
                        f"again: {blocked_action}. Choose a materially different "
                        "command, implementation, or verification strategy now.]"
                    )
                    state.record(
                        "interrupted-action-guard",
                        (
                            "blocked exact replay of a previously interrupted "
                            f"or stalled action: {blocked_action}"
                        ),
                        False,
                    )
                    success, repeats = False, 1
                elif state.identical_result_repeats(
                    call, original_objective
                ) >= 2:
                    repeats = state.identical_result_repeats(
                        call, original_objective
                    )
                    result_str = (
                        "[LOOP GUARD: This exact action already produced the "
                        f"same result {repeats} times. It was blocked before "
                        "execution; gather fresh evidence or change strategy.]"
                    )
                    state.record(
                        "loop-guard",
                        "blocked an exact action before a third identical execution",
                        False,
                    )
                    success = False
                else:
                    state.begin_tool(call, original_objective)
                    checkpoint_task(state, conversation)
                    result_str = execute_tool_call(call, original_objective)
                    success, repeats = state.observe_tool(
                        call, result_str, original_objective
                    )
                    if success and (
                        _is_verification_call(call) or call_type == "read"
                    ):
                        plan.done(1, "fresh evidence was collected")
                    if success and _is_mutating_call(call):
                        plan.done(2, "a requested modifying action completed")
                checkpoint_task(state, conversation)
                if len(result_str) > 40000:
                    result_str = (
                        result_str[:20000]
                        + "\n... [middle omitted; full result was observed] ...\n"
                        + result_str[-20000:]
                    )
                if repeats >= 3:
                    result_str += (
                        f"\n[LOOP GUARD: This action produced the same result "
                        f"{repeats} times. Use a materially different next action.]"
                    )
                tresults.append({
                    "call": desc,
                    "output": result_str,
                    "tool_call_id": call.get("tool_call_id"),
                })
                brief = result_str[:200].replace("\n", " ")
                result_label = "OK" if success else "FAIL"
                result_color = "0;32" if success else "0;31"
                print(
                    f"    \033[{result_color}m{result_label}\033[0m "
                    f"{brief}{'...' if len(result_str) > 200 else ''}"
                )
                print(f"    \033[0;36m{interpret_result(call, result_str)}\033[0m")
            assistant_message = result.get("message")
            if assistant_message is not None and assistant_message.get("tool_calls"):
                conversation.append({
                    "role": "assistant",
                    "content": content,
                    "tool_calls": assistant_message["tool_calls"],
                })
                for tool_result in tresults:
                    if tool_result.get("tool_call_id"):
                        conversation.append({
                            "role": "tool",
                            "tool_call_id": tool_result["tool_call_id"],
                            "content": tool_result["output"],
                        })
            else:
                conversation.append({"role": "assistant", "content": content})
                results_text = "".join(
                    f"\n### {item['call']}\n```\n{item['output']}\n```\n"
                    for item in tresults
                )
                conversation.append({
                    "role": "user",
                    "content": (
                        f"[Tool Results - Round {state.round}]\n{results_text}\n"
                        "Continue the original objective. If modifications are "
                        "finished, run a separate verification after the latest one. "
                        "Only then provide the final answer ending with [TASK_COMPLETE]."
                    ),
                })
            conversation = trim_conversation(conversation, state)
            checkpoint_task(state, conversation)
    except KeyboardInterrupt:
        state.status = "interrupted"
        state.record(
            "interruption",
            "keyboard interruption received; all completed evidence was checkpointed",
            False,
        )
        checkpoint_task(state, conversation)
        print(
            "\n  \033[1;33m[PAUSED SAFELY]\033[0m The unfinished task was "
            "checkpointed. Use /resume now, or restart Nature to resume automatically."
        )
        return "[Task paused safely; no completion was claimed.]"
    except SystemExit:
        raise
    except BaseException as exc:
        state.status = "recovering"
        state.record(
            "unexpected-error",
            f"{type(exc).__name__}: {exc}",
            False,
        )
        checkpoint_task(state, conversation)
        payload = state.to_dict()
        payload["conversation"] = conversation
        return _RetryActiveTask(payload)

def agent_turn(user_message, conversation, resume_payload=None):
    """Never abandon a submitted task after an internal failure."""
    active_resume = resume_payload
    while True:
        result = _agent_turn_active(
            user_message,
            conversation,
            resume_payload=active_resume,
        )
        if not isinstance(result, _RetryActiveTask):
            return result
        active_resume = result.payload
        conversation = active_resume.get("conversation") or conversation
        wait_with_progress(
            min(5 + int(active_resume.get("model_failures", 0)) * 5, 30),
            (
                "An internal failure was checkpointed; restarting the active "
                "task from verified evidence without dropping any requirement"
            ),
        )

# ─── Input handling ─────────────────────────────────────────────────────────

def build_system_prompt():
    """System prompt + persistent memory from previous sessions."""
    mem = load_memory()
    context_parts = []
    try:
        context_paths = json.loads(CONTEXT_FILES_FILE.read_text())
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        context_paths = []
    for raw in context_paths[:40] if isinstance(context_paths, list) else []:
        path = Path(raw)
        try:
            content = path.read_text(errors="replace")
            context_parts.append(
                f"### {path}\n{compact_text(content, 8000)}"
            )
        except OSError:
            continue
    prompt = SYSTEM_PROMPT
    if mem:
        prompt += "\n\n## PERSISTENT MEMORY (facts and decisions from earlier sessions)\n" + mem
    if context_parts:
        prompt += "\n\n## PINNED PROJECT CONTEXT\n" + "\n\n".join(context_parts)
    return prompt

WORKFLOW_COMMANDS = {
    "ask": "Answer this request clearly and directly:",
    "plan": "Create a concrete, ordered implementation plan with verification criteria for:",
    "do": "Execute this task completely now, narrating progress and verifying the final result:",
    "build": "Design, implement, test, and finish this project or feature:",
    "fix": "Reproduce, diagnose the root cause, fix it, and run regression checks for:",
    "debug": "Systematically investigate this problem, gather evidence, fix the root cause, and verify:",
    "review": "Review this target for bugs, regressions, security risks, performance issues, and missing tests:",
    "test": "Run the most relevant tests, investigate failures, fix causes when requested, and report evidence for:",
    "verify": "Independently verify every stated requirement and distinguish passed, failed, blocked, and untested items for:",
    "research": "Research this thoroughly using available sources and tools, compare evidence, and provide an actionable result:",
    "explain": "Explain this accurately in plain English, including important details and examples:",
    "summarize": "Produce a concise, faithful summary of:",
    "refactor": "Refactor this while preserving behavior, then run focused regression tests:",
    "optimize": "Measure or inspect bottlenecks, optimize the highest-impact causes, and verify improvement for:",
    "secure": "Perform an authorized defensive security review, fix confirmed weaknesses, and verify the fixes for:",
    "document": "Create or update accurate, useful documentation for:",
    "lint": "Run the appropriate linters, fix confirmed issues without unrelated churn, and rerun them for:",
    "run": "Launch and exercise the actual application or project, diagnose runtime failures, and verify:",
    "map": "Inspect this project and produce a concise architecture map covering entry points, modules, data flow, and key risks:",
    "architect": "Design a robust architecture and implementation approach, then execute it when the request asks for implementation:",
    "batch": "Break this request into independent work items, execute all of them efficiently, and reconcile the results:",
    "loop": "Repeat the requested inspect-act-verify cycle until the stated success condition is truly met:",
    "undo": "Inspect the latest relevant changes, reverse only the requested work without disturbing unrelated user changes, and verify:",
    "deploy": "Prepare, deploy, and verify the requested target on every named destination:",
    "commit": "Inspect the working tree, include only relevant changes, run checks, and create a clear Git commit for:",
    "pr": "Prepare a complete pull request: review changes, test them, and write an accurate title and description for:",
    "scaffold": "Create a production-ready project skeleton using the target ecosystem's established tooling, then run it:",
    "migrate": "Plan and execute this migration with backups, compatibility checks, and post-migration verification:",
    "release": "Prepare a releasable artifact, run release checks, document changes, and verify the packaged output for:",
    "audit": "Perform a deep evidence-based audit, prioritize findings by impact, and fix confirmed issues when requested for:",
    "perf": "Benchmark the real workload, identify bottlenecks, implement measured improvements, and compare results for:",
    "data": "Inspect, clean, transform, validate, and deliver this data task with reproducible checks:",
    "database": "Design, query, migrate, optimize, or repair this database task with integrity checks:",
    "api": "Design, implement, exercise, and document this API task including failure paths:",
    "frontend": "Build or repair the complete user-facing frontend, run it, and verify desktop and mobile behavior for:",
    "backend": "Build or repair the backend, persistence, validation, errors, security, and tests for:",
    "desktop": "Build this as a native Windows-capable desktop experience, launch the actual target, and verify it:",
    "mobile": "Build or repair the requested mobile experience and verify the named device or emulator surface for:",
    "devops": "Implement and verify the requested build, container, deployment, infrastructure, or operations workflow for:",
    "media": "Inspect, create, convert, edit, or analyze the requested image, audio, or video assets and verify outputs for:",
    "document": "Create, convert, inspect, or repair the requested document with layout and content verification for:",
    "websearch": "Research the current web deeply, prefer primary sources, reconcile disagreements, and answer with source evidence for:",
    "delegate": "Split this into independent lanes, execute them in parallel where supported, reconcile all results, and finish:",
    "troubleshoot": "Reproduce the exact failure, trace it from evidence, repair the root cause, and verify the real user path for:",
    "init": "Inspect this project, discover its conventions and commands, create only genuinely useful agent guidance, and verify:",
    "readonly": "Investigate this without modifying files, settings, accounts, queues, or external state, then report evidence for:",
    "fetch": "Fetch this resource with bounded retries, validate the response, and save or analyze it as requested:",
    "translate": "Translate this faithfully while preserving meaning, terminology, structure, and requested tone:",
    "brainstorm": "Explore strong distinct approaches, compare tradeoffs, and turn the best option into an actionable next step for:",
}

COMMAND_HELP = [
    ("help [command]", "Show all commands or detailed help."),
    ("status", "Show model, server, task, context, directory, and capability status."),
    ("doctor", "Run practical health checks for the model server and core tools."),
    ("clear", "Start a fresh conversation; protected tasks must be resolved first."),
    ("reset | restart", "Restart the model server and start a fresh conversation."),
    ("resume | cancel", "Continue or explicitly abandon the checkpointed task."),
    ("tasks", "List durable task records and the active checkpoint."),
    ("history [N]", "Show the latest N conversation messages."),
    ("prompts [N]", "Show persisted prompts from all sessions."),
    ("context", "Show context usage and limits."),
    ("compact", "Compact older conversation evidence while preserving recent work."),
    ("memory [add|clear] [text]", "View, add to, or clear persistent memory."),
    ("export [path]", "Export the complete conversation as Markdown."),
    ("copy [last|code]", "Copy the latest answer or its last code block to Windows clipboard."),
    ("paste [REQUEST]", "Read Windows clipboard text and optionally ask Nature to act on it."),
    ("pwd | cd PATH | ls [PATH] | tree [PATH]", "Inspect or change the working directory."),
    ("git [args] | diff [args]", "Run Git status/commands or inspect changes."),
    ("shell COMMAND | !COMMAND", "Run a shell command with live output."),
    ("python CODE", "Run Python code with live output."),
    ("browse REQUEST", "Use verified Profile 2 URL opening; interactive control fails closed unless available."),
    ("windows REQUEST", "Ask Nature to operate Windows or the PC."),
    ("model", "Show the selected model and live server properties."),
    ("tokens | settings", "Aliases for context usage or runtime status."),
    ("logs [server|agent]", "Show recent runtime logs."),
    ("command list", "List persistent custom slash commands."),
    ("command add NAME TEMPLATE", "Create a custom command using $ARGUMENTS or $1..$9."),
    ("command remove NAME", "Delete a custom command."),
    ("tools [REQUEST]", "Show all native tools or the exact routed tools for a request."),
    ("capabilities", "Show verified, available, setup-required, and unavailable capabilities."),
    ("profile [fast|balanced|quality]", "View or select the persistent inference profile."),
    ("session", "Show the current session, task, history, and event-log locations."),
    ("checkpoint", "Write the active task checkpoint immediately."),
    ("retry", "Resume the active checkpoint or retry the latest request."),
    ("files [PATH]", "Inspect a path with bounded file metadata."),
    ("search PATTERN [PATH]", "Search file names and text with bounded output."),
    ("open PATH|URL", "Open a local path or URL with the appropriate host tool."),
    ("edit PATH REQUEST", "Ask Nature to make a focused, verified edit."),
    ("apply PATCH_FILE", "Validate and apply a unified diff file."),
    ("append PATH TEXT", "Append one bounded text chunk to a file."),
    ("browser [status|open URL]", "Inspect exact browser capability or open a URL."),
    ("vision IMAGE [REQUEST]", "Send a real image to the selected multimodal model and verify the path."),
    ("mcp [list|add|remove|tools]", "Manage trusted MCP stdio server configuration."),
    ("skills | hooks | permissions", "Inspect extensibility and effective control boundaries."),
    ("metrics | stats", "Show server metrics and durable task-event statistics."),
    ("benchmark [REQUEST]", "Run a measured performance task."),
    ("models", "List installed model, projector, and draft files."),
    ("config [show|set KEY VALUE]", "Inspect or update persistent runtime configuration."),
    ("theme [auto|dark|light|mono]", "Persist the preferred terminal rendering theme."),
    ("background REQUEST", "Run a bounded command as a logged background job."),
    ("jobs [stop ID]", "List durable background jobs or stop one exact verified process group."),
    ("selftest", "Run focused behavioral checks without starting a model task."),
    ("recap", "Summarize the current conversation and active task evidence."),
    ("add PATH", "Pin a file into project context for future sessions."),
    ("drop PATH|all", "Remove a file from persistent project context."),
    ("context-files", "List files pinned into persistent project context."),
    ("fork [path]", "Export this conversation and start a fresh branch of thought."),
    ("rewind", "Show durable task records and recent prompt history."),
    ("quit | exit | q", "Exit Nature safely."),
]
BUILTIN_COMMAND_NAMES = {
    "help", "?", "quit", "exit", "q", "clear", "resume", "continue",
    "cancel", "reset", "restart", "history", "prompts", "memory", "status",
    "doctor", "context", "tasks", "pwd", "cd", "ls", "tree", "git", "diff",
    "shell", "!", "python", "browse", "windows", "model", "logs", "export",
    "copy", "paste", "compact", "tokens", "settings", "command",
    "tools", "capabilities", "profile", "session", "checkpoint", "retry",
    "files", "search", "open", "edit", "apply", "append", "browser", "mcp",
    "vision",
    "skills", "hooks", "permissions", "metrics", "stats", "benchmark",
    "models", "config", "theme", "background", "recap",
    "jobs",
    "selftest",
    "add", "drop", "context-files", "fork", "rewind", "usage", "mode",
    "plugins", "image", "about",
}

def _split_command(text):
    body = text[1:] if text.startswith("/") else text
    name, _, args = body.strip().partition(" ")
    return name.lower(), args.strip()

def _load_custom_commands():
    try:
        data = json.loads(CUSTOM_COMMANDS_FILE.read_text())
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}

def _save_custom_commands(commands):
    _atomic_write_json(CUSTOM_COMMANDS_FILE, commands)
    try:
        os.chmod(CUSTOM_COMMANDS_FILE, 0o600)
    except OSError:
        pass

def _expand_custom_command(template, arguments):
    words = shlex.split(arguments) if arguments else []
    expanded = template.replace("$ARGUMENTS", arguments)
    for index in range(1, 10):
        value = words[index - 1] if index <= len(words) else ""
        expanded = expanded.replace(f"${index}", value)
    return expanded.strip()

def _latest_assistant_text(conversation):
    for message in reversed(conversation):
        if message.get("role") == "assistant" and message.get("content"):
            return message["content"]
    return ""

def _load_runtime_config():
    defaults = {"profile": "balanced", "theme": "auto"}
    try:
        data = json.loads(RUNTIME_CONFIG_FILE.read_text())
        if isinstance(data, dict):
            defaults.update(data)
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        pass
    return defaults

def _save_runtime_config(config):
    _atomic_write_json(RUNTIME_CONFIG_FILE, config)

def _load_capability_state():
    try:
        data = json.loads(CAPABILITY_STATE_FILE.read_text())
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}

def _record_capability(name, state, evidence):
    data = _load_capability_state()
    data[name] = {
        "state": state,
        "evidence": _one_line(evidence, 1000),
        "checked_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
    }
    _atomic_write_json(CAPABILITY_STATE_FILE, data)

def _browser_capability():
    chrome = Path("/mnt/c/Program Files/Google/Chrome/Application/chrome.exe")
    profile = Path(
        "/mnt/c/Users/micha/AppData/Local/Google/Chrome/User Data/Profile 2"
    )
    extension_id = "hehggadaopoacecdllhhajmbjkdcmajg"
    extension_root = profile / "Extensions" / extension_id
    native_manifest = Path(
        "/mnt/c/Users/micha/AppData/Local/OpenAI/extension/"
        "com.openai.codexextension.json"
    )
    helper = shutil.which("browse")
    versions = []
    def path_exists(path):
        try:
            return path.exists()
        except OSError:
            return False

    extension_available = path_exists(extension_root)
    profile_available = path_exists(profile)
    if extension_available:
        try:
            versions = sorted(p.name for p in extension_root.iterdir() if p.is_dir())
        except OSError:
            versions = []
    return {
        "chrome_binary": path_exists(chrome),
        "profile_2": profile_available,
        "profile_name": "Person 1" if profile_available else "unverified",
        "extension_id": extension_id,
        "extension_installed": bool(versions),
        "extension_versions": versions,
        "native_manifest": path_exists(native_manifest),
        "url_open_helper": bool(helper),
        # The bundled extension client requires a privileged host runtime.
        # This standalone WSL process cannot honestly claim a tab session.
        "interactive_signed_in_control": False,
        "interactive_reason": (
            "requires a supported privileged extension-host session that can "
            "freshly enumerate Profile 2 and claim the exact visible tab"
        ),
    }

def _capability_rows():
    browser = _browser_capability()
    observed = _load_capability_state()
    vision_observed = observed.get("vision", {})
    draft_observed = observed.get("speculative_decoding", {})
    return [
        ("Local shell and files", "available", "bounded commands, reads, writes, appends, patches"),
        ("Python execution", "available" if shutil.which("python3") else "missing", shutil.which("python3") or ""),
        ("Git", "available" if shutil.which("git") else "missing", shutil.which("git") or ""),
        ("Windows bridge", "available" if shutil.which("win-tools") else "missing", shutil.which("win-tools") or ""),
        ("Chrome URL opening", "available" if browser["url_open_helper"] else "missing", "approved Windows helper"),
        ("Signed-in Chrome tab control", "setup-required", browser["interactive_reason"]),
        ("Isolated Playwright testing", "available" if (shutil.which("playwright") or (Path(sys.executable).parent / "playwright").exists()) else "setup-required", "not the signed-in profile"),
        ("Vision input", vision_observed.get("state") or ("installed-unverified" if find_mmproj() else "unavailable"), vision_observed.get("evidence") or "run /vision IMAGE REQUEST"),
        ("Speculative decoding", draft_observed.get("state") or ("installed-unverified" if find_draft_model() else "unavailable"), draft_observed.get("evidence") or "run a measured /benchmark"),
        ("MCP servers", "available", str(MCP_CONFIG_FILE)),
        ("Durable tasks", "available", str(ACTIVE_TASK_FILE)),
        ("Cross-session prompt history", "available", str(PROMPT_HISTORY_FILE)),
    ]

def _load_mcp_config():
    try:
        data = json.loads(MCP_CONFIG_FILE.read_text())
        return data if isinstance(data, dict) else {}
    except (FileNotFoundError, json.JSONDecodeError, OSError):
        return {}

def _save_mcp_config(data):
    _atomic_write_json(MCP_CONFIG_FILE, data)
    try:
        os.chmod(MCP_CONFIG_FILE, 0o600)
    except OSError:
        pass

def _mcp_exchange(server_name, method, params=None, timeout=30):
    """Run one bounded MCP stdio session against an explicitly trusted server."""
    config = _load_mcp_config()
    entry = config.get(server_name)
    if not entry or not entry.get("trusted"):
        return {"error": f"MCP server {server_name!r} is not configured as trusted"}
    command = entry.get("command", "")
    try:
        argv = shlex.split(command)
    except ValueError as exc:
        return {"error": f"Invalid MCP command: {exc}"}
    if not argv or not shutil.which(argv[0]):
        return {"error": f"MCP executable is unavailable: {argv[0] if argv else command}"}
    process = subprocess.Popen(
        argv, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, bufsize=1,
        env={**os.environ, "PATH": AGENT_PATH},
        start_new_session=True,
    )

    def send(payload):
        process.stdin.write(json.dumps(payload, separators=(",", ":")) + "\n")
        process.stdin.flush()

    def receive(expected_id, deadline):
        while time.monotonic() < deadline:
            if process.poll() is not None:
                error = process.stderr.read()
                return {"error": f"MCP server exited {process.returncode}: {_one_line(error, 1200)}"}
            ready, _, _ = select.select(
                [process.stdout], [], [], min(0.25, max(0, deadline - time.monotonic()))
            )
            if not ready:
                continue
            line = process.stdout.readline()
            if not line:
                continue
            try:
                message = json.loads(line)
            except json.JSONDecodeError:
                continue
            if message.get("id") == expected_id:
                return message
        return {"error": f"MCP request {method} timed out after {timeout} seconds"}

    deadline = time.monotonic() + timeout
    try:
        send({
            "jsonrpc": "2.0", "id": 1, "method": "initialize",
            "params": {
                "protocolVersion": "2026-07-28",
                "capabilities": {},
                "clientInfo": {"name": "Nature", "version": "10"},
            },
        })
        initialized = receive(1, deadline)
        if initialized.get("error"):
            return initialized
        send({"jsonrpc": "2.0", "method": "notifications/initialized"})
        send({
            "jsonrpc": "2.0", "id": 2, "method": method,
            "params": params or {},
        })
        response = receive(2, deadline)
        if "error" in response:
            return {"error": response["error"]}
        return response.get("result", {})
    except Exception as exc:
        return {"error": f"{type(exc).__name__}: {exc}"}
    finally:
        try:
            process.terminate()
            process.wait(timeout=3)
        except Exception:
            try:
                os.killpg(os.getpgid(process.pid), signal.SIGKILL)
            except Exception:
                pass

def _list_models():
    rows = []
    if MODEL_DIR.exists():
        for path in sorted(MODEL_DIR.rglob("*.gguf")):
            try:
                size = path.stat().st_size / (1024 ** 3)
            except OSError:
                size = 0
            role = "projector" if "mmproj" in path.name.lower() else (
                "draft" if "mtp" in str(path).lower() else "model"
            )
            rows.append((role, size, path))
    return rows

def _print_table(title, headers, rows):
    try:
        from rich.console import Console
        from rich.table import Table
        table = Table(title=title, header_style="bold cyan", border_style="bright_black")
        for header in headers:
            table.add_column(str(header))
        for row in rows:
            table.add_row(*(str(cell) for cell in row))
        Console().print(table)
    except ImportError:
        print(f"\n  {title}")
        print("  " + " | ".join(headers))
        print("  " + "-+-".join("-" * len(h) for h in headers))
        for row in rows:
            print("  " + " | ".join(str(cell) for cell in row))
        print()

def _render_assistant(text):
    try:
        from rich.console import Console
        from rich.markdown import Markdown
        Console().print(Markdown(text or ""))
    except ImportError:
        print(f"\033[1;32m{text}\033[0m")

def _render_banner(model_path):
    browser = _browser_capability()
    config = _load_runtime_config()
    rows = [
        ("Model", model_path.name),
        ("Runtime", f"http://{SERVER_HOST}:{SERVER_PORT}"),
        ("Profile", config.get("profile", "balanced")),
        ("Automation", "durable tasks, live evidence, completion gates"),
        ("Windows", "PowerShell and PC tools"),
        (
            "Browser",
            "Profile 2 opening; tab control setup required"
            if browser["url_open_helper"] else "helper unavailable",
        ),
        ("History", "Up/Down across all sessions; Ctrl+R search"),
    ]
    try:
        from rich.console import Console
        from rich.panel import Panel
        from rich.table import Table
        table = Table.grid(padding=(0, 2))
        table.add_column(style="bold cyan", no_wrap=True)
        table.add_column(style="white")
        for key, value in rows:
            table.add_row(key, value)
        Console().print(Panel(
            table,
            title="[bold green]NATURE LOCAL AI - READY[/bold green]",
            subtitle="[dim]/help for commands | type / then Tab[/dim]",
            border_style="green",
            padding=(1, 2),
        ))
    except ImportError:
        width = 78
        print(f"\033[1;32m+{'-' * width}+\033[0m")
        print("\033[1;32m  NATURE LOCAL AI - READY\033[0m")
        for key, value in rows:
            print(f"  \033[1;37m{key:<12}\033[0m {value}")
        print(f"\033[1;32m+{'-' * width}+\033[0m")
        print("  /help for commands | type / then Tab")

def _run_vision_request(path_text, request, conversation):
    path = Path(normalize_user_path(path_text)).expanduser().resolve()
    if not path.is_file():
        print(f"  Image not found: {path}\n")
        return
    if find_mmproj() is None:
        print("  No multimodal projector is installed for the selected model.\n")
        return
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    if not mime.startswith("image/"):
        print(f"  Unsupported vision input type: {mime}\n")
        return
    encoded = base64.b64encode(path.read_bytes()).decode("ascii")
    message = {
        "role": "user",
        "content": [
            {"type": "text", "text": request or "Describe this image accurately."},
            {"type": "image_url", "image_url": {
                "url": f"data:{mime};base64,{encoded}",
            }},
        ],
    }
    print(f"  Reading {path.name} with the live multimodal model...\n")
    result = send_message(conversation + [message], tools=None)
    if result.get("error") or not result.get("content"):
        detail = result.get("error") or "the model returned no visible image answer"
        _record_capability("vision", "failed", detail)
        print(f"  Vision probe failed: {detail}\n")
        return
    answer = result["content"]
    conversation.extend([message, {"role": "assistant", "content": answer}])
    _record_capability(
        "vision", "verified",
        f"successful live image request for {path.name}",
    )
    _render_assistant(answer)
    print()

def _run_selftest():
    results = []

    def check(label, operation):
        try:
            detail = operation()
            results.append((label, "PASS", detail or "verified"))
        except Exception as exc:
            results.append((label, "FAIL", f"{type(exc).__name__}: {exc}"))

    def routing_test():
        names = {
            item["function"]["name"]
            for item in select_tools(
                r"Build a Python website in F:\demo and open it in Chrome"
            )
        }
        required = {
            "run_command", "run_python", "write_file", "append_file",
            "apply_patch", "read_file", "win_tools", "browse",
        }
        assert required.issubset(names), sorted(required - names)
        return ", ".join(sorted(names))

    def write_cap_test():
        with tempfile.TemporaryDirectory() as folder:
            target = Path(folder) / "blocked.txt"
            result = execute_tool_call({
                "type": "write", "path": str(target),
                "content": "x" * (MAX_WHOLE_FILE_CHARS + 1),
            })
            assert "safe per-call limit" in result and not target.exists()
        return "oversized content rejected before mutation"

    def patch_test():
        with tempfile.TemporaryDirectory() as folder:
            root = Path(folder)
            subprocess.run(
                ["git", "init", "-q"], cwd=root, check=True,
                capture_output=True, text=True,
            )
            (root / "sample.txt").write_text("old\n", encoding="utf-8")
            patch = (
                "diff --git a/sample.txt b/sample.txt\n"
                "--- a/sample.txt\n+++ b/sample.txt\n"
                "@@ -1 +1 @@\n-old\n+new\n"
            )
            old_cwd = Path.cwd()
            try:
                os.chdir(root)
                result = execute_tool_call({"type": "patch", "patch": patch})
            finally:
                os.chdir(old_cwd)
            assert "validated and applied" in result.lower()
            assert (root / "sample.txt").read_text() == "new\n"
        return "git apply --check and mutation passed"

    def history_test():
        key_text = " ".join(
            str(key)
            for binding in build_prompt_key_bindings().bindings
            for key in binding.keys
        )
        assert "Up" in key_text and "Down" in key_text
        with tempfile.TemporaryDirectory() as folder:
            from prompt_toolkit.history import FileHistory
            path = Path(folder) / "history"
            FileHistory(str(path)).append_string("cross-session prompt")
            assert "cross-session prompt" in list(
                FileHistory(str(path)).load_history_strings()
            )
        return key_text

    def browser_test():
        state = _browser_capability()
        assert state["extension_id"] == "hehggadaopoacecdllhhajmbjkdcmajg"
        assert state["interactive_signed_in_control"] is False
        return (
            f"binary={state['chrome_binary']}, profile2={state['profile_2']}, "
            f"extension={state['extension_installed']}, tab-control=fail-closed"
        )

    def storage_test():
        probe = LOG_DIR / ".selftest-write"
        probe.write_text("ok", encoding="utf-8")
        assert probe.read_text() == "ok"
        probe.unlink()
        return str(LOG_DIR)

    check("Task-specific tool routing", routing_test)
    check("Oversized write protection", write_cap_test)
    check("Validated structured patch", patch_test)
    check("Persistent history and keymap", history_test)
    check("Exact browser identity boundary", browser_test)
    check("Durable storage", storage_test)
    _print_table("Nature Self-Test", ("Check", "State", "Evidence"), results)
    passed = sum(1 for _, state, _ in results if state == "PASS")
    print(f"  Result: {passed}/{len(results)} focused checks passed.\n")

def _run_agent_request(request, conversation):
    response = agent_turn(request, conversation)
    for entry in extract_memory_entries(response):
        save_memory("-" + " ".join(entry.splitlines())[:500])
    print()
    _render_assistant(response)
    print()

def _print_help(command=""):
    command = command.lower().lstrip("/")
    if command in WORKFLOW_COMMANDS:
        print(f"\n  /{command} REQUEST\n  {WORKFLOW_COMMANDS[command]}\n")
        return
    if command:
        for syntax, description in COMMAND_HELP:
            if command == syntax.split()[0].split("|")[0]:
                print(f"\n  /{syntax}\n  {description}\n")
                return
    _print_table(
        "Nature Command Center - Direct Commands",
        ("Command", "Purpose"),
        [(f"/{syntax}", description) for syntax, description in COMMAND_HELP],
    )
    _print_table(
        "Nature Command Center - Agent Workflows",
        ("Command", "Behavior"),
        [(f"/{name} REQUEST", description) for name, description in WORKFLOW_COMMANDS.items()],
    )
    custom = _load_custom_commands()
    if custom:
        _print_table(
            "Persistent Custom Commands", ("Command", "Template"),
            [
                (f"/{name}", compact_text(template, 100))
                for name, template in sorted(custom.items())
            ],
        )

def _show_prompts(limit):
    try:
        from prompt_toolkit.history import FileHistory
        entries = list(FileHistory(str(PROMPT_HISTORY_FILE)).load_history_strings())
    except ImportError:
        entries = []
        try:
            import readline
            old_length = readline.get_current_history_length()
            readline.read_history_file(PROMPT_HISTORY_FILE)
            entries = [
                readline.get_history_item(i)
                for i in range(old_length + 1, readline.get_current_history_length() + 1)
            ]
        except (FileNotFoundError, OSError):
            pass
    entries = list(reversed([entry for entry in entries if entry][:limit]))
    for index, entry in enumerate(entries, 1):
        print(f"  {index:>3}. {entry.replace(chr(10), ' ')}")
    print()

def _run_user_input_inner(user_input, conversation):
    """Process a single user input. Returns False to quit."""
    global CURRENT_TASK_STATE, CURRENT_CONVERSATION
    if user_input.startswith("!"):
        command = user_input[1:].strip()
        if command:
            print(execute_tool_call({"type": "command", "cmd": command}, user_input) + "\n")
        return True
    if user_input.startswith("/"):
        name, args = _split_command(user_input)
        name = {
            "usage": "stats",
            "mode": "profile",
            "plugins": "mcp",
            "image": "vision",
            "about": "status",
        }.get(name, name)
        if name in ("quit", "exit", "q"):
            return False
        if name in ("help", "?"):
            _print_help(args)
            return True
        custom = _load_custom_commands()
        if name in custom and name not in BUILTIN_COMMAND_NAMES and name not in WORKFLOW_COMMANDS:
            if load_pending_task():
                print(
                    "\033[1;33m[ACTIVE TASK]\033[0m Use /resume to continue "
                    "the checkpointed task or /cancel before starting another.\n"
                )
                return True
            expanded = _expand_custom_command(custom[name], args)
            if not expanded:
                print("  \033[1;33m[EMPTY CUSTOM COMMAND]\033[0m Nothing to run.\n")
                return True
            _run_agent_request(expanded, conversation)
            return True
        if name in WORKFLOW_COMMANDS:
            if not args:
                print(f"  Usage: /{name} REQUEST\n")
                return True
            if load_pending_task():
                print(
                    "\033[1;33m[ACTIVE TASK]\033[0m Use /resume to continue "
                    "the checkpointed task or /cancel before starting another.\n"
                )
                return True
            _run_agent_request(f"{WORKFLOW_COMMANDS[name]}\n\n{args}", conversation)
            return True
        if name == "clear":
            pending = load_pending_task()
            if pending:
                print(
                    "\033[1;33m[ACTIVE TASK]\033[0m An unfinished task is "
                    "checkpointed. Use /resume to continue it or /cancel to "
                    "explicitly abandon it before clearing.\n"
                )
                return True
            conversation.clear()
            conversation.append({"role": "system", "content": build_system_prompt()})
            print("\033[0;33m[Conversation cleared]\033[0m\n")
            return True
        if name in ("resume", "continue"):
            pending = load_pending_task()
            if not pending:
                print("\033[0;33m[No unfinished task is checkpointed]\033[0m\n")
                return True
            restored = sanitize_resume_conversation(
                pending.get("conversation") or [], pending.get("objective", "")
            )
            conversation.clear()
            conversation.extend(restored)
            response = agent_turn(
                pending.get("objective", ""), conversation,
                resume_payload=pending,
            )
            for entry in extract_memory_entries(response):
                save_memory("-" + " ".join(entry.splitlines())[:500])
            print(f"\n\033[1;32m{response}\033[0m\n")
            return True
        if name == "cancel":
            pending = load_pending_task()
            if pending:
                pending["status"] = "cancelled"
                pending["cancelled_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
                _atomic_write_json(
                    TASK_HISTORY_DIR / f"{pending.get('task_id', 'cancelled')}.json",
                    pending,
                )
                try:
                    ACTIVE_TASK_FILE.unlink()
                except Exception:
                    pass
                CURRENT_TASK_STATE = None
                CURRENT_CONVERSATION = None
                print("\033[0;33m[Unfinished task cancelled explicitly]\033[0m\n")
            else:
                print("\033[0;33m[No unfinished task is checkpointed]\033[0m\n")
            return True
        if name in ("reset", "restart"):
            if load_pending_task():
                print(
                    "\033[1;33m[ACTIVE TASK]\033[0m Resume or cancel the "
                    "checkpointed task before resetting the conversation.\n"
                )
                return True
            stop_server()
            m = find_model()
            if m and start_server(m):
                conversation.clear()
                conversation.append({"role": "system", "content": build_system_prompt()})
                print("\033[0;33m[Reset complete - fresh conversation]\033[0m\n")
            return True
        if name == "history":
            limit = int(args) if args.isdigit() else 20
            for i, m in enumerate(conversation[-limit:], max(0, len(conversation) - limit)):
                role = m["role"]
                preview = compact_text(m.get("content", ""), 240).replace('\n', ' ')
                print(f"  [{i}] {role}: {preview}")
            print()
            return True
        if name == "prompts":
            _show_prompts(int(args) if args.isdigit() else 30)
            return True
        if name == "memory":
            action, _, text = args.partition(" ")
            if action == "add" and text.strip():
                save_memory("- " + text.strip())
                print("\033[0;32m[Memory saved]\033[0m\n")
                return True
            if action == "clear":
                (LOG_DIR / "memory.md").write_text("")
                print("\033[0;33m[Persistent memory cleared]\033[0m\n")
                return True
            print(load_memory() or "(no memory yet)")
            print()
            return True
        if name in ("status", "settings"):
            pending = load_pending_task()
            total = sum(len(m.get("content", "")) for m in conversation)
            print("\n\033[1;36m  NATURE STATUS\033[0m")
            print(f"  Server       {'healthy' if model_server_healthy() else 'unavailable'}")
            print(f"  Model        {(find_model().name if find_model() else 'not found')}")
            print(f"  Directory    {Path.cwd()}")
            print(f"  Conversation {len(conversation)} messages, {total:,} characters")
            print(f"  Context      {CONTEXT_TOKENS:,} tokens; {context_char_budget():,} character budget")
            print(f"  Active task  {pending.get('task_id') if pending else 'none'}")
            print(f"  History      {PROMPT_HISTORY_FILE}")
            print(f"  Custom cmds  {len(_load_custom_commands())}\n")
            return True
        if name == "doctor":
            try:
                key_text = " ".join(
                    str(key)
                    for binding in build_prompt_key_bindings().bindings
                    for key in binding.keys
                )
                history_keys = "Up" in key_text and "Down" in key_text
            except Exception:
                history_keys = False
            browser_state = _browser_capability()
            writable_state = os.access(str(LOG_DIR), os.W_OK)
            checks = [
                ("Model server", model_server_healthy()),
                ("Model file", find_model() is not None),
                ("Agent Python", Path(sys.executable).exists()),
                ("Git", shutil.which("git") is not None),
                ("Structured patch engine", shutil.which("git") is not None),
                ("Windows tools", shutil.which("win-tools") is not None),
                ("Chrome Profile 2 helper", browser_state["url_open_helper"]),
                ("Chrome extension identity", browser_state["extension_installed"]),
                ("Native browser manifest", browser_state["native_manifest"]),
                ("Persistent Up/Down bindings", history_keys),
                ("Writable task/event store", writable_state),
            ]
            _print_table(
                "Nature Doctor", ("Check", "State"),
                [(label, "PASS" if passed else "FAIL") for label, passed in checks],
            )
            if not browser_state["interactive_signed_in_control"]:
                print(
                    "  Signed-in tab interaction: SETUP REQUIRED - "
                    + browser_state["interactive_reason"] + "\n"
                )
            return True
        if name in ("context", "tokens"):
            chars = sum(len(m.get("content", "")) for m in conversation)
            budget = context_char_budget()
            print(f"  Messages: {len(conversation)}")
            print(f"  Characters: {chars:,} / {budget:,} ({min(100, chars * 100 // max(1, budget))}%)")
            print(f"  Server context: {CONTEXT_TOKENS:,} tokens")
            print(f"  Maximum response: {RESPONSE_MAX_TOKENS:,} tokens\n")
            return True
        if name == "compact":
            before = len(conversation)
            compacted = trim_conversation(conversation)
            conversation.clear()
            conversation.extend(compacted)
            print(f"  Conversation compacted: {before} -> {len(conversation)} messages.\n")
            return True
        if name == "tasks":
            pending = load_pending_task()
            print(f"  Active: {pending.get('task_id') if pending else 'none'}")
            records = sorted(TASK_HISTORY_DIR.glob("*.json"), key=lambda p: p.stat().st_mtime, reverse=True)[:20]
            for path in records:
                try:
                    task = json.loads(path.read_text())
                    print(f"  {task.get('status', 'unknown'):<12} {task.get('task_id', path.stem)}  {compact_text(task.get('objective', ''), 70)}")
                except Exception:
                    print(f"  unreadable   {path.name}")
            print()
            return True
        if name == "pwd":
            print(f"  {Path.cwd()}\n")
            return True
        if name == "cd":
            try:
                os.chdir(Path(normalize_user_path(args or str(HOME))).expanduser())
                print(f"  Directory: {Path.cwd()}\n")
            except OSError as exc:
                print(f"  \033[0;31m[CD ERROR]\033[0m {exc}\n")
            return True
        if name in ("ls", "tree"):
            target = shlex.quote(normalize_user_path(args)) if args else "."
            command = f"ls -la {target}" if name == "ls" else f"find {target} -maxdepth 3 -print | head -500"
            print(execute_tool_call({"type": "command", "cmd": command}, user_input) + "\n")
            return True
        if name in ("git", "diff"):
            command = f"git {args}" if name == "git" and args else ("git status --short --branch" if name == "git" else f"git diff {args}")
            print(execute_tool_call({"type": "command", "cmd": command}, user_input) + "\n")
            return True
        if name in ("shell", "!"):
            if not args:
                print("  Usage: /shell COMMAND\n")
            else:
                print(execute_tool_call({"type": "command", "cmd": args}, user_input) + "\n")
            return True
        if name == "python":
            if not args:
                print("  Usage: /python CODE\n")
            else:
                print(execute_tool_call({"type": "python", "code": args}, user_input) + "\n")
            return True
        if name in ("browse", "windows"):
            if not args:
                print(f"  Usage: /{name} REQUEST\n")
            else:
                prefix = (
                    "Use Chrome Profile 2 URL opening where sufficient. Before "
                    "interactive tab work, run the exact browser capability check "
                    "and fail closed if a privileged tab-claim bridge is unavailable: "
                    if name == "browse" else
                    "Use the available Windows and PC control tools to "
                )
                _run_agent_request(prefix + args, conversation)
            return True
        if name == "model":
            model = find_model()
            print(f"  Model file: {model or 'not found'}")
            try:
                print("  Server properties: " + json.dumps(api_call("/props", timeout=10), indent=2)[:4000])
            except Exception as exc:
                print(f"  Server properties unavailable: {exc}")
            print()
            return True
        if name == "logs":
            log_name = "agent.log" if args == "agent" else "server.log"
            path = LOG_DIR / log_name
            if path.exists():
                print("\n".join(path.read_text(errors="replace").splitlines()[-100:]) + "\n")
            else:
                print(f"  No log found at {path}\n")
            return True
        if name == "export":
            destination = Path(normalize_user_path(args)).expanduser() if args else EXPORT_DIR / f"conversation-{time.strftime('%Y%m%d-%H%M%S')}.md"
            destination.parent.mkdir(parents=True, exist_ok=True)
            sections = ["# Nature Conversation", ""]
            for message in conversation:
                sections.extend([f"## {message.get('role', 'unknown').title()}", "", message.get("content", ""), ""])
            destination.write_text("\n".join(sections))
            print(f"  Exported to {destination}\n")
            return True
        if name == "copy":
            text = _latest_assistant_text(conversation)
            if args == "code":
                blocks = re.findall(r"```(?:[^\n]*)\n(.*?)```", text, re.DOTALL)
                text = blocks[-1] if blocks else ""
            if not text:
                print("  Nothing available to copy.\n")
            else:
                try:
                    powershell = _ensure_windows_interop_runtime()
                    proc = subprocess.run(
                        [powershell, "-NoProfile", "-NonInteractive", "-Command",
                         "$input | Set-Clipboard"],
                        input=text, text=True, capture_output=True,
                    )
                    print("  Copied to the Windows clipboard.\n" if proc.returncode == 0 else f"  Clipboard failed: {proc.stderr}\n")
                except Exception as exc:
                    print(f"  Clipboard failed: {exc}\n")
            return True
        if name == "paste":
            try:
                powershell = _ensure_windows_interop_runtime()
                proc = subprocess.run(
                    [powershell, "-NoProfile", "-NonInteractive", "-Command",
                     "Get-Clipboard -Raw"],
                    text=True, capture_output=True,
                )
            except Exception as exc:
                print(f"  Clipboard text unavailable: {exc}\n")
                return True
            clipboard = proc.stdout.strip()
            if proc.returncode != 0 or not clipboard:
                print(f"  Clipboard text unavailable: {proc.stderr.strip() or 'clipboard is empty'}\n")
                return True
            if args:
                if load_pending_task():
                    print("\033[1;33m[ACTIVE TASK]\033[0m Resume or cancel it before starting another.\n")
                    return True
                _run_agent_request(f"{args}\n\nClipboard content:\n{clipboard}", conversation)
            else:
                print(clipboard + "\n")
            return True
        if name == "tools":
            tools = select_tools(args) if args else TOOLS_SPEC
            rows = [
                (item["function"]["name"], item["function"]["description"])
                for item in tools
            ]
            _print_table("Nature Tools", ("Tool", "Purpose"), rows)
            return True
        if name == "capabilities":
            _print_table(
                "Capability Matrix", ("Capability", "State", "Evidence"),
                _capability_rows(),
            )
            return True
        if name == "profile":
            config = _load_runtime_config()
            if not args:
                print(f"  Active inference profile: {config['profile']}\n")
                return True
            profile = args.lower()
            if profile not in ("fast", "balanced", "quality"):
                print("  Usage: /profile fast|balanced|quality\n")
                return True
            config["profile"] = profile
            _save_runtime_config(config)
            print(
                f"  Profile set to {profile}. It takes effect on the next "
                "server restart; use /restart when no task is active.\n"
            )
            return True
        if name == "session":
            pending = load_pending_task()
            rows = [
                ("directory", Path.cwd()),
                ("messages", len(conversation)),
                ("active task", pending.get("task_id") if pending else "none"),
                ("prompt history", PROMPT_HISTORY_FILE),
                ("event log", EVENT_LOG_FILE),
                ("task records", TASK_HISTORY_DIR),
                ("exports", EXPORT_DIR),
            ]
            _print_table("Current Session", ("Item", "Value"), rows)
            return True
        if name == "checkpoint":
            if CURRENT_TASK_STATE and CURRENT_CONVERSATION:
                checkpoint_task(CURRENT_TASK_STATE, CURRENT_CONVERSATION)
                print(f"  Checkpoint saved to {ACTIVE_TASK_FILE}.\n")
            else:
                print("  No active in-process task needs checkpointing.\n")
            return True
        if name == "retry":
            pending = load_pending_task()
            if pending:
                return run_user_input("/resume", conversation)
            latest_user = next(
                (m.get("content", "") for m in reversed(conversation)
                 if m.get("role") == "user" and m.get("content")),
                "",
            )
            if latest_user:
                _run_agent_request(
                    "Retry this request from the existing evidence using a "
                    "materially different approach:\n\n" + latest_user,
                    conversation,
                )
            else:
                print("  There is no previous request to retry.\n")
            return True
        if name == "files":
            target = Path(normalize_user_path(args or ".")).expanduser()
            if not target.exists():
                print(f"  Path not found: {target}\n")
            elif target.is_file():
                stat = target.stat()
                print(
                    f"  {target}\n  file | {stat.st_size:,} bytes | "
                    f"modified {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stat.st_mtime))}\n"
                )
            else:
                rows = []
                for child in sorted(target.iterdir())[:300]:
                    try:
                        stat = child.stat()
                        rows.append((
                            "dir" if child.is_dir() else "file",
                            f"{stat.st_size:,}",
                            child.name,
                        ))
                    except OSError:
                        rows.append(("unreadable", "-", child.name))
                _print_table(str(target), ("Type", "Bytes", "Name"), rows)
            return True
        if name == "search":
            try:
                parts = shlex.split(args)
            except ValueError as exc:
                print(f"  Search arguments are invalid: {exc}\n")
                return True
            if not parts:
                print("  Usage: /search PATTERN [PATH]\n")
                return True
            pattern = parts[0]
            target = normalize_user_path(parts[1]) if len(parts) > 1 else "."
            if shutil.which("rg"):
                command = (
                    f"rg --hidden --glob '!.git' --max-count 200 "
                    f"-- {shlex.quote(pattern)} {shlex.quote(target)}"
                )
            else:
                command = (
                    f"grep -R -n -m 200 --exclude-dir=.git -- "
                    f"{shlex.quote(pattern)} {shlex.quote(target)}"
                )
            print(execute_tool_call({"type": "command", "cmd": command}, user_input) + "\n")
            return True
        if name == "open":
            if not args:
                print("  Usage: /open PATH|URL\n")
            elif re.match(r"^https?://", args, re.IGNORECASE):
                print(execute_tool_call({"type": "command", "cmd": f"browse open {shlex.quote(args)}"}, user_input) + "\n")
            else:
                target = str(Path(normalize_user_path(args)).expanduser().resolve())
                windows_target = subprocess.run(
                    ["wslpath", "-w", target], text=True, capture_output=True,
                ).stdout.strip()
                subprocess.Popen(
                    ["explorer.exe", windows_target or target],
                    stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                )
                print(f"  Opened {windows_target or target}.\n")
            return True
        if name == "edit":
            path_text, _, request = args.partition(" ")
            if not path_text or not request:
                print("  Usage: /edit PATH REQUEST\n")
            elif load_pending_task():
                print("\033[1;33m[ACTIVE TASK]\033[0m Resume or cancel it first.\n")
            else:
                _run_agent_request(
                    f"Edit {path_text} with focused patches, preserve unrelated "
                    f"work, then test the result: {request}",
                    conversation,
                )
            return True
        if name == "apply":
            patch_path = Path(normalize_user_path(args)).expanduser()
            if not args or not patch_path.is_file():
                print("  Usage: /apply PATCH_FILE\n")
            else:
                result = execute_tool_call(
                    {"type": "patch", "patch": patch_path.read_text(errors="replace")},
                    user_input,
                )
                print(result + "\n")
            return True
        if name == "append":
            path_text, _, text = args.partition(" ")
            if not path_text:
                print("  Usage: /append PATH TEXT\n")
            else:
                print(execute_tool_call({
                    "type": "append", "path": path_text, "content": text,
                }, user_input) + "\n")
            return True
        if name == "browser":
            action, _, value = args.partition(" ")
            if action in ("", "status"):
                state = _browser_capability()
                _print_table(
                    "Approved Browser Capability", ("Check", "Value"),
                    [(key.replace("_", " "), value) for key, value in state.items()],
                )
            elif action == "open" and value:
                print(execute_tool_call({
                    "type": "command", "cmd": f"browse open {shlex.quote(value)}",
                }, user_input) + "\n")
            else:
                print("  Usage: /browser status | /browser open URL\n")
            return True
        if name == "vision":
            try:
                parts = shlex.split(args)
            except ValueError as exc:
                print(f"  Vision arguments are invalid: {exc}\n")
                return True
            if not parts:
                print("  Usage: /vision IMAGE [REQUEST]\n")
            else:
                _run_vision_request(
                    parts[0],
                    " ".join(parts[1:]) or "Describe this image accurately.",
                    conversation,
                )
            return True
        if name == "mcp":
            action, _, rest = args.partition(" ")
            config = _load_mcp_config()
            if action in ("", "list"):
                rows = [
                    (server, entry.get("command", ""), "trusted" if entry.get("trusted") else "disabled")
                    for server, entry in sorted(config.items())
                ]
                _print_table("MCP Servers", ("Name", "Command", "Trust"), rows)
            elif action == "add":
                server, _, command = rest.partition(" ")
                if not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_-]{0,63}", server) or not command:
                    print("  Usage: /mcp add NAME COMMAND\n")
                else:
                    config[server] = {"command": command, "trusted": True}
                    _save_mcp_config(config)
                    print(f"  Trusted MCP server {server} saved.\n")
            elif action == "remove" and rest in config:
                del config[rest]
                _save_mcp_config(config)
                print(f"  MCP server {rest} removed.\n")
            elif action == "tools":
                server = rest.strip()
                if server:
                    result = _mcp_exchange(server, "tools/list", {}, timeout=30)
                    if result.get("error"):
                        print(f"  MCP discovery failed: {result['error']}\n")
                    else:
                        rows = [
                            (
                                tool.get("name", ""),
                                tool.get("description", ""),
                            )
                            for tool in result.get("tools", [])
                        ]
                        _print_table(
                            f"MCP Tools: {server}", ("Tool", "Description"), rows
                        )
                else:
                    rows = []
                    for server_name, entry in sorted(config.items()):
                        command = entry.get("command", "")
                        executable = shlex.split(command)[0] if command else ""
                        rows.append((
                            server_name,
                            "ready" if entry.get("trusted") and shutil.which(executable) else "unavailable",
                            command,
                        ))
                    _print_table("MCP Tool Providers", ("Server", "State", "Command"), rows)
            elif action == "call":
                try:
                    server, tool, raw = rest.split(" ", 2)
                    arguments = json.loads(raw)
                except (ValueError, json.JSONDecodeError):
                    print("  Usage: /mcp call SERVER TOOL JSON_ARGUMENTS\n")
                    return True
                result = _mcp_exchange(
                    server, "tools/call",
                    {"name": tool, "arguments": arguments},
                    timeout=60,
                )
                print(json.dumps(result, indent=2, ensure_ascii=False) + "\n")
            else:
                print("  Usage: /mcp list | add NAME COMMAND | remove NAME | tools [NAME] | call SERVER TOOL JSON\n")
            return True
        if name in ("skills", "hooks", "permissions"):
            if name == "permissions":
                rows = [
                    ("WSL shell/files", "enabled"),
                    ("sudo", "configured by installer"),
                    ("Windows bridge", "enabled when win-tools is installed"),
                    ("Chrome URL opening", "enabled when browse is installed"),
                    ("signed-in tab interaction", "fail-closed without privileged bridge"),
                    ("MCP execution", "trusted configured servers only"),
                ]
            else:
                base = LOG_DIR / name
                base.mkdir(parents=True, exist_ok=True)
                rows = [("directory", base), ("entries", len(list(base.iterdir())))]
            _print_table(name.title(), ("Item", "Value"), rows)
            return True
        if name in ("metrics", "stats"):
            rows = []
            for endpoint in ("/metrics", "/slots"):
                try:
                    with urllib.request.urlopen(
                        f"http://{SERVER_HOST}:{SERVER_PORT}{endpoint}", timeout=5
                    ) as response:
                        payload = response.read(8000).decode("utf-8", errors="replace")
                    rows.append((endpoint, "available", _one_line(payload, 500)))
                except Exception as exc:
                    rows.append((endpoint, "unavailable", _one_line(str(exc), 240)))
            try:
                event_count = sum(1 for _ in EVENT_LOG_FILE.open(encoding="utf-8"))
            except (FileNotFoundError, OSError):
                event_count = 0
            rows.append(("events", event_count, EVENT_LOG_FILE))
            _print_table("Runtime Metrics", ("Source", "State", "Detail"), rows)
            return True
        if name == "benchmark":
            request = args or "Measure local model response latency and report exact timings."
            _run_agent_request(
                "Benchmark this using repeatable commands and report measured "
                "before/after evidence only:\n\n" + request,
                conversation,
            )
            return True
        if name == "models":
            _print_table(
                "Installed GGUF Files", ("Role", "GiB", "Path"),
                [(role, f"{size:.2f}", path) for role, size, path in _list_models()],
            )
            return True
        if name == "config":
            action, _, rest = args.partition(" ")
            config = _load_runtime_config()
            if action in ("", "show"):
                _print_table("Runtime Configuration", ("Key", "Value"), sorted(config.items()))
            elif action == "set":
                key, _, value = rest.partition(" ")
                if not re.fullmatch(r"[a-zA-Z][a-zA-Z0-9_.-]{0,63}", key) or not value:
                    print("  Usage: /config set KEY VALUE\n")
                else:
                    config[key] = value
                    _save_runtime_config(config)
                    print(f"  Configuration {key} saved.\n")
            else:
                print("  Usage: /config show | /config set KEY VALUE\n")
            return True
        if name == "theme":
            config = _load_runtime_config()
            if not args:
                print(f"  Theme: {config.get('theme', 'auto')}\n")
            elif args in ("auto", "dark", "light", "mono"):
                config["theme"] = args
                _save_runtime_config(config)
                print(f"  Theme set to {args}.\n")
            else:
                print("  Usage: /theme auto|dark|light|mono\n")
            return True
        if name == "background":
            if not args:
                print("  Usage: /background COMMAND\n")
            else:
                stamp = time.strftime("%Y%m%d-%H%M%S")
                job_id = f"{stamp}-{uuid.uuid4().hex[:6]}"
                log_path = JOB_DIR / f"{job_id}.log"
                handle = open(log_path, "a", encoding="utf-8")
                process = subprocess.Popen(
                    args, shell=True, stdout=handle, stderr=subprocess.STDOUT,
                    start_new_session=True, env={**os.environ, "PATH": AGENT_PATH},
                )
                handle.close()
                receipt = {
                    "id": job_id,
                    "pid": process.pid,
                    "start_token": _process_start_token(process.pid),
                    "command": args,
                    "log": str(log_path),
                    "started_at": time.strftime("%Y-%m-%dT%H:%M:%S%z"),
                }
                _atomic_write_json(JOB_DIR / f"{job_id}.json", receipt)
                emit_event("background-start", "working", args, pid=process.pid, log=str(log_path))
                print(f"  Background job {job_id} started as PID {process.pid}; live log: {log_path}\n")
            return True
        if name == "jobs":
            action, _, job_id = args.partition(" ")
            if action == "stop" and job_id:
                receipt_path = JOB_DIR / f"{job_id}.json"
                try:
                    receipt = json.loads(receipt_path.read_text())
                    pid = int(receipt["pid"])
                except Exception:
                    print(f"  Unknown job receipt: {job_id}\n")
                    return True
                if (
                    not receipt.get("start_token")
                    or _process_start_token(pid) != receipt.get("start_token")
                ):
                    print(
                        "  The recorded PID is no longer the same process; "
                        "nothing was stopped.\n"
                    )
                    return True
                try:
                    os.killpg(os.getpgid(pid), signal.SIGTERM)
                    receipt["stopped_at"] = time.strftime("%Y-%m-%dT%H:%M:%S%z")
                    _atomic_write_json(receipt_path, receipt)
                    emit_event("background-stop", "completed", job_id, pid=pid)
                    print(f"  Stopped verified background job {job_id}.\n")
                except Exception as exc:
                    print(f"  Could not stop {job_id}: {exc}\n")
                return True
            rows = []
            for receipt_path in sorted(
                JOB_DIR.glob("*.json"), key=lambda path: path.stat().st_mtime,
                reverse=True,
            )[:50]:
                try:
                    receipt = json.loads(receipt_path.read_text())
                    pid = int(receipt.get("pid", 0))
                    same = (
                        receipt.get("start_token")
                        and _process_start_token(pid) == receipt.get("start_token")
                    )
                    rows.append((
                        receipt.get("id", receipt_path.stem),
                        "running" if same else ("stopped" if receipt.get("stopped_at") else "finished"),
                        pid,
                        _one_line(receipt.get("command", ""), 120),
                        receipt.get("log", ""),
                    ))
                except Exception:
                    rows.append((receipt_path.stem, "unreadable", "-", "-", "-"))
            _print_table(
                "Background Jobs", ("ID", "State", "PID", "Command", "Log"), rows
            )
            return True
        if name == "selftest":
            _run_selftest()
            return True
        if name == "recap":
            pending = load_pending_task()
            latest = _latest_assistant_text(conversation)
            print(f"  Messages: {len(conversation)}")
            print(f"  Active task: {pending.get('task_id') if pending else 'none'}")
            print(f"  Latest answer: {_one_line(latest, 800) or 'none'}\n")
            return True
        if name in ("add", "drop", "context-files"):
            try:
                paths = json.loads(CONTEXT_FILES_FILE.read_text())
                if not isinstance(paths, list):
                    paths = []
            except (FileNotFoundError, json.JSONDecodeError, OSError):
                paths = []
            if name == "context-files":
                _print_table(
                    "Pinned Project Context", ("State", "Path"),
                    [
                        ("available" if Path(path).is_file() else "missing", path)
                        for path in paths
                    ],
                )
                return True
            if name == "drop" and args == "all":
                _atomic_write_json(CONTEXT_FILES_FILE, [])
                print("  All pinned project context was removed.\n")
                return True
            path = Path(normalize_user_path(args)).expanduser().resolve() if args else None
            if path is None:
                print(f"  Usage: /{name} PATH" + ("|all\n" if name == "drop" else "\n"))
                return True
            value = str(path)
            if name == "add":
                if not path.is_file():
                    print(f"  Context file not found: {path}\n")
                elif value in paths:
                    print(f"  Already pinned: {path}\n")
                else:
                    paths.append(value)
                    _atomic_write_json(CONTEXT_FILES_FILE, paths[-40:])
                    print(f"  Pinned for future sessions: {path}\n")
            else:
                paths = [item for item in paths if item != value]
                _atomic_write_json(CONTEXT_FILES_FILE, paths)
                print(f"  Removed from persistent context: {path}\n")
            return True
        if name == "fork":
            if load_pending_task():
                print("\033[1;33m[ACTIVE TASK]\033[0m Finish or cancel it before forking.\n")
                return True
            destination = (
                Path(normalize_user_path(args)).expanduser()
                if args else
                EXPORT_DIR / f"fork-{time.strftime('%Y%m%d-%H%M%S')}.md"
            )
            destination.parent.mkdir(parents=True, exist_ok=True)
            sections = ["# Nature Conversation Fork", ""]
            for message in conversation:
                sections.extend([
                    f"## {message.get('role', 'unknown').title()}",
                    "", message.get("content", ""), "",
                ])
            destination.write_text("\n".join(sections), encoding="utf-8")
            conversation.clear()
            conversation.append({"role": "system", "content": build_system_prompt()})
            print(f"  Fork exported to {destination}; a fresh conversation is ready.\n")
            return True
        if name == "rewind":
            run_user_input("/tasks", conversation)
            run_user_input("/prompts 20", conversation)
            return True
        if name == "command":
            action, _, rest = args.partition(" ")
            commands = _load_custom_commands()
            if action == "list" or not action:
                for custom_name, template in sorted(commands.items()):
                    print(f"  /{custom_name:<20} {template}")
                print()
                return True
            custom_name, _, template = rest.partition(" ")
            custom_name = custom_name.lower().lstrip("/")
            if action == "add" and re.fullmatch(r"[a-z][a-z0-9_-]{0,31}", custom_name) and template:
                if custom_name in WORKFLOW_COMMANDS or custom_name in BUILTIN_COMMAND_NAMES:
                    print("  That name is reserved by a built-in command.\n")
                    return True
                commands[custom_name] = template
                _save_custom_commands(commands)
                print(f"  Custom command /{custom_name} saved.\n")
                return True
            if action == "remove" and custom_name in commands:
                del commands[custom_name]
                _save_custom_commands(commands)
                print(f"  Custom command /{custom_name} removed.\n")
                return True
            print("  Usage: /command list | /command add NAME TEMPLATE | /command remove NAME\n")
            return True
        print(f"  Unknown command: {user_input}")
        print("  Type /help to see every available command.\n")
        return True

    if load_pending_task():
        print(
            "\033[1;33m[ACTIVE TASK]\033[0m An unfinished task is protected "
            "from being overwritten. Use /resume to continue it or /cancel to "
            "abandon it explicitly.\n"
        )
        return True

    try:
        _run_agent_request(user_input, conversation)
    except Exception as e:
        print(f"\n\033[0;31m[ERROR]\033[0m {type(e).__name__}: {e}\n")
    return True


def run_user_input(user_input, conversation):
    """Run one submitted job and ring exactly once at its terminal outcome."""
    with completion_chime_after_job():
        return _run_user_input_inner(user_input, conversation)


def build_prompt_key_bindings():
    """Create deterministic history bindings used by the interactive prompt."""
    from prompt_toolkit.key_binding import KeyBindings
    bindings = KeyBindings()

    @bindings.add("up", eager=True)
    def _older_prompt(event):
        event.current_buffer.history_backward()

    @bindings.add("down", eager=True)
    def _newer_prompt(event):
        event.current_buffer.history_forward()

    @bindings.add("c-r")
    def _reverse_search(event):
        event.current_buffer.start_history_lines_completion()

    return bindings

def build_prompt_reader():
    """Return an input reader with durable Up/Down history across launches."""
    PROMPT_HISTORY_FILE.touch(mode=0o600, exist_ok=True)
    try:
        os.chmod(PROMPT_HISTORY_FILE, 0o600)
    except OSError:
        pass

    try:
        from prompt_toolkit import PromptSession
        from prompt_toolkit.auto_suggest import AutoSuggestFromHistory
        from prompt_toolkit.completion import Completer, Completion
        from prompt_toolkit.history import FileHistory
        from prompt_toolkit.styles import Style

        class SlashCommandCompleter(Completer):
            def get_completions(self, document, complete_event):
                text = document.text_before_cursor
                if not text.startswith("/") or " " in text:
                    return
                names = {
                    item[0].split()[0].split("|")[0]
                    for item in COMMAND_HELP
                }
                names.update(BUILTIN_COMMAND_NAMES)
                names.update(WORKFLOW_COMMANDS)
                names.update(_load_custom_commands())
                prefix = text[1:].lower()
                for command in sorted(names):
                    if command.startswith(prefix):
                        yield Completion(
                            "/" + command,
                            start_position=-len(text),
                        )

        session = PromptSession(
            history=FileHistory(str(PROMPT_HISTORY_FILE)),
            enable_history_search=False,
            completer=SlashCommandCompleter(),
            complete_while_typing=True,
            complete_in_thread=True,
            auto_suggest=AutoSuggestFromHistory(),
            key_bindings=build_prompt_key_bindings(),
        )
        style = Style.from_dict({"label": "bold #ffffff", "arrow": "#00d7ff"})

        def read_prompt():
            return session.prompt(
                [("class:label", "  YOU "), ("class:arrow", "› ")],
                style=style,
            ).strip()

        return read_prompt
    except ImportError:
        try:
            import readline

            try:
                readline.read_history_file(PROMPT_HISTORY_FILE)
            except (FileNotFoundError, OSError):
                pass
            readline.set_history_length(-1)

            def read_prompt():
                value = input("\033[1;37m  YOU › \033[0m").strip()
                if value:
                    readline.write_history_file(PROMPT_HISTORY_FILE)
                return value

            return read_prompt
        except ImportError:
            return lambda: input("\033[1;37m  YOU › \033[0m").strip()


def interactive_mode(model_path):
    """Run the agent in interactive (chat) mode."""
    ensure_initial_server_until_ready(model_path)

    conversation = [{"role": "system", "content": build_system_prompt()}]

    _render_banner(model_path)
    print()

    # Pipe mode (for echo "task" | llama-agent)
    if not sys.stdin.isatty():
        lines = [l.strip() for l in sys.stdin if l.strip()]
        pending = load_pending_task()
        if pending and not lines:
            print(pending_task_notice(pending) + "\n")
        for line in lines:
            if not run_user_input(line, conversation):
                break
        stop_server()
        return

    # Interactive REPL
    graceful_interactive_exit = False
    try:
        read_prompt = build_prompt_reader()
        pending = load_pending_task()
        if pending:
            print("  " + pending_task_notice(pending) + "\n")
        consecutive_prompt_eofs = 0
        while True:
            try:
                user_input = read_prompt()
            except EOFError:
                consecutive_prompt_eofs += 1
                mark_current_task_interrupted(
                    "interactive prompt input stream ended unexpectedly"
                )
                print(
                    "\n\033[1;33m[RECOVERY]\033[0m Interactive input ended "
                    "unexpectedly. Rebuilding the prompt; Ctrl+C still returns "
                    "to PowerShell."
                )
                if consecutive_prompt_eofs >= 3:
                    raise RuntimeError(
                        "interactive input stream ended three consecutive times"
                    )
                time.sleep(2)
                read_prompt = build_prompt_reader()
                continue
            consecutive_prompt_eofs = 0
            if not user_input:
                continue
            if not run_user_input(user_input, conversation):
                graceful_interactive_exit = True
                break
    except KeyboardInterrupt:
        graceful_interactive_exit = True
    finally:
        stop_server()
        if graceful_interactive_exit:
            print("\n\033[0;37mGoodbye!\033[0m")

def _single_shot_mode_inner(msg, model_path, resume=False):
    """Run one task and exit."""
    pending = load_pending_task()
    if pending and not resume:
        print(pending_task_notice(pending))
        return
    if resume and not pending:
        print("\033[0;33m[NO ACTIVE TASK]\033[0m No checkpoint is available to resume.")
        return
    if resume:
        conversation = sanitize_resume_conversation(
            pending.get("conversation") or [], pending.get("objective", "")
        )
        print(f"\033[1;35m[RECOVERY]\033[0m Resuming unfinished task {pending.get('task_id', '')}.")
        response = agent_turn(
            pending.get("objective", ""), conversation,
            resume_payload=pending,
        )
    else:
        conversation = [{"role": "system", "content": build_system_prompt()}]
        response = agent_turn(msg, conversation)
    for entry in extract_memory_entries(response):
        save_memory("-" + " ".join(entry.splitlines())[:500])
    print(response)
    stop_server()


def single_shot_mode(msg, model_path, resume=False):
    """Run one noninteractive job and always signal when it stops."""
    ensure_initial_server_until_ready(model_path)
    with completion_chime_after_job():
        return _single_shot_mode_inner(msg, model_path, resume=resume)


def _server_mode_inner(model_path):
    """Run as an HTTP API server (don't start agent loop)."""
    ensure_initial_server_until_ready(model_path)
    print(f"\033[1;32m  API server running at http://{SERVER_HOST}:{SERVER_PORT}\033[0m")
    print(f"\033[0;37m  Press Ctrl+C to stop\033[0m\n")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        pass
    finally:
        stop_server()


def server_mode(model_path):
    """Run the API service and ring when the service actually stops."""
    with completion_chime_after_job():
        return _server_mode_inner(model_path)


# ─── Entry point ────────────────────────────────────────────────────────────

def main():
    model_path = find_model()
    if not model_path:
        print("\033[0;31m[ERROR]\033[0m No .gguf model found in ~/models/")
        print("  Download one: wget -O ~/models/model.gguf <url>")
        sys.exit(1)

    args = sys.argv[1:]

    if "--server" in args:
        server_mode(model_path)
    elif args:
        resume_requested = "--resume" in args
        msg = " ".join(a for a in args if not a.startswith("-"))
        if resume_requested and msg:
            print("\033[0;31m[USAGE]\033[0m llama --resume does not accept a second task.")
            sys.exit(2)
        single_shot_mode(msg, model_path, resume=resume_requested)
    else:
        interactive_mode(model_path)

def _shutdown_signal(signum, frame):
    mark_current_task_interrupted(f"process received signal {signum}")
    stop_server()
    raise SystemExit(128 + signum)

if __name__ == "__main__":
    signal.signal(signal.SIGTERM, _shutdown_signal)
    signal.signal(signal.SIGINT, signal.default_int_handler)
    main()
AGENTEOF
chmod +x "$HOME/.local/bin/llama-agent"

# ── Shell wrappers ──
cat > "$HOME/.local/bin/llama" <<'LLEOF'
#!/usr/bin/env bash
# llama — start the interactive AI agent
export PATH="$HOME/.local/share/mise/shims:$HOME/.cargo/bin:$HOME/llama.cpp/build/bin:/usr/local/cuda/bin:$HOME/.local/bin:$PATH"
export PATH="/usr/lib/wsl/lib:$PATH"
export LD_LIBRARY_PATH="$HOME/llama.cpp/build/bin:${LD_LIBRARY_PATH:-}"
PY="$HOME/.local/share/llama-agent/venv/bin/python"
[ -x "$PY" ] || PY=python3
trap 'exit 130' INT TERM
while true; do
    "$PY" "$HOME/.local/bin/llama-agent" "$@"
    status=$?
    if [ "$status" -eq 0 ]; then
        exit 0
    fi
    printf '\n[RECOVERY] Nature ended unexpectedly (exit %s). The protected checkpoint remains available; restarting this session in 2 seconds. Press Ctrl+C to return to PowerShell.\n' "$status" >&2
    sleep 2
done
LLEOF
chmod +x "$HOME/.local/bin/llama"

cat > "$HOME/.local/bin/chat" <<'CHEOF'
#!/usr/bin/env bash
# chat — alias for llama
exec "$HOME/.local/bin/llama" "$@"
CHEOF
chmod +x "$HOME/.local/bin/chat"

ok "AI agent v11 installed"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 9 — Models listing helper
# ═══════════════════════════════════════════════════════════════════════════════
cat > "$HOME/.local/bin/models" <<'MODEOF'
#!/usr/bin/env bash
# models — list downloaded GGUF models
MODEL_DIR="$HOME/models"
if [ ! -d "$MODEL_DIR" ] || [ -z "$(ls "$MODEL_DIR"/*.gguf 2>/dev/null)" ]; then
    echo "No models downloaded yet."
    echo "Download one: wget -O ~/models/model.gguf <huggingface-url>"
    exit 0
fi
echo "Downloaded models:"
echo ""
for f in "$MODEL_DIR"/*.gguf; do
    size=$(du -h "$f" | cut -f1)
    name=$(basename "$f")
    echo "  $size  $name"
done
MODEOF
chmod +x "$HOME/.local/bin/models"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 10 — Environment configuration
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 10/11: Configuring environment..."

add_to_bashrc() {
    local pattern="$1" line="$2"
    grep -q "$pattern" ~/.bashrc 2>/dev/null || echo "$line" >> ~/.bashrc
}
add_to_bashrc '$HOME/.local/bin' 'export PATH="$HOME/.local/bin:$PATH"'
add_to_bashrc '$HOME/.local/share/mise/shims' 'export PATH="$HOME/.local/share/mise/shims:$PATH"'
add_to_bashrc '$HOME/.cargo/bin' 'export PATH="$HOME/.cargo/bin:$PATH"'
add_to_bashrc 'llama.cpp/build/bin' 'export LD_LIBRARY_PATH="$HOME/llama.cpp/build/bin:${LD_LIBRARY_PATH:-}"'
add_to_bashrc '/usr/local/cuda/bin' 'export PATH="/usr/local/cuda/bin:$PATH"'
add_to_bashrc '/usr/lib/wsl/lib' 'export PATH="/usr/lib/wsl/lib:$PATH"'

# Make the primary commands available to `wsl.exe -- llama ...` and other
# noninteractive shells that intentionally skip ~/.bashrc.
for executable in llama chat models; do
    if [ -x "$HOME/.local/bin/$executable" ]; then
        sudo ln -sfn "$HOME/.local/bin/$executable" "/usr/local/bin/$executable" \
            || warn "$executable is installed in ~/.local/bin but could not be exposed through /usr/local/bin"
    fi
done

ok "Environment configured"

# ═══════════════════════════════════════════════════════════════════════════════
# STEP 11 — End-to-end tests
# ═══════════════════════════════════════════════════════════════════════════════
info "Step 11/11: Running end-to-end tests..."

# Test 1: llama-server binary exists
if [ -n "${LLAMA_SERVER_PATH:-}" ] && [ -f "$LLAMA_SERVER_PATH" ]; then
    ok "Test 1/4: llama-server binary exists"
else
    LA_APP=$(find "$LLAMA_DIR/build" -name "llama" -type f -executable 2>/dev/null | head -1)
    if [ -n "$LA_APP" ]; then
        ok "Test 1/4: llama binary exists (server via subcommand)"
    else
        warn "Test 1/4: Server binary not found"
    fi
fi

# Test 2: Model exists
MODEL_FILE=""
if [ -f "$MODEL_DIR/.chosen-model" ]; then
    CHOSEN_NAME=$(cat "$MODEL_DIR/.chosen-model" 2>/dev/null || true)
    if [ -n "$CHOSEN_NAME" ] && [ -f "$MODEL_DIR/$CHOSEN_NAME" ] && is_main_model_file "$MODEL_DIR/$CHOSEN_NAME"; then
        MODEL_FILE="$MODEL_DIR/$CHOSEN_NAME"
    fi
fi
if [ -z "$MODEL_FILE" ]; then
    MODEL_FILE=$(find "$MODEL_DIR" -maxdepth 1 -name "*.gguf" -type f -printf '%s %p\n' 2>/dev/null \
        | while read -r size path; do
            is_main_model_file "$path" && printf '%s %s\n' "$size" "$path"
          done \
        | sort -rn | head -1 | cut -d' ' -f2-)
fi
if [ -n "$MODEL_FILE" ]; then
    ok "Test 2/4: Model: $(basename "$MODEL_FILE") ($(du -h "$MODEL_FILE" | cut -f1))"
else
    warn "Test 2/4: No model found"
fi

# Verify the broad development baseline before the installer can commit a stamp.
export PATH="$HOME/.local/share/mise/shims:$HOME/.cargo/bin:$HOME/.local/bin:/usr/local/bin:$PATH"
TOOLCHAIN_COMMANDS=(
    gcc g++ clang cmake ninja meson gdb
    python3 pip3 node npm npx tsc eslint
    dotnet java javac mvn gradle go rustc cargo
    ruby gem php composer lua luac luarocks
    R Rscript ghc cabal nim crystal erl elixir
    mono fpc ocaml opam clojure kotlinc scala
    pwsh mise
)
TOOLCHAIN_MISSING=()
for executable in "${TOOLCHAIN_COMMANDS[@]}"; do
    command -v "$executable" >/dev/null 2>&1 ||
        TOOLCHAIN_MISSING+=("$executable")
done
if [ "${#TOOLCHAIN_MISSING[@]}" -gt 0 ]; then
    fail "Toolchain acceptance failed; missing commands: ${TOOLCHAIN_MISSING[*]}"
fi
NODE_MAJOR=$(FORCE_COLOR=0 node -p 'Number(process.versions.node.split(".")[0])')
if ! [[ "$NODE_MAJOR" =~ ^[0-9]+$ ]]; then
    fail "Toolchain acceptance could not parse the installed Node.js major version: ${NODE_MAJOR:-empty output}"
fi
if [ "$NODE_MAJOR" -lt 24 ]; then
    fail "Toolchain acceptance requires Node.js 24 LTS or newer; found $(node --version)"
fi

TOOLCHAIN_SMOKE=$(mktemp -d)
cleanup_toolchain_smoke() {
    rm -rf "$TOOLCHAIN_SMOKE"
}
trap 'cleanup_toolchain_smoke; stop_progress_clock' EXIT
set_activity "Compiling and running smoke programs with C, C++, Python, Node, .NET, Java, Go, and Rust"
printf '%s\n' '#include <stdio.h>' 'int main(void){puts("C_OK");return 0;}' \
    > "$TOOLCHAIN_SMOKE/main.c"
gcc "$TOOLCHAIN_SMOKE/main.c" -o "$TOOLCHAIN_SMOKE/c-smoke"
[ "$("$TOOLCHAIN_SMOKE/c-smoke")" = "C_OK" ] ||
    fail "C compiler smoke test failed"
printf '%s\n' '#include <iostream>' 'int main(){std::cout<<"CPP_OK";}' \
    > "$TOOLCHAIN_SMOKE/main.cpp"
g++ "$TOOLCHAIN_SMOKE/main.cpp" -o "$TOOLCHAIN_SMOKE/cpp-smoke"
[ "$("$TOOLCHAIN_SMOKE/cpp-smoke")" = "CPP_OK" ] ||
    fail "C++ compiler smoke test failed"
[ "$(python3 -c 'print("PYTHON_OK")')" = "PYTHON_OK" ] ||
    fail "Python runtime smoke test failed"
[ "$(node -e 'process.stdout.write("NODE_OK")')" = "NODE_OK" ] ||
    fail "Node.js runtime smoke test failed"
dotnet new console --force -n DotnetSmoke -o "$TOOLCHAIN_SMOKE/dotnet" \
    >/dev/null
[ "$(dotnet run --project "$TOOLCHAIN_SMOKE/dotnet" --no-restore)" = "Hello, World!" ] ||
    fail ".NET SDK compile/run smoke test failed"
printf '%s\n' \
    'public class Main { public static void main(String[] args) { System.out.print("JAVA_OK"); } }' \
    > "$TOOLCHAIN_SMOKE/Main.java"
javac "$TOOLCHAIN_SMOKE/Main.java"
[ "$(java -cp "$TOOLCHAIN_SMOKE" Main)" = "JAVA_OK" ] ||
    fail "Java compiler smoke test failed"
printf '%s\n' \
    'package main' \
    'import "fmt"' \
    'func main(){fmt.Print("GO_OK")}' \
    > "$TOOLCHAIN_SMOKE/main.go"
[ "$(go run "$TOOLCHAIN_SMOKE/main.go")" = "GO_OK" ] ||
    fail "Go compiler smoke test failed"
printf '%s\n' 'fn main(){print!("RUST_OK");}' > "$TOOLCHAIN_SMOKE/main.rs"
rustc "$TOOLCHAIN_SMOKE/main.rs" -o "$TOOLCHAIN_SMOKE/rust-smoke"
[ "$("$TOOLCHAIN_SMOKE/rust-smoke")" = "RUST_OK" ] ||
    fail "Rust compiler smoke test failed"
cleanup_toolchain_smoke
trap stop_progress_clock EXIT
ok "Toolchain acceptance: 46 commands found; 8 representative languages compiled and ran"

# Test 3: Server starts and responds
MODEL_SIZE_GB=$(du -m "$MODEL_FILE" 2>/dev/null | cut -f1)
MODEL_SIZE_GB=$(( (MODEL_SIZE_GB + 1024) / 1024 ))
if [ -n "${MODEL_FILE:-}" ] && [ $(( MODEL_SIZE_GB - 4 )) -le "$MEM_GB" ]; then
    export PATH="$LLAMA_DIR/build/bin:/usr/local/cuda/bin:$PATH"
    export LD_LIBRARY_PATH="$LLAMA_DIR/build/bin:/usr/local/cuda/lib64:${LD_LIBRARY_PATH:-}"

    TEST_PORT=""
    TEST_PID=""
    TEST_OWNS_SERVER=0
    TEST_OK=0
    TEST_BASE_URL=""
    TEST_RESPONSE_PID=""
    TEST_RESPONSE_FILE=""
    cleanup_model_acceptance() {
        if [ -n "${TEST_RESPONSE_PID:-}" ] &&
           kill -0 "$TEST_RESPONSE_PID" 2>/dev/null; then
            kill "$TEST_RESPONSE_PID" 2>/dev/null || true
            wait "$TEST_RESPONSE_PID" 2>/dev/null || true
        fi
        [ -n "${TEST_RESPONSE_FILE:-}" ] &&
            rm -f "$TEST_RESPONSE_FILE"
        if [ "${TEST_OWNS_SERVER:-0}" -eq 1 ] &&
           [ -n "${TEST_PID:-}" ]; then
            kill "$TEST_PID" 2>/dev/null || true
            wait "$TEST_PID" 2>/dev/null || true
        fi
        TEST_RESPONSE_PID=""
        TEST_RESPONSE_FILE=""
        TEST_PID=""
        TEST_OWNS_SERVER=0
    }
    trap 'cleanup_model_acceptance; stop_progress_clock' EXIT
    EXISTING_MODEL=$(curl -sS --max-time 4 \
        "http://127.0.0.1:8080/v1/models" 2>/dev/null |
        jq -r '.data[0].id // .models[0].model // empty' 2>/dev/null || true)
    if curl -sS --max-time 4 "http://127.0.0.1:8080/health" 2>/dev/null |
       grep -q ok &&
       [ -n "$EXISTING_MODEL" ] &&
       [ "$(basename "$EXISTING_MODEL")" = "$(basename "$MODEL_FILE")" ]; then
        TEST_PORT=8080
        TEST_BASE_URL="http://127.0.0.1:$TEST_PORT"
        TEST_OK=1
        set_activity "Verifying the healthy existing model server on port 8080; its exact model matches and it will not be stopped"
        ok "Test 3/4: Reused the healthy exact-model server on port 8080 without stopping it"
    else
        TEST_PORT=$("$AGENT_VENV/bin/python" - <<'PYEOF'
import socket
with socket.socket() as sock:
    sock.bind(("127.0.0.1", 0))
    print(sock.getsockname()[1])
PYEOF
        )
        TEST_BASE_URL="http://127.0.0.1:$TEST_PORT"
        info "  Using isolated dynamic test port $TEST_PORT; no existing process will be stopped"

        # Find and start one isolated server only when no compatible live
        # server exists. This process is the only one cleanup may stop.
        LA_BIN=$(find "$LLAMA_DIR/build" -name "llama-server" -type f -executable 2>/dev/null | head -1)
        if [ -z "$LA_BIN" ]; then
            LA_BIN=$(find "$LLAMA_DIR/build" -name "llama" -type f -executable 2>/dev/null | head -1)
            LA_CMD=("$LA_BIN" "server")
        else
            LA_CMD=("$LA_BIN")
        fi

        # --flash-attn changed in newer llama.cpp: bare flag now eats the next
        # argument and the server exits immediately. Detect the build's style.
        FLASH_FLAG="--flash-attn"
        if "$LA_BIN" --help 2>/dev/null | grep -q -- '--flash-attn \[on'; then
            FLASH_FLAG="--flash-attn on"
        fi
        TEST_GPU_ARGS=()
        if [ "${HAS_NVIDIA:-0}" -eq 1 ]; then
            TEST_FIT_TARGET_MB=$(( ${GPU_VRAM_MB:-0} * 22 / 100 ))
            [ "$TEST_FIT_TARGET_MB" -lt 3072 ] && TEST_FIT_TARGET_MB=3072
            [ "$TEST_FIT_TARGET_MB" -gt 4096 ] && TEST_FIT_TARGET_MB=4096
            TEST_MODEL_MB=$(( ($(stat -c %s "$MODEL_FILE") + 1048575) / 1048576 ))
            TEST_FREE_MB=$("$NVIDIA_SMI" --query-gpu=memory.free --format=csv,noheader,nounits 2>/dev/null |
                head -1 | tr -dc '0-9')
            [ -z "$TEST_FREE_MB" ] && TEST_FREE_MB=0
            if [ "$TEST_FREE_MB" -gt 0 ] &&
               [ $(( TEST_MODEL_MB + 1024 + TEST_FIT_TARGET_MB )) -le "$TEST_FREE_MB" ]; then
                TEST_GPU_ARGS=(--n-gpu-layers 999)
                info "  The selected model fits fully on the GPU while preserving ${TEST_FIT_TARGET_MB}MB for context and Windows"
            elif "$LA_BIN" --help 2>&1 | grep -q -- '--fit-target'; then
                TEST_GPU_ARGS=(
                    --n-gpu-layers auto --fit on
                    --fit-target "$TEST_FIT_TARGET_MB"
                )
                info "  Isolated model test will automatically fit GPU layers while keeping ${TEST_FIT_TARGET_MB}MB of VRAM free"
            else
                TEST_GPU_ARGS=(--n-gpu-layers 0)
                info "  This llama.cpp build lacks safe automatic fitting; the isolated health test will use system RAM"
            fi
        else
            TEST_GPU_ARGS=(--n-gpu-layers 0)
        fi

        "${LA_CMD[@]}" \
            --model "$MODEL_FILE" --threads "$(( CORES > 8 ? 8 : CORES ))" --ctx-size 32768 \
            --host 127.0.0.1 --port "$TEST_PORT" \
            "${TEST_GPU_ARGS[@]}" \
            $FLASH_FLAG --jinja --cont-batching \
            </dev/null >/tmp/llama_test.log 2>&1 &
        TEST_PID=$!
        TEST_OWNS_SERVER=1

        for i in $(seq 1 90); do
            if curl -sS --max-time 4 "$TEST_BASE_URL/health" 2>/dev/null |
               grep -q ok; then
                TEST_OK=1
                break
            fi
            if ! kill -0 "$TEST_PID" 2>/dev/null; then
                break
            fi
            TEST_RSS_KB=$(ps -o rss= -p "$TEST_PID" 2>/dev/null | tr -d ' ' || true)
            TEST_CPU=$(ps -o %cpu= -p "$TEST_PID" 2>/dev/null | xargs || true)
            TEST_RSS_MB=$(( ${TEST_RSS_KB:-0} / 1024 ))
            set_activity "Loading the isolated model test on port $TEST_PORT: $(( i * 2 )) seconds elapsed, ${TEST_RSS_MB} MB in memory, ${TEST_CPU:-0}% CPU"
            sleep 2
        done
        if [ "$TEST_OK" -eq 1 ]; then
            ok "Test 3/4: Isolated server starts and responds to health check"
        fi
    fi

    if [ "$TEST_OK" -eq 1 ]; then
        # Model response test. Modern picks (GLM-4.7-Flash, Qwen3, ...) are
        # REASONING models: they think first (reasoning_content) and emit the
        # visible answer in `content` only afterwards. A tiny max_tokens makes
        # the answer never appear, so we retry with a real budget and accept a
        # plain-English reply.
        CONTENT=""
        REASONING=""
        ACTIVE_MODEL_ACTIONS=0
        if [ "$TEST_OWNS_SERVER" -eq 0 ] &&
           [ -f "$HOME/.local/share/llama-agent/active-task.json" ]; then
            ACTIVE_MODEL_ACTIONS=$("$AGENT_VENV/bin/python" - <<'PYEOF'
import json
import time
from pathlib import Path

path = Path.home() / ".local/share/llama-agent/active-task.json"
try:
    data = json.loads(path.read_text())
    recent = time.time() - path.stat().st_mtime <= 900
    actions = int(data.get("successful_actions", 0))
    print(actions if data.get("status") == "running" and recent else 0)
except Exception:
    print(0)
PYEOF
            )
        fi
        if [ "${ACTIVE_MODEL_ACTIONS:-0}" -gt 0 ]; then
            CONTENT="active-task-evidence"
            ok "Test 4/4: Existing model session already produced ${ACTIVE_MODEL_ACTIONS} successful tool action(s) for the current task"
        else
            for attempt in 1 2 3 4; do
                TEST_RESPONSE_FILE=$(mktemp)
                curl -sS --max-time 180 "$TEST_BASE_URL/v1/chat/completions" \
                    -H "Content-Type: application/json" \
                    -d '{"model":"local","messages":[{"role":"user","content":"Say exactly and only: test passed"}],"max_tokens":512,"temperature":0.3}' \
                    >"$TEST_RESPONSE_FILE" 2>/dev/null &
                TEST_RESPONSE_PID=$!
                for response_wait in $(seq 1 90); do
                    if ! kill -0 "$TEST_RESPONSE_PID" 2>/dev/null; then
                        break
                    fi
                    set_activity "Testing one visible model answer on port $TEST_PORT: attempt $attempt, $(( response_wait * 2 )) seconds elapsed"
                    sleep 2
                done
                wait "$TEST_RESPONSE_PID" 2>/dev/null || true
                TEST_RESPONSE_PID=""
                RESP=$(cat "$TEST_RESPONSE_FILE" 2>/dev/null || true)
                rm -f "$TEST_RESPONSE_FILE"
                TEST_RESPONSE_FILE=""
                CONTENT=$(echo "$RESP" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
                REASONING=$(echo "$RESP" | jq -r '.choices[0].message.reasoning_content // empty' 2>/dev/null)
                [ -n "$CONTENT" ] && break
                sleep 2
            done
        fi
        if [ "$CONTENT" = "active-task-evidence" ]; then
            :
        elif [ -n "$CONTENT" ]; then
            ok "Test 4/4: Model responds: $CONTENT"
        elif [ -n "$REASONING" ]; then
            fail "Test 4/4: Model produced reasoning but no visible answer after four attempts"
        else
            fail "Test 4/4: Model produced no visible response after four attempts"
        fi
    else
        fail "Test 3/4: Server did not respond in time"
    fi

    if [ "$TEST_OWNS_SERVER" -eq 1 ]; then
        cleanup_model_acceptance
        sleep 1
    fi
    trap stop_progress_clock EXIT
elif [ -n "${MODEL_FILE:-}" ]; then
    info "  Test 3+4 skipped: the ${MODEL_SIZE_GB}GB model needs more RAM than this ${MEM_GB}GB WSL session."
    info "  Restart WSL once (run: wsl --shutdown) so the 16GB from .wslconfig takes effect,"
    info "  then just run: llama"
fi

# Test: win-tools
if [ -d "/mnt/c/Users" ]; then
    WIN_RESULT=$(PATH="$HOME/.local/bin:$PATH" win-tools disk C 2>&1 | head -5 || true)
    if echo "$WIN_RESULT" | grep -qi "drive\|GB\|Free"; then
        ok "Test: win-tools works"
    else
        fail "Test: win-tools returned unexpected output: ${WIN_RESULT:-no output}"
    fi
    WIN_DIR=$(PATH="$HOME/.local/bin:$PATH" win-tools dir C 2>&1 | head -8 || true)
    if echo "$WIN_DIR" | grep -qi "folders on\|Name"; then
        ok "Test: win-tools dir works"
    else
        fail "Test: win-tools dir returned unexpected output: ${WIN_DIR:-no output}"
    fi
    WIN_FOLDERS=$(PATH="$HOME/.local/bin:$PATH" win-tools dir C FOLDERS 2>&1 || true)
    WIN_FOLDER_ROWS=$(printf '%s\n' "$WIN_FOLDERS" | grep -c '^FOLDER|' || true)
    WIN_FOLDER_TOTAL=$(printf '%s\n' "$WIN_FOLDERS" |
        sed -n 's/^SUMMARY|dir|.*|folders=\([0-9][0-9]*\)|mode=folders-only$/\1/p' |
        tail -1)
    if [ -z "$WIN_FOLDER_TOTAL" ] ||
       [ "$WIN_FOLDER_ROWS" -ne "$WIN_FOLDER_TOTAL" ] ||
       printf '%s\n' "$WIN_FOLDERS" | grep -q '^FILE|'; then
        fail "Test: folder-only drive listing was incomplete or included files: ${WIN_FOLDERS:-no output}"
    fi
    ok "Test: win-tools folder-only mode returned all $WIN_FOLDER_TOTAL folders and no files"
fi

# Test: browse
if [ -x "$HOME/.local/bin/browse" ]; then
    ok "Test: browse command installed"
else
    warn "Test: browse command missing"
fi

info "  Testing the extracted agent, routed tools, bounded edits, and cross-session history..."
if "$AGENT_VENV/bin/python" -m py_compile "$HOME/.local/bin/llama-agent" && \
   "$AGENT_VENV/bin/python" - "$HOME/.local/bin/llama-agent" <<'PYTESTEOF'
import contextlib
import importlib.util
from importlib.machinery import SourceFileLoader
import io
import inspect
import json
import os
import tempfile
import threading
import time
from pathlib import Path

agent_path = os.sys.argv[1]
agent_source = Path(agent_path).read_text(encoding="utf-8")
loader = SourceFileLoader("nature_acceptance", agent_path)
spec = importlib.util.spec_from_loader(loader.name, loader)
nature = importlib.util.module_from_spec(spec)
loader.exec_module(nature)

assert nature.merge_stream_fragment("", "read_") == "read_"
assert nature.merge_stream_fragment("read_", "file") == "read_file"
assert nature.merge_stream_fragment("abc", "abc") == "abcabc"
assert nature.merge_stream_fragment("abc", "c") == "abcc"
assert nature.merge_stream_fragment("old", "new", snapshot=True) == "new"
assert nature.merge_tool_name_fragment("run_", "run_command") == "run_command"
assert nature.merge_tool_name_fragment("read_file", "read_file") == "read_file"
stream_body = nature._prepare_stream_body({"model": "local"})
assert stream_body["return_progress"] is True
assert stream_body["sse_ping_interval"] == 1
assert stream_body["parse_tool_calls"] is True
assert stream_body["parallel_tool_calls"] is False
assert nature.DISABLE_MODEL_THINKING is True
assert "chat_template_kwargs" in inspect.getsource(nature.send_message)

class FakeResponse:
    def __init__(self, lines):
        self.lines = lines
    def __enter__(self):
        return self
    def __exit__(self, exc_type, exc, tb):
        return False
    def __iter__(self):
        for blob in self.lines:
            for line in blob.splitlines(keepends=True):
                yield line

def sse_event(payload):
    return ("data: " + json.dumps(payload) + "\n\n").encode("utf-8")

original_urlopen = nature.urllib.request.urlopen
try:
    nature.urllib.request.urlopen = lambda *args, **kwargs: FakeResponse([
        sse_event({"prompt_progress": {
            "total": 100, "cache": 25, "processed": 50, "time_ms": 12,
        }}),
        sse_event({"choices": [{"delta": {
            "content": "abc",
            "tool_calls": [{
                "index": 0, "id": "call-1",
                "function": {
                    "name": "run_",
                    "arguments": '{"command":"printf ',
                },
            }],
        }}]}),
        sse_event({"choices": [{"delta": {
            "content": "abc",
            "tool_calls": [{
                "index": 0, "id": "call-1",
                "function": {
                    "name": "run_command",
                    "arguments": 'ready"}',
                },
            }],
        }}]}),
        sse_event({"choices": [{"delta": {}, "finish_reason": "tool_calls"}]}),
        b"data: [DONE]\n\n",
    ])
    streamed = nature.api_chat_stream({
        "model": "local",
        "messages": [{"role": "user", "content": "fixture"}],
        "tools": [nature.TOOL_CATALOG["run_command"]],
    }, 1)
finally:
    nature.urllib.request.urlopen = original_urlopen
streamed_message = streamed["choices"][0]["message"]
assert streamed_message["content"] == "abcabc", streamed_message
assert streamed_message["tool_calls"][0]["id"] == "call-1", streamed_message
assert (
    streamed_message["tool_calls"][0]["function"]["name"] == "run_command"
), streamed_message
assert json.loads(
    streamed_message["tool_calls"][0]["function"]["arguments"]
) == {"command": "printf ready"}

try:
    nature.urllib.request.urlopen = lambda *args, **kwargs: FakeResponse([
        b"data: {malformed-json}\n\n",
    ])
    malformed_stream = nature.api_chat_stream({
        "model": "local",
        "messages": [{"role": "user", "content": "fixture"}],
    }, 1)
finally:
    nature.urllib.request.urlopen = original_urlopen
assert "Malformed SSE JSON" in malformed_stream["error"], malformed_stream

try:
    nature.urllib.request.urlopen = lambda *args, **kwargs: FakeResponse([
        sse_event({"choices": [{
            "delta": {"content": "partial"},
            "finish_reason": "stop",
        }]}),
    ])
    incomplete_stream = nature.api_chat_stream({
        "model": "local",
        "messages": [{"role": "user", "content": "fixture"}],
    }, 1)
finally:
    nature.urllib.request.urlopen = original_urlopen
assert "required [DONE] marker" in incomplete_stream["error"], incomplete_stream

malformed_arguments = (
    '{"path":"/tmp/app.py","content":"prefix\\n'
    'uninstall_string = winreg.QueryValueEx(root, "UninstallString")[0]\\n'
    '# Extract path\\nNEW_TAIL'
)
malformed_view = nature._decode_partial_json_field(
    malformed_arguments, "content"
)
assert "NEW_TAIL" in malformed_view["text"], malformed_view
assert malformed_view["status"] == "ambiguous_quote", malformed_view
assert malformed_view["raw_length"] == len(malformed_arguments)
invalid_escape = nature._decode_partial_json_field(
    '{"content":"keep' + chr(92) + 'qtail', "content"
)
assert "\\q" in invalid_escape["text"], invalid_escape
assert invalid_escape["status"] == "invalid_escape", invalid_escape
partial_unicode = nature._decode_partial_json_field(
    '{"content":"value ' + chr(92) + 'u12', "content"
)
assert partial_unicode["status"] == "partial_unicode", partial_unicode
surrogate_pair = nature._decode_partial_json_field(
    '{"content":"' + chr(92) + 'uD83D' + chr(92) + 'uDE00"}', "content"
)
assert surrogate_pair["text"] == "\U0001F600", surrogate_pair
lone_surrogate = nature._decode_partial_json_field(
    '{"content":"' + chr(92) + 'uDEAD', "content"
)
assert lone_surrogate["text"] == "\\uDEAD", lone_surrogate
assert lone_surrogate["status"] == "unpaired_surrogate", lone_surrogate
telemetry = nature.ModelTelemetry(1, 1, 1)
telemetry.update({
    "tool_calls": [{"index": 0, "function": {"name": "read_file"}}],
})
telemetry.update({
    "tool_calls": [{"index": 0, "function": {"name": "read_file"}}],
})
assert telemetry.tool_names[0] == "read_file", telemetry.tool_names
tool_status = telemetry.report(1)
assert tool_status[0] == "model-tool:0:read_file", tool_status
assert "selecting the exact file to read" in tool_status[1].lower(), tool_status
assert "read fileread file" not in tool_status[1]
reasoning_telemetry = nature.ModelTelemetry(2, 1, 1)
reasoning_telemetry.connected = True
reasoning_telemetry.update({
    "reasoning_content": (
        "I will inspect /mnt/f/Downloads/c first, then build the installed-app "
        "inventory scanner."
    )
})
reasoning_status = reasoning_telemetry.report(1)
assert reasoning_status[0].startswith("model-planning:"), reasoning_status
assert "next concrete action" in reasoning_status[1], reasoning_status
assert "88 reasoning characters" in reasoning_status[1], reasoning_status
assert "/mnt/f/Downloads/c" not in reasoning_status[1], reasoning_status
reasoning_telemetry.update({
    "reasoning_content": " Next I will create app.py with the GUI entry point."
})
reasoning_status_second = reasoning_telemetry.report(2)
assert reasoning_status_second[0] == reasoning_status[0]
assert "reasoning characters" in reasoning_status_second[1]
assert reasoning_status_second[1] != reasoning_status[1]
reasoning_telemetry.last_event_at = time.monotonic() - 13
quiet_reasoning_status = reasoning_telemetry.report(13)
assert quiet_reasoning_status[0].startswith("model-planning:"), quiet_reasoning_status
assert quiet_reasoning_status[1] != reasoning_status_second[1], quiet_reasoning_status
assert "in 13 seconds" in quiet_reasoning_status[1], quiet_reasoning_status
assert "app.py with the GUI entry point" not in quiet_reasoning_status[1]
write_telemetry = nature.ModelTelemetry(2, 1, 1)
write_telemetry.connected = True
write_telemetry.update({
    "tool_calls": [{
        "index": 0,
        "function": {
            "name": "write_file",
            "arguments": (
                '{"path":"/mnt/f/Downloads/c/app.py","content":'
                '"import tkinter as tk\\nclass InstalledAppScanner:'
            ),
        },
    }],
})
write_status = write_telemetry.report(3)
assert "/mnt/f/Downloads/c/app.py" in write_status[1], write_status
assert "import: import tkinter as tk" in write_status[1], write_status
assert "InstalledAppScanner" not in write_status[1], write_status
assert "building /mnt/f/Downloads/c/app.py now" in write_status[1], write_status
assert "characters generated" in write_status[1], write_status
assert "InstalledAppScanner class" in nature._describe_generated_text(
    "import tkinter as tk\nclass InstalledAppScanner:",
    final=True,
)
write_quiet_status = write_telemetry.report(4)
assert write_quiet_status[1] == write_status[1], write_quiet_status
assert "/mnt/f/Downloads/c/app.py" in write_quiet_status[1], write_quiet_status
write_telemetry.update({
    "tool_calls": [{
        "index": 0,
        "function": {"arguments": (
            '\\nuninstall_string = root.QueryValue("UninstallString")\\n'
            'NEW_STREAM_TAIL'
        )},
    }],
})
malformed_write_status = write_telemetry.report(5)
assert "generating its first file content now" in malformed_write_status[1], malformed_write_status
assert malformed_write_status[1] != write_status[1]
command_telemetry = nature.ModelTelemetry(2, 1, 1)
command_telemetry.connected = True
command_telemetry.update({
    "tool_calls": [{
        "index": 0,
        "function": {
            "name": "run_command",
            "arguments": (
                '{"command":"python -m pytest '
                '/mnt/f/Downloads/c/tests/test_inventory.py'
            ),
        },
    }],
})
command_status = command_telemetry.report(5)
assert "request characters have arrived" in command_status[1], command_status
assert "pytest" not in command_status[1], command_status
complete_command_status = nature._tool_progress_description(
    "run_command",
    '{"command":"python -m pytest /mnt/f/Downloads/c/tests/test_inventory.py"}',
    72,
    5,
    False,
)
assert "pytest" in complete_command_status, complete_command_status
assert "test_inventory.py" in complete_command_status, complete_command_status
live_capture = io.StringIO()
captured_progress = nature.LiveProgress(
    stream=live_capture,
    interactive=False,
)
captured_progress.start(
    (
        "controlled-quiet-stream",
        "The controlled stream is open and waiting for its first protocol event.",
    ),
    reporter=lambda elapsed: (
        "controlled-quiet-stream",
        "The controlled stream is open and waiting for its first protocol event.",
    ),
)
time.sleep(2.15)
captured_progress.stop()
live_lines = [line for line in live_capture.getvalue().splitlines() if "[WORKING]" in line]
assert len(live_lines) == 1, live_lines
original_heartbeat = nature.LIVE_LOG_HEARTBEAT_SECONDS
original_refresh = nature.LIVE_REFRESH_SECONDS
try:
    nature.LIVE_LOG_HEARTBEAT_SECONDS = 0.15
    nature.LIVE_REFRESH_SECONDS = 0.02
    heartbeat_capture = io.StringIO()
    heartbeat_progress = nature.LiveProgress(
        stream=heartbeat_capture,
        interactive=False,
    )
    heartbeat_progress.start((
        "accelerated-silence-test",
        "The test operation is waiting for its first measurable result.",
    ))
    time.sleep(0.55)
    heartbeat_progress.stop()
    heartbeat_lines = [
        line for line in heartbeat_capture.getvalue().splitlines()
        if "[WORKING]" in line
    ]
    assert len(heartbeat_lines) == 1, heartbeat_lines
    assert "Observation" not in heartbeat_capture.getvalue(), (
        heartbeat_capture.getvalue()
    )
finally:
    nature.LIVE_LOG_HEARTBEAT_SECONDS = original_heartbeat
    nature.LIVE_REFRESH_SECONDS = original_refresh
interactive_heartbeat_capture = io.StringIO()
interactive_heartbeat_capture.isatty = lambda: True
try:
    nature.LIVE_LOG_HEARTBEAT_SECONDS = 0.15
    nature.LIVE_REFRESH_SECONDS = 0.02
    interactive_heartbeat_progress = nature.LiveProgress(
        stream=interactive_heartbeat_capture,
        interactive=True,
    )
    interactive_heartbeat_progress.start((
        "interactive-heartbeat-test",
        "The interactive operation is waiting for its first measurable result.",
    ))
    time.sleep(0.55)
    interactive_heartbeat_progress.stop()
finally:
    nature.LIVE_LOG_HEARTBEAT_SECONDS = original_heartbeat
    nature.LIVE_REFRESH_SECONDS = original_refresh
interactive_heartbeat_lines = [
    line for line in interactive_heartbeat_capture.getvalue().splitlines()
    if "[WORKING]" in line
]
assert len(interactive_heartbeat_lines) == 1, interactive_heartbeat_lines
assert "Observation" not in interactive_heartbeat_capture.getvalue(), (
    interactive_heartbeat_capture.getvalue()
)
tty_capture = io.StringIO()
tty_capture.isatty = lambda: True
tty_progress = nature.LiveProgress(stream=tty_capture)
tty_state = {
    "key": "controlled-quiet-stream",
    "message": "The controlled stream has started.",
}
tty_progress.start(
    (tty_state["key"], tty_state["message"]),
    reporter=lambda elapsed: (tty_state["key"], tty_state["message"]),
)
tty_progress.refresh()
tty_progress.refresh()
tty_state["message"] = "One new verified result arrived."
tty_progress.refresh()
tty_state["message"] = "The controlled stream has started."
tty_progress.refresh()
tty_progress.stop()
tty_output = tty_capture.getvalue()
assert tty_output.count("\n") == 0, repr(tty_output)
assert tty_output.count("[WORKING]") == 2, repr(tty_output)
assert tty_output.count("\r\033[2K") == 3, repr(tty_output)
assert tty_output.endswith("\r\033[2K"), repr(tty_output)
nature.LiveProgress.begin_job()
next_job_capture = io.StringIO()
next_job_capture.isatty = lambda: True
next_job_progress = nature.LiveProgress(stream=next_job_capture)
next_job_progress.start((
    "controlled-quiet-stream",
    "The controlled stream has started.",
))
next_job_progress.stop()
assert next_job_capture.getvalue().count("[WORKING]") == 1
live_progress_source = agent_source[
    agent_source.index("class LiveProgress:"):
    agent_source.index("\nLIVE = LiveProgress()")
]
assert "_commit_transient" not in live_progress_source
assert '"/dev/tty"' in live_progress_source
assert nature.LIVE_LOG_HEARTBEAT_SECONDS <= 8.0
installer_prefix = Path(agent_path).parent.parent.parent
assert "LIVE_LOG_HEARTBEAT_SECONDS = min(" in agent_source
history_bindings = nature.build_prompt_key_bindings()
history_keys = " ".join(
    str(key) for binding in history_bindings.bindings for key in binding.keys
)
assert "Up" in history_keys and "Down" in history_keys, history_keys
files_hint = nature.plan_hint(
    "scan and list the top 50 biggest heaviest files all over my c drive ranked by size"
)
assert "50 largest files on drive C" in files_hint[0], files_hint
assert "win-tools files C 50" in files_hint[1], files_hint
assert nature.direct_largest_files_request(
    "Output the top 100 heaviest files in C-drive, ranked downwards."
) == ("C", 100)
assert nature.direct_largest_files_request(
    "Scan and list. In here the top of 100 files in my C drive ranked "
    "from heaviest downwards."
) == ("C", 100)
assert nature.normalize_windows_drive("air") == "R"
assert nature.normalize_windows_drive("R:") == "R"
assert nature.normalize_windows_drive("nonsense") is None
assert nature.extract_windows_drive(
    "List all the folders in my air drive"
) == "R"
assert nature.direct_drive_listing_request(
    "List all the folders in my air drive"
) == "R"
assert nature.direct_drive_listing_request(
    "Delete folders in my R drive"
) is None
assert nature.intercept_command(
    "win-tools dir air",
    "List all the folders in my air drive",
) == "win-tools dir R:"
assert nature.intercept_command(
    "win-tools dir air FOLDERS",
    "List all the folders in my air drive",
) == "win-tools dir R: FOLDERS"
assert nature.intercept_command(
    "win-tools disk air",
    "Show free space on my air drive",
) == "win-tools disk R"
toolchain_survey = (
    r'pwsh -NoProfile -Command "Write-Host ''--- dotnet ---''; '
    r'Get-ChildItem ''C:\Program Files\dotnet'' -Name 2>$null | '
    r'Select-Object -First 5; Write-Host ''--- python ---''; '
    r'(Get-Command python -ErrorAction SilentlyContinue).Source; '
    r'Write-Host ''--- pipx / py launcher ---''; '
    r'(Get-Command py -ErrorAction SilentlyContinue).Source"'
)
assert nature.intercept_command(
    toolchain_survey,
    "Create a Windows desktop project at F:\\Downloads\\Example and test it.",
) == "dotnet --info"
assert 0 < nature.CMD_STALL_TIMEOUT <= 30, nature.CMD_STALL_TIMEOUT
drive_hint = nature.plan_hint("List all the folders in my air drive")
assert "drive R" in drive_hint[0], drive_hint
assert "win-tools dir R FOLDERS" in drive_hint[1], drive_hint
exact_file_request = (
    "Create /tmp/nature-final-progress-proof.txt containing exactly "
    "FINAL_PROGRESS_OK, read it back, verify the exact content, then report "
    "the verified full path and content."
)
assert nature.direct_exact_file_request(exact_file_request) == (
    "/tmp/nature-final-progress-proof.txt",
    "FINAL_PROGRESS_OK",
)
assert nature.direct_exact_file_request(
    'Write the file at "/tmp/exact phrase.txt" with the content exactly '
    '"two words", then read and verify it.'
) == ("/tmp/exact phrase.txt", "two words")
assert nature.direct_exact_file_request(
    "Build a project that can create files containing exactly what users type."
) is None
read_only_request = (
    "Read /proc/sys/kernel/osrelease using tools, verify the result, "
    "and do not change any files."
)
assert not nature.objective_requires_action(read_only_request), read_only_request
assert nature.objective_requires_verification(read_only_request), read_only_request
assert not nature.objective_requires_action(
    "Verify the value without modifying files."
)
assert nature.objective_requires_action(
    "Fix the parser without changing its public API."
)
assert nature.objective_requires_action(
    "Do not stop until you fix the parser."
)
read_only_state = nature.TaskState(read_only_request)
assert not read_only_state.requires_action
assert read_only_state.requires_verification
assert read_only_state.completion_gaps("[TASK_COMPLETE]") == [
    "no successful verification action has been recorded"
]
read_only_state.sequence = 1
read_only_state.last_verification_sequence = 1
assert read_only_state.completion_gaps("[TASK_COMPLETE]") == []
verification_pressure_state = nature.TaskState(
    "Create and verify a complete project in /tmp/pressure-project"
)
verification_pressure_state.mutations = (
    nature.MAX_MUTATIONS_WITHOUT_VERIFICATION
)
assert verification_pressure_state.verification_due()
automatic_checkpoint_call = nature.automatic_verification_checkpoint_call()
assert nature._is_verification_call(automatic_checkpoint_call)
assert not nature._is_mutating_call(automatic_checkpoint_call)
automatic_checkpoint_result = nature.execute_tool_call(
    automatic_checkpoint_call,
    verification_pressure_state.objective,
)
automatic_checkpoint_success, _ = verification_pressure_state.observe_tool(
    automatic_checkpoint_call,
    automatic_checkpoint_result,
    verification_pressure_state.objective,
)
assert automatic_checkpoint_success, automatic_checkpoint_result
assert not verification_pressure_state.verification_due()
assert "AUTOMATIC_VERIFICATION_CHECKPOINT" in automatic_checkpoint_result
spaced_target_objective = (
    r"Create the Windows project in F:\Downloads\New folder in this specific path."
)
spaced_target_paths = nature.extract_target_paths(spaced_target_objective)
assert spaced_target_paths[0] == "/mnt/f/Downloads/New folder", spaced_target_paths
capability_clause_target = nature.extract_target_paths(
    r"Create a Windows desktop GUI in F:\Downloads\New folder that lists "
    r"installed applications."
)
assert capability_clause_target == [
    "/mnt/f/Downloads/New folder"
], capability_clause_target
targeted_checkpoint_call = nature.automatic_verification_checkpoint_call(
    spaced_target_objective
)
assert "/mnt/f/Downloads/New folder" in targeted_checkpoint_call["cmd"]
assert "CHECKPOINT_ROOT=" in targeted_checkpoint_call["cmd"]
unprobed_spaced_target_objective = (
    r"Create the Windows project in F:\Missing Parent\project with spaces "
    r"in this specific path."
)
unprobed_spaced_target_paths = nature.extract_target_paths(
    unprobed_spaced_target_objective
)
assert unprobed_spaced_target_paths == [
    "/mnt/f/Missing Parent/project with spaces"
], unprobed_spaced_target_paths
unprobed_checkpoint_call = nature.automatic_verification_checkpoint_call(
    unprobed_spaced_target_objective
)
assert "/mnt/f/Missing Parent/project with spaces" in unprobed_checkpoint_call["cmd"]
dependency_preflight = nature.intercept_command(
    "apt-get update && apt-get install -y dotnet-sdk-8.0 && "
    "cd /mnt/f/Downloads/New\\ folder && dotnet new console -n StartupAppsViewer",
    spaced_target_objective,
)
assert dependency_preflight == "dotnet --info", dependency_preflight
restored_spaced_target_state = nature.TaskState(
    spaced_target_objective,
    restored={"target_paths": ["/mnt/f/Downloads/New"]},
)
assert restored_spaced_target_state.target_paths == [
    "/mnt/f/Downloads/New folder"
], restored_spaced_target_state.target_paths
    saved_prompt_builder = nature.build_system_prompt
    try:
        nature.build_system_prompt = lambda: "fresh-system-prompt"
    sanitized_resume = nature.sanitize_resume_conversation(
        [
            {
                "role": "assistant",
                "content": (
                    "```bash\npowershell -Command \"cd /mnt/f/Downloads/New\\ "
                    "folder && dotnet new console -n StartupAppsViewer\"\n```"
                ),
            },
            {
                "role": "system",
                "content": (
                    "[AUTOMATIC RECONCILIATION CHECKPOINT]\n"
                    "CHECKPOINT_ROOT=/mnt/f/Downloads/New folder\n"
                ),
            },
            {
                "role": "user",
                "content": "[Tool Results]\n/bin/bash: powershell: command not found",
            },
        ],
        spaced_target_objective,
    )
finally:
    nature.build_system_prompt = saved_prompt_builder
assert sanitized_resume[0] == {
    "role": "system", "content": "fresh-system-prompt"
}, sanitized_resume
assert sanitized_resume[-1] == {
    "role": "user", "content": spaced_target_objective
}, sanitized_resume
    assert "/mnt/f/Downloads/New folder" in sanitized_resume[1]["content"]
    assert "StartupAppsViewer" not in "\n".join(
        row["content"] for row in sanitized_resume
    ), sanitized_resume
    normalized_checkpoint = nature.normalize_model_messages([
        {"role": "system", "content": "base rules"},
        {"role": "system", "content": "resume facts"},
        {"role": "user", "content": "continue the task"},
        {"role": "system", "content": "checkpoint evidence"},
        {"role": "system", "content": "recovery instruction"},
    ])
    assert [row["role"] for row in normalized_checkpoint] == [
        "system", "user", "user", "user",
    ], normalized_checkpoint
    assert "base rules\n\nresume facts" == normalized_checkpoint[0]["content"]
    assert normalized_checkpoint[1]["content"] == "continue the task"
    assert normalized_checkpoint[2]["content"].startswith(
        "[RUNTIME INSTRUCTION]\ncheckpoint evidence"
    )
    assert normalized_checkpoint[3]["content"].startswith(
        "[RUNTIME INSTRUCTION]\nrecovery instruction"
    )
    previous_task_state = nature.CURRENT_TASK_STATE
divergent_scaffold_state = nature.TaskState(spaced_target_objective)
divergent_scaffold_state.target_checks[
    "/mnt/f/Downloads/New folder"
] = {
    "exists": True,
    "nonempty": True,
    "kind": "directory",
}
try:
    nature.CURRENT_TASK_STATE = divergent_scaffold_state
    existing_gui_read_command = (
        'cd "/mnt/f/Downloads/New folder" && echo "=== README.txt ===" && '
        'cat README.txt && echo "" && echo "=== app_gui.py ===" && '
        'cat app_gui.py'
    )
    existing_gui_read = nature.intercept_command(
        existing_gui_read_command,
        spaced_target_objective,
    )
    divergent_scaffold = nature.intercept_command(
        'powershell -Command "cd /mnt/f/Downloads/New\\ folder && '
        'dotnet new console -n StartupAppsViewer"',
        spaced_target_objective,
    )
    assert divergent_scaffold.startswith(
        nature.COMMAND_REJECTION_PREFIX
    ), divergent_scaffold
    divergent_result = nature.execute_tool_call(
        {
            "type": "command",
            "cmd": 'powershell -Command "cd /mnt/f/Downloads/New\\ folder && '
                   'dotnet new console -n StartupAppsViewer"',
        },
        spaced_target_objective,
    )
finally:
    nature.CURRENT_TASK_STATE = previous_task_state
assert existing_gui_read == existing_gui_read_command, existing_gui_read
assert divergent_result.startswith("[RECOVERY REQUIRED:"), divergent_result
assert "second GUI scaffold" in divergent_result, divergent_result
raw_project_overwrite_state = nature.TaskState(spaced_target_objective)
raw_project_overwrite_state.target_checks[
    "/mnt/f/Downloads/New folder"
] = {
    "exists": True,
    "nonempty": True,
    "kind": "directory",
}
try:
    nature.CURRENT_TASK_STATE = raw_project_overwrite_state
    existing_read_pipeline_command = (
        'cd "/mnt/f/Downloads/New folder" && '
        'cat README.txt app_gui.py app_manager.py run_gui.bat 2>&1 | head -80'
    )
    existing_read_pipeline = nature.intercept_command(
        existing_read_pipeline_command,
        spaced_target_objective,
    )
    raw_project_overwrite = nature.intercept_command(
        "cd /mnt/f/Downloads/New\\ folder && cat <<'EOF' "
        "> InstalledApplicationManager.ps1\n"
        "Add-Type -AssemblyName PresentationFramework\nEOF",
        spaced_target_objective,
    )
    assert raw_project_overwrite.startswith(
        nature.COMMAND_REJECTION_PREFIX
    ), raw_project_overwrite
    raw_project_overwrite_result = nature.execute_tool_call(
        {
            "type": "command",
            "cmd": (
                "cd /mnt/f/Downloads/New\\ folder && cat <<'EOF' "
                "> InstalledApplicationManager.ps1\n"
                "Add-Type -AssemblyName PresentationFramework\nEOF"
            ),
        },
        spaced_target_objective,
    )
    powershell_project_overwrite = nature.intercept_command(
        r'powershell.exe -NoProfile -Command "Set-Location '
        r'F:\Downloads\New folder; Set-Content -Path '
        r'InstalledApplicationManager.ps1 -Value \"replacement\""',
        spaced_target_objective,
    )
finally:
    nature.CURRENT_TASK_STATE = previous_task_state
assert existing_read_pipeline == existing_read_pipeline_command, existing_read_pipeline
assert raw_project_overwrite_result.startswith(
    "[RECOVERY REQUIRED:"
), raw_project_overwrite_result
assert "Raw shell, PowerShell, or script file replacement" in raw_project_overwrite_result, (
    raw_project_overwrite_result
)
assert powershell_project_overwrite.startswith(
    nature.COMMAND_REJECTION_PREFIX
), powershell_project_overwrite
with tempfile.TemporaryDirectory(prefix="nature-existing-write-") as temp_root:
    guarded_root = Path(temp_root)
    existing_file = guarded_root / "existing.txt"
    existing_file.write_text("original", encoding="utf-8")
    guarded_write_state = nature.TaskState("Repair the existing project safely.")
    guarded_write_state.target_paths = [str(guarded_root)]
    guarded_write_state.target_checks[str(guarded_root)] = {
        "exists": True,
        "nonempty": True,
        "kind": "directory",
    }
    previous_task_state = nature.CURRENT_TASK_STATE
    try:
        nature.CURRENT_TASK_STATE = guarded_write_state
        existing_write_result = nature.execute_tool_call(
            {
                "type": "write",
                "path": str(existing_file),
                "content": "replacement",
            },
            "Repair the existing project safely.",
        )
        existing_append_result = nature.execute_tool_call(
            {
                "type": "append",
                "path": str(existing_file),
                "content": " appended",
            },
            "Repair the existing project safely.",
        )
        new_file = guarded_root / "new.txt"
        new_write_result = nature.execute_tool_call(
            {
                "type": "write",
                "path": str(new_file),
                "content": "new file",
            },
            "Repair the existing project safely.",
        )
    finally:
        nature.CURRENT_TASK_STATE = previous_task_state
    assert existing_write_result.startswith(
        "[RECOVERY REQUIRED:"
    ), existing_write_result
    assert existing_append_result.startswith(
        "[RECOVERY REQUIRED:"
    ), existing_append_result
    assert existing_file.read_text(encoding="utf-8") == "original"
    assert new_write_result.startswith("[File written atomically:"), new_write_result
    assert new_file.read_text(encoding="utf-8") == "new file"
class _PromptEofFixture:
    def isatty(self):
        return True

prompt_readers = []
def _build_recovered_prompt():
    prompt_readers.append(True)
    if len(prompt_readers) == 1:
        def _first_reader():
            raise EOFError()
        return _first_reader
    return lambda: "recovered prompt input"

saved_stdin = nature.sys.stdin
saved_server_start = nature.ensure_initial_server_until_ready
saved_banner = nature._render_banner
saved_prompt_reader = nature.build_prompt_reader
saved_run_user_input = nature.run_user_input
saved_stop_server = nature.stop_server
saved_sleep = nature.time.sleep
saved_task_state = nature.CURRENT_TASK_STATE
saved_conversation = nature.CURRENT_CONVERSATION
interactive_stops = []
try:
    nature.sys.stdin = _PromptEofFixture()
    nature.ensure_initial_server_until_ready = lambda model: None
    nature._render_banner = lambda model: None
    nature.build_prompt_reader = _build_recovered_prompt
    nature.run_user_input = lambda user_input, conversation: False
    nature.stop_server = lambda: interactive_stops.append(True)
    nature.time.sleep = lambda seconds: None
    nature.CURRENT_TASK_STATE = None
    nature.CURRENT_CONVERSATION = None
    nature.interactive_mode(Path("/tmp/interactive-eof-test.gguf"))
finally:
    nature.sys.stdin = saved_stdin
    nature.ensure_initial_server_until_ready = saved_server_start
    nature._render_banner = saved_banner
    nature.build_prompt_reader = saved_prompt_reader
    nature.run_user_input = saved_run_user_input
    nature.stop_server = saved_stop_server
    nature.time.sleep = saved_sleep
    nature.CURRENT_TASK_STATE = saved_task_state
    nature.CURRENT_CONVERSATION = saved_conversation
assert len(prompt_readers) == 2, prompt_readers
assert len(interactive_stops) == 1, interactive_stops
three_eof_readers = []
def _build_three_eof_prompt():
    three_eof_readers.append(True)
    def _reader():
        raise EOFError()
    return _reader

saved_stdin = nature.sys.stdin
saved_server_start = nature.ensure_initial_server_until_ready
saved_banner = nature._render_banner
saved_prompt_reader = nature.build_prompt_reader
saved_stop_server = nature.stop_server
saved_sleep = nature.time.sleep
try:
    nature.sys.stdin = _PromptEofFixture()
    nature.ensure_initial_server_until_ready = lambda model: None
    nature._render_banner = lambda model: None
    nature.build_prompt_reader = _build_three_eof_prompt
    nature.stop_server = lambda: None
    nature.time.sleep = lambda seconds: None
    with contextlib.redirect_stdout(io.StringIO()) as captured:
        try:
            nature.interactive_mode(Path("/tmp/three-eof-test.gguf"))
            raise AssertionError("three prompt EOFs must be a recovery failure")
        except RuntimeError as exc:
            assert "three consecutive" in str(exc), exc
finally:
    nature.sys.stdin = saved_stdin
    nature.ensure_initial_server_until_ready = saved_server_start
    nature._render_banner = saved_banner
    nature.build_prompt_reader = saved_prompt_reader
    nature.stop_server = saved_stop_server
    nature.time.sleep = saved_sleep
assert len(three_eof_readers) == 3, three_eof_readers
assert "[RECOVERY]" in captured.getvalue(), captured.getvalue()
assert "Goodbye!" not in captured.getvalue(), captured.getvalue()
checkpoint_evidence_state = nature.TaskState(unprobed_spaced_target_objective)
checkpoint_evidence_call = nature.automatic_verification_checkpoint_call(
    unprobed_spaced_target_objective
)
checkpoint_evidence_state.observe_tool(
    checkpoint_evidence_call,
    "AUTOMATIC_VERIFICATION_CHECKPOINT\n"
    "CHECKPOINT_ROOT=/mnt/f/Missing Parent/project with spaces\n"
    "/mnt/f/Missing Parent/project with spaces/README.md\t1\t2026-08-16T00:00:00\n",
    unprobed_spaced_target_objective,
)
assert checkpoint_evidence_state.target_evidence() == [{
    "path": "/mnt/f/Missing Parent/project with spaces",
    "exists": True,
    "nonempty": True,
    "kind": "directory",
}], checkpoint_evidence_state.target_evidence()
restored_reconciliation = nature.TaskState(
    spaced_target_objective,
    restored={
        "inflight": {
            "type": "write",
            "mutating": True,
            "description": "interrupted write to the requested project",
        },
    },
)
assert restored_reconciliation.pending_reconciliation is not None
reconciliation_result = nature.execute_tool_call(
    targeted_checkpoint_call,
    spaced_target_objective,
)
reconciliation_success, _ = restored_reconciliation.observe_tool(
    targeted_checkpoint_call,
    reconciliation_result,
    spaced_target_objective,
)
assert reconciliation_success, reconciliation_result
assert restored_reconciliation.pending_reconciliation is None
direct_powershell = (
    r'powershell -NoProfile -NonInteractive -Command '
    r'"Set-Location /mnt/f/Downloads/New\ folder; Get-ChildItem"'
)
normalized_powershell = nature.normalize_direct_windows_powershell(
    direct_powershell
)
assert normalized_powershell.startswith(str(nature.WINDOWS_POWERSHELL))
assert r"F:\Downloads\New folder" in normalized_powershell
assert nature.command_uses_direct_windows_powershell(normalized_powershell)
linux_powershell_probe = (
    'ls -la "/mnt/f/Downloads/New folder" 2>&1; echo "---"; '
    'which dotnet pwsh powershell.exe 2>&1; echo "---"; '
    'ls /mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe 2>&1'
)
assert not nature.command_uses_direct_windows_powershell(linux_powershell_probe)
assert (
    nature.normalize_direct_windows_powershell(linux_powershell_probe)
    == linux_powershell_probe
)
assert nature.intercept_command(linux_powershell_probe) == linux_powershell_probe
literal_powershell_data_probe = (
    "printf %s /mnt/c/Windows/System32/WindowsPowerShell/v1.0/"
    "powershell.exe; echo Get-Process"
)
assert not nature.command_uses_direct_windows_powershell(
    literal_powershell_data_probe
)
assert (
    nature.intercept_command(
        literal_powershell_data_probe,
        "Inspect this literal command without changing anything.",
    )
    == literal_powershell_data_probe
)
assert nature.incomplete_shell_heredoc_marker(
    "cat <<'EOF' > /tmp/incomplete.txt\npartial content"
) == "EOF"
assert nature.incomplete_shell_heredoc_marker(
    "cd /tmp/project && cat <<'EOF' > /tmp/incomplete-chained.txt\npartial content"
) == "EOF"
assert not nature.incomplete_shell_heredoc_marker(
    "cat <<'EOF' > /tmp/complete.txt\ncomplete content\nEOF"
)
assert nature._is_verification_call({
    "type": "command",
    "cmd": "python3 /tmp/pressure-project/run_tests.py",
})
for verification_command in (
    "pylint /tmp/project/main.py",
    "ruff check /tmp/project",
    "mypy /tmp/project",
    "flake8 /tmp/project",
    "pyright /tmp/project",
    "php -l /tmp/project/index.php",
    "ruby -c /tmp/project/app.rb",
    "luac -p /tmp/project/app.lua",
    "javac /tmp/project/Main.java",
    "clang -fsyntax-only /tmp/project/main.c",
):
    assert nature._is_verification_call({
        "type": "command",
        "cmd": verification_command,
    }), verification_command
assert not nature._is_verification_call({
    "type": "command",
    "cmd": "mkdir -p /tmp/pressure-project/extra",
})
windows_path_command = (
    r"mkdir -p F:\Downloads\c\AppList && "
    r"cd F:\Downloads\c\AppList && chmod +x F:\Downloads\c\AppList\main.py"
)
assert nature.normalize_windows_paths_in_bash(windows_path_command) == (
    "mkdir -p /mnt/f/Downloads/c/AppList && "
    "cd /mnt/f/Downloads/c/AppList && chmod +x /mnt/f/Downloads/c/AppList/main.py"
)
assert nature.normalize_windows_paths_in_bash(
    r'powershell.exe -Command "Get-Item F:\Downloads\c\AppList"'
) == r'powershell.exe -Command "Get-Item F:\Downloads\c\AppList"'
requested_app_objective = (
    r"Create and verify the Windows application in F:\Downloads\c\AppList."
)
hallucinated_mirror = "/mnt/c/Users/micha/F_Downloads/c/AppList"
aligned_command = nature.align_call_to_requested_targets({
    "type": "command",
    "cmd": (
        f"cd {hallucinated_mirror} && "
        "dotnet build AppList/AppList.csproj"
    ),
}, requested_app_objective)
assert hallucinated_mirror not in aligned_command["cmd"], aligned_command
assert "/mnt/f/Downloads/c/AppList" in aligned_command["cmd"], aligned_command
assert "intent_repaired" in aligned_command, aligned_command
aligned_write = nature.align_call_to_requested_targets({
    "type": "write",
    "path": f"{hallucinated_mirror}/AppList/MainWindow.xaml",
    "content": "<Window />",
}, requested_app_objective)
assert aligned_write["path"] == (
    "/mnt/f/Downloads/c/AppList/AppList/MainWindow.xaml"
), aligned_write
assert nature.missing_command_recovery("dotnet") == (
    "dotnet-sdk-10.0", "dotnet --info"
)
assert nature.missing_command_recovery("cargo") == (
    "rustup", "cargo --version"
)
for command_name, tool_name in (
    ("zig", "zig"),
    ("deno", "deno"),
    ("bun", "bun"),
    ("julia", "julia"),
    ("swift", "swift"),
    ("dart", "dart"),
    ("flutter", "flutter"),
):
    package, verification = nature.missing_command_recovery(command_name)
    assert package == f"mise:{tool_name}", (command_name, package)
    assert command_name in verification, (command_name, verification)
assert nature.missing_command_recovery("unknown-tool") is None
assert nature.is_foreground_gui_command(
    "python3 /mnt/f/Downloads/c/AppList/main.py"
)
assert not nature.is_foreground_gui_command(
    "python3 -m py_compile /mnt/f/Downloads/c/AppList/main.py"
)
for verification_script in (
    "python3 /mnt/f/Downloads/c/test_app.py",
    "python3 /mnt/f/Downloads/c/final_check.py",
    "python3 /mnt/f/Downloads/c/check_inventory.py",
    "python3 /mnt/f/Downloads/c/inventory_test.py",
):
    assert not nature.is_foreground_gui_command(
        verification_script
    ), verification_script
assert nature.harden_local_tool_launchers("win-tools boot") == (
    '/bin/bash "$HOME/.local/bin/win-tools" boot'
)
assert nature.harden_local_tool_launchers(
    'win-tools scan C 50 && win-tools startup'
) == (
    '/bin/bash "$HOME/.local/bin/win-tools" scan C 50 && '
    '/bin/bash "$HOME/.local/bin/win-tools" startup'
)
python_compile_narration = nature.narrate({
    "type": "command",
    "cmd": "python3 -m py_compile /tmp/project/main.py",
})
python_test_narration = nature.narrate({
    "type": "command",
    "cmd": "python3 -m unittest discover -s /tmp/project/tests -v",
})
assert python_compile_narration != python_test_narration
assert "syntax" in python_compile_narration.lower()
assert "test" in python_test_narration.lower()
dotnet_narration = nature.narrate({
    "type": "command",
    "cmd": "dotnet build /tmp/project/App.csproj",
})
assert "building" in dotnet_narration.lower()
assert "app.csproj" in dotnet_narration.lower()
mkdir_narration = nature.narrate({
    "type": "command",
    "cmd": "mkdir -p /tmp/project/src",
})
assert "creating" in mkdir_narration.lower()
assert "/tmp/project/src" in mkdir_narration
assert 0 < nature.CMD_STALL_TIMEOUT <= 90
agent_turn_source = inspect.getsource(nature.agent_turn)
active_turn_source = inspect.getsource(nature._agent_turn_active)
assert "while True" in agent_turn_source
assert "_agent_turn_active" in agent_turn_source
assert "ensure_model_server_until_ready" in active_turn_source
assert "except SystemExit:" in active_turn_source
assert active_turn_source.index("except SystemExit:") < active_turn_source.index(
    "except BaseException as exc:"
)
assert "local model server failed to start. The task checkpoint is" not in (
    active_turn_source
)
assert "ensure_initial_server_until_ready" in inspect.getsource(
    nature.interactive_mode
)
assert "ensure_initial_server_until_ready" in inspect.getsource(
    nature.single_shot_mode
)
verification_pressure_state.observe_tool(
    {"type": "read", "path": "/tmp/pressure-project/check.txt"},
    "verified bytes",
)
assert not verification_pressure_state.verification_due()
assert (
    verification_pressure_state.verified_mutation_count
    == verification_pressure_state.mutations
)
partial_answer_progress = nature._describe_generated_text("**Final")
assert "7 characters generated" in partial_answer_progress
assert "**Final" not in partial_answer_progress
complete_answer_progress = nature._describe_generated_text(
    "Both files were read and verified.\n| File"
)
assert "Both files were read and verified" in complete_answer_progress
assert "| File" not in complete_answer_progress
table_answer_progress = nature._describe_generated_text(
    "| Check passed? | Yes |\n"
)
assert "Check passed?: Yes" in table_answer_progress
assert nature._plain_generated_line("[TASK_COMPLETE]") == ""
partial_command_progress = nature._tool_progress_description(
    "run_command",
    '{"command":"cat /proc/sys',
    24,
    1.0,
    False,
)
assert "request characters have arrived" in partial_command_progress
assert "cat /proc/sys" not in partial_command_progress
exact_file_answer = nature.deterministic_exact_file_answer(
    "/tmp/nature-final-progress-proof.txt",
    "FINAL_PROGRESS_OK",
)
assert "FINAL_PROGRESS_OK" in exact_file_answer
assert "18 bytes" not in exact_file_answer
assert "[TASK_COMPLETE]" not in exact_file_answer
largest_answer = nature.deterministic_largest_files_answer(
    "C:\\small.bin|10|0 GB\nC:\\large.bin|100|0.001 GB\n"
    "SUMMARY|files|ranked=2|directories=3|files=4",
    "C",
    100,
)
assert largest_answer.index("C:\\large.bin") < largest_answer.index("C:\\small.bin")
assert "100 bytes" in largest_answer
assert nature.intercept_command(
    "win-tools scan C",
    "scan and list the top 50 biggest heaviest files all over my c drive ranked by size",
) == "win-tools files C 50"
assert "largest files" in nature.narrate({"type": "command", "cmd": "win-tools files C 50"}).lower()
assert "files were measured" in nature.interpret_result(
    {"type": "command", "cmd": "win-tools files C 50"},
    "C:\\sample.bin|1048576|0.001 GB",
).lower()
power_shell_parameter_error = (
    "Get-ChildItem : A parameter cannot be found that matches parameter name "
    "'Directory'.\nCategoryInfo : InvalidArgument\n"
    "FullyQualifiedErrorId : NamedParameterNotFound"
)
assert nature._tool_failed(power_shell_parameter_error)
assert "failed" in nature.interpret_result(
    {"type": "command", "cmd": "win-tools dir R"},
    power_shell_parameter_error,
).lower()
drive_answer = nature.deterministic_drive_listing_answer(
    "Top-level folders on R (NAME|LASTWRITE):\n"
    "FOLDER|Projects|8/16/2026 1:00:00 PM\n"
    "FOLDER|Study|8/16/2026 2:00:00 PM\n"
    "FILE|note.txt|0.1\n"
    "SUMMARY|dir|drive=R|folders=2|files=1",
    "R",
)
assert "Projects" in drive_answer and "Study" in drive_answer
assert "note.txt" not in drive_answer
assert "every top-level folder" in nature.narrate({
    "type": "command",
    "cmd": "win-tools dir C FOLDERS",
}).lower()
assert "2 verified top-level folders" in nature.interpret_result(
    {"type": "command", "cmd": "win-tools dir C FOLDERS"},
    "FOLDER|Projects|now\nFOLDER|Study|now\n"
    "SUMMARY|dir|drive=C|folders=2|mode=folders-only",
).lower()
assert nature.response_delegates_action_to_user(
    "Would you like me to execute these commands?"
)
handoff_state = nature.TaskState("List the folders on drive R")
handoff_gaps = handoff_state.completion_gaps(
    "Would you like me to execute these commands?\n[TASK_COMPLETE]"
)
assert (
    "the response asks the user to perform work that the agent must execute"
    in handoff_gaps
), handoff_gaps
write_summary = nature.interpret_result(
    {"type": "write", "path": "/tmp/unique-result.txt"},
    "[File written atomically: /tmp/unique-result.txt (686 characters, 9 ms)]",
)
assert "/tmp/unique-result.txt" in write_summary, write_summary
assert "686 characters" in write_summary, write_summary
assert "9 ms" in write_summary, write_summary
assert "confirming it is in place" not in write_summary.lower(), write_summary
read_summary = nature.interpret_result(
    {"type": "read", "path": "/tmp/unique-result.txt"},
    "first line\nsecond line\n",
)
assert "/tmp/unique-result.txt" in read_summary, read_summary
assert "2 non-empty line" in read_summary, read_summary
assert "22 characters" in read_summary, read_summary
filename_hint = nature.plan_hint(
    "find and output the full path to freebuff exe specifically"
)
assert "freebuff.exe" in filename_hint[0].lower(), filename_hint
assert "win-tools search ALL freebuff.exe FIRST" in filename_hint[1], filename_hint
fixture_request = (
    "find and output the full path to "
    "nature-progress-fixture-6f4a2c9e.exe specifically on F drive"
)
assert not nature.objective_requires_action(fixture_request), fixture_request
assert nature.is_direct_windows_filename_request(fixture_request), fixture_request
fixture_hint = nature.plan_hint(fixture_request)
assert "win-tools search F nature-progress-fixture-6f4a2c9e.exe FIRST" in fixture_hint[1]
assert nature.intercept_command(
    "win-tools search F nature-progress-fixture-6f4a2c9e.exe",
    fixture_request,
) == "win-tools search F nature-progress-fixture-6f4a2c9e.exe FIRST"
assert nature.objective_requires_action(
    "fix the program that searches for nature-progress-fixture-6f4a2c9e.exe"
)
assert not nature.is_direct_windows_filename_request(
    "fix the program that searches for nature-progress-fixture-6f4a2c9e.exe"
)
assert nature.intercept_command(
    'find /mnt/c /mnt/d /mnt/e /mnt/f -name "freebuff.exe" 2>/dev/null',
    "find and output the full path to freebuff exe specifically",
) == "win-tools search ALL freebuff.exe FIRST"
assert nature.intercept_command(
    'find /mnt/c -name "freebuff.exe" 2>/dev/null',
    "find and output the full path to freebuff exe specifically on C drive",
) == "win-tools search C freebuff.exe FIRST"
assert nature.intercept_command(
    'find /mnt/c /mnt/d /mnt/e /mnt/f -iname "freebuff.exe" 2>/dev/null',
    "find and output the full path to freebuff exe specifically",
) == "win-tools search ALL freebuff.exe FIRST"
assert nature.intercept_command(
    "win-tools search ALL freebuff.exe FIRST",
    "find and output the full path to freebuff exe specifically",
) == "win-tools search ALL freebuff.exe FIRST"
assert nature.intercept_command(
    "win-tools search ALL 'Program Files & Tools.exe' ALL",
    "find every matching filename",
) == "win-tools search ALL 'Program Files & Tools.exe' ALL"
assert nature.deterministic_filename_answer(
    "MATCH|C:\\Tools\\Freebuff.exe|188772104\n"
    "SUMMARY|search|mode=FIRST|matches=1|reported=1",
    "freebuff.exe",
) == "The full path is:\nC:\\Tools\\Freebuff.exe"
assert nature.deterministic_filename_answer(
    "SUMMARY|search|mode=FIRST|matches=0|reported=0",
    "missing.exe",
) == "No exact Windows filename match was found for missing.exe in the scanned scope."
progress_event = nature.parse_live_progress_line(
    r"LLAMA_PROGRESS|search|scanning|C:|37|1284|0|C:\Windows\System32"
)
assert progress_event and progress_event[0].startswith("tool-progress:search:scanning:C:")
assert "1,284 files" in progress_event[1], progress_event
assert "C:\\Windows\\System32" in progress_event[1], progress_event
progress_match = nature.parse_live_progress_line(
    r"LLAMA_PROGRESS|search|match|C:|38|1301|1|C:\Tools\freebuff.exe"
)
assert progress_match, progress_match
assert "c:\\tools\\freebuff.exe" in progress_match[1].lower(), progress_match
assert "1,301 files, 38 folders checked" in progress_match[1], progress_match
marker_state = nature.TaskState("answer this read-only question")
marker_gaps = marker_state.completion_gaps("The verified answer is ready.", "stop")
assert marker_gaps == ["the final completion marker is missing"], marker_gaps
assert nature.accept_marker_only_completion(
    marker_state,
    "The verified answer is ready.",
    marker_gaps,
) == []
assert marker_state.events[-1]["kind"] == "completion-marker-repaired"
rejection_state = nature.TaskState("Create and verify /tmp/rejection-fixture")
rejection_gaps = ["no successful modifying action has been recorded"]
first_repeat, first_status = nature.register_completion_rejection(
    rejection_state, rejection_gaps
)
second_repeat, second_status = nature.register_completion_rejection(
    rejection_state, rejection_gaps
)
assert first_repeat == 1 and second_repeat == 2
assert first_status != second_status
assert "No-action recovery 1" in first_status
assert "No-action recovery 2" in second_status
rejection_payload = rejection_state.to_dict()
restored_rejection = nature.TaskState(
    rejection_state.objective,
    restored=rejection_payload,
)
third_repeat, third_status = nature.register_completion_rejection(
    restored_rejection, rejection_gaps
)
assert third_repeat == 3
assert "No-action recovery 3" in third_status
active_turn_source = inspect.getsource(nature._agent_turn_active)
assert "Completion was rejected:" not in active_turn_source
assert "wait_with_progress(" in active_turn_source
assert "recover_model_server(force=True)" in active_turn_source
code, streamed_result, streamed_error = nature.run_live_process(
    "printf 'LLAMA_PROGRESS|search|scanning|C:|1|2|0|C:\\\\fixture\\n'; printf 'MATCH|C:\\\\fixture\\\\freebuff.exe|12\\n'",
    shell=True,
    timeout=10,
    env=os.environ.copy(),
    label="Running command: structured progress fixture",
)
assert code == 0 and not streamed_error, streamed_error
assert "LLAMA_PROGRESS" not in streamed_result, streamed_result
assert "MATCH|C:\\fixture\\freebuff.exe|12" in streamed_result, streamed_result
checkpoint_notice = nature.pending_task_notice({
    "task_id": "task-preserved",
    "objective": "finish the preserved verification task",
})
assert "task-preserved" in checkpoint_notice, checkpoint_notice
assert "llama --resume" in checkpoint_notice, checkpoint_notice
assert "before starting different work" in checkpoint_notice, checkpoint_notice
assert 1 <= nature.MODEL_ACTION_TIMEOUT <= 30, nature.MODEL_ACTION_TIMEOUT
assert nature.MODEL_STREAM_IDLE_TIMEOUT > 0
assert nature.FOCUSED_ACTION_MAX_TOKENS >= 4096
chime_path = nature._ensure_completion_chime()
chime_bytes = chime_path.read_bytes()
assert chime_bytes[:4] == b"RIFF" and chime_bytes[8:12] == b"WAVE"
assert len(chime_bytes) > 50000, len(chime_bytes)
chime_command = nature._completion_chime_command(chime_path)
assert Path(chime_command[0]).name == "powershell.exe", chime_command
assert "-EncodedCommand" in chime_command, chime_command
chime_calls = []
original_play_completion_chime = nature.play_completion_chime
nature.play_completion_chime = (
    lambda wait=False: chime_calls.append(wait) or True
)
try:
    with nature.completion_chime_after_job():
        with nature.completion_chime_after_job():
            pass
finally:
    nature.play_completion_chime = original_play_completion_chime
assert chime_calls == [False], chime_calls
loop_state = nature.TaskState("inspect a stable fixture")
loop_call = {"type": "command", "cmd": "printf stable"}
loop_fingerprint = nature._call_fingerprint(
    loop_call, loop_state.objective
)
loop_state.fingerprints[loop_fingerprint] = {
    "output_hash": "fixture",
    "repeats": 2,
    "sequence": 1,
}
assert loop_state.identical_result_repeats(
    loop_call, loop_state.objective
) == 2
native_read_a = {
    "type": "read",
    "path": "/tmp/repeated-read.txt",
    "tool_call_id": "call-first",
}
native_read_b = {
    "type": "read",
    "path": "/tmp/repeated-read.txt",
    "tool_call_id": "call-second",
}
assert nature._call_fingerprint(native_read_a) == nature._call_fingerprint(
    native_read_b
)
native_loop_state = nature.TaskState("read one exact file")
missing_result = "[File not found: /tmp/repeated-read.txt]"
native_loop_state.observe_tool(native_read_a, missing_result)
native_loop_state.observe_tool(native_read_b, missing_result)
assert native_loop_state.identical_result_repeats(native_read_a) == 2
assert nature._tool_failed(
    "[VERIFICATION REQUIRED: run a readback before another write.]"
)
missing_add_prefix = nature.normalize_unified_diff_hunks(
    "--- /dev/null\n+++ b/new.py\n"
    "@@ -0,0 +1 @@\n"
    "print('ready')\n"
)
assert "\n+print('ready')\n" in missing_add_prefix, missing_add_prefix
missing_context_prefix = nature.normalize_unified_diff_hunks(
    "--- a/sample.py\n+++ b/sample.py\n"
    "@@ -1,2 +1,2 @@\n"
    "alpha\n"
    "beta\n"
)
assert "\n alpha\n beta\n" in missing_context_prefix, missing_context_prefix
gpu_command = ["llama-server", "--model", "/tmp/model.gguf", "--n-gpu-layers", "999"]
assert "--n-gpu-layers" not in nature._set_gpu_layers(gpu_command, None)
cpu_command = nature._set_gpu_layers(gpu_command, 0)
assert cpu_command[cpu_command.index("--n-gpu-layers") + 1] == "0"
assert nature._gpu_layer_value(gpu_command) == "999"
assert nature._gpu_layer_value(cpu_command) == "0"
malformed_read_error = (
    "HTTPError: HTTP 500: Failed to parse tool call arguments as JSON; "
    "last read: '\\\"cat /tmp/project/server.py 2>/dev/null || echo "
    "\\\"NOT FOUND\\\"}'"
)
assert nature.recover_malformed_read_call(malformed_read_error) == {
    "type": "read",
    "path": "/tmp/project/server.py",
}
assert nature.recover_malformed_read_call(
    "Failed to parse tool call arguments as JSON; last read: 'rm -rf /tmp/project'"
) is None
assert nature.recover_malformed_read_call(
    "Failed to parse tool call arguments as JSON; last read: 'cat relative.txt'"
) is None
assert not nature._command_edits_project_files(
    'find / -name "FlowForge" -type d 2>/dev/null | head -10'
)
assert not nature._command_edits_project_files(
    'python3 -m pytest tests -v > /tmp/nature-tests.log 2>&1'
)
assert not nature._is_mutating_call({
    "type": "command",
    "cmd": 'python3 -m pytest tests -v > /tmp/nature-tests.log 2>&1',
})
assert nature._command_edits_project_files(
    'python3 -m pytest tests -v > project-test-output.log 2>&1'
)
assert nature._is_mutating_call({
    "type": "command",
    "cmd": 'cd nested && printf done > result.txt',
})
bounded_find = nature.intercept_command(
    'find / -name "FlowForge" -type d 2>/dev/null | head -10'
)
assert bounded_find.startswith('find . -maxdepth 5 -name "FlowForge"'), bounded_find
restored_find = nature.TaskState("find project", restored={
    "inflight": {
        "type": "command",
        "mutating": True,
        "description": (
            'find / -name "FlowForge" -type d 2>/dev/null | head -10'
        ),
    },
})
assert restored_find.pending_reconciliation is None
assert restored_find.action_was_interrupted({
    "type": "command",
    "cmd": 'find / -name "FlowForge" -type d 2>/dev/null | head -10',
})
restored_stuck_gui = nature.TaskState("build a Windows application", restored={
    "inflight": {
        "fingerprint": nature._call_fingerprint({
            "type": "command",
            "cmd": (
                "Xvfb :99 -screen 0 1024x768x24 & DISPLAY=:99 "
                "python3 /mnt/f/Downloads/c/AppList/main.py"
            ),
        }, "build a Windows application"),
        "type": "command",
        "mutating": False,
        "description": (
            "Xvfb :99 -screen 0 1024x768x24 & DISPLAY=:99 "
            "python3 /mnt/f/Downloads/c/AppList/main.py"
        ),
    },
})
stuck_gui_call = {
    "type": "command",
    "cmd": (
        "Xvfb :99 -screen 0 1024x768x24 & DISPLAY=:99 "
        "python3 /mnt/f/Downloads/c/AppList/main.py"
    ),
}
assert restored_stuck_gui.action_was_interrupted(
    stuck_gui_call, "build a Windows application"
)
assert "Xvfb" in restored_stuck_gui.interrupted_action_reason(
    stuck_gui_call, "build a Windows application"
)
serialized_stuck_gui = restored_stuck_gui.to_dict()
reloaded_stuck_gui = nature.TaskState(
    "build a Windows application", restored=serialized_stuck_gui
)
assert reloaded_stuck_gui.action_was_interrupted(
    stuck_gui_call, "build a Windows application"
)
assert f"Current working directory: {Path.cwd()}." in restored_find.context_summary()
sanitized = nature.sanitize_native_tool_history([
    {
        "role": "assistant",
        "content": "Keep this useful explanation.",
        "tool_calls": [{
            "id": "broken-call",
            "type": "function",
            "function": {
                "name": "run_command",
                "arguments": '{"command":"unterminated',
            },
        }],
    },
    {
        "role": "tool",
        "tool_call_id": "broken-call",
        "content": "[ERROR: malformed call]",
    },
])
assert len(sanitized) == 1, sanitized
assert sanitized[0]["role"] == "assistant", sanitized
assert "Keep this useful explanation." in sanitized[0]["content"], sanitized
assert "[INVALID TOOL CALL PRESERVED AS DATA]" in sanitized[0]["content"], sanitized
assert "broken-call" in sanitized[0]["content"], sanitized
assert "tool_calls" not in sanitized[0], sanitized

routed = {
    item["function"]["name"]
    for item in nature.select_tools(
        r"Build and test a Python website in F:\demo, then open it in Chrome"
    )
}
assert {
    "run_command", "run_python", "read_file", "write_file",
    "append_file", "apply_patch", "win_tools", "browse",
}.issubset(routed), routed

malformed_native = nature.tool_calls_to_calls([{
    "id": "bad-json",
    "function": {
        "name": "win_tools",
        "arguments": '{"action":"search"',
    },
}])[0]
assert malformed_native["type"] == "invalid", malformed_native
assert "rejected before execution" in malformed_native["error"], malformed_native
assert nature.execute_tool_call(malformed_native).startswith("[ERROR:")
python_command_alias = nature.tool_calls_to_calls([{
    "id": "python-command",
    "function": {
        "name": "python",
        "arguments": '{"command":"printf ready"}',
    },
}])[0]
assert python_command_alias["type"] == "command", python_command_alias
assert python_command_alias["cmd"] == "printf ready", python_command_alias
quoted_search = nature.tool_calls_to_calls([{
    "id": "quoted-search",
    "function": {
        "name": "win_tools",
        "arguments": json.dumps({
            "action": "search",
            "drive": "ALL",
            "args": ["Program Files & Tools.exe"],
        }),
    },
}])[0]
assert quoted_search["cmd"] == (
    "win-tools search ALL 'Program Files & Tools.exe'"
), quoted_search
dict_arguments = nature.tool_calls_to_calls([{
    "id": "dict-arguments",
    "function": {
        "name": "run_command",
        "arguments": {"command": "printf dict-ok"},
    },
}])[0]
assert dict_arguments["type"] == "command", dict_arguments
mcp_schema = nature.TOOL_CATALOG["mcp_call"]["function"]["parameters"]
assert (
    mcp_schema["properties"]["arguments"]["additionalProperties"] is True
), mcp_schema

retry_source = {
    "model": "local",
    "messages": [{"role": "user", "content": "build it"}],
    "tools": nature.TOOLS_SPEC,
    "temperature": 0.6,
    "cache_prompt": True,
}
oversized_retry = nature._build_retry_body(
    retry_source,
    retry_source["messages"],
    "oversized_write: 13000 decoded characters",
    1,
)
retry_tool_names = {
    tool["function"]["name"] for tool in oversized_retry["tools"]
}
assert "write_file" not in retry_tool_names
assert "append_file" not in retry_tool_names
assert {
    "run_command", "run_python", "apply_patch", "read_file",
}.issubset(retry_tool_names), retry_tool_names
assert oversized_retry["cache_prompt"] is False
assert oversized_retry["temperature"] == 0.1
assert oversized_retry["reasoning_effort"] == "none"

with tempfile.TemporaryDirectory() as folder:
    root = Path(folder)
    anchored_test = root / "tests" / "test_atlasflow.py"
    anchored_test.parent.mkdir()
    anchored_test.write_text("pass\n", encoding="utf-8")
    old_cwd = Path.cwd()
    try:
        os.chdir(root)
        anchored_find = nature.intercept_command(
            'find /mnt/c/Users -name "test_atlasflow.py" 2>/dev/null | head -5',
            "Fix the project tests/test_atlasflow.py and run every test.",
        )
    finally:
        os.chdir(old_cwd)
    assert anchored_find == (
        "find . -maxdepth 8 -type f "
        "-path './tests/test_atlasflow.py' -print"
    ), anchored_find

    oversized_parent = root / "must-not-exist-parent"
    oversized = oversized_parent / "must-not-exist.txt"
    result = nature.execute_tool_call({
        "type": "write",
        "path": str(oversized),
        "content": "x" * (nature.MAX_WHOLE_FILE_CHARS + 1),
    })
    assert "safe per-call limit" in result
    assert not oversized.exists()
    assert not oversized_parent.exists()

    history_path = root / "history"
    from prompt_toolkit.history import FileHistory
    FileHistory(str(history_path)).append_string("persistent prompt one")
    loaded = list(FileHistory(str(history_path)).load_history_strings())
    assert "persistent prompt one" in loaded
    key_text = " ".join(
        str(key)
        for binding in nature.build_prompt_key_bindings().bindings
        for key in binding.keys
    )
    assert "Up" in key_text and "Down" in key_text, key_text

    from prompt_toolkit import PromptSession
    from prompt_toolkit.input.defaults import create_pipe_input
    from prompt_toolkit.output import DummyOutput
    FileHistory(str(history_path)).append_string("persistent prompt two")
    with create_pipe_input() as pipe_input:
        prompt = PromptSession(
            history=FileHistory(str(history_path)),
            input=pipe_input,
            output=DummyOutput(),
            key_bindings=nature.build_prompt_key_bindings(),
            enable_history_search=False,
        )
        def press_history_keys():
            for keys in ("\x1b[A", "\x1b[A", "\x1b[B", "\r"):
                time.sleep(0.1)
                pipe_input.send_text(keys)
        threading.Thread(target=press_history_keys, daemon=True).start()
        assert prompt.prompt() == "persistent prompt two"

    sample = root / "sample.txt"
    sample.write_text("old\n")
    patch = (
        "diff --git a/sample.txt b/sample.txt\n"
        "--- a/sample.txt\n+++ b/sample.txt\n"
        "@@ -1 +1 @@\n-old\n+new\n"
    )
    try:
        os.chdir(root)
        patch_result = nature.execute_tool_call({"type": "patch", "patch": patch})
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in patch_result.lower(), patch_result
    assert sample.read_text() == "new\n"

    nested_project = root / "Project" / "AtlasFlow"
    nested_project.mkdir(parents=True)
    nested_api = nested_project / "api.py"
    nested_api.write_text("before\n", encoding="utf-8")
    nested_patch = (
        "diff --git a/AtlasFlow/api.py b/AtlasFlow/api.py\n"
        "--- a/AtlasFlow/api.py\n+++ b/AtlasFlow/api.py\n"
        "@@ -1 +1 @@\n-before\n+after\n"
    )
    try:
        os.chdir(root)
        rebased_result = nature.execute_tool_call({
            "type": "patch", "patch": nested_patch,
        })
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in rebased_result.lower(), rebased_result
    assert nested_api.read_text(encoding="utf-8") == "after\n"

    malformed_context = root / "malformed_context.py"
    malformed_context.write_text(
        "def first():\n    return 1\n\ndef second():\n    return 2\n",
        encoding="utf-8",
    )
    malformed_patch = (
        "--- a/malformed_context.py\n+++ b/malformed_context.py\n"
        "@@ -1,2 +1,3 @@\n"
        "def first():\n"
        "    return 1\n"
        "+    # verified\n"
        "@@ -4,2 +5,2 @@\n"
        "def second():\n"
        "-    return 2\n"
        "+    return 3\n"
    )
    try:
        os.chdir(root)
        malformed_result = nature.execute_tool_call({
            "type": "patch", "patch": malformed_patch,
        })
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in malformed_result.lower(), malformed_result
    assert "# verified" in malformed_context.read_text(encoding="utf-8")
    assert "return 3" in malformed_context.read_text(encoding="utf-8")

    stale = root / "stale.txt"
    stale.write_text("alpha\nunique old line\nomega\n", encoding="utf-8")
    stale_patch = (
        "--- a/stale.txt\n+++ b/stale.txt\n"
        "@@ -50,3 +50,3 @@\n"
        " context that is intentionally stale\n"
        "-unique old line\n"
        "+unique new line\n"
        " another stale context line\n"
    )
    try:
        os.chdir(root)
        stale_result = nature.execute_tool_call({
            "type": "patch", "patch": stale_patch,
        })
    finally:
        os.chdir(old_cwd)
    assert (
        stale_result.startswith("[PATCH APPLIED:")
        or "validated and applied" in stale_result.lower()
    ), stale_result
    assert stale.read_text(encoding="utf-8") == "alpha\nunique new line\nomega\n"

    refresh = root / "refresh.py"
    refresh.write_text("one\ntwo\nthree\n", encoding="utf-8")
    refresh_patch = (
        "--- a/refresh.py\n+++ b/refresh.py\n"
        "@@ -99,1 +99,1 @@\n"
        "-missing stale line\n"
        "+fresh line\n"
    )
    try:
        os.chdir(root)
        refresh_result = nature.execute_tool_call({
            "type": "patch", "patch": refresh_patch,
        })
    finally:
        os.chdir(old_cwd)
    assert refresh_result.startswith("[ERROR: Patch validation failed"), refresh_result
    assert "[FRESH TARGET EVIDENCE: refresh.py (complete file)" in refresh_result
    assert "one\ntwo\nthree" in refresh_result
    assert refresh.read_text(encoding="utf-8") == "one\ntwo\nthree\n"

    direct = root / "direct.txt"
    direct.write_text("before\nunique direct line\nafter\n", encoding="utf-8")
    try:
        os.chdir(root)
        direct_result = nature.apply_unique_single_line_patch(
            "--- a/direct.txt\n+++ b/direct.txt\n"
            "@@ -99,1 +99,1 @@\n"
            "-unique direct line\n"
            "+recovered direct line\n"
        )
    finally:
        os.chdir(old_cwd)
    assert direct_result.startswith("[PATCH APPLIED:"), direct_result
    assert direct.read_text(encoding="utf-8") == (
        "before\nrecovered direct line\nafter\n"
    )

    multi = root / "multi.txt"
    multi.write_text("alpha\none\nmiddle\ntwo\nomega\n", encoding="utf-8")
    try:
        os.chdir(root)
        multi_result = nature.execute_tool_call({
            "type": "patch",
            "patch": (
                "--- a/multi.txt\n+++ b/multi.txt\n"
                "@@ -1,3 +1,3 @@\n"
                " alpha\n-one\n+ONE\n"
                " middle\n"
                "@@ -3,3 +3,3 @@\n"
                " middle\n-two\n+TWO\n"
                " omega\n"
            ),
        })
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in multi_result.lower(), multi_result
    assert multi.read_text(encoding="utf-8") == (
        "alpha\nONE\nmiddle\nTWO\nomega\n"
    )

    atomic_a = root / "atomic-a.txt"
    atomic_b = root / "atomic-b.txt"
    atomic_a.write_text("old-a\n", encoding="utf-8")
    atomic_b.write_text("old-b\n", encoding="utf-8")
    try:
        os.chdir(root)
        atomic_result = nature.execute_tool_call({
            "type": "patch",
            "patch": (
                "--- a/atomic-a.txt\n+++ b/atomic-a.txt\n"
                "@@ -1 +1 @@\n-old-a\n+new-a\n"
                "--- a/atomic-b.txt\n+++ b/atomic-b.txt\n"
                "@@ -1 +1 @@\n-old-b\n+new-b\n"
            ),
        })
    finally:
        os.chdir(old_cwd)
    assert "validated and applied" in atomic_result.lower(), atomic_result
    assert atomic_a.read_text(encoding="utf-8") == "new-a\n"
    assert atomic_b.read_text(encoding="utf-8") == "new-b\n"

    unsafe = nature.execute_tool_call({
        "type": "patch",
        "patch": (
            "--- a/../escape.txt\n+++ b/../escape.txt\n"
            "@@ -0,0 +1 @@\n+blocked\n"
        ),
    })
    assert "Unsafe patch path rejected" in unsafe

    pipeline_result = nature.execute_tool_call({
        "type": "command",
        "cmd": "printf 'visible pipeline output\\n'; false | true",
    })
    assert "[EXIT CODE:" in pipeline_result, pipeline_result

    original_run_live_process = nature.run_live_process
    try:
        def raise_process_interrupted(*args, **kwargs):
            raise nature.ProcessInterrupted(
                "The operator interrupted only the running subprocess."
            )
        nature.run_live_process = raise_process_interrupted
        interrupted_result = nature.execute_tool_call({
            "type": "command",
            "cmd": "sleep 999",
        })
    finally:
        nature.run_live_process = original_run_live_process
    assert interrupted_result.startswith("[INTERRUPTED SUBPROCESS:"), interrupted_result
    assert "parent task will continue" in interrupted_result.lower(), interrupted_result
    interrupted_state = nature.TaskState("finish the task")
    interrupted_call = {"type": "command", "cmd": "sleep 999"}
    interrupted_state.observe_tool(
        interrupted_call, interrupted_result, "finish the task"
    )
    assert interrupted_state.action_was_interrupted(
        interrupted_call, "finish the task"
    )

    truncated_test = nature.execute_tool_call({
        "type": "command",
        "cmd": "python3 -m unittest discover -v 2>&1 | tail -20",
    })
    assert "Verification output truncation was rejected" in truncated_test

    unchanged = root / "unchanged.txt"
    unchanged.write_text("same", encoding="utf-8")
    no_change = nature.execute_tool_call({
        "type": "write",
        "path": str(unchanged),
        "content": "same",
    })
    assert no_change.startswith("[NO CHANGE:"), no_change
    state = nature.TaskState("change the unchanged test file")
    success, _ = state.observe_tool(
        {"type": "write", "path": str(unchanged), "content": "same"},
        no_change,
        "change the unchanged test file",
    )
    assert success is False
    assert state.pending_reconciliation is None
    assert not state.requires_reconciliation_before({
        "type": "write", "path": str(unchanged), "content": "different",
    })
    migrated = nature.TaskState("resume safely", restored={
        "pending_reconciliation": {
            "description": (
                "a no-op mutation was rejected because the target already "
                "contained the proposed content"
            ),
        },
    })
    assert migrated.pending_reconciliation is None

    identical_sed = nature.execute_tool_call({
        "type": "command",
        "cmd": "sed -i 's/status: int = 20)/status: int = 20)/' unchanged.txt",
    })
    assert "search and replacement are identical" in identical_sed
    assert unchanged.read_text(encoding="utf-8") == "same"
    repaired_call = nature.repair_identical_numeric_sed_from_message(
        {
            "type": "command",
            "cmd": "sed -i 's/status: int = 20)/status: int = 20)/' server.py",
        },
        "Change the default status code from 20 to 200.",
    )
    assert "status: int = 200)" in repaired_call["cmd"], repaired_call
    assert repaired_call.get("intent_repaired"), repaired_call
    repaired_instead = nature.repair_identical_numeric_sed_from_message(
        {
            "type": "command",
            "cmd": "sed -i 's/= 20)/= 20)/g' server.py",
        },
        "I keep typing `20)` instead of `200)`. I will fix it now.",
    )
    assert "s/= 20)/= 200)/g" in repaired_instead["cmd"], repaired_instead
    previous_state = nature.CURRENT_TASK_STATE
    nature.CURRENT_TASK_STATE = nature.TaskState(
        "The current invalid source is exactly: for in range(15): and its "
        "body references i. Change only that line to exactly: "
        "for i in range(15): using one focused patch."
    )
    try:
        repaired_literal = nature.repair_identical_numeric_sed_from_message(
            {
                "type": "command",
                "cmd": (
                    "sed -i 's/for in range(15):/for in range(15):/' "
                    "tests/test_atlasflow.py"
                ),
            },
            "Applying the exact requested edit.",
        )
    finally:
        nature.CURRENT_TASK_STATE = previous_state
    assert "s/for in range(15):/for i in range(15):/" in repaired_literal["cmd"]

    class LoopRepairState:
        objective = (
            "The streamed code dropped the missing loop variable i. "
            "Restore the missing loop variable i before execution."
        )

    nature.CURRENT_TASK_STATE = LoopRepairState()
    repaired_loop = nature.repair_missing_python_loop_variable(
        {
            "type": "python",
            "code": "values = []\nfor in range(3):\n    values.append(i)\n",
        },
        "",
    )
    assert "for i in range(3):" in repaired_loop["code"]
    assert "intent_repaired" in repaired_loop
    untouched_loop = nature.repair_missing_python_loop_variable(
        {"type": "python", "code": "for item in range(3):\n    print(item)\n"},
        "",
    )
    assert untouched_loop["code"] == "for item in range(3):\n    print(item)\n"
    nature.CURRENT_TASK_STATE = None

with tempfile.TemporaryDirectory() as transaction_dir:
    previous_cwd = Path.cwd()
    os.chdir(transaction_dir)
    try:
        guarded_python = Path("guarded.py")
        original_python = "for i in range(2):\n    print(i)\n"
        guarded_python.write_text(original_python)
        rollback_result = nature.execute_tool_call({
            "type": "command",
            "cmd": "sed -i 's/for i in range(2):/for in range(2):/' guarded.py",
        })
        assert rollback_result.startswith("[ROLLED BACK:"), rollback_result
        assert guarded_python.read_text() == original_python
    finally:
        os.chdir(previous_cwd)

with tempfile.TemporaryDirectory() as exact_intent_dir:
    previous_cwd = Path.cwd()
    os.chdir(exact_intent_dir)
    try:
        exact_file = Path("sample.py")
        exact_file.write_text("def build():\n    count)(3):\n        print(i)\n")
        exact_calls = nature.objective_exact_line_patch_calls(
            "Current line 2 is exactly count)(3): but must be "
            "for i in range(3):. The missing loop variable i must be restored."
        )
        assert len(exact_calls) == 1, exact_calls
        exact_result = nature.execute_tool_call(exact_calls[0])
        assert (
            exact_result.startswith("[PATCH APPLIED:")
            or exact_result.startswith("[Patch validated and applied")
        ), exact_result
        assert "    for i in range(3):" in exact_file.read_text()
        quoted_file = Path("quoted.py")
        quoted_file.write_text('    "old payload",\n')
        quoted_calls = nature.objective_exact_line_patch_calls(
            'Current line 1 is exactly "old payload", but must be '
            '"new payload". Make only that repair.'
        )
        assert len(quoted_calls) == 1, quoted_calls
        quoted_result = nature.execute_tool_call(quoted_calls[0])
        assert (
            quoted_result.startswith("[PATCH APPLIED:")
            or quoted_result.startswith("[Patch validated and applied")
        ), quoted_result
        assert quoted_file.read_text() == '    "new payload",\n'
    finally:
        os.chdir(previous_cwd)
    assert repaired_literal.get("intent_repaired"), repaired_literal
    ambiguous_call = nature.repair_identical_numeric_sed_from_message(
        {
            "type": "command",
            "cmd": "sed -i 's/value=20/value=20/' settings.py",
        },
        "Possible values range from 20 to 200 or from 20 to 201.",
    )
    assert ambiguous_call["cmd"].endswith("value=20/' settings.py")

    captured = io.StringIO()
    progress = nature.LiveProgress(stream=captured, interactive=False)
    observed = {
        "key": "fixture-started",
        "message": "The tester started reading a fixed progress fixture.",
    }
    progress.start(
        (observed["key"], observed["message"]),
        reporter=lambda elapsed: (observed["key"], observed["message"]),
    )
    progress.refresh()
    observed.update({
        "key": "fixture-output",
        "message": "The tester received one new line from the fixture.",
    })
    progress.refresh()
    progress.refresh()
    progress.stop()
    live_lines = [
        line for line in captured.getvalue().splitlines()
        if "[WORKING]" in line
    ]
    assert len(live_lines) == 2, live_lines
    live_payloads = [line.split("] ", 1)[-1] for line in live_lines]
    assert len(live_payloads) == len(set(live_payloads)), live_payloads
    static_capture = io.StringIO()
    static_progress = nature.LiveProgress(
        stream=static_capture,
        interactive=False,
    )
    static_progress.start((
        "fixed-observation",
        "The tester is reading one unchanged observed state.",
    ))
    time.sleep(1.1)
    static_progress.stop()
    static_lines = [
        line for line in static_capture.getvalue().splitlines()
        if "[WORKING]" in line
    ]
    assert len(static_lines) == 1, static_lines
    assert any("[WORKING]" in line for line in static_lines), static_lines
    plan_capture = io.StringIO()
    with contextlib.redirect_stdout(plan_capture):
        silent_plan = nature.TaskPlan(
            "Find and rank the 100 largest files on C drive."
        )
        silent_plan.done(1, "the live scan completed")
    assert plan_capture.getvalue() == "", repr(plan_capture.getvalue())
    server_wait_source = agent_source[
        agent_source.index("def _wait_ready("):
        agent_source.index("\ndef _strip_perf_flags", agent_source.index("def _wait_ready("))
    ]
    assert "LiveProgress()" in server_wait_source, server_wait_source
    assert "print(rendered" not in server_wait_source, server_wait_source
    assert "server-startup-loading" in server_wait_source, server_wait_source

    original_group_stats = nature._process_group_stats
    nature._process_group_stats = lambda pid: (0.0, 12.0, "")
    original_group_io_stats = nature._process_group_io_stats
    nature._process_group_io_stats = lambda pid: (0, 0)
    try:
        process = nature.ProcessTelemetry("Running command: fixed scan")
        process.pid = 42
        started = process.report(0)
        first_quiet_tick = process.report(3)
        assert first_quiet_tick == started, (started, first_quiet_tick)
        assert first_quiet_tick[0] == started[0], (started, first_quiet_tick)
        assert "has not written output yet" in first_quiet_tick[1].lower(), first_quiet_tick
        process.update("Scanning C: drive\n", "output")
        output_event = process.report(4)
        assert output_event[0].startswith("output:"), output_event
        quiet_output_tick = process.report(5)
        assert quiet_output_tick == output_event, (output_event, quiet_output_tick)
        process.last_output_at = time.monotonic() - 9
        waiting_event = process.report(14)
        assert waiting_event[0].startswith("quiet:"), waiting_event
        process.last_output_at -= 1.1
        waiting_tick = process.report(15)
        assert waiting_tick[0] == waiting_event[0], (waiting_event, waiting_tick)
        assert waiting_tick == waiting_event, (waiting_event, waiting_tick)
        assert "remains alive" not in waiting_tick[1].lower(), waiting_tick
        assert "no measurable output, cpu time, or file i/o" in (
            waiting_tick[1].lower()
        ), waiting_tick
        process.last_output_at -= 10
        escalated_tick = process.report(25)
        assert escalated_tick[0] != waiting_event[0], escalated_tick
        assert "recovery" in escalated_tick[1].lower(), escalated_tick
        process.update("C:\\done.bin|1|0 GB\n", "output")
        resumed_event = process.report(16)
        assert resumed_event[0].startswith("output:"), resumed_event
        assert "output resumed" in resumed_event[1].lower(), resumed_event
        process.update(
            r"LLAMA_PROGRESS|search|scanning|C:|37|1284|0|C:\Windows\System32" + "\n",
            "output",
        )
        checkpoint_event = process.report(17)
        assert checkpoint_event[0].startswith("tool-progress:"), checkpoint_event
        assert checkpoint_event[1].startswith(
            "1,284 files, 37 folders checked"
        ), checkpoint_event
        checkpoint_tick = process.report(18)
        assert checkpoint_tick[0] == checkpoint_event[0], checkpoint_tick
        assert checkpoint_tick[1] == checkpoint_event[1], checkpoint_tick
    finally:
        nature._process_group_stats = original_group_stats
        nature._process_group_io_stats = original_group_io_stats

browser = nature._browser_capability()
assert browser["extension_id"] == "hehggadaopoacecdllhhajmbjkdcmajg"
assert browser["interactive_signed_in_control"] is False
print("NATURE_ACCEPTANCE_OK")
PYTESTEOF
then
    ok "Test: syntax, routing, pipefail, complete verification output, no-op strategy guards, bounded writes, safe patches, live progress, browser boundary, and persistent Up/Down history passed"
else
    fail "Agent acceptance tests failed"
fi

INSTALL_SOURCE_PATH=$(readlink -f "$0" 2>/dev/null || printf '%s' "$0")
INSTALL_FINISH_SOURCE_HASH=$(sha256sum "$INSTALL_SOURCE_PATH" | { read -r hash _; printf '%s' "$hash"; })
if [ "$INSTALL_FINISH_SOURCE_HASH" != "$INSTALL_START_SOURCE_HASH" ]; then
    fail "Installer source changed while this installation was running; success was not stamped"
    exit 1
fi
INSTALLED_AGENT_HASH=$(sha256sum "$HOME/.local/bin/llama-agent" | { read -r hash _; printf '%s' "$hash"; })
INSTALL_STAMP="$HOME/.local/share/llama-agent/installed-source.sha256"
printf '%s|%s\n' "$INSTALL_START_SOURCE_HASH" "$INSTALLED_AGENT_HASH" > "${INSTALL_STAMP}.next"
mv -f "${INSTALL_STAMP}.next" "$INSTALL_STAMP"

# ═══════════════════════════════════════════════════════════════════════════════
# FINAL SUMMARY
# ═══════════════════════════════════════════════════════════════════════════════
echo ""
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo -e "${GREEN}${BOLD}  ULTIMATE LOCAL AI AGENT v11 - SETUP COMPLETE!${NC}"
echo -e "${GREEN}${BOLD}============================================================${NC}"
echo ""
echo -e "  ${BOLD}Getting started:${NC}"
echo -e "    ${CYAN}source ~/.bashrc && llama${NC}"
echo ""
echo -e "  ${BOLD}Commands:${NC}"
echo -e "    ${CYAN}llama${NC}              Interactive agent (REPL)"
echo -e "    ${CYAN}chat${NC}               Same thing (alias)"
echo -e "    ${CYAN}llama 'task'${NC}       Single-shot: do one task and exit"
echo -e "    ${CYAN}llama-agent --server${NC}   Run as HTTP API server"
echo -e "    ${CYAN}browse open <url>${NC}  Open URL in Chrome (your profile)"
echo -e "    ${CYAN}win-tools scan C${NC}   Scan Windows drive"
echo -e "    ${CYAN}models${NC}             List downloaded models"
echo ""
echo -e "  ${BOLD}Slash commands:${NC}"
echo -e "    ${CYAN}/help${NC}                 Show the complete live command catalog"
echo -e "    ${CYAN}/status  /doctor${NC}      Inspect Nature and test its core capabilities"
echo -e "    ${CYAN}/do  /plan  /fix${NC}      Execute, plan, debug, review, test, verify, deploy"
echo -e "    ${CYAN}/shell  /python${NC}       Run direct shell commands or Python"
echo -e "    ${CYAN}/browse  /windows${NC}     Control the approved browser or Windows PC"
echo -e "    ${CYAN}/command add${NC}          Create permanent custom slash commands"
echo ""
echo -e "  ${BOLD}Prompt history:${NC} Up/Down recalls every submitted prompt across sessions"
echo -e "  ${BOLD}Completion:${NC}     Type / and press Tab to discover commands"
echo ""
echo -e "  ${BOLD}Hardware:${NC} $CORES cores | ${MEM_GB}GB RAM | $GPU_NAME (${GPU_VRAM_GB} GB)"
if [ -n "${CHOSEN_LABEL:-}" ]; then
    echo -e "  ${BOLD}Model:${NC}    $CHOSEN_LABEL"
fi
if [ -n "${EFFECTIVE_RAM_GB:-}" ] && [ "$EFFECTIVE_RAM_GB" -gt $(( MEM_GB + 3 )) ]; then
    echo ""
    echo -e "  ${YELLOW}${BOLD}IMPORTANT:${NC} .wslconfig now allows ${EFFECTIVE_RAM_GB}GB of RAM,"
    echo -e "  ${YELLOW}but this WSL session still has ${MEM_GB}GB. Restart WSL once:${NC}"
    echo -e "    ${CYAN}wsl --shutdown${NC}   (then reopen this terminal and run: llama)"
fi
echo ""
echo -e "  ${BOLD}Capabilities:${NC}"
echo -e "    ✓ Auto-executes shell commands from AI output"
echo -e "    ✓ Writes and reads files autonomously"
echo -e "    ✓ Runs Python scripts"
echo -e "    ✓ Passwordless sudo for system admin"
echo -e "    ✓ Native tool-calling (Qwen3/Gemma3 function calling)"
echo -e "    ✓ Exact Chrome Profile 2 / Person 1 URL opening and extension identity checks"
echo -e "    ! Interactive signed-in tab control fails closed unless a privileged bridge is live"
echo -e "    ✓ Windows drive operations via PowerShell (win-tools)"
echo -e "    ✓ Windows GUI automation, clipboard, notifications, screenshots+OCR"
echo -e "    ✓ Media (ffmpeg), documents (pandoc), PDFs (pdftotext), OCR (tesseract)"
echo -e "    ✓ Databases (sqlite3), network (nmap), GitHub (gh), Docker"
echo -e "    ✓ Factual English progress: one live status line plus real phase changes, never repeated transcript spam"
echo -e "    ✓ Unique Windows completion ringtone after every submitted job stops"
echo -e "    ✓ Fast/balanced/quality profiles with feature-detected llama-server flags"
echo -e "    ✓ Optional MTP speculative decoding, reported as verified only after benchmarking"
echo -e "    ✓ Optional vision via mmproj, reported as verified only after a live image probe"
echo -e "    ✓ Bounded atomic writes, chunked append, and validated structured patches"
echo -e "    ✓ Task-specific tool routing, JSONL event receipts, and explicit capability states"
echo -e "    ✓ Persistent slash commands, MCP server registry, metrics, and background jobs"
echo -e "    ✓ Persistent memory + atomic resumable task checkpoints"
echo -e "    ✓ Self-verification before final answers"
echo -e "    ✓ No fixed action-round ceiling for unfinished tasks"
echo -e "    ✓ Error recovery — retries with different approaches"
echo -e "    ✓ Exhaustive alternate-method recovery with honest blocker reporting"
echo ""
echo -e "  ${DIM}Run:  source ~/.bashrc && llama${NC}"
echo ""
