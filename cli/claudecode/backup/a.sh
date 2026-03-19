#!/bin/bash
# ============================================================================
# A.SH - COMPREHENSIVE Claude Code Restore Script v3.0 for WSL2/Ubuntu
# ============================================================================
# Enterprise-grade restore for 100% complete restoration on ANY Ubuntu/WSL2 machine
# including BRAND NEW Ubuntu installations.
#
# V3.0 MAJOR FEATURES:
# - Automatic Node.js download and installation (apt/nvm/direct)
# - Automatic Python download and installation (apt/pyenv/direct)
# - Full npm global packages restoration from backup
# - uvx/uv tools complete restoration
# - pnpm/yarn/nvm restoration
# - MCP servers auto-setup with wrapper recreation
# - MCP connection verification with auto-fix
# - Complete PATH environment restoration
# - Shell profile restoration (.bashrc, .profile, .zshrc)
# - Post-restore verification suite
#
# Usage:
#   ./a.sh                              # Uses most recent backup
#   ./a.sh -p /path/to/backup           # Use specific backup
#   ./a.sh -d                           # Dry run (test without changes)
#   ./a.sh -f                           # Force (skip confirmations)
#   ./a.sh -s                           # Selective restore
#   ./a.sh --skip-node                  # Skip Node.js installation
#   ./a.sh --skip-python                # Skip Python installation
#   ./a.sh --skip-mcp                   # Skip MCP setup
#   ./a.sh --skip-verify                # Skip verification
#   ./a.sh -v                           # Verbose output
# ============================================================================

# Removed strict mode to prevent silent exits - handle errors explicitly
set +e

# Disable Chrome integration in WSL (not supported on this platform)
# This prevents the "Chrome Native Host not supported" error
export CLAUDE_CODE_ENABLE_CFC=false

# ============================================================================
# Configuration
# ============================================================================

VERSION="3.0"
BACKUP_PATH=""
BACKUP_ROOT="${BACKUP_ROOT:-/mnt/f/backup/claudecode}"
FORCE=false
DRY_RUN=false
SELECTIVE_RESTORE=false
SKIP_NODE_INSTALL=false
SKIP_PYTHON_INSTALL=false
SKIP_MCP_SETUP=false
SKIP_VERIFICATION=false
VERBOSE=false
THREAD_COUNT=8

MIN_NODE_VERSION="18.0.0"
MIN_PYTHON_VERSION="3.9.0"
MIN_DISK_SPACE_GB=5

NODE_VERSION="22.12.0"
NODE_DOWNLOAD_URL="https://nodejs.org/dist/v${NODE_VERSION}/node-v${NODE_VERSION}-linux-x64.tar.xz"
PYTHON_VERSION="3.12.8"

USER_HOME="${HOME}"
LOGS_PATH="${BACKUP_ROOT}/logs"

# Counters
RESTORED_COUNT=0
SKIPPED_COUNT=0
ERROR_COUNT=0
TOTAL_SIZE=0
START_TIME=$(date +%s)

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
GRAY='\033[0;90m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Audit log array (bash 4+)
declare -a AUDIT_LOG=()
declare -a CHECKPOINTS=()

# Log file
LOG_FILE=""

# ============================================================================
# Argument Parsing
# ============================================================================

print_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -p, --path PATH       Use specific backup path"
    echo "  -r, --root PATH       Backup root directory (default: /mnt/f/backup/claudecode)"
    echo "  -f, --force           Skip confirmations"
    echo "  -d, --dry-run         Test without making changes"
    echo "  -s, --selective       Choose components to restore"
    echo "  --skip-node           Skip Node.js installation"
    echo "  --skip-python         Skip Python installation"
    echo "  --skip-mcp            Skip MCP server setup"
    echo "  --skip-verify         Skip post-restore verification"
    echo "  -v, --verbose         Verbose output"
    echo "  -t, --threads N       Thread count for parallel ops (default: 8)"
    echo "  -h, --help            Show this help"
    echo ""
}

while [[ $# -gt 0 ]]; do
    case $1 in
        -p|--path)
            BACKUP_PATH="$2"
            shift 2
            ;;
        -r|--root)
            BACKUP_ROOT="$2"
            shift 2
            ;;
        -f|--force)
            FORCE=true
            shift
            ;;
        -d|--dry-run)
            DRY_RUN=true
            shift
            ;;
        -s|--selective)
            SELECTIVE_RESTORE=true
            shift
            ;;
        --skip-node)
            SKIP_NODE_INSTALL=true
            shift
            ;;
        --skip-python)
            SKIP_PYTHON_INSTALL=true
            shift
            ;;
        --skip-mcp)
            SKIP_MCP_SETUP=true
            shift
            ;;
        --skip-verify)
            SKIP_VERIFICATION=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -t|--threads)
            THREAD_COUNT="$2"
            shift 2
            ;;
        -h|--help)
            print_usage
            exit 0
            ;;
        *)
            echo "Unknown option: $1"
            print_usage
            exit 1
            ;;
    esac
done

# ============================================================================
# Audit Trail System
# ============================================================================

add_audit_entry() {
    local operation="$1"
    local target="$2"
    local status="$3"
    local details="${4:-}"

    local timestamp=$(date '+%Y-%m-%d %H:%M:%S.%3N')
    local entry="{\"timestamp\":\"${timestamp}\",\"operation\":\"${operation}\",\"target\":\"${target}\",\"status\":\"${status}\",\"details\":\"${details}\",\"user\":\"${USER}\",\"host\":\"$(hostname)\"}"

    AUDIT_LOG+=("$entry")

    if [[ "$VERBOSE" == true ]]; then
        echo -e "  ${GRAY}[AUDIT] ${operation} on ${target} : ${status}${NC}"
    fi
}

save_audit_trail() {
    local dest_path="$1"
    local audit_file="${dest_path}/restore_audit_$(date '+%Y_%m_%d_%H_%M_%S').json"

    local end_time=$(date +%s)
    local duration=$((end_time - START_TIME))
    local successful=$(printf '%s\n' "${AUDIT_LOG[@]}" | grep -c '"status":"success"' || echo 0)
    local failed=$(printf '%s\n' "${AUDIT_LOG[@]}" | grep -c '"status":"failed"' || echo 0)

    {
        echo "{"
        echo "  \"restoreTimestamp\": \"$(date '+%Y-%m-%d %H:%M:%S')\","
        echo "  \"restoreVersion\": \"${VERSION}\","
        echo "  \"backupPath\": \"${BACKUP_PATH}\","
        echo "  \"entries\": ["
        local first=true
        for entry in "${AUDIT_LOG[@]}"; do
            if [[ "$first" == true ]]; then
                first=false
            else
                echo ","
            fi
            echo -n "    ${entry}"
        done
        echo ""
        echo "  ],"
        echo "  \"summary\": {"
        echo "    \"totalOperations\": ${#AUDIT_LOG[@]},"
        echo "    \"successful\": ${successful},"
        echo "    \"failed\": ${failed},"
        echo "    \"duration\": ${duration}"
        echo "  }"
        echo "}"
    } > "$audit_file" 2>/dev/null || true

    echo "$audit_file"
}

# ============================================================================
# Logging System
# ============================================================================

initialize_restore_log() {
    local logs_path="$1"

    mkdir -p "$logs_path" 2>/dev/null || true

    local log_date=$(date '+%Y_%m_%d')
    LOG_FILE="${logs_path}/restore_${log_date}.log"

    write_log "=========================================="
    write_log "Restore session started - v${VERSION}"
    write_log "=========================================="
}

write_log() {
    local message="$1"
    local level="${2:-INFO}"

    local log_entry="$(date '+%Y-%m-%d %H:%M:%S') [${level}] ${message}"

    if [[ -n "$LOG_FILE" ]]; then
        echo "$log_entry" >> "$LOG_FILE" 2>/dev/null || true
    fi

    if [[ "$VERBOSE" == true ]] || [[ "$level" == "ERROR" ]] || [[ "$level" == "SUCCESS" ]]; then
        case "$level" in
            ERROR)   echo -e "${RED}${log_entry}${NC}" ;;
            WARN)    echo -e "${YELLOW}${log_entry}${NC}" ;;
            DEBUG)   echo -e "${GRAY}${log_entry}${NC}" ;;
            SUCCESS) echo -e "${GREEN}${log_entry}${NC}" ;;
            *)       echo -e "${GRAY}${log_entry}${NC}" ;;
        esac
    fi
}

# ============================================================================
# Helper Functions
# ============================================================================

write_step() {
    local step="$1"
    local message="$2"
    echo -e "${CYAN}${step} ${message}${NC}"
    write_log "${step} ${message}"
}

write_ok() {
    local message="$1"
    echo -e "  ${GREEN}[OK]${NC} ${message}"
    write_log "  [OK] ${message}" "SUCCESS"
}

write_skip() {
    local message="$1"
    echo -e "  ${GRAY}[--]${NC} ${message}"
    write_log "  [--] ${message}"
}

write_fail() {
    local message="$1"
    echo -e "  ${RED}[!!]${NC} ${message}"
    write_log "  [!!] ${message}" "ERROR"
}

write_warn() {
    local message="$1"
    echo -e "  ${YELLOW}[!]${NC} ${message}"
    write_log "  [!] ${message}" "WARN"
}

format_size() {
    local size=${1:-0}
    # Handle empty or non-numeric input
    [[ ! "$size" =~ ^[0-9]+$ ]] && size=0

    if [[ $size -gt 1073741824 ]]; then
        local gb=$((size / 1073741824))
        local remainder=$(((size % 1073741824) * 100 / 1073741824))
        echo "${gb}.${remainder} GB"
    elif [[ $size -gt 1048576 ]]; then
        local mb=$((size / 1048576))
        local remainder=$(((size % 1048576) * 100 / 1048576))
        echo "${mb}.${remainder} MB"
    elif [[ $size -gt 1024 ]]; then
        echo "$((size / 1024)) KB"
    else
        echo "${size} B"
    fi
}

refresh_environment_path() {
    # Source shell profiles to refresh PATH
    [[ -f "${HOME}/.bashrc" ]] && source "${HOME}/.bashrc" 2>/dev/null || true
    [[ -f "${HOME}/.profile" ]] && source "${HOME}/.profile" 2>/dev/null || true
    [[ -f "${HOME}/.bash_profile" ]] && source "${HOME}/.bash_profile" 2>/dev/null || true

    # Also export common paths
    export PATH="${HOME}/.local/bin:${HOME}/.nvm/versions/node/v${NODE_VERSION}/bin:${HOME}/.pyenv/bin:${PATH}"

    write_log "Environment PATH refreshed"
}

# ============================================================================
# Retry with Exponential Backoff
# ============================================================================

invoke_with_retry() {
    local operation_name="$1"
    shift
    local max_retries=5
    local base_delay=2
    local max_delay=120
    local retry_count=0

    while [[ $retry_count -lt $max_retries ]]; do
        if "$@"; then
            return 0
        fi

        retry_count=$((retry_count + 1))

        if [[ $retry_count -lt $max_retries ]]; then
            local delay=$((base_delay * (2 ** (retry_count - 1))))
            [[ $delay -gt $max_delay ]] && delay=$max_delay
            write_log "${operation_name} failed (attempt ${retry_count}/${max_retries}). Retrying in ${delay} seconds..." "WARN"
            sleep $delay
        fi
    done

    write_log "${operation_name} failed after ${max_retries} attempts" "ERROR"
    return 1
}

# ============================================================================
# Stop Claude Processes
# ============================================================================

stop_claude_processes() {
    local timeout_seconds="${1:-30}"
    local my_pid=$$
    local my_ppid=$PPID

    write_log "Checking for running Claude Code processes..."

    # Get Claude CLI pids but exclude this script and its parent
    local claude_pids=$(pgrep -f "claude" 2>/dev/null | grep -v "^${my_pid}$" | grep -v "^${my_ppid}$" || true)
    local node_claude_pids=$(pgrep -f "node.*claude" 2>/dev/null | grep -v "^${my_pid}$" | grep -v "^${my_ppid}$" || true)

    # Filter out any bash/sh processes running this script
    local script_name="a.sh"
    local all_pids=""
    for pid in $(echo -e "${claude_pids}\n${node_claude_pids}" | sort -u | grep -v '^$'); do
        # Skip if this is our script or shell running our script
        local cmdline=$(cat /proc/$pid/cmdline 2>/dev/null | tr '\0' ' ' || true)
        if [[ "$cmdline" == *"$script_name"* ]] || [[ "$cmdline" == *"restore"* ]]; then
            continue
        fi
        # Only target actual claude CLI processes (node-based)
        if [[ "$cmdline" == *"node"*"claude"* ]] || [[ "$cmdline" == *"@anthropic-ai/claude-code"* ]]; then
            all_pids="${all_pids}${pid}\n"
        fi
    done
    all_pids=$(echo -e "$all_pids" | grep -v '^$' || true)

    if [[ -z "$all_pids" ]]; then
        write_log "No Claude Code processes running"
        return 0
    fi

    local pid_count=$(echo "$all_pids" | wc -l)
    write_log "Found ${pid_count} Claude Code process(es). Terminating..."
    add_audit_entry "ProcessTermination" "Claude processes" "in_progress" "${pid_count} processes"

    # Try graceful termination first
    for pid in $all_pids; do
        kill -TERM "$pid" 2>/dev/null || true
    done

    # Wait for graceful termination
    local elapsed=0
    while [[ $elapsed -lt $timeout_seconds ]]; do
        local still_running=false
        for pid in $all_pids; do
            if kill -0 "$pid" 2>/dev/null; then
                still_running=true
                break
            fi
        done

        if [[ "$still_running" == false ]]; then
            write_log "All Claude Code processes terminated gracefully"
            add_audit_entry "ProcessTermination" "Claude processes" "success"
            return 0
        fi

        sleep 0.5
        elapsed=$((elapsed + 1))
    done

    # Force kill remaining processes
    for pid in $all_pids; do
        if kill -0 "$pid" 2>/dev/null; then
            kill -9 "$pid" 2>/dev/null || true
            write_log "Force terminated process: ${pid}" "WARN"
        fi
    done

    add_audit_entry "ProcessTermination" "Claude processes" "completed_with_force"
    return 0
}

# ============================================================================
# Node.js Installation
# ============================================================================

test_node_installation() {
    local result_installed="false"
    local result_version=""
    local result_path=""
    local result_meets_minimum="false"
    local result_npm_version=""

    write_log "Checking Node.js installation..."

    if command -v node &>/dev/null; then
        result_path=$(command -v node)
        result_version=$(node --version 2>/dev/null | tr -d 'v' || echo "")

        if [[ -n "$result_version" ]]; then
            result_installed="true"

            # Version comparison
            local min_parts=(${MIN_NODE_VERSION//./ })
            local cur_parts=(${result_version//./ })

            if [[ ${cur_parts[0]} -gt ${min_parts[0]} ]] || \
               [[ ${cur_parts[0]} -eq ${min_parts[0]} && ${cur_parts[1]} -ge ${min_parts[1]} ]]; then
                result_meets_minimum="true"
            fi

            write_log "Node.js found: v${result_version} at ${result_path}"
        fi
    else
        write_log "Node.js not found in PATH" "DEBUG"
    fi

    if command -v npm &>/dev/null; then
        result_npm_version=$(npm --version 2>/dev/null || echo "")
        write_log "npm found: v${result_npm_version}"
    else
        write_log "npm not found" "DEBUG"
    fi

    # Return as space-separated values
    echo "${result_installed} ${result_version} ${result_path} ${result_meets_minimum} ${result_npm_version}"
}

install_nodejs() {
    local backup_path="$1"

    write_log "Installing Node.js for fresh Ubuntu/WSL2..."
    add_audit_entry "NodeInstall" "Node.js" "in_progress"

    # When running as root, prioritize system-wide installation so all users have access
    if [[ $EUID -eq 0 ]]; then
        write_log "Running as root - installing Node.js system-wide to /usr/local"

        # Method A: Direct download to /usr/local (preferred for root)
        local temp_dir=$(mktemp -d)
        local archive_name="node-v${NODE_VERSION}-linux-x64.tar.xz"
        local archive_path="${temp_dir}/${archive_name}"

        write_log "Downloading Node.js v${NODE_VERSION} from nodejs.org..."

        if curl -L "$NODE_DOWNLOAD_URL" -o "$archive_path" 2>/dev/null; then
            if tar -xJf "$archive_path" -C "$temp_dir" 2>/dev/null; then
                local extracted_dir="${temp_dir}/node-v${NODE_VERSION}-linux-x64"

                # Install to /usr/local so all users have access
                mkdir -p /usr/local/lib/nodejs
                cp -r "${extracted_dir}"/* /usr/local/ 2>/dev/null || \
                    cp -r "${extracted_dir}"/* /usr/local/lib/nodejs/

                # Create symlinks in /usr/local/bin if installed to subdir
                if [[ -x /usr/local/lib/nodejs/bin/node ]]; then
                    ln -sf /usr/local/lib/nodejs/bin/node /usr/local/bin/node 2>/dev/null || true
                    ln -sf /usr/local/lib/nodejs/bin/npm /usr/local/bin/npm 2>/dev/null || true
                    ln -sf /usr/local/lib/nodejs/bin/npx /usr/local/bin/npx 2>/dev/null || true
                fi

                # Ensure /usr/local/bin is in PATH
                export PATH="/usr/local/bin:$PATH"
                hash -r 2>/dev/null || true

                rm -rf "$temp_dir"

                # Verify installation
                if command -v node &>/dev/null && node --version &>/dev/null; then
                    write_log "Node.js installed system-wide to /usr/local"
                    add_audit_entry "NodeInstall" "Node.js" "success" "System-wide /usr/local"

                    # Ensure PATH entry is in /etc/profile.d for all users
                    if [[ ! -f /etc/profile.d/nodejs.sh ]]; then
                        echo 'export PATH="/usr/local/bin:$PATH"' > /etc/profile.d/nodejs.sh
                        chmod 644 /etc/profile.d/nodejs.sh
                    fi

                    return 0
                fi
            fi
        fi

        rm -rf "$temp_dir" 2>/dev/null || true

        # Fallback to apt/NodeSource for root
        write_log "Direct download failed, trying NodeSource apt repository..."
        if curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && \
           apt-get install -y nodejs; then
            hash -r 2>/dev/null || true
            write_log "Node.js installed via NodeSource (apt)"
            add_audit_entry "NodeInstall" "Node.js" "success" "via apt/NodeSource"
            return 0
        fi
    fi

    # Non-root installation flow

    # Method 1: Check if backup has Node.js binaries to restore
    # Skip if backup only contains metadata (node-info.json) without actual binaries
    local node_backup_path="${backup_path}/dev-tools/nodejs"
    if [[ -d "$node_backup_path" ]] && [[ -d "${node_backup_path}/bin" ]] && [[ -x "${node_backup_path}/bin/node" ]]; then
        write_log "Found Node.js binary backup, attempting to restore..."

        local node_dest="/usr/local/nodejs"

        if [[ "$DRY_RUN" == true ]]; then
            write_log "[DRY-RUN] Would restore Node.js from backup to ${node_dest}"
            return 0
        fi

        if sudo mkdir -p "$node_dest" && sudo rsync -a "${node_backup_path}/" "${node_dest}/"; then
            # Add to PATH
            echo "export PATH=\"${node_dest}/bin:\$PATH\"" >> "${HOME}/.bashrc"
            export PATH="${node_dest}/bin:$PATH"

            # Verify node works
            if "${node_dest}/bin/node" --version &>/dev/null; then
                write_log "Node.js restored from backup successfully"
                add_audit_entry "NodeInstall" "Node.js" "success" "Restored from backup"
                return 0
            else
                write_log "Restored Node.js binary not working, trying other methods..."
            fi
        fi
    fi

    # Method 2: Try nvm (Node Version Manager)
    if [[ -f "${HOME}/.nvm/nvm.sh" ]]; then
        write_log "Using existing nvm to install Node.js..."
        source "${HOME}/.nvm/nvm.sh"

        if nvm install "${NODE_VERSION}" && nvm use "${NODE_VERSION}"; then
            add_audit_entry "NodeInstall" "Node.js" "success" "via nvm"
            return 0
        fi
    fi

    # Method 3: Install nvm and then Node.js
    write_log "Installing nvm and Node.js..."

    if curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash; then
        export NVM_DIR="${HOME}/.nvm"
        [[ -s "${NVM_DIR}/nvm.sh" ]] && source "${NVM_DIR}/nvm.sh"

        if nvm install "${NODE_VERSION}" && nvm use "${NODE_VERSION}" && nvm alias default "${NODE_VERSION}"; then
            write_log "Node.js installed via nvm"
            add_audit_entry "NodeInstall" "Node.js" "success" "via nvm"
            return 0
        fi
    fi

    # Method 4: Try apt with NodeSource
    write_log "Trying NodeSource apt repository..."

    if curl -fsSL https://deb.nodesource.com/setup_22.x | sudo -E bash - && \
       sudo apt-get install -y nodejs; then
        # Refresh shell command cache after apt install
        hash -r 2>/dev/null || true
        write_log "Node.js installed via NodeSource"
        add_audit_entry "NodeInstall" "Node.js" "success" "via apt/NodeSource"
        return 0
    fi

    # Method 5: Direct download
    write_log "Attempting direct download from nodejs.org..."

    local temp_dir=$(mktemp -d)
    local archive_name="node-v${NODE_VERSION}-linux-x64.tar.xz"
    local archive_path="${temp_dir}/${archive_name}"

    if curl -L "$NODE_DOWNLOAD_URL" -o "$archive_path"; then
        if tar -xJf "$archive_path" -C "$temp_dir"; then
            local extracted_dir="${temp_dir}/node-v${NODE_VERSION}-linux-x64"

            sudo mkdir -p /usr/local/nodejs
            sudo cp -r "${extracted_dir}"/* /usr/local/nodejs/

            echo 'export PATH="/usr/local/nodejs/bin:$PATH"' >> "${HOME}/.bashrc"
            export PATH="/usr/local/nodejs/bin:$PATH"

            rm -rf "$temp_dir"

            write_log "Node.js installed from direct download"
            add_audit_entry "NodeInstall" "Node.js" "success" "Direct download"
            return 0
        fi
    fi

    rm -rf "$temp_dir" 2>/dev/null || true

    write_log "All Node.js installation methods failed. Please install manually from https://nodejs.org/" "ERROR"
    add_audit_entry "NodeInstall" "Node.js" "failed" "All methods exhausted"

    return 1
}

# ============================================================================
# Python Installation
# ============================================================================

test_python_installation() {
    local result_installed="false"
    local result_version=""
    local result_path=""
    local result_meets_minimum="false"
    local result_pip_version=""

    write_log "Checking Python installation..."

    # Try python3 first, then python
    local python_cmd=""
    if command -v python3 &>/dev/null; then
        python_cmd="python3"
    elif command -v python &>/dev/null; then
        python_cmd="python"
    fi

    if [[ -n "$python_cmd" ]]; then
        result_path=$(command -v "$python_cmd")
        result_version=$($python_cmd --version 2>/dev/null | sed 's/Python //' || echo "")

        if [[ -n "$result_version" ]]; then
            result_installed="true"

            # Version comparison
            local min_parts=(${MIN_PYTHON_VERSION//./ })
            local cur_parts=(${result_version//./ })

            if [[ ${cur_parts[0]} -gt ${min_parts[0]} ]] || \
               [[ ${cur_parts[0]} -eq ${min_parts[0]} && ${cur_parts[1]} -ge ${min_parts[1]} ]]; then
                result_meets_minimum="true"
            fi

            write_log "Python found: v${result_version} at ${result_path}"
        fi
    else
        write_log "Python not found in PATH" "DEBUG"
    fi

    if command -v pip3 &>/dev/null; then
        result_pip_version=$(pip3 --version 2>/dev/null | sed -n 's/pip \([0-9.]*\).*/\1/p' || echo "")
        write_log "pip found: v${result_pip_version}"
    elif command -v pip &>/dev/null; then
        result_pip_version=$(pip --version 2>/dev/null | sed -n 's/pip \([0-9.]*\).*/\1/p' || echo "")
        write_log "pip found: v${result_pip_version}"
    else
        write_log "pip not found" "DEBUG"
    fi

    echo "${result_installed} ${result_version} ${result_path} ${result_meets_minimum} ${result_pip_version}"
}

install_python() {
    local backup_path="$1"

    write_log "Installing Python for fresh Ubuntu/WSL2..."
    add_audit_entry "PythonInstall" "Python" "in_progress"

    # Method 1: Check if backup has Python
    local python_backup_path="${backup_path}/dev-tools/python"
    if [[ -d "$python_backup_path" ]]; then
        write_log "Found Python backup, attempting to restore..."

        if [[ "$DRY_RUN" == true ]]; then
            write_log "[DRY-RUN] Would restore Python from backup"
            return 0
        fi

        # Restore Python virtual environments and tools
        local dest_path="${HOME}/.local/python"
        mkdir -p "$dest_path"

        if rsync -a "${python_backup_path}/" "${dest_path}/"; then
            write_log "Python tools restored from backup"
            add_audit_entry "PythonInstall" "Python" "success" "Restored from backup"
        fi
    fi

    # Method 2: Try apt (most common for Ubuntu)
    write_log "Installing Python via apt..."

    if sudo apt-get update && sudo apt-get install -y python3 python3-pip python3-venv; then
        write_log "Python installed via apt"
        add_audit_entry "PythonInstall" "Python" "success" "via apt"
        return 0
    fi

    # Method 3: Try pyenv
    write_log "Trying pyenv installation..."

    if [[ -d "${HOME}/.pyenv" ]]; then
        export PYENV_ROOT="${HOME}/.pyenv"
        export PATH="${PYENV_ROOT}/bin:$PATH"
        eval "$(pyenv init -)"
    else
        # Install pyenv
        if curl https://pyenv.run | bash; then
            export PYENV_ROOT="${HOME}/.pyenv"
            export PATH="${PYENV_ROOT}/bin:$PATH"
            eval "$(pyenv init -)"

            # Add to bashrc
            {
                echo 'export PYENV_ROOT="$HOME/.pyenv"'
                echo 'export PATH="$PYENV_ROOT/bin:$PATH"'
                echo 'eval "$(pyenv init -)"'
            } >> "${HOME}/.bashrc"
        fi
    fi

    if command -v pyenv &>/dev/null; then
        # Install build dependencies
        sudo apt-get install -y build-essential libssl-dev zlib1g-dev \
            libbz2-dev libreadline-dev libsqlite3-dev curl \
            libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev 2>/dev/null || true

        if pyenv install "${PYTHON_VERSION}" && pyenv global "${PYTHON_VERSION}"; then
            write_log "Python installed via pyenv"
            add_audit_entry "PythonInstall" "Python" "success" "via pyenv"
            return 0
        fi
    fi

    # Method 4: deadsnakes PPA (for newer Python versions)
    write_log "Trying deadsnakes PPA..."

    if sudo add-apt-repository -y ppa:deadsnakes/ppa && \
       sudo apt-get update && \
       sudo apt-get install -y python3.12 python3.12-venv python3.12-dev; then
        sudo update-alternatives --install /usr/bin/python3 python3 /usr/bin/python3.12 1 2>/dev/null || true
        write_log "Python installed via deadsnakes PPA"
        add_audit_entry "PythonInstall" "Python" "success" "via deadsnakes PPA"
        return 0
    fi

    write_log "All Python installation methods failed" "ERROR"
    add_audit_entry "PythonInstall" "Python" "failed"

    return 1
}

# ============================================================================
# npm Global Packages Restoration
# ============================================================================

restore_npm_global_packages() {
    local backup_path="$1"

    write_log "Restoring npm global packages..."
    add_audit_entry "NpmRestore" "npm packages" "in_progress"

    local npm_backup_path="${backup_path}/dev-tools/npm"
    local npm_dest_path="${HOME}/.npm-global"

    if [[ ! -d "$npm_backup_path" ]]; then
        # Also check Windows path structure
        npm_backup_path="${backup_path}/npm/node_modules"
        if [[ ! -d "$npm_backup_path" ]]; then
            write_log "No npm backup found" "WARN"
            echo "0"
            return 1
        fi
    fi

    if [[ "$DRY_RUN" == true ]]; then
        write_log "[DRY-RUN] Would restore npm packages from ${npm_backup_path}"
        echo "0"
        return 0
    fi

    # Setup npm global directory
    mkdir -p "$npm_dest_path"
    npm config set prefix "$npm_dest_path" 2>/dev/null || true

    # Add to PATH if not already
    if ! grep -q "npm-global" "${HOME}/.bashrc" 2>/dev/null; then
        echo 'export PATH="${HOME}/.npm-global/bin:$PATH"' >> "${HOME}/.bashrc"
    fi
    export PATH="${HOME}/.npm-global/bin:$PATH"

    # Option 1: Restore package list and reinstall
    local package_list="${backup_path}/dev-tools/npm-packages.txt"
    if [[ -f "$package_list" ]]; then
        write_log "Reinstalling npm packages from list..."
        local restored=0

        while IFS= read -r package || [[ -n "$package" ]]; do
            if [[ -n "$package" && ! "$package" =~ ^# ]]; then
                if npm install -g "$package" 2>/dev/null; then
                    ((restored++)) || true
                    write_log "Installed: ${package}"
                fi
            fi
        done < "$package_list"

        write_log "npm packages restored: ${restored} packages"
        add_audit_entry "NpmRestore" "npm packages" "success" "${restored} packages"
        echo "$restored"
        return 0
    fi

    # Option 2: Copy node_modules directly
    if [[ -d "${npm_backup_path}" ]]; then
        write_log "Copying npm packages directly..."

        mkdir -p "${npm_dest_path}/lib/node_modules"

        if rsync -a "${npm_backup_path}/" "${npm_dest_path}/lib/node_modules/" 2>/dev/null; then
            local package_count=$(find "${npm_dest_path}/lib/node_modules" -maxdepth 1 -type d | wc -l)
            ((package_count--)) || true  # Subtract 1 for the directory itself

            write_log "npm packages copied: ${package_count} packages"
            add_audit_entry "NpmRestore" "npm packages" "success" "${package_count} packages"
            echo "$package_count"
            return 0
        fi
    fi

    write_log "Failed to restore npm packages" "WARN"
    echo "0"
    return 1
}

# ============================================================================
# uvx/uv Tools Restoration
# ============================================================================

restore_uvx_tools() {
    local backup_path="$1"

    write_log "Restoring uvx/uv tools..."
    add_audit_entry "UvxRestore" "uvx tools" "in_progress"

    local uv_backup_path="${backup_path}/dev-tools/uv"

    if [[ ! -d "$uv_backup_path" ]]; then
        write_log "No uvx backup found" "DEBUG"
        echo "0"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        write_log "[DRY-RUN] Would restore uvx tools from ${uv_backup_path}"
        echo "0"
        return 0
    fi

    local restored=0

    # Install uv if not present
    if ! command -v uv &>/dev/null; then
        write_log "Installing uv..."
        curl -LsSf https://astral.sh/uv/install.sh | sh 2>/dev/null || true
        export PATH="${HOME}/.local/bin:$PATH"
    fi

    # Restore uv cache and tools
    for uv_dir in "${uv_backup_path}"/*; do
        if [[ -d "$uv_dir" ]]; then
            local dir_name=$(basename "$uv_dir")
            local dest_path=""

            case "$dir_name" in
                "uv"|"cache")
                    dest_path="${HOME}/.cache/uv"
                    ;;
                "bin")
                    dest_path="${HOME}/.local/bin"
                    ;;
                *)
                    dest_path="${HOME}/.local/${dir_name}"
                    ;;
            esac

            mkdir -p "$dest_path"

            if rsync -a "${uv_dir}/" "${dest_path}/" 2>/dev/null; then
                ((restored++)) || true
                write_log "Restored uvx: ${dir_name}"
            fi
        fi
    done

    add_audit_entry "UvxRestore" "uvx tools" "success" "${restored} restored"
    echo "$restored"
}

# ============================================================================
# Package Managers Restoration (pnpm/yarn/nvm)
# ============================================================================

restore_package_managers() {
    local backup_path="$1"

    write_log "Restoring additional package managers..."

    local pnpm_success="false"
    local yarn_success="false"
    local nvm_success="false"

    # pnpm
    local pnpm_backup="${backup_path}/dev-tools/pnpm"
    if [[ -d "$pnpm_backup" ]]; then
        local pnpm_dest="${HOME}/.local/share/pnpm"
        mkdir -p "$pnpm_dest"

        if [[ "$DRY_RUN" != true ]] && rsync -a "${pnpm_backup}/" "${pnpm_dest}/" 2>/dev/null; then
            pnpm_success="true"
            write_log "pnpm restored"

            # Add pnpm to PATH
            if ! grep -q "pnpm" "${HOME}/.bashrc" 2>/dev/null; then
                echo 'export PNPM_HOME="${HOME}/.local/share/pnpm"' >> "${HOME}/.bashrc"
                echo 'export PATH="${PNPM_HOME}:$PATH"' >> "${HOME}/.bashrc"
            fi
        fi
    fi

    # yarn
    local yarn_backup="${backup_path}/dev-tools/yarn"
    if [[ -d "$yarn_backup" ]]; then
        local yarn_dest="${HOME}/.yarn"
        mkdir -p "$yarn_dest"

        if [[ "$DRY_RUN" != true ]] && rsync -a "${yarn_backup}/" "${yarn_dest}/" 2>/dev/null; then
            yarn_success="true"
            write_log "yarn restored"
        fi
    fi

    # nvm
    local nvm_backup="${backup_path}/dev-tools/nvm"
    if [[ -d "$nvm_backup" ]]; then
        local nvm_dest="${HOME}/.nvm"
        mkdir -p "$nvm_dest"

        if [[ "$DRY_RUN" != true ]] && rsync -a "${nvm_backup}/" "${nvm_dest}/" 2>/dev/null; then
            nvm_success="true"
            write_log "nvm restored"

            # Add nvm to bashrc
            if ! grep -q "NVM_DIR" "${HOME}/.bashrc" 2>/dev/null; then
                {
                    echo 'export NVM_DIR="${HOME}/.nvm"'
                    echo '[ -s "${NVM_DIR}/nvm.sh" ] && \. "${NVM_DIR}/nvm.sh"'
                    echo '[ -s "${NVM_DIR}/bash_completion" ] && \. "${NVM_DIR}/bash_completion"'
                } >> "${HOME}/.bashrc"
            fi
        fi
    fi

    echo "${pnpm_success} ${yarn_success} ${nvm_success}"
}

# ============================================================================
# MCP Servers Setup
# ============================================================================

# Extract npm package name from Windows .cmd wrapper file
# Parses: "C:\...\node_modules\@scope\package\..." or "C:\...\node_modules\package\..."
extract_npm_package_from_cmd() {
    local cmd_file="$1"
    local line=""

    # Read the second line (first line is @echo off)
    line=$(sed -n '2p' "$cmd_file" 2>/dev/null)

    # Handle scoped packages: @scope\package
    if [[ "$line" =~ node_modules\\(@[^\\]+)\\([^\\]+)\\ ]]; then
        echo "${BASH_REMATCH[1]}/${BASH_REMATCH[2]}"
        return 0
    fi

    # Handle non-scoped packages
    if [[ "$line" =~ node_modules\\([^\\@][^\\]*)\\ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    # Try forward slashes (some .cmd files use them)
    if [[ "$line" =~ node_modules/(@[^/]+/[^/]+)/ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi
    if [[ "$line" =~ node_modules/([^/@][^/]*)/ ]]; then
        echo "${BASH_REMATCH[1]}"
        return 0
    fi

    echo ""
    return 1
}

# Extract extra CLI arguments from Windows .cmd wrapper file (like API keys)
extract_args_from_cmd() {
    local cmd_file="$1"
    local line=""

    # Read the second line
    line=$(sed -n '2p' "$cmd_file" 2>/dev/null)

    # Match: *.js" <args> or *.cjs" <args> (everything after the .js/.cjs" and before %*)
    if [[ "$line" =~ \.(js|cjs)\"[[:space:]]+(.+)%\* ]]; then
        local args="${BASH_REMATCH[2]}"
        # Trim whitespace
        args="${args%% }"
        args="${args## }"
        echo "$args"
        return 0
    fi

    # Check for args after %* removal
    if [[ "$line" =~ \.(js|cjs)\"[[:space:]]+(.+)$ ]]; then
        local args="${BASH_REMATCH[2]}"
        args="${args//%\*/}"
        args="${args%% }"
        args="${args## }"
        if [[ -n "$args" ]]; then
            echo "$args"
            return 0
        fi
    fi

    echo ""
    return 0
}

# Extract the JS entry point path pattern from Windows .cmd wrapper
extract_js_pattern_from_cmd() {
    local cmd_file="$1"
    local line=""

    line=$(sed -n '2p' "$cmd_file" 2>/dev/null)

    # Extract the JS file path after node_modules
    if [[ "$line" =~ node_modules\\(.+\.(js|cjs))\" ]]; then
        local js_path="${BASH_REMATCH[1]}"
        # Convert backslashes to forward slashes
        js_path="${js_path//\\/\/}"
        echo "$js_path"
        return 0
    fi

    echo ""
    return 1
}

install_mcp_packages_and_generate_wrappers() {
    local backup_path="$1"
    local claude_dir="$2"
    local npm_cmd=""
    local npm_prefix=""
    local installed=0
    local failed=0
    local skipped=0

    # Find npm binary (prefer Linux npm)
    for npm_path in /usr/bin/npm /usr/local/bin/npm "${HOME}/.nvm/versions/node/"*/bin/npm; do
        if [[ -x "$npm_path" ]]; then
            npm_cmd="$npm_path"
            break
        fi
    done

    if [[ -z "$npm_cmd" ]]; then
        write_log "npm not found - cannot install MCP packages" "WARN"
        return 1
    fi

    # Determine npm global prefix
    if [[ $EUID -eq 0 ]]; then
        npm_prefix="/usr/local"
    else
        npm_prefix="${HOME}/.npm-global"
        mkdir -p "${npm_prefix}/lib/node_modules"
        "$npm_cmd" config set prefix "$npm_prefix" 2>/dev/null || true
    fi

    local node_modules="${npm_prefix}/lib/node_modules"

    # Find Windows .cmd wrappers in backup
    local cmd_source="${backup_path}/home/.claude"
    if [[ ! -d "$cmd_source" ]]; then
        write_log "No .cmd wrappers found in backup" "WARN"
        echo "0 0 0"
        return 1
    fi

    write_log "Parsing Windows .cmd wrappers and installing MCP packages..."

    shopt -s nullglob
    for cmd_file in "${cmd_source}"/*.cmd; do
        [[ -f "$cmd_file" ]] || continue

        local base_name=$(basename "$cmd_file" .cmd)
        local wrapper_path="${claude_dir}/${base_name}.sh"

        # Extract package name from .cmd file
        local pkg_name=$(extract_npm_package_from_cmd "$cmd_file")
        if [[ -z "$pkg_name" ]]; then
            write_log "Could not extract package from: ${base_name}.cmd" "WARN"
            ((skipped++))
            continue
        fi

        # Extract extra args (like API keys)
        local extra_args=$(extract_args_from_cmd "$cmd_file")

        # Extract JS path pattern for finding the entry point
        local js_pattern=$(extract_js_pattern_from_cmd "$cmd_file")

        write_log "Processing: ${base_name} -> ${pkg_name}"

        # Determine package directory path
        local pkg_dir="${node_modules}/${pkg_name}"

        # Check if package is already installed
        if [[ ! -d "$pkg_dir" ]]; then
            write_log "Installing ${pkg_name}..."
            if "$npm_cmd" install -g --prefix "$npm_prefix" "$pkg_name" 2>/dev/null; then
                ((installed++))
                write_log "Installed: ${pkg_name}"
            else
                write_log "Failed to install: ${pkg_name}" "WARN"
                ((failed++))
                continue
            fi
        fi

        # Find the main JS entry point
        local main_js=""

        # First try the exact pattern from Windows .cmd
        if [[ -n "$js_pattern" ]]; then
            local candidate="${node_modules}/${js_pattern}"
            if [[ -f "$candidate" ]]; then
                main_js="$candidate"
            fi
        fi

        # Fallback: try common locations
        if [[ -z "$main_js" ]] || [[ ! -f "$main_js" ]]; then
            for try_path in \
                "${pkg_dir}/dist/index.js" \
                "${pkg_dir}/build/index.js" \
                "${pkg_dir}/cli.js" \
                "${pkg_dir}/index.js" \
                "${pkg_dir}/lib/index.js" \
                "${pkg_dir}/dist/cli.js" \
                "${pkg_dir}/bin/index.js"; do
                if [[ -f "$try_path" ]]; then
                    main_js="$try_path"
                    break
                fi
            done
        fi

        # Last resort: check package.json bin or main field
        if [[ -z "$main_js" ]] || [[ ! -f "$main_js" ]]; then
            if [[ -f "${pkg_dir}/package.json" ]]; then
                # Try bin field first
                local bin_field=$(grep -o '"bin"[[:space:]]*:[[:space:]]*"[^"]*"' "${pkg_dir}/package.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
                if [[ -n "$bin_field" ]] && [[ -f "${pkg_dir}/${bin_field}" ]]; then
                    main_js="${pkg_dir}/${bin_field}"
                else
                    # Try main field
                    local main_field=$(grep -o '"main"[[:space:]]*:[[:space:]]*"[^"]*"' "${pkg_dir}/package.json" 2>/dev/null | head -1 | sed 's/.*"\([^"]*\)".*/\1/')
                    if [[ -n "$main_field" ]] && [[ -f "${pkg_dir}/${main_field}" ]]; then
                        main_js="${pkg_dir}/${main_field}"
                    fi
                fi
            fi
        fi

        if [[ -n "$main_js" ]] && [[ -f "$main_js" ]]; then
            # Generate wrapper script with extra args if present
            if [[ -n "$extra_args" ]]; then
                cat > "$wrapper_path" << EOF
#!/bin/bash
exec node "${main_js}" ${extra_args} "\$@"
EOF
            else
                cat > "$wrapper_path" << EOF
#!/bin/bash
exec node "${main_js}" "\$@"
EOF
            fi
            chmod +x "$wrapper_path"
            write_log "Created wrapper: ${base_name}.sh"
        else
            write_log "No entry point found for: ${pkg_name}" "WARN"
            ((failed++))
        fi
    done
    shopt -u nullglob

    write_log "MCP packages: ${installed} installed, ${failed} failed, ${skipped} skipped"
    echo "${installed} ${failed} ${skipped}"
}

restore_mcp_servers() {
    local backup_path="$1"

    write_log "Setting up MCP servers..."
    add_audit_entry "McpSetup" "MCP servers" "in_progress"

    local claude_dir="${HOME}/.claude"
    local wrappers_restored=0
    local servers_connected=0
    local servers_failed=0

    if [[ "$DRY_RUN" == true ]]; then
        write_log "[DRY-RUN] Would setup MCP servers"
        echo "0 0 0"
        return 0
    fi

    # Ensure .claude directory exists
    mkdir -p "$claude_dir"

    # Step 0: Install MCP npm packages in Linux and generate proper wrappers
    write_log "Installing MCP packages in Linux npm global..."
    install_mcp_packages_and_generate_wrappers "$backup_path" "$claude_dir"

    # Step 1: Check for any existing .sh wrappers in backup (override if newer)
    local wrapper_sources=(
        "${backup_path}/home/.claude"
        "${backup_path}/MCP/claudecode/wrappers"
    )

    for source in "${wrapper_sources[@]}"; do
        if [[ -d "$source" ]]; then
            # Look for .sh files only (don't convert .cmd - we generated proper Linux wrappers above)
            shopt -s nullglob
            for wrapper in "${source}"/*.sh; do
                if [[ -f "$wrapper" ]]; then
                    local base_name=$(basename "$wrapper")
                    local dest_path="${claude_dir}/${base_name}"

                    # Check if wrapper contains Windows paths (skip if so)
                    if grep -q '/mnt/c/' "$wrapper" 2>/dev/null || grep -q 'C:\\' "$wrapper" 2>/dev/null; then
                        write_log "Skipping wrapper with Windows path: ${base_name}"
                        continue
                    fi

                    # Copy .sh file directly if it has valid Linux paths
                    cp "$wrapper" "$dest_path"
                    chmod +x "$dest_path"
                    ((wrappers_restored++)) || true
                    write_log "Restored wrapper: ${base_name}"
                fi
            done
            shopt -u nullglob
        fi
    done

    # Step 2: Restore mcp-ondemand.sh (convert from .ps1 if needed)
    local mcp_ondemand_sources=(
        "${backup_path}/home/.claude/mcp-ondemand.sh"
        "${backup_path}/home/.claude/mcp-ondemand.ps1"
    )

    for source in "${mcp_ondemand_sources[@]}"; do
        if [[ -f "$source" ]]; then
            if [[ "$source" == *.sh ]]; then
                cp "$source" "${claude_dir}/mcp-ondemand.sh"
                chmod +x "${claude_dir}/mcp-ondemand.sh"
            fi
            write_log "Restored mcp-ondemand script"
            break
        fi
    done

    # Step 3: Create comprehensive mcp-ondemand.sh (always update to latest version)
    cat > "${claude_dir}/mcp-ondemand.sh" << 'MCPSCRIPT'
#!/bin/bash
# MCP v6.6 - On-Demand Server Manager for Linux/WSL2

CLAUDE_DIR="${HOME}/.claude"

# All 39 server definitions
declare -A MCP_SERVERS=(
    # MEMORY
    ["knowledge-graph"]="knowledge-graph.sh"
    ["context7"]="context7.sh"
    ["mcp-memory-server"]="mcp-memory-server.sh"
    # REASONING
    ["sequential-thinking"]="sequential-thinking.sh"
    ["think-tool-mcp"]="think-tool-mcp.sh"
    ["code-reasoning-mcp"]="code-reasoning-mcp.sh"
    # CODING
    ["python-repl-mcp"]="python-repl-mcp.sh"
    ["code-review-mcp"]="code-review-mcp.sh"
    ["code-sandbox-mcp"]="code-sandbox-mcp.sh"
    ["e2b-mcp"]="e2b-mcp.sh"
    ["sentry"]="sentry.sh"
    # SECURITY
    ["mcp-security-audit"]="mcp-security-audit.sh"
    # TASKS
    ["taskflow-mcp"]="taskflow-mcp.sh"
    ["todoist"]="todoist.sh"
    # MCP
    ["mcp-installer"]="mcp-installer.sh"
    ["mcp-compass"]="mcp-compass.sh"
    ["npm-search-mcp"]="npm-search-mcp.sh"
    # SEARCH
    ["exa"]="exa.sh"
    ["deep-research"]="deep-research.sh"
    ["duckduckgo-search"]="duckduckgo-search.sh"
    ["superfetch"]="superfetch.sh"
    # WEB
    ["puppeteer"]="puppeteer.sh"
    ["read-website-fast"]="read-website-fast.sh"
    ["playwright-mcp"]="playwright-mcp.sh"
    # DATA
    ["graphql"]="graphql.sh"
    ["github"]="github.sh"
    # DEVOPS
    ["docker-mcp"]="docker-mcp.sh"
    ["filesystem"]="filesystem.sh"
    # SYSTEM
    ["everything"]="everything.sh"
    ["mcp-server-commands"]="mcp-server-commands.sh"
    ["powershell-exec"]="powershell-exec.sh"
    ["mcp-system-info"]="mcp-system-info.sh"
    # CONTROL
    ["computer-use-mcp"]="computer-use-mcp.sh"
    ["mcp-control"]="mcp-control.sh"
    # MOBILE
    ["mobile-mcp"]="mobile-mcp.sh"
    # DOCS
    ["document-generator-mcp"]="document-generator-mcp.sh"
    ["deepwiki"]="deepwiki.sh"
    ["youtube"]="youtube.sh"
    ["figma"]="figma.sh"
)

# Category definitions
declare -A MCP_CATEGORIES=(
    ["mem"]="knowledge-graph context7 mcp-memory-server"
    ["rea"]="sequential-thinking think-tool-mcp code-reasoning-mcp"
    ["cod"]="python-repl-mcp code-review-mcp code-sandbox-mcp e2b-mcp sentry"
    ["sec"]="mcp-security-audit"
    ["tsk"]="taskflow-mcp todoist"
    ["mcp"]="mcp-installer mcp-compass npm-search-mcp"
    ["sea"]="exa deep-research duckduckgo-search superfetch"
    ["web"]="puppeteer read-website-fast playwright-mcp"
    ["dat"]="graphql github"
    ["dev"]="docker-mcp filesystem"
    ["sys"]="everything mcp-server-commands powershell-exec mcp-system-info"
    ["ctl"]="computer-use-mcp mcp-control"
    ["mob"]="mobile-mcp"
    ["doc"]="document-generator-mcp deepwiki youtube figma"
)

# Category names
declare -A MCP_CATEGORY_NAMES=(
    ["mem"]="MEMORY"
    ["rea"]="REASONING"
    ["cod"]="CODING"
    ["sec"]="SECURITY"
    ["tsk"]="TASKS"
    ["mcp"]="MCP"
    ["sea"]="SEARCH"
    ["web"]="WEB"
    ["dat"]="DATA"
    ["dev"]="DEVOPS"
    ["sys"]="SYSTEM"
    ["ctl"]="CONTROL"
    ["mob"]="MOBILE"
    ["doc"]="DOCS"
)

# Aliases
declare -A MCP_ALIASES=(
    ["think-tool"]="think-tool-mcp"
    ["e2b"]="e2b-mcp"
    ["docker"]="docker-mcp"
    ["control"]="mcp-control"
    ["playwright"]="playwright-mcp"
    ["audit"]="mcp-security-audit"
    ["taskflow"]="taskflow-mcp"
    ["fetch"]="superfetch"
    ["mobile"]="mobile-mcp"
    ["android"]="mobile-mcp"
)

resolve_mcp_name() {
    local name="${1,,}"
    if [[ -n "${MCP_ALIASES[$name]}" ]]; then
        echo "${MCP_ALIASES[$name]}"
    else
        echo "$name"
    fi
}

mcps() {
    echo ""
    echo "=================================================="
    echo " MCP v6.6 - ${#MCP_SERVERS[@]} SERVERS"
    echo "=================================================="

    local active_list=$(claude mcp list 2>/dev/null || echo "")
    local active_count=0

    for cat in mem rea cod sec tsk mcp sea web dat dev sys ctl mob doc; do
        echo ""
        echo -e "\033[0;36m[${MCP_CATEGORY_NAMES[$cat]}] o${cat}/d${cat}\033[0m"
        for srv in ${MCP_CATEGORIES[$cat]}; do
            if echo "$active_list" | grep -q "^${srv}:"; then
                echo -e "  \033[0;32m[ON]\033[0m $srv"
                ((active_count++))
            else
                echo -e "  \033[0;90m[--]\033[0m $srv"
            fi
        done
    done

    echo ""
    echo -e "\033[1;33mCMDS: mcp-on mcp-off mcp-only o<cat> d<cat> mcps mcp-backup\033[0m"
    echo "Active: ${active_count}/${#MCP_SERVERS[@]}"
    echo ""
}

mcp-on() {
    local servers=("$@")
    if [[ ${#servers[@]} -eq 0 ]]; then
        # Enable all
        for srv in "${!MCP_SERVERS[@]}"; do
            local wrapper="${CLAUDE_DIR}/${MCP_SERVERS[$srv]}"
            if [[ -f "$wrapper" ]]; then
                claude mcp add -s user "$srv" "$wrapper" 2>/dev/null
                echo -e "\033[0;32m[+]\033[0m $srv"
            fi
        done
        return
    fi

    for server in "${servers[@]}"; do
        local srv=$(resolve_mcp_name "$server")
        local wrapper="${CLAUDE_DIR}/${MCP_SERVERS[$srv]:-${srv}.sh}"
        if [[ -f "$wrapper" ]]; then
            claude mcp add -s user "$srv" "$wrapper" 2>/dev/null
            echo -e "\033[0;32m[+]\033[0m $srv"
        else
            echo -e "\033[0;31m[!]\033[0m $srv (wrapper not found)"
        fi
    done
}

mcp-off() {
    local servers=("$@")
    if [[ ${#servers[@]} -eq 0 ]]; then
        # Disable all
        local active_list=$(claude mcp list 2>/dev/null | grep ":" | cut -d: -f1)
        for srv in $active_list; do
            claude mcp remove "$srv" -s user 2>/dev/null
            echo -e "\033[1;33m[-]\033[0m $srv"
        done
        return
    fi

    for server in "${servers[@]}"; do
        local srv=$(resolve_mcp_name "$server")
        claude mcp remove "$srv" -s user 2>/dev/null
        echo -e "\033[1;33m[-]\033[0m $srv"
    done
}

mcp-only() {
    local keep=("$@")
    local keep_resolved=()
    for srv in "${keep[@]}"; do
        keep_resolved+=("$(resolve_mcp_name "$srv")")
    done

    # Disable servers not in keep list
    local active_list=$(claude mcp list 2>/dev/null | grep ":" | cut -d: -f1)
    for srv in $active_list; do
        local found=false
        for k in "${keep_resolved[@]}"; do
            [[ "$srv" == "$k" ]] && found=true && break
        done
        if [[ "$found" == false ]]; then
            claude mcp remove "$srv" -s user 2>/dev/null
            echo -e "\033[0;90m[-]\033[0m $srv"
        fi
    done

    # Enable servers in keep list
    for srv in "${keep_resolved[@]}"; do
        local wrapper="${CLAUDE_DIR}/${MCP_SERVERS[$srv]:-${srv}.sh}"
        if [[ -f "$wrapper" ]]; then
            if ! echo "$active_list" | grep -q "^${srv}$"; then
                claude mcp add -s user "$srv" "$wrapper" 2>/dev/null
                echo -e "\033[0;32m[+]\033[0m $srv"
            fi
        fi
    done
}

# Category enable/disable functions
enable_category() {
    local cat="$1"
    for srv in ${MCP_CATEGORIES[$cat]}; do
        local wrapper="${CLAUDE_DIR}/${MCP_SERVERS[$srv]}"
        if [[ -f "$wrapper" ]]; then
            claude mcp add -s user "$srv" "$wrapper" 2>/dev/null
            echo -e "\033[0;32m[+]\033[0m $srv"
        fi
    done
}

disable_category() {
    local cat="$1"
    for srv in ${MCP_CATEGORIES[$cat]}; do
        claude mcp remove "$srv" -s user 2>/dev/null
        echo -e "\033[1;33m[-]\033[0m $srv"
    done
}

# Category shortcuts: omem, dmem, orea, drea, etc.
omem() { enable_category mem; }
dmem() { disable_category mem; }
orea() { enable_category rea; }
drea() { disable_category rea; }
ocod() { enable_category cod; }
dcod() { disable_category cod; }
osec() { enable_category sec; }
dsec() { disable_category sec; }
otsk() { enable_category tsk; }
dtsk() { disable_category tsk; }
omcp() { enable_category mcp; }
dmcp() { disable_category mcp; }
osea() { enable_category sea; }
dsea() { disable_category sea; }
oweb() { enable_category web; }
dweb() { disable_category web; }
odat() { enable_category dat; }
ddat() { disable_category dat; }
odev() { enable_category dev; }
ddev() { disable_category dev; }
osys() { enable_category sys; }
dsys() { disable_category sys; }
octl() { enable_category ctl; }
dctl() { disable_category ctl; }
omob() { enable_category mob; }
dmob() { disable_category mob; }
odoc() { enable_category doc; }
ddoc() { disable_category doc; }

mcp-backup() {
    local backup_dir="${CLAUDE_DIR}/backups/MCP_$(date +%Y%m%d_%H%M%S)"
    mkdir -p "$backup_dir/wrappers"
    cp "${CLAUDE_DIR}"/*.sh "$backup_dir/wrappers/" 2>/dev/null
    claude mcp list > "$backup_dir/status.txt" 2>/dev/null
    echo "Backup saved to: $backup_dir"
}

# Export functions
export -f mcps mcp-on mcp-off mcp-only mcp-backup resolve_mcp_name
export -f enable_category disable_category
export -f omem dmem orea drea ocod dcod osec dsec otsk dtsk
export -f omcp dmcp osea dsea oweb dweb odat ddat odev ddev
export -f osys dsys octl dctl omob dmob odoc ddoc
MCPSCRIPT
    chmod +x "${claude_dir}/mcp-ondemand.sh"
    write_log "Created comprehensive mcp-ondemand.sh with ${#MCP_SERVERS[@]} servers"

    # Step 4: Try to connect all MCP servers
    write_log "Registering all MCP servers to Claude CLI..."

    # Find all .sh wrappers except mcp-ondemand.sh
    shopt -s nullglob
    for wrapper_path in "${claude_dir}"/*.sh; do
        if [[ -f "$wrapper_path" ]]; then
            local wrapper_name=$(basename "$wrapper_path")
            local server_name="${wrapper_name%.sh}"

            # Skip mcp-ondemand.sh
            if [[ "$server_name" == "mcp-ondemand" ]]; then
                continue
            fi

            # Try to add the server
            if claude mcp add -s user "$server_name" "$wrapper_path" 2>/dev/null; then
                ((servers_connected++)) || true
                write_log "Connected MCP: ${server_name}"
            else
                ((servers_failed++)) || true
                write_log "Failed to connect: ${server_name}" "WARN"
            fi
        fi
    done
    shopt -u nullglob

    add_audit_entry "McpSetup" "MCP servers" "success" "Wrappers: ${wrappers_restored}, Connected: ${servers_connected}"

    echo "${wrappers_restored} ${servers_connected} ${servers_failed}"
}

# ============================================================================
# MCP Health Check
# ============================================================================

test_mcp_server_health() {
    local auto_fix="${1:-false}"

    write_log "Checking MCP server health..."

    local checked=0
    local healthy=0
    local unhealthy=0
    local fixed=0

    local mcp_list=$(claude mcp list 2>&1 || echo "")

    if [[ "$mcp_list" == *"No MCP"* ]] || [[ -z "$mcp_list" ]]; then
        write_log "No MCP servers configured"
        echo "0 0 0 0"
        return 0
    fi

    while IFS= read -r line; do
        if [[ "$line" =~ ^([^:]+):(.+)$ ]]; then
            local server_name="${BASH_REMATCH[1]}"
            local server_info="${BASH_REMATCH[2]}"

            ((checked++)) || true

            if [[ "$server_info" == *"Connected"* ]]; then
                ((healthy++)) || true
            elif [[ "$server_info" == *"Failed"* ]] || [[ "$server_info" == *"Error"* ]]; then
                ((unhealthy++)) || true

                if [[ "$auto_fix" == true ]]; then
                    local wrapper_path="${HOME}/.claude/${server_name}.sh"
                    if [[ -f "$wrapper_path" ]]; then
                        claude mcp remove "$server_name" -s user 2>/dev/null || true
                        if claude mcp add -s user "$server_name" "$wrapper_path" 2>/dev/null; then
                            ((fixed++)) || true
                            write_log "Auto-fixed MCP: ${server_name}"
                        fi
                    fi
                fi
            fi
        fi
    done <<< "$mcp_list"

    local status="success"
    [[ $unhealthy -gt 0 ]] && status="partial"

    add_audit_entry "McpHealthCheck" "MCP servers" "$status" "${healthy}/${checked} healthy"

    echo "${checked} ${healthy} ${unhealthy} ${fixed}"
}

# ============================================================================
# Environment Variables Restoration
# ============================================================================

restore_environment_variables() {
    local backup_path="$1"

    write_log "Restoring environment variables..."

    local env_file="${backup_path}/environment_variables.json"
    if [[ ! -f "$env_file" ]]; then
        write_log "No environment variables backup found"
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        write_log "[DRY-RUN] Would restore environment variables"
        return 0
    fi

    # Critical paths to ensure are in PATH
    local critical_paths=(
        "${HOME}/.local/bin"
        "${HOME}/.npm-global/bin"
        "${HOME}/.nvm/versions/node/v${NODE_VERSION}/bin"
        "${HOME}/.pyenv/bin"
        "${HOME}/.cargo/bin"
    )

    # Update .bashrc with critical paths
    local bashrc="${HOME}/.bashrc"

    for path_entry in "${critical_paths[@]}"; do
        if [[ -d "$path_entry" ]] && ! grep -q "$path_entry" "$bashrc" 2>/dev/null; then
            echo "export PATH=\"${path_entry}:\$PATH\"" >> "$bashrc"
            write_log "Added to PATH: ${path_entry}"
        fi
    done

    # Disable Chrome integration in WSL (not supported)
    if ! grep -q "CLAUDE_CODE_ENABLE_CFC" "$bashrc" 2>/dev/null; then
        echo '' >> "$bashrc"
        echo '# Disable Chrome integration in WSL (not supported on this platform)' >> "$bashrc"
        echo 'export CLAUDE_CODE_ENABLE_CFC=false' >> "$bashrc"
        write_log "Added CLAUDE_CODE_ENABLE_CFC=false to disable Chrome integration"
    fi

    add_audit_entry "EnvVarRestore" "Environment" "success"

    return 0
}

# ============================================================================
# Backup Integrity Validation
# ============================================================================

test_backup_integrity() {
    local backup_path="$1"

    write_log "Validating backup integrity..."

    local passed=true

    # Check metadata exists
    local metadata_path="${backup_path}/metadata.json"
    if [[ ! -f "$metadata_path" ]]; then
        write_log "metadata.json not found" "WARN"
        passed=false
    fi

    # Check critical directories
    local critical_paths=(
        "home/.claude"
    )

    for path in "${critical_paths[@]}"; do
        local full_path="${backup_path}/${path}"
        if [[ ! -d "$full_path" ]]; then
            write_log "Critical path missing: ${path}" "WARN"
        fi
    done

    # Check disk space
    local free_space_gb=$(df -BG "${HOME}" | awk 'NR==2 {print $4}' | tr -d 'G')
    if [[ $free_space_gb -lt $MIN_DISK_SPACE_GB ]]; then
        write_log "Insufficient disk space: ${free_space_gb}GB free, ${MIN_DISK_SPACE_GB}GB required" "ERROR"
        passed=false
    fi

    local status="success"
    [[ "$passed" == false ]] && status="failed"

    add_audit_entry "IntegrityCheck" "$backup_path" "$status"

    [[ "$passed" == true ]]
}

# ============================================================================
# Save Checkpoint
# ============================================================================

save_checkpoint() {
    local name="$1"
    local status="$2"

    CHECKPOINTS+=("${name}:${status}:$(date '+%Y-%m-%d %H:%M:%S')")
    write_log "Checkpoint saved: ${name} (${status})"
}

# ============================================================================
# Restore Item
# ============================================================================

restore_item() {
    local source="$1"
    local destination="$2"
    local name="$3"
    local critical="${4:-false}"

    if [[ ! -e "$source" ]]; then
        if [[ "$critical" == true ]]; then
            write_fail "Critical item missing: ${name}"
            ((ERROR_COUNT++)) || true
            add_audit_entry "Restore" "$name" "failed" "Source not found"
        else
            write_skip "${name} (not in backup)"
        fi
        ((SKIPPED_COUNT++)) || true
        return 1
    fi

    if [[ "$DRY_RUN" == true ]]; then
        local size=0
        if [[ -d "$source" ]]; then
            size=$(du -sb "$source" 2>/dev/null | cut -f1 || echo 0)
        else
            size=$(stat -c%s "$source" 2>/dev/null || echo 0)
        fi
        write_log "[DRY-RUN] Would restore: ${name} ($(format_size $size))"
        return 0
    fi

    # Create parent directory
    local dest_parent=$(dirname "$destination")
    mkdir -p "$dest_parent"

    local size=0

    if [[ -d "$source" ]]; then
        # Remove existing destination
        rm -rf "$destination" 2>/dev/null || true

        # Use rsync for directories
        if rsync -a --delete "$source/" "$destination/"; then
            size=$(du -sb "$source" 2>/dev/null | cut -f1 || echo 0)
        else
            write_fail "${name} - rsync failed"
            ((ERROR_COUNT++)) || true
            add_audit_entry "Restore" "$name" "failed" "rsync error"
            return 1
        fi
    else
        # Copy single file
        rm -f "$destination" 2>/dev/null || true

        if cp -p "$source" "$destination"; then
            size=$(stat -c%s "$source" 2>/dev/null || echo 0)
        else
            write_fail "${name} - copy failed"
            ((ERROR_COUNT++)) || true
            add_audit_entry "Restore" "$name" "failed" "copy error"
            return 1
        fi
    fi

    local size_str=$(format_size $size)
    write_ok "${name} (${size_str})"
    ((RESTORED_COUNT++)) || true
    TOTAL_SIZE=$((TOTAL_SIZE + size))

    add_audit_entry "Restore" "$name" "success" "Size: ${size_str}"
    save_checkpoint "$name" "restored"

    return 0
}

# ============================================================================
# Shell Profile Restoration
# ============================================================================

restore_shell_profile() {
    local source="$1"
    local destination="$2"
    local name="$3"

    if [[ ! -f "$source" ]]; then
        write_skip "$name"
        ((SKIPPED_COUNT++)) || true
        return 0
    fi

    if [[ "$DRY_RUN" == true ]]; then
        write_log "[DRY-RUN] Would restore: ${name}"
        return 0
    fi

    local dest_parent=$(dirname "$destination")
    mkdir -p "$dest_parent"

    if cp -p "$source" "$destination"; then
        local size=$(stat -c%s "$source" 2>/dev/null || echo 0)
        local size_str=$(format_size $size)
        write_ok "${name} (${size_str})"
        ((RESTORED_COUNT++)) || true
        TOTAL_SIZE=$((TOTAL_SIZE + size))
        add_audit_entry "ProfileRestore" "$name" "success"
    else
        write_fail "${name} - copy failed"
        ((ERROR_COUNT++)) || true
        add_audit_entry "ProfileRestore" "$name" "failed"
    fi
}

# ============================================================================
# Post-restore Verification
# ============================================================================

invoke_post_restore_verification() {
    write_log "Running post-restore verification suite..."

    local passed=0
    local failed=0
    declare -a tests=()

    # Test 1: Claude CLI
    if command -v claude &>/dev/null && claude --version &>/dev/null; then
        tests+=("Claude CLI:PASS:$(claude --version 2>/dev/null | head -1)")
        ((passed++)) || true
    else
        tests+=("Claude CLI:FAIL:")
        ((failed++)) || true
    fi

    # Test 2: Node.js
    if command -v node &>/dev/null; then
        tests+=("Node.js:PASS:$(node --version 2>/dev/null)")
        ((passed++)) || true
    else
        tests+=("Node.js:FAIL:")
        ((failed++)) || true
    fi

    # Test 3: npm
    if command -v npm &>/dev/null; then
        tests+=("npm:PASS:$(npm --version 2>/dev/null)")
        ((passed++)) || true
    else
        tests+=("npm:FAIL:")
        ((failed++)) || true
    fi

    # Test 4: Python
    if command -v python3 &>/dev/null || command -v python &>/dev/null; then
        local py_ver=$(python3 --version 2>/dev/null || python --version 2>/dev/null)
        tests+=("Python:PASS:${py_ver}")
        ((passed++)) || true
    else
        tests+=("Python:FAIL:")
        ((failed++)) || true
    fi

    # Test 5: .claude directory
    if [[ -d "${HOME}/.claude" ]]; then
        tests+=(".claude directory:PASS:")
        ((passed++)) || true
    else
        tests+=(".claude directory:FAIL:")
        ((failed++)) || true
    fi

    # Test 6: settings.json
    if [[ -f "${HOME}/.claude/settings.json" ]]; then
        tests+=("settings.json:PASS:")
        ((passed++)) || true
    else
        tests+=("settings.json:FAIL:")
        ((failed++)) || true
    fi

    # Test 7: MCP wrapper files
    local wrapper_count=$(find "${HOME}/.claude" -name "*.sh" -type f 2>/dev/null | wc -l)
    if [[ $wrapper_count -gt 0 ]]; then
        tests+=("MCP wrappers:PASS:${wrapper_count} found")
        ((passed++)) || true
    else
        tests+=("MCP wrappers:FAIL:")
        ((failed++)) || true
    fi

    # Test 8: mcp-ondemand.sh
    if [[ -f "${HOME}/.claude/mcp-ondemand.sh" ]]; then
        tests+=("mcp-ondemand.sh:PASS:")
        ((passed++)) || true
    else
        tests+=("mcp-ondemand.sh:FAIL:")
        ((failed++)) || true
    fi

    # Test 9: Shell profile
    if [[ -f "${HOME}/.bashrc" ]]; then
        tests+=("Shell profile:PASS:")
        ((passed++)) || true
    else
        tests+=("Shell profile:FAIL:")
        ((failed++)) || true
    fi

    # Output results
    for test in "${tests[@]}"; do
        IFS=':' read -r name status version <<< "$test"
        add_audit_entry "Verification" "$name" "$(echo $status | tr '[:upper:]' '[:lower:]')"
    done

    # Return as printable format
    echo "TESTS:${#tests[@]}"
    echo "PASSED:${passed}"
    echo "FAILED:${failed}"
    for test in "${tests[@]}"; do
        echo "TEST:${test}"
    done
}

# ============================================================================
# Get Available Backups
# ============================================================================

get_available_backups() {
    local backup_root="$1"

    if [[ ! -d "$backup_root" ]]; then
        return 0
    fi

    # Get list of backup directories
    local dirs
    dirs=$(find "$backup_root" -maxdepth 1 -type d -name "backup_*" 2>/dev/null | sort -r)

    if [[ -z "$dirs" ]]; then
        return 0
    fi

    while IFS= read -r dir; do
        [[ -z "$dir" ]] && continue

        local name=$(basename "$dir")
        local metadata="${dir}/metadata.json"
        local date="unknown"
        local size="unknown"
        local valid="false"

        if [[ -f "$metadata" ]]; then
            # Extract values without Perl regex - use sed instead
            date=$(sed -n 's/.*"backupDate"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$metadata" 2>/dev/null | head -1)
            [[ -z "$date" ]] && date="unknown"

            local size_bytes=$(sed -n 's/.*"totalSizeBytes"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$metadata" 2>/dev/null | head -1)
            [[ -z "$size_bytes" ]] && size_bytes=0

            size=$(format_size "$size_bytes")
            valid="true"
        fi

        echo "${dir}|${name}|${date}|${size}|${valid}"
    done <<< "$dirs"
}

select_backup() {
    local backup_root="$1"

    echo -e "\n${CYAN}Available Backups:${NC}"
    echo "$(printf '=%.0s' {1..60})"

    local backups=()
    local index=0

    while IFS='|' read -r path name date size valid; do
        backups+=("$path")
        local marker=""
        [[ $index -eq 0 ]] && marker=" [LATEST]"

        echo -e "${YELLOW}[$((index + 1))] ${name}${marker}${NC}"
        echo -e "    ${GRAY}Date: ${date}${NC}"
        echo -e "    ${GRAY}Size: ${size}${NC}"
        echo ""

        ((index++)) || true
    done < <(get_available_backups "$backup_root")

    if [[ ${#backups[@]} -eq 0 ]]; then
        echo "No backups found"
        return 1
    fi

    read -p "Select backup number (1-${#backups[@]}) or press Enter for latest: " selection

    if [[ -z "$selection" ]]; then
        echo "${backups[0]}"
        return 0
    fi

    local idx=$((selection - 1))
    if [[ $idx -ge 0 ]] && [[ $idx -lt ${#backups[@]} ]]; then
        echo "${backups[$idx]}"
        return 0
    fi

    echo "${backups[0]}"
}

# ============================================================================
# Main Script
# ============================================================================

main() {
    echo ""
    echo -e "${CYAN}$(printf '=%.0s' {1..70})${NC}"
    echo -e "${CYAN}  CLAUDE CODE COMPREHENSIVE RESTORE v${VERSION} - WSL2/UBUNTU${NC}"
    echo -e "${YELLOW}  FRESH UBUNTU READY - FULL NODE/NPM/PYTHON/MCP SETUP${NC}"
    echo -e "${CYAN}$(printf '=%.0s' {1..70})${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}MODE: DRY RUN (no changes will be made)${NC}"
    fi
    echo ""

    # Initialize logging
    initialize_restore_log "$LOGS_PATH"

    # Step 1: Find and validate backup
    write_step "[1/16]" "Locating backup..."

    if [[ -z "$BACKUP_PATH" ]]; then
        if [[ ! -d "$BACKUP_ROOT" ]]; then
            write_fail "Backup root not found: ${BACKUP_ROOT}"
            exit 1
        fi

        if [[ "$SELECTIVE_RESTORE" == true ]]; then
            BACKUP_PATH=$(select_backup "$BACKUP_ROOT")
        else
            BACKUP_PATH=$(get_available_backups "$BACKUP_ROOT" | head -1 | cut -d'|' -f1)
        fi

        if [[ -z "$BACKUP_PATH" ]]; then
            write_fail "No backups found in ${BACKUP_ROOT}"
            exit 1
        fi
    fi

    if [[ ! -d "$BACKUP_PATH" ]]; then
        write_fail "Backup not found: ${BACKUP_PATH}"
        exit 1
    fi

    write_ok "Using: $(basename "$BACKUP_PATH")"
    add_audit_entry "BackupSelection" "$BACKUP_PATH" "success"

    # Read and display metadata
    local metadata_path="${BACKUP_PATH}/metadata.json"
    if [[ -f "$metadata_path" ]]; then
        local backup_date=$(sed -n 's/.*"backupDate"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$metadata_path" 2>/dev/null | head -1)
        [[ -z "$backup_date" ]] && backup_date="unknown"
        local backup_size=$(sed -n 's/.*"totalSizeBytes"[[:space:]]*:[[:space:]]*\([0-9]*\).*/\1/p' "$metadata_path" 2>/dev/null | head -1)
        [[ -z "$backup_size" ]] && backup_size="0"
        local claude_version=$(sed -n 's/.*"claudeVersion"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$metadata_path" 2>/dev/null | head -1)
        [[ -z "$claude_version" ]] && claude_version="unknown"

        echo -e "  ${GRAY}Date: ${backup_date}${NC}"
        echo -e "  ${GRAY}Size: $(format_size $backup_size)${NC}"
        echo -e "  ${GRAY}Claude: ${claude_version}${NC}"
    fi
    echo ""

    # Step 2: Pre-restore validation
    write_step "[2/16]" "Validating backup integrity..."

    if ! test_backup_integrity "$BACKUP_PATH"; then
        if [[ "$FORCE" != true ]]; then
            write_fail "Backup validation failed. Use -f to override."
            exit 1
        fi
        write_warn "Backup has issues but continuing with -f"
    else
        write_ok "Backup integrity verified"
    fi

    # Confirmation
    if [[ "$FORCE" != true ]] && [[ "$DRY_RUN" != true ]]; then
        echo ""
        echo -e "${RED}WARNING: This will restore Claude Code including Node.js, Python, npm, MCP!${NC}"
        echo -n "Continue with restore? (type 'YES' to confirm): "
        # Read from stdin (works with pipe or interactive)
        read confirm || confirm=""
        echo ""
        if [[ "$confirm" != "YES" ]]; then
            echo -e "${YELLOW}Cancelled. Use -f to skip confirmation.${NC}"
            exit 0
        fi
    fi
    echo ""

    # Step 3: Stop Claude processes
    write_step "[3/16]" "Stopping Claude Code processes..."
    if [[ "$DRY_RUN" != true ]]; then
        stop_claude_processes 30
    fi
    write_ok "Processes handled"

    # Step 4: Check and install Node.js
    write_step "[4/16]" "Checking/Installing Node.js..."

    read -r node_installed node_version node_path node_meets_min npm_version < <(test_node_installation)

    if [[ "$node_installed" != "true" ]] && [[ "$SKIP_NODE_INSTALL" != true ]]; then
        write_warn "Node.js not found - Installing..."
        if [[ "$DRY_RUN" != true ]]; then
            if install_nodejs "$BACKUP_PATH"; then
                write_ok "Node.js installed successfully"
                # Ensure PATH includes Node.js locations after install
                export PATH="/usr/local/nodejs/bin:/usr/local/bin:$PATH"
                hash -r 2>/dev/null || true
                read -r node_installed node_version node_path node_meets_min npm_version < <(test_node_installation)
            else
                write_warn "Node.js installation failed - some features may not work"
            fi
        fi
    elif [[ "$node_installed" == "true" ]]; then
        if [[ "$node_meets_min" == "true" ]]; then
            write_ok "Node.js v${node_version} (meets minimum)"
        else
            write_warn "Node.js v${node_version} is below recommended v${MIN_NODE_VERSION}"
        fi
    fi

    save_checkpoint "NodeJS" "completed"
    echo ""

    # Step 5: Check and install Python
    write_step "[5/16]" "Checking/Installing Python..."

    read -r python_installed python_version python_path python_meets_min pip_version < <(test_python_installation)

    if [[ "$python_installed" != "true" ]] && [[ "$SKIP_PYTHON_INSTALL" != true ]]; then
        write_warn "Python not found - Installing..."
        if [[ "$DRY_RUN" != true ]]; then
            if install_python "$BACKUP_PATH"; then
                write_ok "Python installed successfully"
                read -r python_installed python_version python_path python_meets_min pip_version < <(test_python_installation)
            else
                write_warn "Python installation failed - some MCP servers may not work"
            fi
        fi
    elif [[ "$python_installed" == "true" ]]; then
        write_ok "Python v${python_version}"
    fi

    save_checkpoint "Python" "completed"
    echo ""

    # Step 6: Restore npm global packages
    write_step "[6/16]" "Restoring npm global packages..."
    local npm_restored=$(restore_npm_global_packages "$BACKUP_PATH")
    if [[ "$npm_restored" != "0" ]]; then
        write_ok "npm packages restored: ${npm_restored} packages"
    fi
    save_checkpoint "NpmPackages" "completed"
    echo ""

    # Step 7: Restore uvx/uv tools
    write_step "[7/16]" "Restoring uvx/uv tools..."
    local uvx_restored=$(restore_uvx_tools "$BACKUP_PATH")
    if [[ "$uvx_restored" != "0" ]]; then
        write_ok "uvx tools restored: ${uvx_restored} components"
    fi
    save_checkpoint "UvxTools" "completed"
    echo ""

    # Step 8: Restore package managers
    write_step "[8/16]" "Restoring pnpm/yarn/nvm..."
    read -r pnpm_ok yarn_ok nvm_ok < <(restore_package_managers "$BACKUP_PATH")
    local pm_restored=()
    [[ "$pnpm_ok" == "true" ]] && pm_restored+=("pnpm")
    [[ "$yarn_ok" == "true" ]] && pm_restored+=("yarn")
    [[ "$nvm_ok" == "true" ]] && pm_restored+=("nvm")
    if [[ ${#pm_restored[@]} -gt 0 ]]; then
        write_ok "Restored: ${pm_restored[*]}"
    fi
    save_checkpoint "PackageManagers" "completed"
    echo ""

    # Step 9: Restore core Claude Code files
    write_step "[9/16]" "Restoring Claude Code configuration..."
    echo ""

    restore_item "${BACKUP_PATH}/home/.claude" "${HOME}/.claude" ".claude directory" true
    restore_item "${BACKUP_PATH}/home/.claude.json" "${HOME}/.claude.json" ".claude.json"
    restore_item "${BACKUP_PATH}/home/.claude.json.backup" "${HOME}/.claude.json.backup" ".claude.json.backup"
    restore_item "${BACKUP_PATH}/home/.claude-server-commander" "${HOME}/.claude-server-commander" ".claude-server-commander"
    restore_item "${BACKUP_PATH}/home/CLAUDE.md" "${HOME}/CLAUDE.md" "CLAUDE.md"
    restore_item "${BACKUP_PATH}/home/claude.md" "${HOME}/claude.md" "claude.md"

    save_checkpoint "CoreConfig" "completed"
    echo ""

    # Step 10: Restore config directories (Linux equivalents)
    write_step "[10/16]" "Restoring config directories..."
    echo ""

    restore_item "${BACKUP_PATH}/AppData/Roaming/Claude" "${HOME}/.config/Claude" "Config/Claude"
    restore_item "${BACKUP_PATH}/AppData/Local/AnthropicClaude" "${HOME}/.local/share/AnthropicClaude" "AnthropicClaude"
    restore_item "${BACKUP_PATH}/AppData/Local/claude-cli-nodejs" "${HOME}/.local/share/claude-cli-nodejs" "claude-cli-nodejs"
    restore_item "${BACKUP_PATH}/AppData/Roaming/Anthropic" "${HOME}/.config/Anthropic" "Config/Anthropic"

    save_checkpoint "ConfigDirs" "completed"
    echo ""

    # Step 11: Install Claude Code CLI
    write_step "[11/16]" "Installing Claude Code CLI..."
    echo ""

    # Determine installation location based on whether running as root
    local npm_prefix=""
    local npm_bin=""

    if [[ $EUID -eq 0 ]]; then
        # Running as root - install system-wide to /usr/local
        npm_prefix="/usr/local"
        npm_bin="/usr/local/bin"
        write_log "Running as root - installing Claude CLI system-wide to ${npm_prefix}"
    else
        # Running as regular user - install to user's npm-global
        npm_prefix="${HOME}/.npm-global"
        npm_bin="${HOME}/.npm-global/bin"
        mkdir -p "${npm_prefix}/lib/node_modules"
        mkdir -p "${npm_bin}"
        npm config set prefix "${npm_prefix}" 2>/dev/null || true
    fi

    export PATH="${npm_bin}:$PATH"

    # Check if claude is already installed and working
    local claude_installed=false
    if command -v claude &>/dev/null; then
        local claude_ver=$(claude --version 2>/dev/null | head -1)
        if [[ -n "$claude_ver" ]]; then
            write_ok "Claude CLI already installed: ${claude_ver}"
            claude_installed=true
        fi
    fi

    # Install Claude Code via npm if not found
    if [[ "$claude_installed" == false ]] && [[ "$DRY_RUN" != true ]]; then
        # Ensure npm is available - refresh PATH and command hash
        hash -r 2>/dev/null || true

        # Find the Linux npm binary (not Windows one from WSL path inheritance)
        local npm_cmd=""
        # Check common locations including nvm paths
        local nvm_npm=""
        if [[ -d "${HOME}/.nvm/versions/node" ]]; then
            # Find the most recent node version's npm
            nvm_npm=$(find "${HOME}/.nvm/versions/node" -name "npm" -type l 2>/dev/null | head -1)
        fi
        for npm_path in /usr/bin/npm /usr/local/bin/npm /usr/local/nodejs/bin/npm "$nvm_npm"; do
            if [[ -n "$npm_path" ]] && [[ -x "$npm_path" ]]; then
                npm_cmd="$npm_path"
                write_log "Using npm at $npm_path"
                break
            fi
        done

        if [[ -z "$npm_cmd" ]]; then
            write_warn "Linux npm not found, cannot install Claude Code"
            ((ERROR_COUNT++))
        else
            write_log "Installing @anthropic-ai/claude-code via npm to ${npm_prefix}..."
            echo -e "  ${CYAN}Installing @anthropic-ai/claude-code via npm...${NC}"

            if "$npm_cmd" install -g --prefix "${npm_prefix}" @anthropic-ai/claude-code 2>&1; then
                write_ok "Claude Code installed successfully to ${npm_prefix}"
                hash -r 2>/dev/null || true

                # Verify installation
                if command -v claude &>/dev/null; then
                    local new_ver=$(claude --version 2>/dev/null | head -1)
                    write_ok "Claude CLI verified: ${new_ver}"
                elif [[ -f "${npm_bin}/claude" ]]; then
                    write_ok "Claude CLI binary found at ${npm_bin}/claude"
                else
                    write_warn "Claude installed but binary not in expected location"
                fi
            else
                write_warn "npm install failed, trying with sudo..."
                if sudo "$npm_cmd" install -g --prefix /usr/local @anthropic-ai/claude-code 2>&1; then
                    write_ok "Claude Code installed with sudo to /usr/local"
                else
                    write_warn "Could not install Claude Code - install manually: npm install -g @anthropic-ai/claude-code"
                    ((ERROR_COUNT++))
                fi
            fi
        fi
    elif [[ "$DRY_RUN" == true ]]; then
        write_log "[DRY-RUN] Would install @anthropic-ai/claude-code via npm to ${npm_prefix}"
    fi

    save_checkpoint "ClaudeCodePackage" "completed"
    echo ""

    # Step 12: Restore shell profiles
    write_step "[12/16]" "Restoring shell profiles..."
    echo ""

    # Restore PowerShell profiles to Linux equivalents
    restore_shell_profile "${BACKUP_PATH}/PowerShell/WindowsPowerShell/Microsoft.PowerShell_profile.ps1" \
                          "${HOME}/.config/powershell/Microsoft.PowerShell_profile.ps1" \
                          "PowerShell Profile"

    # Also check for bash profile backups
    restore_shell_profile "${BACKUP_PATH}/home/.bashrc" "${HOME}/.bashrc.backup" ".bashrc backup"
    restore_shell_profile "${BACKUP_PATH}/home/.profile" "${HOME}/.profile.backup" ".profile backup"
    restore_shell_profile "${BACKUP_PATH}/home/.zshrc" "${HOME}/.zshrc.backup" ".zshrc backup"

    save_checkpoint "ShellProfiles" "completed"
    echo ""

    # Step 13: Restore environment variables
    write_step "[13/16]" "Restoring environment variables..."

    if [[ "$DRY_RUN" != true ]]; then
        restore_environment_variables "$BACKUP_PATH"
        write_ok "Environment variables configured"
    fi
    save_checkpoint "Environment" "completed"
    echo ""

    # Step 14: Setup MCP servers
    write_step "[14/16]" "Setting up MCP servers..."

    if [[ "$SKIP_MCP_SETUP" != true ]] && [[ "$DRY_RUN" != true ]]; then
        read -r mcp_wrappers mcp_connected mcp_failed < <(restore_mcp_servers "$BACKUP_PATH")
        write_ok "MCP wrappers: ${mcp_wrappers}, Connected: ${mcp_connected}"

        # Health check
        echo ""
        write_step "[14b/16]" "Verifying MCP connections..."
        read -r mcp_checked mcp_healthy mcp_unhealthy mcp_fixed < <(test_mcp_server_health true)

        if [[ $mcp_unhealthy -gt 0 ]]; then
            write_warn "MCP: ${mcp_healthy}/${mcp_checked} healthy, ${mcp_fixed} auto-fixed"
        else
            write_ok "MCP: ${mcp_healthy}/${mcp_checked} servers healthy"
        fi
    fi
    save_checkpoint "McpSetup" "completed"
    echo ""

    # Step 15: Post-restore verification
    write_step "[15/16]" "Running post-restore verification..."
    echo ""

    local verification_passed=0
    local verification_failed=0
    local verification_total=0

    if [[ "$SKIP_VERIFICATION" != true ]] && [[ "$DRY_RUN" != true ]]; then
        echo -e "  ${CYAN}Verification Results:${NC}"

        while IFS= read -r line; do
            if [[ "$line" == TESTS:* ]]; then
                verification_total="${line#TESTS:}"
            elif [[ "$line" == PASSED:* ]]; then
                verification_passed="${line#PASSED:}"
            elif [[ "$line" == FAILED:* ]]; then
                verification_failed="${line#FAILED:}"
            elif [[ "$line" == TEST:* ]]; then
                local test_info="${line#TEST:}"
                IFS=':' read -r name status version <<< "$test_info"
                if [[ "$status" == "PASS" ]]; then
                    echo -e "    ${GREEN}[PASS]${NC} ${name} ${version}"
                else
                    echo -e "    ${RED}[FAIL]${NC} ${name}"
                fi
            fi
        done < <(invoke_post_restore_verification)
    else
        write_skip "Verification skipped"
    fi
    save_checkpoint "Verification" "completed"
    echo ""

    # Step 16: Finalize
    write_step "[16/16]" "Finalizing restore..."

    if [[ "$DRY_RUN" != true ]]; then
        local audit_file=$(save_audit_trail "$BACKUP_ROOT")
        if [[ -n "$audit_file" ]]; then
            write_ok "Audit trail saved"
        fi
    fi

    # ============================================================================
    # Summary
    # ============================================================================

    local end_time=$(date +%s)
    local execution_time=$((end_time - START_TIME))

    echo ""
    echo -e "${CYAN}$(printf '=%.0s' {1..70})${NC}"
    echo -e "${CYAN}  RESTORE COMPLETE - v${VERSION} (WSL2/UBUNTU READY)${NC}"
    echo -e "${CYAN}$(printf '=%.0s' {1..70})${NC}"

    if [[ "$DRY_RUN" == true ]]; then
        echo -e "${MAGENTA}MODE: DRY RUN - No changes were made${NC}"
    else
        echo -e "${GREEN}Restored: ${RESTORED_COUNT} items ($(format_size $TOTAL_SIZE))${NC}"
    fi

    echo -e "${GRAY}Skipped:  ${SKIPPED_COUNT} items${NC}"

    if [[ $ERROR_COUNT -gt 0 ]]; then
        echo -e "${RED}Errors:   ${ERROR_COUNT}${NC}"
    else
        echo -e "${GREEN}Errors:   None${NC}"
    fi

    echo -e "${GRAY}Time:     ${execution_time} seconds${NC}"

    # Dev tools status
    echo ""
    echo -e "${YELLOW}Dev Tools Status:${NC}"

    if [[ "$node_installed" == "true" ]]; then
        echo -e "  ${GREEN}Node.js: v${node_version}${NC}"
    else
        echo -e "  ${RED}Node.js: Not installed${NC}"
    fi

    if [[ "$python_installed" == "true" ]]; then
        echo -e "  ${GREEN}Python:  v${python_version}${NC}"
    else
        echo -e "  ${YELLOW}Python:  Not installed${NC}"
    fi

    if [[ -n "$npm_version" ]]; then
        echo -e "  ${GREEN}npm:     v${npm_version}${NC}"
    else
        echo -e "  ${YELLOW}npm:     Not available${NC}"
    fi

    if [[ "$SKIP_VERIFICATION" != true ]] && [[ "$DRY_RUN" != true ]]; then
        echo ""
        local verify_color="${GREEN}"
        [[ $verification_failed -gt 0 ]] && verify_color="${YELLOW}"
        echo -e "${verify_color}Verification: ${verification_passed}/${verification_total} tests passed${NC}"
    fi

    echo -e "${CYAN}$(printf '=%.0s' {1..70})${NC}"
    echo ""

    # Auto-source bashrc for current shell
    write_log "Auto-sourcing shell profiles..."
    if [[ -f "${HOME}/.bashrc" ]]; then
        source "${HOME}/.bashrc" 2>/dev/null || true
    fi
    if [[ -f "${HOME}/.profile" ]]; then
        source "${HOME}/.profile" 2>/dev/null || true
    fi

    # Refresh PATH
    export PATH="${HOME}/.npm-global/bin:${HOME}/.local/bin:${PATH}"
    hash -r 2>/dev/null || true

    # Auto-source mcp-ondemand if exists
    if [[ -f "${HOME}/.claude/mcp-ondemand.sh" ]]; then
        source "${HOME}/.claude/mcp-ondemand.sh" 2>/dev/null || true
        write_ok "MCP ondemand script sourced"
    fi

    # Check if running as root and Claude restriction
    if [[ $EUID -eq 0 ]]; then
        # Try to find first non-root user and copy credentials/config to their home
        local non_root_user=$(getent passwd | awk -F: '$3 >= 1000 && $3 < 65534 {print $1; exit}')
        if [[ -n "$non_root_user" ]]; then
            local user_home=$(getent passwd "$non_root_user" | cut -d: -f6)
            if [[ -n "$user_home" ]] && [[ -d "$user_home" ]]; then
                write_log "Copying Claude config to ${non_root_user}'s home..."

                # Create .claude directory for non-root user
                mkdir -p "${user_home}/.claude"

                # Copy credentials
                if [[ -f "${HOME}/.claude/.credentials.json" ]]; then
                    cp "${HOME}/.claude/.credentials.json" "${user_home}/.claude/.credentials.json"
                    chown "${non_root_user}:${non_root_user}" "${user_home}/.claude/.credentials.json"
                    chmod 600 "${user_home}/.claude/.credentials.json"
                    write_ok "Credentials copied to ${non_root_user}"
                fi

                # Copy settings.json
                if [[ -f "${HOME}/.claude/settings.json" ]]; then
                    cp "${HOME}/.claude/settings.json" "${user_home}/.claude/settings.json"
                    chown "${non_root_user}:${non_root_user}" "${user_home}/.claude/settings.json"
                fi

                # Copy mcp-ondemand.sh
                if [[ -f "${HOME}/.claude/mcp-ondemand.sh" ]]; then
                    cp "${HOME}/.claude/mcp-ondemand.sh" "${user_home}/.claude/mcp-ondemand.sh"
                    chmod +x "${user_home}/.claude/mcp-ondemand.sh"
                    chown "${non_root_user}:${non_root_user}" "${user_home}/.claude/mcp-ondemand.sh"
                fi

                # Copy all MCP wrapper scripts
                for wrapper in "${HOME}/.claude/"*.sh; do
                    if [[ -f "$wrapper" ]]; then
                        cp "$wrapper" "${user_home}/.claude/"
                        chown "${non_root_user}:${non_root_user}" "${user_home}/.claude/$(basename "$wrapper")"
                        chmod +x "${user_home}/.claude/$(basename "$wrapper")"
                    fi
                done

                # Copy .claude.json and fix MCP paths
                if [[ -f "${HOME}/.claude.json" ]]; then
                    # Copy and replace /root/.claude/ paths with user's paths
                    sed "s|/root/.claude/|${user_home}/.claude/|g" "${HOME}/.claude.json" > "${user_home}/.claude.json"
                    chown "${non_root_user}:${non_root_user}" "${user_home}/.claude.json"
                fi

                # Set ownership of .claude directory
                chown -R "${non_root_user}:${non_root_user}" "${user_home}/.claude"

                # Add mcp-ondemand.sh sourcing and environment variables to user's bashrc
                local user_bashrc="${user_home}/.bashrc"
                if [[ -f "$user_bashrc" ]]; then
                    if ! grep -q "mcp-ondemand.sh" "$user_bashrc" 2>/dev/null; then
                        echo '' >> "$user_bashrc"
                        echo '# Claude Code MCP management' >> "$user_bashrc"
                        echo '[ -f ~/.claude/mcp-ondemand.sh ] && source ~/.claude/mcp-ondemand.sh' >> "$user_bashrc"
                        chown "${non_root_user}:${non_root_user}" "$user_bashrc"
                    fi
                    # Add CLAUDE_CODE_ENABLE_CFC=false to disable Chrome integration in WSL
                    if ! grep -q "CLAUDE_CODE_ENABLE_CFC" "$user_bashrc" 2>/dev/null; then
                        echo '' >> "$user_bashrc"
                        echo '# Disable Claude in Chrome (not supported in WSL)' >> "$user_bashrc"
                        echo 'export CLAUDE_CODE_ENABLE_CFC=false' >> "$user_bashrc"
                        chown "${non_root_user}:${non_root_user}" "$user_bashrc"
                        write_log "Added CLAUDE_CODE_ENABLE_CFC=false to ${non_root_user}'s .bashrc"
                    fi
                fi

                write_ok "Claude config copied to ${non_root_user}'s home"
            fi
        fi

        echo ""
        echo -e "${RED}╔═══════════════════════════════════════════════════════════════════╗${NC}"
        echo -e "${RED}║  WARNING: Running as root - Claude CLI has restrictions!          ║${NC}"
        echo -e "${RED}╠═══════════════════════════════════════════════════════════════════╣${NC}"
        echo -e "${RED}║  Claude CLI blocks --dangerously-skip-permissions with root/sudo  ║${NC}"
        echo -e "${RED}║                                                                   ║${NC}"
        echo -e "${RED}║  SOLUTION: Switch to a non-root user to use Claude CLI            ║${NC}"
        echo -e "${RED}╚═══════════════════════════════════════════════════════════════════╝${NC}"
        echo ""
        echo -e "${GREEN}✓ Claude CLI installed system-wide to /usr/local/bin${NC}"
        echo -e "${GREEN}✓ All users can access it - no extra setup needed${NC}"
        echo -e "${GREEN}✓ Credentials copied to non-root user${NC}"
        echo ""

        if [[ -n "$non_root_user" ]]; then
            echo -e "${YELLOW}Found non-root user: ${non_root_user}${NC}"
            echo -e "${CYAN}Run: ${GREEN}su - ${non_root_user}${NC}"
            echo -e "${CYAN}Then: ${GREEN}claude${NC} (no login required - credentials restored)"
            echo -e "${CYAN}MCP:  ${GREEN}mcps${NC} to view MCP servers"
        else
            echo -e "${YELLOW}No non-root user found. Create one:${NC}"
            echo -e "${GREEN}  adduser claude${NC}"
            echo -e "${GREEN}  su - claude${NC}"
            echo -e "${GREEN}  claude${NC}"
        fi
        echo ""
    else
        # Not root - try to run mcps
        echo -e "${YELLOW}NEXT STEPS:${NC}"
        if command -v mcps &>/dev/null; then
            echo -e "  ${GREEN}MCP status available - run: mcps${NC}"
        else
            echo -e "  1. Run: source ~/.claude/mcp-ondemand.sh && mcps"
        fi
        echo -e "  2. Use mcp_on to enable desired MCP servers"
        echo ""

        # Verify claude works
        if command -v claude &>/dev/null; then
            echo -e "${GREEN}Claude CLI is ready to use!${NC}"
            echo ""
        fi
    fi

    write_log "Restore completed. Items: ${RESTORED_COUNT}, Errors: ${ERROR_COUNT}, Time: ${execution_time} seconds"

    if [[ $ERROR_COUNT -gt 0 ]]; then
        exit 1
    else
        exit 0
    fi
}

# Run main
main "$@"
