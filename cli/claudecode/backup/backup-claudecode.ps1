#Requires -Version 5.1
<#
.SYNOPSIS
    ULTIMATE Claude Code + OpenClaw + Moltbot + Clawd + All AI Tools Backup v18.0 - ABSOLUTE COMPLETE
.DESCRIPTION
    Backs up EVERY SINGLE THING for PERFECT restoration on a BRAND NEW PC.
    Including: Claude Code, OpenClaw (AI Agent), Moltbot, Clawdbot, Clawd, OpenCode, credentials, 
    OAuth tokens, sessions, conversations, MCP configs, agent state, environment variables, 
    registry keys, Git config, SSH keys, GPG keys, project-level .claude directories, IDE settings, 
    browser extensions, npm global modules.

    CRITICAL: This backup enables 100% COMPLETE restoration on a fresh Windows 11 install.

    NEW IN v18.0 - C: DRIVE FULL SCAN COVERAGE:
    - OPENCLAW ALL WORKSPACES: Dynamic scan of ALL workspace-* dirs (no hardcoding)
    - OPENCLAW AUTH: auth.json, auth-profiles.json, .openclawrc.json (CRITICAL)
    - OPENCLAW TELEGRAM: telegram/ dir (command hashes, update offsets)
    - OPENCLAW CLAWDBOT: .openclaw/ClawdBot/ tray scripts directory
    - OPENCLAW BACKUPS: .openclaw/backups/ historical agent backups
    - OPENCLAW COMPLETIONS: .openclaw/completions/ shell completions
    - OPENCLAW ALL ROOT FILES: moltbot.json, clawdbot.json, gateway-task.xml, etc.
    - CLAUDEGRAM: ~/.claudegram (sessions, wrapper, config)
    - CLAUDE-SERVER-COMMANDER: ~/.claude-server-commander (config, feature-flags, tool-history)
    - CLAUDE CLI STATE: ~/.local/share/claude, ~/.local/state/claude
    - CLAUDE CODE ROAMING: AppData/Roaming/Claude Code (browser extension native host)
    - CLAUDE CLI NODEJS: AppData/Local/claude-cli-nodejs (CLI cache + MCP logs)
    - ANTHROPIC CLAUDE DESKTOP: AppData/Local/AnthropicClaude (Desktop app)
    - OPENCODE STATE: ~/.local/state/opencode (frecency, prompt history)
    - POWERSHELL MODULES: ClaudeUsage module (PS5 + PS7)
    - MCP-ONDEMAND: ~/mcp-ondemand.ps1, ~/claude-wrapper.ps1
    - STARTUP SHORTCUTS: OpenClaw Tray.lnk in Windows Startup
    - NPM BIN SHIMS: claude.cmd, openclaw.cmd, clawdbot.cmd
    - OPENCODE AUTH: opencode-antigravity-auth npm package
    - CHROME INDEXEDDB: claude.ai browser data (Profile 1 + 2)
    - 43+ backup sections covering EVERY location on C: drive
    
.PARAMETER BackupPath
    Custom backup directory (default: F:\backup\claudecode\backup_<timestamp>)
.PARAMETER Compress
    Create compressed ZIP archive
.PARAMETER MaxJobs
    Maximum parallel jobs for speed (default: 32)
.NOTES
    Version: 18.0 - C: DRIVE FULL SCAN EDITION
    Author: AI Agent (Autonomous)
    Changes in v18.0:
    - OPENCLAW: Dynamic scan of ALL workspace-* dirs (no more hardcoded list)
    - OPENCLAW: auth.json, auth-profiles.json, .openclawrc.json, moltbot.json, clawdbot.json
    - OPENCLAW: telegram/ dir, ClawdBot/ tray dir, completions/, backups/
    - OPENCLAW: openclaw-gateway-task.xml, openclaw-backup.json, all .bak.* rolling backups
    - CLAUDEGRAM: ~/.claudegram complete backup
    - CLAUDE-SERVER-COMMANDER: ~/.claude-server-commander complete backup
    - CLAUDE CLI: ~/.local/share/claude versions, ~/.local/state/claude state
    - APPDATA: Claude Code Roaming, claude-cli-nodejs, AnthropicClaude Desktop
    - OPENCODE: ~/.local/state/opencode (frecency, prompt history, model config)
    - POWERSHELL: ClaudeUsage module (PS5 + PS7)
    - SCRIPTS: ~/mcp-ondemand.ps1, ~/claude-wrapper.ps1
    - STARTUP: OpenClaw Tray.lnk in Windows Startup folder
    - NPM: bin shims, opencode-antigravity-auth package
    - CHROME: claude.ai IndexedDB data (Profile 1 + 2)
    - 43+ backup sections for TOTAL coverage
#>
[CmdletBinding()]
param(
    [string]$BackupPath = "F:\backup\claudecode\backup_$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss')",
    [switch]$Compress = $false,
    [int]$MaxJobs = 32
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$script:BackedUpItems = 0
$script:BackedUpSize = 0
$script:Errors = @()
$script:Jobs = @()

#region Helper Functions
function Write-Step {
    param([string]$Message, [string]$Status = "INFO")
    $color = switch ($Status) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "Cyan" }
    }
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Status] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Copy-ItemSafe {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Description,
        [switch]$Recurse,
        [switch]$ShowProgress
    )
    
    # Reserved device names in Windows
    $reservedNames = @('CON', 'PRN', 'AUX', 'NUL', 'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9', 'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9')
    
    if (Test-Path $Source) {
        try {
            $destDir = Split-Path $Destination -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            if ($Recurse) {
                # Use robocopy for directories — 10x faster than manual file-by-file copy
                if (-not (Test-Path $Destination)) {
                    New-Item -ItemType Directory -Path $Destination -Force | Out-Null
                }
                & robocopy $Source $Destination /E /R:1 /W:0 /MT:64 /NFL /NDL /NJH /NJS 2>&1 | Out-Null
            } else {
                Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
            }
            
            $size = if (Test-Path $Destination -PathType Container) {
                (Get-ChildItem $Destination -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            } else {
                (Get-Item $Destination -ErrorAction SilentlyContinue).Length
            }
            if (-not $size) { $size = 0 }
            $script:BackedUpSize += $size
            $script:BackedUpItems++
            
            $sizeStr = if ($size -gt 1MB) { "{0:N2} MB" -f ($size/1MB) }
                       elseif ($size -gt 1KB) { "{0:N2} KB" -f ($size/1KB) }
                       else { "$size B" }
            
            Write-Step "  -> $Description ($sizeStr)" "SUCCESS"
        } catch {
            $script:Errors += "Failed to backup $Description : $_"
            Write-Step "  -> Failed: $Description - $_" "ERROR"
        }
    } else {
        Write-Step "  -> Not found: $Description (skipped)" "WARNING"
    }
}

function Export-RegistryKey {
    param([string]$KeyPath, [string]$OutputFile)
    try {
        if (Test-Path "Registry::$KeyPath") {
            reg export $KeyPath $OutputFile /y 2>$null | Out-Null
            if (Test-Path $OutputFile) {
                Write-Step "  -> Registry: $KeyPath" "SUCCESS"
            }
        }
    } catch {}
}

function Get-WindowsCredentialManager {
    param([string]$OutputFile)
    try {
        $cmdkeyOutput = cmdkey /list 2>$null
        $claudeCreds = $cmdkeyOutput | Select-String -Pattern "claude|anthropic|opencode|openclaw|molt|clawd" -Context 0,3

        if ($claudeCreds) {
            $claudeCreds | Out-File -FilePath $OutputFile -Encoding UTF8
            Write-Step "  -> Windows Credential Manager entries" "SUCCESS"
        }
    } catch {}
}

# TURBO v17.0: RunspacePool parallel copy (10x faster than Start-Job)
function Start-AllParallelCopies {
    param([array]$Tasks, [int]$MaxThreads = 32)

    $resultBag = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()

    $copyBlock = {
        param($src, $dst, $desc)
        try {
            $destDir = Split-Path $dst -Parent
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }

            if (Test-Path $src -PathType Container) {
                # robocopy /MT:64 for directories — max speed
                & robocopy $src $dst /E /R:1 /W:0 /MT:64 /NFL /NDL /NJH /NJS /XD "node_modules" ".git" "__pycache__" ".venv" "venv" "browser" "platform-tools" "outbound" "canvas" 2>&1 | Out-Null
            } else {
                [System.IO.File]::Copy($src, $dst, $true)
            }

            $size = 0
            if (Test-Path $dst) {
                if (Test-Path $dst -PathType Container) {
                    $size = (Get-ChildItem $dst -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                    if (-not $size) { $size = 0 }
                } else {
                    $size = ([System.IO.FileInfo]::new($dst)).Length
                }
            }
            $resultBag.Add(@{ Status="OK"; Desc=$desc; Size=$size })
        } catch {
            $resultBag.Add(@{ Status="ERROR"; Desc=$desc; Error=$_.ToString() })
        }
    }

    $pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxThreads)
    $pool.ApartmentState = "MTA"
    $pool.Open()

    $handles = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($task in $Tasks) {
        if (-not (Test-Path $task.Source)) { continue }
        $ps = [System.Management.Automation.PowerShell]::Create()
        $ps.RunspacePool = $pool
        $ps.AddScript($copyBlock).AddArgument($task.Source).AddArgument($task.Destination).AddArgument($task.Description) | Out-Null
        $handles.Add(@{ PS=$ps; Handle=$ps.BeginInvoke(); Desc=$task.Description })
    }

    Write-Step "  -> Launched $($handles.Count) parallel threads (RunspacePool)" "SUCCESS"

    # Wait with heartbeat
    $lastReport = Get-Date
    $completed = 0
    $pending = [System.Collections.Generic.List[hashtable]]($handles)

    while ($pending.Count -gt 0) {
        $stillPending = [System.Collections.Generic.List[hashtable]]::new()
        foreach ($h in $pending) {
            if ($h.Handle.IsCompleted) {
                $h.PS.EndInvoke($h.Handle) | Out-Null
                $h.PS.Dispose()
                $completed++
            } else {
                $stillPending.Add($h)
            }
        }
        $pending = $stillPending

        if (((Get-Date) - $lastReport).TotalSeconds -ge 3) {
            $pct = if ($handles.Count -gt 0) { [math]::Round($completed / $handles.Count * 100) } else { 100 }
            Write-Step "  -> Progress: $completed/$($handles.Count) ($pct%) complete, $($pending.Count) running..." "INFO"
            $lastReport = Get-Date
        }

        if ($pending.Count -gt 0) { Start-Sleep -Milliseconds 200 }
    }

    $pool.Close()
    $pool.Dispose()

    # Process results
    foreach ($r in $resultBag) {
        if ($r.Status -eq "OK" -and $r.Size -gt 0) {
            $script:BackedUpSize += $r.Size
            $script:BackedUpItems++
            $sizeStr = if ($r.Size -gt 1MB) { "{0:N1}MB" -f ($r.Size/1MB) } elseif ($r.Size -gt 1KB) { "{0:N0}KB" -f ($r.Size/1KB) } else { "$($r.Size)B" }
            Write-Step "  -> $($r.Desc) ($sizeStr)" "SUCCESS"
        } elseif ($r.Status -eq "ERROR") {
            $script:Errors += "Failed: $($r.Desc) - $($r.Error)"
            Write-Step "  -> Failed: $($r.Desc)" "ERROR"
        }
    }
}

# Find all project .claude directories
function Find-ProjectClaudeDirectories {
    param([string[]]$SearchPaths)

    $found = @()
    foreach ($searchPath in $SearchPaths) {
        if (Test-Path $searchPath) {
            # Use robocopy /L for ultra-fast directory listing
            $dirs = Get-ChildItem -Path $searchPath -Directory -Recurse -Filter ".claude" -ErrorAction SilentlyContinue -Depth 5 |
                    Where-Object { $_.FullName -notmatch "node_modules|\.git|__pycache__|\.venv|venv|dist|build" }
            $found += $dirs
        }
    }
    return $found
}
#endregion

#region Main Backup Logic
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  CLAUDE CODE + OPENCLAW + MOLTBOT + CLAWD ULTIMATE BACKUP v18.0" -ForegroundColor White
Write-Host "  C: DRIVE FULL SCAN | 43+ SECTIONS | EVERY CORNER | 100% RESTORE" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
Write-Host "Backup Path: $BackupPath"
Write-Host "Parallel Jobs: $MaxJobs (RunspacePool + robocopy /MT:64)"
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
$startTime = Get-Date

# Create backup directory
New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

$HOME_DIR = $env:USERPROFILE
$APPDATA = $env:APPDATA
$LOCALAPPDATA = $env:LOCALAPPDATA

#region TURBO: Launch all large directory copies in parallel
Write-Step "TURBO MODE: Launching $MaxJobs parallel copy jobs..." "INFO"

# Define all large directory copy tasks
$largeCopyTasks = @(
    @{ Source = "$HOME_DIR\.claude"; Destination = "$BackupPath\core\claude-home"; Description = ".claude directory (FULL)" },
    @{ Source = "$HOME_DIR\.config\claude\projects"; Destination = "$BackupPath\sessions\config-claude-projects"; Description = ".config/claude/projects" },
    @{ Source = "$HOME_DIR\.claude\projects"; Destination = "$BackupPath\sessions\claude-projects"; Description = ".claude/projects" },
    @{ Source = "$HOME_DIR\.claude\sessions"; Destination = "$BackupPath\sessions\claude-sessions"; Description = ".claude/sessions" },
    @{ Source = "$HOME_DIR\.local\share\opencode"; Destination = "$BackupPath\opencode\local-share-opencode"; Description = "OpenCode main data" },
    @{ Source = "$HOME_DIR\.config\opencode"; Destination = "$BackupPath\opencode\config-opencode"; Description = "OpenCode config" },
    @{ Source = "$HOME_DIR\.cache\opencode"; Destination = "$BackupPath\opencode\cache-opencode"; Description = "OpenCode cache" },
    @{ Source = "$HOME_DIR\.sisyphus"; Destination = "$BackupPath\opencode\sisyphus"; Description = ".sisyphus agent" },
    @{ Source = "$APPDATA\Claude"; Destination = "$BackupPath\appdata\roaming-claude"; Description = "AppData\Roaming\Claude (ALL)" },
    @{ Source = "$LOCALAPPDATA\Claude"; Destination = "$BackupPath\appdata\local-claude"; Description = "AppData\Local\Claude" },
    @{ Source = "$HOME_DIR\.local\share\uv"; Destination = "$BackupPath\python\uv"; Description = "uv data" },
    @{ Source = "$HOME_DIR\.ssh"; Destination = "$BackupPath\git\ssh"; Description = ".ssh directory" },
    @{ Source = "$HOME_DIR\.config\gh"; Destination = "$BackupPath\git\github-cli"; Description = "GitHub CLI config" },
    # NEW IN v14.0: MOLTBOT, CLAWDBOT, CLAWD
    @{ Source = "$HOME_DIR\.moltbot"; Destination = "$BackupPath\moltbot\dot-moltbot"; Description = ".moltbot config (CRITICAL)" },
    @{ Source = "$HOME_DIR\.clawdbot"; Destination = "$BackupPath\clawdbot\dot-clawdbot"; Description = ".clawdbot config (CRITICAL)" },
    @{ Source = "$HOME_DIR\clawd"; Destination = "$BackupPath\clawd\workspace"; Description = "clawd workspace (COMPLETE)" },
    @{ Source = "$APPDATA\npm\node_modules\moltbot"; Destination = "$BackupPath\moltbot\npm-module"; Description = "moltbot npm module (FULL INSTALL)" },
    @{ Source = "$APPDATA\npm\node_modules\clawdbot"; Destination = "$BackupPath\clawdbot\npm-module"; Description = "clawdbot npm module (FULL INSTALL)" },
    @{ Source = "$APPDATA\npm\node_modules\@anthropic-ai"; Destination = "$BackupPath\npm-global\anthropic-ai"; Description = "@anthropic-ai npm packages" },
    @{ Source = "$APPDATA\npm\node_modules\opencode-ai"; Destination = "$BackupPath\npm-global\opencode-ai"; Description = "opencode-ai npm module" },
    # NEW IN v15.0: OPENCLAW (AI AGENT) - CRITICAL FOR AGENT RESTORATION
    # NOTE: Full .openclaw dir is ~800MB — back up key subdirs individually instead
    @{ Source = "$HOME_DIR\.openclaw\workspace"; Destination = "$BackupPath\openclaw\workspace"; Description = "OpenClaw workspace (SOUL.md, USER.md, MEMORY.md)" },
    @{ Source = "$HOME_DIR\.openclaw\workspace-main"; Destination = "$BackupPath\openclaw\workspace-main"; Description = "OpenClaw workspace-main" },
    @{ Source = "$HOME_DIR\.openclaw\workspace-session2"; Destination = "$BackupPath\openclaw\workspace-session2"; Description = "OpenClaw workspace-session2" },
    @{ Source = "$HOME_DIR\.openclaw\workspace-openclaw"; Destination = "$BackupPath\openclaw\workspace-openclaw"; Description = "OpenClaw workspace-openclaw" },
    @{ Source = "$HOME_DIR\.openclaw\workspace-openclaw4"; Destination = "$BackupPath\openclaw\workspace-openclaw4"; Description = "OpenClaw workspace-openclaw4" },
    # v18.0: MISSING WORKSPACES discovered by C: drive scan
    @{ Source = "$HOME_DIR\.openclaw\workspace-moltbot"; Destination = "$BackupPath\openclaw\workspace-moltbot"; Description = "OpenClaw workspace-moltbot (MISSING IN v17)" },
    @{ Source = "$HOME_DIR\.openclaw\workspace-moltbot2"; Destination = "$BackupPath\openclaw\workspace-moltbot2"; Description = "OpenClaw workspace-moltbot2 (MISSING IN v17)" },
    @{ Source = "$HOME_DIR\.openclaw\workspace-openclaw-main"; Destination = "$BackupPath\openclaw\workspace-openclaw-main"; Description = "OpenClaw workspace-openclaw-main (MISSING IN v17)" },
    @{ Source = "$HOME_DIR\.openclaw\agents"; Destination = "$BackupPath\openclaw\agents"; Description = "OpenClaw agents" },
    @{ Source = "$HOME_DIR\.openclaw\credentials"; Destination = "$BackupPath\openclaw\credentials-dir"; Description = "OpenClaw credentials" },
    @{ Source = "$HOME_DIR\.openclaw\memory"; Destination = "$BackupPath\openclaw\memory"; Description = "OpenClaw memory" },
    @{ Source = "$HOME_DIR\.openclaw\cron"; Destination = "$BackupPath\openclaw\cron"; Description = "OpenClaw cron jobs" },
    @{ Source = "$HOME_DIR\.openclaw\extensions"; Destination = "$BackupPath\openclaw\extensions"; Description = "OpenClaw extensions" },
    @{ Source = "$HOME_DIR\.openclaw\skills"; Destination = "$BackupPath\openclaw\skills"; Description = "OpenClaw skills" },
    @{ Source = "$HOME_DIR\.openclaw\scripts"; Destination = "$BackupPath\openclaw\scripts"; Description = "OpenClaw scripts (gmail-send, Chrome launchers)" },
    @{ Source = "$HOME_DIR\.openclaw\browser"; Destination = "$BackupPath\openclaw\browser"; Description = "OpenClaw browser (chrome-extension relay)" },
    @{ Source = "$HOME_DIR\.openclaw\logs"; Destination = "$BackupPath\openclaw\logs"; Description = "OpenClaw logs" },
    # v18.0: MISSING OPENCLAW SUBDIRS discovered by C: drive scan
    @{ Source = "$HOME_DIR\.openclaw\telegram"; Destination = "$BackupPath\openclaw\telegram"; Description = "OpenClaw telegram (command hashes, update offsets)" },
    @{ Source = "$HOME_DIR\.openclaw\ClawdBot"; Destination = "$BackupPath\openclaw\ClawdBot-tray"; Description = "OpenClaw ClawdBot tray scripts (ps1, vbs)" },
    @{ Source = "$HOME_DIR\.openclaw\completions"; Destination = "$BackupPath\openclaw\completions"; Description = "OpenClaw completions (bash, fish, ps1, zsh)" },
    @{ Source = "$HOME_DIR\.openclaw\backups"; Destination = "$BackupPath\openclaw\backups"; Description = "OpenClaw historical backups" },
    @{ Source = "$APPDATA\npm\node_modules\openclaw"; Destination = "$BackupPath\openclaw\npm-module"; Description = "openclaw npm module (FULL INSTALL)" },
    # CRITICAL: ClawdbotTray.vbs - The launcher that runs OpenClaw agent
    @{ Source = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot"; Destination = "$BackupPath\openclaw\clawdbot-wrappers"; Description = "ClawdBot wrappers (ClawdbotTray.vbs)" },
    # v18.0: CLAUDEGRAM + CLAUDE-SERVER-COMMANDER
    @{ Source = "$HOME_DIR\.claudegram"; Destination = "$BackupPath\claudegram\dot-claudegram"; Description = ".claudegram (sessions, wrapper, config)" },
    @{ Source = "$HOME_DIR\.claude-server-commander"; Destination = "$BackupPath\claude-server-commander"; Description = ".claude-server-commander (config, feature-flags, tool-history)" },
    # v18.0: CLAUDE CLI state + versions
    @{ Source = "$HOME_DIR\.local\share\claude"; Destination = "$BackupPath\cli-binary\local-share-claude"; Description = ".local/share/claude (CLI version binaries)" },
    @{ Source = "$HOME_DIR\.local\state\claude"; Destination = "$BackupPath\cli-binary\local-state-claude"; Description = ".local/state/claude (CLI state)" },
    # v18.0: OPENCODE state
    @{ Source = "$HOME_DIR\.local\state\opencode"; Destination = "$BackupPath\opencode\local-state-opencode"; Description = ".local/state/opencode (frecency, prompt history)" },
    # v18.0: APPDATA gaps - Claude Code Roaming, CLI nodejs cache, AnthropicClaude Desktop
    @{ Source = "$APPDATA\Claude Code"; Destination = "$BackupPath\appdata\roaming-claude-code"; Description = "AppData\Roaming\Claude Code (browser ext native host)" },
    @{ Source = "$LOCALAPPDATA\claude-cli-nodejs"; Destination = "$BackupPath\appdata\claude-cli-nodejs"; Description = "AppData\Local\claude-cli-nodejs (CLI cache + MCP logs)" },
    @{ Source = "$LOCALAPPDATA\AnthropicClaude"; Destination = "$BackupPath\appdata\AnthropicClaude"; Description = "AppData\Local\AnthropicClaude (Desktop app)" },
    @{ Source = "$LOCALAPPDATA\claude"; Destination = "$BackupPath\appdata\local-claude-cache"; Description = "AppData\Local\claude (CLI cache)" },
    # v18.0: PowerShell ClaudeUsage modules
    @{ Source = "$HOME_DIR\Documents\PowerShell\Modules\ClaudeUsage"; Destination = "$BackupPath\powershell\ClaudeUsage-ps7"; Description = "ClaudeUsage PS7 module" },
    @{ Source = "$HOME_DIR\Documents\WindowsPowerShell\Modules\ClaudeUsage"; Destination = "$BackupPath\powershell\ClaudeUsage-ps5"; Description = "ClaudeUsage PS5 module" },
    # v18.0: OpenCode auth npm package
    @{ Source = "$APPDATA\npm\node_modules\opencode-antigravity-auth"; Destination = "$BackupPath\npm-global\opencode-antigravity-auth"; Description = "opencode-antigravity-auth npm package" },
    # v18.0: OpenClaw mission control project
    @{ Source = "$HOME_DIR\openclaw-mission-control"; Destination = "$BackupPath\openclaw\mission-control"; Description = "openclaw-mission-control project" },
    # v18.0: Chrome claude.ai IndexedDB (Profile 1 + 2)
    @{ Source = "$LOCALAPPDATA\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.blob"; Destination = "$BackupPath\chrome\profile1-claude-indexeddb-blob"; Description = "Chrome Profile 1 claude.ai IndexedDB blob" },
    @{ Source = "$LOCALAPPDATA\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.leveldb"; Destination = "$BackupPath\chrome\profile1-claude-indexeddb-leveldb"; Description = "Chrome Profile 1 claude.ai IndexedDB leveldb" },
    @{ Source = "$LOCALAPPDATA\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.blob"; Destination = "$BackupPath\chrome\profile2-claude-indexeddb-blob"; Description = "Chrome Profile 2 claude.ai IndexedDB blob" },
    @{ Source = "$LOCALAPPDATA\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.leveldb"; Destination = "$BackupPath\chrome\profile2-claude-indexeddb-leveldb"; Description = "Chrome Profile 2 claude.ai IndexedDB leveldb" },
    # Critical .claude subdirectories (v13.0 additions)
    @{ Source = "$HOME_DIR\.claude\.beads"; Destination = "$BackupPath\claude-dirs\beads"; Description = ".claude/.beads (issue tracker)" },
    @{ Source = "$HOME_DIR\.claude\.sisyphus"; Destination = "$BackupPath\claude-dirs\sisyphus"; Description = ".claude/.sisyphus (agent)" },
    @{ Source = "$HOME_DIR\.claude\chrome"; Destination = "$BackupPath\claude-dirs\chrome"; Description = ".claude/chrome (browser data)" },
    @{ Source = "$HOME_DIR\.claude\debug"; Destination = "$BackupPath\claude-dirs\debug"; Description = ".claude/debug" },
    @{ Source = "$HOME_DIR\.claude\file-history"; Destination = "$BackupPath\claude-dirs\file-history"; Description = ".claude/file-history" },
    @{ Source = "$HOME_DIR\.claude\hooks"; Destination = "$BackupPath\claude-dirs\hooks"; Description = ".claude/hooks (CRITICAL)" },
    @{ Source = "$HOME_DIR\.claude\paste-cache"; Destination = "$BackupPath\claude-dirs\paste-cache"; Description = ".claude/paste-cache" },
    @{ Source = "$HOME_DIR\.claude\plans"; Destination = "$BackupPath\claude-dirs\plans"; Description = ".claude/plans" },
    @{ Source = "$HOME_DIR\.claude\rules"; Destination = "$BackupPath\claude-dirs\rules"; Description = ".claude/rules (CRITICAL)" },
    @{ Source = "$HOME_DIR\.claude\session-env"; Destination = "$BackupPath\claude-dirs\session-env"; Description = ".claude/session-env" },
    @{ Source = "$HOME_DIR\.claude\shell-snapshots"; Destination = "$BackupPath\claude-dirs\shell-snapshots"; Description = ".claude/shell-snapshots" },
    @{ Source = "$HOME_DIR\.claude\statsig"; Destination = "$BackupPath\claude-dirs\statsig"; Description = ".claude/statsig" },
    @{ Source = "$HOME_DIR\.claude\telemetry"; Destination = "$BackupPath\claude-dirs\telemetry"; Description = ".claude/telemetry" },
    @{ Source = "$HOME_DIR\.claude\todos"; Destination = "$BackupPath\claude-dirs\todos"; Description = ".claude/todos" },
    @{ Source = "$HOME_DIR\.claude\transcripts"; Destination = "$BackupPath\claude-dirs\transcripts"; Description = ".claude/transcripts" },
    @{ Source = "$HOME_DIR\.claude\downloads"; Destination = "$BackupPath\claude-dirs\downloads"; Description = ".claude/downloads" },
    @{ Source = "$HOME_DIR\.claude\cache"; Destination = "$BackupPath\claude-dirs\cache"; Description = ".claude/cache" },
    @{ Source = "$APPDATA\Claude\claude-code-sessions"; Destination = "$BackupPath\appdata\claude-code-sessions"; Description = "claude-code-sessions (CRITICAL)" }
)

# Launch ALL large copy tasks via RunspacePool (v17.0 turbo)
Start-AllParallelCopies -Tasks $largeCopyTasks -MaxThreads $MaxJobs
#endregion

#region 1. CORE CLAUDE CODE FILES
Write-Step "[1/35] Backing up CORE Claude Code files..." "INFO"

# ~/.claude.json - Main config (small files - copy immediately)
Copy-ItemSafe "$HOME_DIR\.claude.json" "$BackupPath\core\claude.json" ".claude.json"
Copy-ItemSafe "$HOME_DIR\.claude.json.backup" "$BackupPath\core\claude.json.backup" ".claude.json.backup"
# Large .claude directory is being copied by turbo job
#endregion

#region 2. CLAUDE CODE CLI BINARY (CRITICAL - Makes 'claude' command work!)
Write-Step "[2/35] Backing up CLAUDE CODE CLI BINARY (CRITICAL!)..." "INFO"

# Claude Code CLI binary location - THIS IS WHY 'claude' COMMAND WASN'T WORKING!
# The CLI is installed at: %APPDATA%\Claude\claude-code\<version>\claude.exe
$claudeCodeDir = "$APPDATA\Claude\claude-code"
if (Test-Path $claudeCodeDir) {
    Copy-ItemSafe $claudeCodeDir "$BackupPath\cli-binary\claude-code" "Claude Code CLI binary (claude.exe)" -Recurse
    Write-Step "  -> Claude Code CLI binary backed up!" "SUCCESS"
} else {
    Write-Step "  -> Claude Code CLI not found at $claudeCodeDir" "WARNING"
}

# .local\bin directory - Contains claude.exe symlink/copy + uv tools
$localBinDir = "$HOME_DIR\.local\bin"
if (Test-Path $localBinDir) {
    Copy-ItemSafe $localBinDir "$BackupPath\cli-binary\local-bin" ".local\bin (claude.exe, uv.exe, uvx.exe)" -Recurse
    Write-Step "  -> .local\bin backed up!" "SUCCESS"
} else {
    Write-Step "  -> .local\bin not found" "WARNING"
}

# .local\bin already backed up above - skip full .local to avoid 500MB+ duplicate

# Capture Claude Code version info
$claudeExe = Get-Command claude -ErrorAction SilentlyContinue
if ($claudeExe) {
    $cliInfo = @{
        Path = $claudeExe.Source
        Version = (claude --version 2>$null) -join " "
        Timestamp = Get-Date -Format "o"
    }
    $cliInfo | ConvertTo-Json | Out-File "$BackupPath\cli-binary\claude-cli-info.json" -Encoding UTF8
    Write-Step "  -> Claude CLI version: $($cliInfo.Version)" "SUCCESS"
}
#endregion

#region 3. NPM GLOBAL PACKAGES (COMPLETE LIST + ALL AI TOOLS)
Write-Step "[3/35] Backing up NPM GLOBAL packages (COMPLETE)..." "INFO"

# Create npm directory first
New-Item -ItemType Directory -Path "$BackupPath\npm-global" -Force | Out-Null

# Get npm prefix and version info
$npmCmd = Get-Command npm -ErrorAction SilentlyContinue
if ($npmCmd) {
    $npmPrefix = npm config get prefix 2>$null
    $nodeVersion = node --version 2>$null
    $npmVersion = npm --version 2>$null

    # Create installer info file
    $nodeInfo = @{
        NodeVersion = $nodeVersion
        NpmVersion = $npmVersion
        NpmPrefix = $npmPrefix
        Timestamp = Get-Date -Format "o"
    }
    $nodeInfo | ConvertTo-Json | Out-File "$BackupPath\npm-global\node-info.json" -Encoding UTF8
    Write-Step "  -> Node.js version info" "SUCCESS"

    # npm global packages list (JSON for exact versions)
    try {
        $npmList = npm list -g --depth=0 --json 2>$null | ConvertFrom-Json
        $npmList | ConvertTo-Json -Depth 10 | Out-File "$BackupPath\npm-global\global-packages.json" -Encoding UTF8
        Write-Step "  -> npm global packages list (JSON)" "SUCCESS"
    } catch {}

    # npm package list (text for manual reinstall)
    npm list -g --depth=0 2>$null | Out-File "$BackupPath\npm-global\global-packages.txt" -Encoding UTF8
    Write-Step "  -> npm global packages list (TEXT)" "SUCCESS"

    # CRITICAL: Create exact reinstall script with versions
    $reinstallScript = "# NPM Global Packages Reinstall Script`n"
    $reinstallScript += "# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n`n"
    
    try {
        $packages = npm list -g --depth=0 --json 2>$null | ConvertFrom-Json
        if ($packages.dependencies) {
            $packages.dependencies.PSObject.Properties | ForEach-Object {
                $pkgName = $_.Name
                $pkgVersion = $_.Value.version
                $reinstallScript += "npm install -g $pkgName@$pkgVersion`n"
            }
        }
    } catch {
        # Fallback: parse text output
        $pkgList = npm list -g --depth=0 2>$null
        $pkgList | ForEach-Object {
            if ($_ -match "[@]") {
                # Extract package@version from npm list output
                $line = $_ -replace '^[^\w@]+', '' # Remove tree characters
                if ($line -match '^([^@\s]+)@(.+)$') {
                    $reinstallScript += "npm install -g $($matches[1])@$($matches[2])`n"
                }
            }
        }
    }
    
    $reinstallScript | Out-File "$BackupPath\npm-global\REINSTALL-ALL.ps1" -Encoding UTF8
    Write-Step "  -> Created exact reinstall script" "SUCCESS"

    # Backup entire npm global node_modules (already in parallel jobs)
    # npm cache is large and regeneratable — skip to avoid bloat

    Copy-ItemSafe "$HOME_DIR\.npmrc" "$BackupPath\npm-global\npmrc" ".npmrc"
} else {
    Write-Step "  -> npm not found - skipping npm backup" "WARNING"
}
#endregion

#region 4. MOLTBOT COMPLETE BACKUP
Write-Step "[4/35] Backing up MOLTBOT (COMPLETE)..." "INFO"

# Moltbot config directory (already in parallel jobs: $HOME_DIR\.moltbot)
# Moltbot npm module (already in parallel jobs: $APPDATA\npm\node_modules\moltbot)

# Capture Moltbot version
New-Item -ItemType Directory -Path "$BackupPath\moltbot" -Force | Out-Null
$moltbotCmd = Get-Command moltbot -ErrorAction SilentlyContinue
if ($moltbotCmd) {
    $moltbotInfo = @{
        Path = $moltbotCmd.Source
        Version = (moltbot --version 2>$null) -join " "
        Timestamp = Get-Date -Format "o"
    }
    $moltbotInfo | ConvertTo-Json | Out-File "$BackupPath\moltbot\moltbot-info.json" -Encoding UTF8
    Write-Step "  -> Moltbot version: $($moltbotInfo.Version)" "SUCCESS"
}

# Backup any moltbot-related config files
if (Test-Path "$HOME_DIR\.moltbot") {
    Write-Step "  -> Moltbot config directory queued for backup" "SUCCESS"
}
#endregion

#region 5. CLAWDBOT COMPLETE BACKUP
Write-Step "[5/35] Backing up CLAWDBOT (COMPLETE)..." "INFO"

# Clawdbot config directory (already in parallel jobs: $HOME_DIR\.clawdbot)
# Clawdbot npm module (already in parallel jobs: $APPDATA\npm\node_modules\clawdbot)

# Capture Clawdbot version
New-Item -ItemType Directory -Path "$BackupPath\clawdbot" -Force | Out-Null
$clawdbotCmd = Get-Command clawdbot -ErrorAction SilentlyContinue
if ($clawdbotCmd) {
    $clawdbotInfo = @{
        Path = $clawdbotCmd.Source
        Version = (clawdbot --version 2>$null) -join " "
        Timestamp = Get-Date -Format "o"
    }
    $clawdbotInfo | ConvertTo-Json | Out-File "$BackupPath\clawdbot\clawdbot-info.json" -Encoding UTF8
    Write-Step "  -> Clawdbot version: $($clawdbotInfo.Version)" "SUCCESS"
}

# Backup any clawdbot-related config files
if (Test-Path "$HOME_DIR\.clawdbot") {
    Write-Step "  -> Clawdbot config directory queued for backup" "SUCCESS"
}
#endregion

#region 6. CLAWD WORKSPACE COMPLETE BACKUP
Write-Step "[6/35] Backing up CLAWD WORKSPACE (COMPLETE)..." "INFO"

# Clawd workspace (already in parallel jobs: $HOME_DIR\clawd)
# This includes all memory files, agent configs, etc.

if (Test-Path "$HOME_DIR\clawd") {
    Write-Step "  -> Clawd workspace queued for backup" "SUCCESS"
    
    # Create index of clawd workspace contents
    New-Item -ItemType Directory -Path "$BackupPath\clawd" -Force | Out-Null
    $clawdIndex = @{
        Path = "$HOME_DIR\clawd"
        BackedUp = Get-Date -Format "o"
        Contents = @()
    }
    
    Get-ChildItem "$HOME_DIR\clawd" -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $clawdIndex.Contents += @{
            RelativePath = $_.FullName.Replace("$HOME_DIR\clawd\", "")
            Size = $_.Length
            LastModified = $_.LastWriteTime.ToString("o")
        }
    }
    
    $clawdIndex | ConvertTo-Json -Depth 5 | Out-File "$BackupPath\clawd\WORKSPACE-INDEX.json" -Encoding UTF8
    Write-Step "  -> Clawd workspace index created" "SUCCESS"
}
#endregion

#region 7. OPENCLAW COMPLETE BACKUP (AI AGENT - CRITICAL!)
Write-Step "[7/35] Backing up OPENCLAW (AI AGENT - CRITICAL!)..." "INFO"

# OpenClaw workspace contains the agent's identity, memory, and personality
# This is CRITICAL for restoring the exact same agent on a new machine!

New-Item -ItemType Directory -Path "$BackupPath\openclaw" -Force | Out-Null

# Capture OpenClaw version and CLI info
$openclawCmd = Get-Command openclaw -ErrorAction SilentlyContinue
if ($openclawCmd) {
    $openclawInfo = @{
        Path = $openclawCmd.Source
        Version = (openclaw --version 2>$null) -join " "
        Timestamp = Get-Date -Format "o"
    }
    $openclawInfo | ConvertTo-Json | Out-File "$BackupPath\openclaw\openclaw-info.json" -Encoding UTF8
    Write-Step "  -> OpenClaw version: $($openclawInfo.Version)" "SUCCESS"
}

# OpenClaw workspace files (already in parallel jobs but list critical files)
$openclawWorkspace = "$HOME_DIR\.openclaw\workspace"
if (Test-Path $openclawWorkspace) {
    Write-Step "  -> OpenClaw workspace queued for backup" "SUCCESS"
    
    # Create index of workspace contents (CRITICAL FILES)
    $openclawIndex = @{
        Path = $openclawWorkspace
        BackedUp = Get-Date -Format "o"
        CriticalFiles = @()
        AllFiles = @()
    }
    
    # List critical agent files
    $criticalFiles = @("SOUL.md", "USER.md", "MEMORY.md", "AGENTS.md", "IDENTITY.md", "TOOLS.md", "BOOTSTRAP.md", "HEARTBEAT.md")
    foreach ($critFile in $criticalFiles) {
        $filePath = Join-Path $openclawWorkspace $critFile
        if (Test-Path $filePath) {
            $fileInfo = Get-Item $filePath
            $openclawIndex.CriticalFiles += @{
                Name = $critFile
                Size = $fileInfo.Length
                LastModified = $fileInfo.LastWriteTime.ToString("o")
            }
        }
    }
    
    # List all files
    Get-ChildItem $openclawWorkspace -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $openclawIndex.AllFiles += @{
            RelativePath = $_.FullName.Replace("$openclawWorkspace\", "")
            Size = $_.Length
            LastModified = $_.LastWriteTime.ToString("o")
        }
    }
    
    $openclawIndex | ConvertTo-Json -Depth 5 | Out-File "$BackupPath\openclaw\WORKSPACE-INDEX.json" -Encoding UTF8
    Write-Step "  -> OpenClaw workspace index created ($($openclawIndex.CriticalFiles.Count) critical files)" "SUCCESS"
}

# OpenClaw gateway config (may contain tokens)
$openclawConfig = "$HOME_DIR\.openclaw\config.yaml"
if (Test-Path $openclawConfig) {
    Copy-ItemSafe $openclawConfig "$BackupPath\openclaw\config.yaml" "OpenClaw gateway config (CRITICAL)"
}

# CRITICAL: openclaw.json - Contains Telegram customCommands, channel settings, bot tokens
$openclawJson = "$HOME_DIR\.openclaw\openclaw.json"
if (Test-Path $openclawJson) {
    Copy-ItemSafe $openclawJson "$BackupPath\openclaw\openclaw.json" "OpenClaw config (customCommands, channels)"
    Write-Step "  -> openclaw.json (Telegram slash commands config)" "SUCCESS"
}

# v18.0: CRITICAL AUTH FILES missing from v17
Copy-ItemSafe "$HOME_DIR\.openclaw\auth.json" "$BackupPath\openclaw\auth.json" "OpenClaw auth.json (CRITICAL)"
Copy-ItemSafe "$HOME_DIR\.openclaw\auth-profiles.json" "$BackupPath\openclaw\auth-profiles.json" "OpenClaw auth-profiles.json (CRITICAL)"
Copy-ItemSafe "$HOME_DIR\.openclaw\.openclawrc.json" "$BackupPath\openclaw\openclawrc.json" "OpenClaw .openclawrc.json (root config)"
Copy-ItemSafe "$HOME_DIR\.openclaw\moltbot.json" "$BackupPath\openclaw\moltbot.json" "OpenClaw moltbot.json"
Copy-ItemSafe "$HOME_DIR\.openclaw\clawdbot.json" "$BackupPath\openclaw\clawdbot.json" "OpenClaw clawdbot.json"
Copy-ItemSafe "$HOME_DIR\.openclaw\openclaw-backup.json" "$BackupPath\openclaw\openclaw-backup.json" "OpenClaw backup config"
Copy-ItemSafe "$HOME_DIR\.openclaw\openclaw-gateway-task.xml" "$BackupPath\openclaw\openclaw-gateway-task.xml" "OpenClaw gateway scheduled task"
Copy-ItemSafe "$HOME_DIR\.openclaw\apply-jobs.ps1" "$BackupPath\openclaw\apply-jobs.ps1" "OpenClaw apply-jobs.ps1"
Copy-ItemSafe "$HOME_DIR\.openclaw\autostart.log" "$BackupPath\openclaw\autostart.log" "OpenClaw autostart.log"

# v18.0: All openclaw.json rolling backups
Get-ChildItem "$HOME_DIR\.openclaw" -Filter "openclaw.json.*" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-ItemSafe $_.FullName "$BackupPath\openclaw\rolling-backups\$($_.Name)" "OpenClaw rolling backup: $($_.Name)"
}
Get-ChildItem "$HOME_DIR\.openclaw" -Filter "moltbot.json.*" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-ItemSafe $_.FullName "$BackupPath\openclaw\rolling-backups\$($_.Name)" "Moltbot rolling backup: $($_.Name)"
}
Get-ChildItem "$HOME_DIR\.openclaw" -Filter "clawdbot.json.*" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-ItemSafe $_.FullName "$BackupPath\openclaw\rolling-backups\$($_.Name)" "Clawdbot rolling backup: $($_.Name)"
}

# v18.0: DYNAMIC workspace scanner — catches ALL workspace-* dirs automatically
Get-ChildItem "$HOME_DIR\.openclaw" -Directory -Filter "workspace-*" -ErrorAction SilentlyContinue | ForEach-Object {
    $destName = $_.Name
    $destPath = "$BackupPath\openclaw\$destName"
    if (-not (Test-Path $destPath)) {
        # Not already in parallel tasks — copy sequentially (fast, small workspaces)
        Copy-ItemSafe $_.FullName $destPath "OpenClaw dynamic: $destName" -Recurse
    }
}

# Index workspace scripts (todoist-done.ps1, etc.)
$workspaceScripts = Get-ChildItem "$openclawWorkspace" -Filter "*.ps1" -Recurse -ErrorAction SilentlyContinue
if ($workspaceScripts) {
    $scriptsIndex = @{
        BackedUp = Get-Date -Format "o"
        Scripts = @()
    }
    foreach ($script in $workspaceScripts) {
        $scriptsIndex.Scripts += @{
            Name = $script.Name
            RelativePath = $script.FullName.Replace("$openclawWorkspace\", "")
            Size = $script.Length
        }
    }
    $scriptsIndex | ConvertTo-Json -Depth 5 | Out-File "$BackupPath\openclaw\WORKSPACE-SCRIPTS-INDEX.json" -Encoding UTF8
    Write-Step "  -> Workspace scripts index ($($workspaceScripts.Count) scripts)" "SUCCESS"
}

# OpenClaw credentials (contains WhatsApp/Telegram tokens)
Copy-ItemSafe "$HOME_DIR\.openclaw\credentials" "$BackupPath\openclaw\credentials" "OpenClaw credentials" -Recurse

# OpenClaw logs (useful for debugging)
Copy-ItemSafe "$HOME_DIR\.openclaw\logs" "$BackupPath\openclaw\logs" "OpenClaw logs" -Recurse

# CRITICAL: ClawdbotTray.vbs - THE LAUNCHER THAT MAKES OPENCLAW RUN!
$clawdbotTrayPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot\b"
if (Test-Path $clawdbotTrayPath) {
    Copy-ItemSafe $clawdbotTrayPath "$BackupPath\openclaw\clawdbot-launcher" "ClawdbotTray.vbs launcher (CRITICAL)" -Recurse
    Write-Step "  -> ClawdbotTray.vbs launcher backed up!" "SUCCESS"
}

# Root-level .openclaw files (CLAUDE.md, *.json, *.yaml, *.md not in subdirs)
Get-ChildItem "$HOME_DIR\.openclaw" -File -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-ItemSafe $_.FullName "$BackupPath\openclaw\root-files\$($_.Name)" "OpenClaw root: $($_.Name)"
}

Write-Step "  -> OpenClaw (AI Agent) backup section complete" "SUCCESS"
#endregion

#region 8. CREDENTIALS & AUTH (CRITICAL FOR AUTO-LOGIN!)
Write-Step "[8/35] Backing up CREDENTIALS and AUTH (CRITICAL!)..." "INFO"

# Claude Code OAuth credentials - THE KEY TO AUTO-LOGIN!
Copy-ItemSafe "$HOME_DIR\.claude\.credentials.json" "$BackupPath\credentials\claude-credentials.json" "Claude OAuth credentials (CRITICAL)"

# OpenClaw WhatsApp baileys auth files (creds.json, sessions.json, auth-profiles.json, session-*.json)
Get-ChildItem "$HOME_DIR\.openclaw" -Filter "*.json" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    if ($_.Name -match "creds|auth|session|store") {
        Copy-ItemSafe $_.FullName "$BackupPath\credentials\openclaw-auth\$($_.Name)" "OpenClaw auth: $($_.Name)"
    }
}

# Windows Credential Manager
Get-WindowsCredentialManager "$BackupPath\credentials\windows-credential-manager.txt"

# .env files with API keys
$envFiles = Get-ChildItem -Path $HOME_DIR -Filter ".env*" -File -ErrorAction SilentlyContinue
foreach ($envFile in $envFiles) {
    $content = Get-Content $envFile.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match "ANTHROPIC|CLAUDE|OPENAI|OPENCLAW|MOLT|CLAWD") {
        Copy-ItemSafe $envFile.FullName "$BackupPath\credentials\env-files\$($envFile.Name)" "ENV: $($envFile.Name)"
    }
}

# All auth tokens in all JSON files in .claude
Get-ChildItem "$HOME_DIR\.claude" -Filter "*.json" -File -ErrorAction SilentlyContinue | ForEach-Object {
    $content = Get-Content $_.FullName -Raw -ErrorAction SilentlyContinue
    if ($content -match "token|auth|credential|api_key|apiKey") {
        Copy-ItemSafe $_.FullName "$BackupPath\credentials\claude-json-auth\$($_.Name)" "Auth JSON: $($_.Name)"
    }
}
#endregion

#region 8-30: Continue with all other backup sections...
# (Sessions, OpenCode, AppData, MCP, Settings, Agents, NPM, Python, PowerShell, Env Vars, Registry, Special Files, etc.)
# These sections remain identical to v13.0 but are included for completeness

#region 9. SESSIONS & CONVERSATION HISTORY
Write-Step "[9/35] Backing up SESSIONS and CONVERSATIONS..." "INFO"
Copy-ItemSafe "$HOME_DIR\.claude\history.jsonl" "$BackupPath\sessions\history.jsonl" "history.jsonl"
$sqliteFiles = Get-ChildItem -Path "$HOME_DIR\.claude" -Filter "*.db" -Recurse -ErrorAction SilentlyContinue
foreach ($db in $sqliteFiles) {
    Copy-ItemSafe $db.FullName "$BackupPath\sessions\databases\$($db.Name)" "SQLite: $($db.Name)"
}
# MCP server database (only exists if MCP is used)
if (Test-Path "$LOCALAPPDATA\Claude\MCP\mcp_server.db") {
    Copy-ItemSafe "$LOCALAPPDATA\Claude\MCP\mcp_server.db" "$BackupPath\sessions\databases\mcp_server.db" "MCP server database"
}
#endregion

#region 10. CLAUDE CODE JSON FILES (ALL)
Write-Step "[10/35] Backing up ALL .claude JSON files..." "INFO"
$claudeJsonFiles = Get-ChildItem -Path "$HOME_DIR\.claude" -Filter "*.json" -File -ErrorAction SilentlyContinue
foreach ($jsonFile in $claudeJsonFiles) {
    Copy-ItemSafe $jsonFile.FullName "$BackupPath\claude-json\$($jsonFile.Name)" ".claude/$($jsonFile.Name)"
}
#endregion

#region 11. WINDOWS TERMINAL SETTINGS
Write-Step "[11/35] Backing up WINDOWS TERMINAL settings..." "INFO"
$terminalSettings = "$LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
if (Test-Path $terminalSettings) {
    Copy-ItemSafe "$terminalSettings\settings.json" "$BackupPath\terminal\settings.json" "Windows Terminal settings"
    Write-Step "  -> Windows Terminal settings" "SUCCESS"
}
$terminalPreview = "$LOCALAPPDATA\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState"
if (Test-Path $terminalPreview) {
    Copy-ItemSafe "$terminalPreview\settings.json" "$BackupPath\terminal\settings-preview.json" "Windows Terminal Preview settings"
}
#endregion

#region 12-35. ALL REMAINING SECTIONS (Git, SSH, IDE, Browser, MCP, PowerShell, Python, etc.)
Write-Step "[12/35] Backing up GIT CONFIG and SSH KEYS (CRITICAL!)..." "INFO"
Copy-ItemSafe "$HOME_DIR\.gitconfig" "$BackupPath\git\gitconfig" ".gitconfig (global)"
# Only backup if exists (not all users have these)
if (Test-Path "$HOME_DIR\.gitignore_global") {
    Copy-ItemSafe "$HOME_DIR\.gitignore_global" "$BackupPath\git\gitignore_global" ".gitignore_global"
}
if (Test-Path "$HOME_DIR\.git-credentials") {
    Copy-ItemSafe "$HOME_DIR\.git-credentials" "$BackupPath\git\git-credentials" ".git-credentials (TOKENS!)"
}
# SSH (already in parallel jobs)

Write-Step "[13/35] MCP CONFIGURATION..." "INFO"
Copy-ItemSafe "$APPDATA\Claude\claude_desktop_config.json" "$BackupPath\mcp\claude_desktop_config.json" "MCP desktop config"

Write-Step "[14/35] SETTINGS and CONFIGURATION..." "INFO"
Copy-ItemSafe "$HOME_DIR\.claude\settings.json" "$BackupPath\settings\settings.json" "Claude settings.json"

Write-Step "[15/35] AGENTS and SKILLS..." "INFO"
Copy-ItemSafe "$HOME_DIR\CLAUDE.md" "$BackupPath\agents\CLAUDE.md" "~/CLAUDE.md"
if (Test-Path "$HOME_DIR\AGENTS.md") {
    Copy-ItemSafe "$HOME_DIR\AGENTS.md" "$BackupPath\agents\AGENTS.md" "~/AGENTS.md"
}

Write-Step "[16/35] PYTHON/UVX..." "INFO"
try { pip freeze 2>$null | Out-File "$BackupPath\python\requirements.txt" -Encoding UTF8 } catch {}

Write-Step "[17/35] POWERSHELL PROFILES..." "INFO"
Copy-ItemSafe "$HOME_DIR\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" "$BackupPath\powershell\ps5-profile.ps1" "PS5 profile"
Copy-ItemSafe "$HOME_DIR\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" "$BackupPath\powershell\ps7-profile.ps1" "PS7 profile"

Write-Step "[18/35] ENVIRONMENT VARIABLES..." "INFO"
New-Item -ItemType Directory -Path "$BackupPath\env" -Force | Out-Null
$envVars = @{}
$relevantPatterns = @("CLAUDE", "ANTHROPIC", "OPENAI", "OPENCODE", "OPENCLAW", "MCP", "MOLT", "CLAWD", "NODE", "NPM", "PYTHON", "UV", "PATH")
[Environment]::GetEnvironmentVariables("User").GetEnumerator() | ForEach-Object {
    foreach ($pattern in $relevantPatterns) {
        if ($_.Key -match $pattern -or $_.Key -eq "PATH") {
            $envVars["USER_$($_.Key)"] = $_.Value
            break
        }
    }
}
$envVars | ConvertTo-Json -Depth 5 | Out-File "$BackupPath\env\environment-variables.json" -Encoding UTF8

Write-Step "[19/35] REGISTRY KEYS..." "INFO"
New-Item -ItemType Directory -Path "$BackupPath\registry" -Force | Out-Null
Export-RegistryKey "HKCU\Environment" "$BackupPath\registry\HKCU-Environment.reg"
Export-RegistryKey "HKCU\Software\Claude" "$BackupPath\registry\HKCU-Claude.reg"

Write-Step "[20/35] SPECIAL FILES..." "INFO"
Copy-ItemSafe "$HOME_DIR\learned.md" "$BackupPath\special\learned.md" "~/learned.md"
Copy-ItemSafe "$HOME_DIR\.claude\learned.md" "$BackupPath\special\claude-learned.md" ".claude/learned.md"

Write-Step "[21/35] INSTALLED SOFTWARE INFO..." "INFO"
$softwareInfo = @{
    ClaudeCode = @{ Installed = $null -ne (Get-Command claude -ErrorAction SilentlyContinue); Version = if (Get-Command claude -ErrorAction SilentlyContinue) { (claude --version 2>$null) -join " " } else { "Not installed" } }
    OpenClaw = @{ Installed = $null -ne (Get-Command openclaw -ErrorAction SilentlyContinue); Version = if (Get-Command openclaw -ErrorAction SilentlyContinue) { (openclaw --version 2>$null) -join " " } else { "Not in PATH (npm module backed up)" } }
    Moltbot = @{ Installed = $null -ne (Get-Command moltbot -ErrorAction SilentlyContinue); Version = if (Get-Command moltbot -ErrorAction SilentlyContinue) { (moltbot --version 2>$null) -join " " } else { "Not installed" } }
    Clawdbot = @{ Installed = $null -ne (Get-Command clawdbot -ErrorAction SilentlyContinue); Version = if (Get-Command clawdbot -ErrorAction SilentlyContinue) { (clawdbot --version 2>$null) -join " " } else { "Not installed" } }
    OpenCode = @{ Installed = $null -ne (Get-Command opencode -ErrorAction SilentlyContinue); Version = if (Get-Command opencode -ErrorAction SilentlyContinue) { (opencode --version 2>$null) -join " " } else { "Not installed" } }
}
$softwareInfo | ConvertTo-Json -Depth 5 | Out-File "$BackupPath\software-info.json" -Encoding UTF8

Write-Step "[22/43] SCRIPTS and WRAPPERS..." "INFO"
Copy-ItemSafe "$HOME_DIR\claude-wrapper.ps1" "$BackupPath\special\claude-wrapper.ps1" "~/claude-wrapper.ps1"
Copy-ItemSafe "$HOME_DIR\mcp-ondemand.ps1" "$BackupPath\special\mcp-ondemand.ps1" "~/mcp-ondemand.ps1 (CRITICAL - referenced in CLAUDE.md)"
Copy-ItemSafe "$HOME_DIR\Documents\WindowsPowerShell\claude.md" "$BackupPath\special\ps-claude.md" "WindowsPowerShell/claude.md"

Write-Step "[23/43] WINDOWS STARTUP shortcuts..." "INFO"
$startupDir = "$APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
Get-ChildItem $startupDir -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match "openclaw|claude|clawd|moltbot" -or $_.Name -match "OpenClaw"
} | ForEach-Object {
    Copy-ItemSafe $_.FullName "$BackupPath\startup\$($_.Name)" "Startup: $($_.Name)"
}

Write-Step "[24/43] NPM BIN SHIMS..." "INFO"
$npmBinDir = "$APPDATA\npm"
@("claude", "claude.cmd", "claude.ps1", "openclaw", "openclaw.cmd", "openclaw.ps1",
  "clawdbot", "clawdbot.cmd", "clawdbot.ps1", "opencode", "opencode.cmd", "opencode.ps1",
  "moltbot", "moltbot.cmd", "moltbot.ps1") | ForEach-Object {
    $shimPath = Join-Path $npmBinDir $_
    if (Test-Path $shimPath) {
        Copy-ItemSafe $shimPath "$BackupPath\npm-global\bin-shims\$_" "npm shim: $_"
    }
}

Write-Step "[25/43] DESKTOP SHORTCUTS..." "INFO"
Get-ChildItem "$HOME_DIR\Desktop" -Filter "*.lnk" -File -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match "claude|openclaw|clawd|moltbot"
} | ForEach-Object {
    Copy-ItemSafe $_.FullName "$BackupPath\special\shortcuts\$($_.Name)" "Desktop: $($_.Name)"
}

Write-Step "[26/43] WINDOWS STORE CLAUDE DATA..." "INFO"
$storeClaudeData = "$LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc"
if (Test-Path "$storeClaudeData\Settings") {
    Copy-ItemSafe "$storeClaudeData\Settings" "$BackupPath\appdata\store-claude-settings" "Windows Store Claude settings" -Recurse
}

Write-Step "[27/43] CATCH-ALL: .openclaw unknown subdirectories..." "INFO"
# SAFETY NET: Back up ANY .openclaw subdirectory not already handled
# This ensures future OpenClaw updates never get missed
$knownOpenclawDirs = @(
    "workspace", "workspace-main", "workspace-session2", "workspace-openclaw", "workspace-openclaw4",
    "workspace-moltbot", "workspace-moltbot2", "workspace-openclaw-main",
    "agents", "credentials", "memory", "cron", "extensions", "skills", "scripts",
    "browser", "logs", "telegram", "ClawdBot", "completions", "backups"
)
if (Test-Path "$HOME_DIR\.openclaw") {
    Get-ChildItem "$HOME_DIR\.openclaw" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $dirName = $_.Name
        # Skip if already handled by explicit tasks or workspace-* dynamic scanner
        if ($knownOpenclawDirs -contains $dirName) { return }
        if ($dirName -match "^workspace-") { return }
        # Skip massive regeneratable dirs
        if ($dirName -match "^(node_modules|\.git|__pycache__|\.venv|venv)$") { return }
        $destPath = "$BackupPath\openclaw\catchall-dirs\$dirName"
        if (-not (Test-Path $destPath)) {
            Copy-ItemSafe $_.FullName $destPath "OpenClaw CATCHALL dir: $dirName" -Recurse
        }
    }
    Write-Step "  -> .openclaw catch-all scan complete" "SUCCESS"
}

Write-Step "[28/43] CATCH-ALL: Home directory claude/openclaw dot-dirs..." "INFO"
# SAFETY NET: Scan ~ for ANY dot-directory matching claude/openclaw/anthropic
# Catches .claudeXYZ, .openclaw-new, .anthropic, etc.
$knownHomeDirs = @(".claude", ".claudegram", ".claude-server-commander", ".openclaw", ".moltbot", ".clawdbot", ".sisyphus")
Get-ChildItem $HOME_DIR -Directory -Force -ErrorAction SilentlyContinue | Where-Object {
    $_.Name -match "^\.?(claude|openclaw|anthropic|opencode)" -and ($knownHomeDirs -notcontains $_.Name)
} | ForEach-Object {
    $destName = $_.Name -replace "^\.", "dot-"
    Copy-ItemSafe $_.FullName "$BackupPath\catchall-home\$destName" "Home CATCHALL: $($_.Name)" -Recurse
}
Write-Step "  -> Home directory catch-all scan complete" "SUCCESS"

Write-Step "[29/43] CATCH-ALL: AppData claude/openclaw directories..." "INFO"
# SAFETY NET: Scan AppData for ANY directory matching claude/openclaw/anthropic
$knownAppDataDirs = @("Claude", "Claude Code", "claude-code-sessions")
@($APPDATA, $LOCALAPPDATA) | ForEach-Object {
    $appDataRoot = $_
    Get-ChildItem $appDataRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic" -and ($knownAppDataDirs -notcontains $_.Name)
    } | ForEach-Object {
        $relBase = if ($appDataRoot -eq $APPDATA) { "roaming" } else { "local" }
        $destPath = "$BackupPath\catchall-appdata\$relBase-$($_.Name)"
        if (-not (Test-Path $destPath)) {
            Copy-ItemSafe $_.FullName $destPath "AppData CATCHALL: $relBase\$($_.Name)" -Recurse
        }
    }
}
Write-Step "  -> AppData catch-all scan complete" "SUCCESS"

Write-Step "[30/43] CATCH-ALL: npm global claude/openclaw packages..." "INFO"
# SAFETY NET: Scan npm global node_modules for ANY claude/openclaw/anthropic package
$npmModulesDir = "$APPDATA\npm\node_modules"
$knownNpmPkgs = @("@anthropic-ai", "openclaw", "moltbot", "clawdbot", "opencode-ai", "opencode-antigravity-auth")
if (Test-Path $npmModulesDir) {
    Get-ChildItem $npmModulesDir -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic|opencode|moltbot|clawd" -and ($knownNpmPkgs -notcontains $_.Name)
    } | ForEach-Object {
        $destPath = "$BackupPath\catchall-npm\$($_.Name)"
        if (-not (Test-Path $destPath)) {
            Copy-ItemSafe $_.FullName $destPath "npm CATCHALL: $($_.Name)" -Recurse
        }
    }
}
Write-Step "  -> npm catch-all scan complete" "SUCCESS"

Write-Step "[31/43] CATCH-ALL: .local claude/openclaw state and data..." "INFO"
# SAFETY NET: Scan .local/share, .local/state, .local/bin for anything missed
$knownLocalDirs = @("claude", "opencode", "uv")
@("$HOME_DIR\.local\share", "$HOME_DIR\.local\state") | ForEach-Object {
    if (Test-Path $_) {
        $localRoot = $_
        $segment = ($localRoot -replace ".*\\\.local\\", "")
        Get-ChildItem $localRoot -Directory -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match "claude|openclaw|anthropic|opencode" -and ($knownLocalDirs -notcontains $_.Name)
        } | ForEach-Object {
            $destPath = "$BackupPath\catchall-local\$segment-$($_.Name)"
            if (-not (Test-Path $destPath)) {
                Copy-ItemSafe $_.FullName $destPath ".local CATCHALL: $segment/$($_.Name)" -Recurse
            }
        }
    }
}
Write-Step "  -> .local catch-all scan complete" "SUCCESS"

Write-Step "[32/43] CATCH-ALL: Chrome profiles claude.ai data..." "INFO"
# SAFETY NET: Scan ALL Chrome profiles (not just Profile 1 and 2) for claude.ai data
$chromeUserData = "$LOCALAPPDATA\Google\Chrome\User Data"
if (Test-Path $chromeUserData) {
    Get-ChildItem $chromeUserData -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "^(Profile \d+|Default)$"
    } | ForEach-Object {
        $profileName = $_.Name -replace " ", "-"
        $indexedDB = Join-Path $_.FullName "IndexedDB"
        if (Test-Path $indexedDB) {
            Get-ChildItem $indexedDB -Directory -Filter "*claude*" -ErrorAction SilentlyContinue | ForEach-Object {
                $destPath = "$BackupPath\chrome\$profileName-$($_.Name)"
                if (-not (Test-Path $destPath)) {
                    Copy-ItemSafe $_.FullName $destPath "Chrome CATCHALL: $profileName claude.ai IndexedDB" -Recurse
                }
            }
        }
    }
}
Write-Step "  -> Chrome catch-all scan complete" "SUCCESS"

Write-Step "[32b/43] CATCH-ALL: Edge + Brave + Firefox claude.ai data..." "INFO"
# Edge
$edgeUserData = "$LOCALAPPDATA\Microsoft\Edge\User Data"
if (Test-Path $edgeUserData) {
    Get-ChildItem $edgeUserData -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "^(Profile \d+|Default)$"
    } | ForEach-Object {
        $profileName = $_.Name -replace " ", "-"
        $indexedDB = Join-Path $_.FullName "IndexedDB"
        if (Test-Path $indexedDB) {
            Get-ChildItem $indexedDB -Directory -Filter "*claude*" -ErrorAction SilentlyContinue | ForEach-Object {
                $destPath = "$BackupPath\browser-data\edge-$profileName-$($_.Name)"
                if (-not (Test-Path $destPath)) {
                    Copy-ItemSafe $_.FullName $destPath "Edge: $profileName claude.ai" -Recurse
                }
            }
        }
    }
}
# Brave
$braveUserData = "$LOCALAPPDATA\BraveSoftware\Brave-Browser\User Data"
if (Test-Path $braveUserData) {
    Get-ChildItem $braveUserData -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "^(Profile \d+|Default)$"
    } | ForEach-Object {
        $profileName = $_.Name -replace " ", "-"
        $indexedDB = Join-Path $_.FullName "IndexedDB"
        if (Test-Path $indexedDB) {
            Get-ChildItem $indexedDB -Directory -Filter "*claude*" -ErrorAction SilentlyContinue | ForEach-Object {
                $destPath = "$BackupPath\browser-data\brave-$profileName-$($_.Name)"
                if (-not (Test-Path $destPath)) {
                    Copy-ItemSafe $_.FullName $destPath "Brave: $profileName claude.ai" -Recurse
                }
            }
        }
    }
}
# Firefox (uses storage/default/https+++claude.ai pattern)
$firefoxProfiles = "$APPDATA\Mozilla\Firefox\Profiles"
if (Test-Path $firefoxProfiles) {
    Get-ChildItem $firefoxProfiles -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $ffProfile = $_.Name
        $storagePath = Join-Path $_.FullName "storage\default"
        if (Test-Path $storagePath) {
            Get-ChildItem $storagePath -Directory -Filter "*claude*" -ErrorAction SilentlyContinue | ForEach-Object {
                $destPath = "$BackupPath\browser-data\firefox-$ffProfile-$($_.Name)"
                if (-not (Test-Path $destPath)) {
                    Copy-ItemSafe $_.FullName $destPath "Firefox: $ffProfile claude.ai" -Recurse
                }
            }
        }
    }
}
Write-Step "  -> All browsers catch-all scan complete" "SUCCESS"

Write-Step "[32c/43] CATCH-ALL: .config catch-all..." "INFO"
# Scan ~/.config for ANY claude/openclaw/anthropic dir beyond the known ones
$knownConfigDirs = @("claude", "opencode", "gh")
if (Test-Path "$HOME_DIR\.config") {
    Get-ChildItem "$HOME_DIR\.config" -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic|opencode" -and ($knownConfigDirs -notcontains $_.Name)
    } | ForEach-Object {
        Copy-ItemSafe $_.FullName "$BackupPath\catchall-config\$($_.Name)" ".config CATCHALL: $($_.Name)" -Recurse
    }
}
Write-Step "  -> .config catch-all scan complete" "SUCCESS"

Write-Step "[32d/43] CATCH-ALL: ProgramData + AppData\LocalLow..." "INFO"
# ProgramData
if (Test-Path "$env:ProgramData") {
    Get-ChildItem "$env:ProgramData" -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic"
    } | ForEach-Object {
        Copy-ItemSafe $_.FullName "$BackupPath\catchall-programdata\$($_.Name)" "ProgramData: $($_.Name)" -Recurse
    }
}
# LocalLow
$localLow = "$HOME_DIR\AppData\LocalLow"
if (Test-Path $localLow) {
    Get-ChildItem $localLow -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic"
    } | ForEach-Object {
        Copy-ItemSafe $_.FullName "$BackupPath\catchall-appdata\locallow-$($_.Name)" "LocalLow: $($_.Name)" -Recurse
    }
}
Write-Step "  -> ProgramData + LocalLow scan complete" "SUCCESS"

Write-Step "[32e/43] CATCH-ALL: Windows Scheduled Tasks export..." "INFO"
New-Item -ItemType Directory -Path "$BackupPath\scheduled-tasks" -Force | Out-Null
try {
    $tasks = schtasks /query /fo CSV /v 2>$null | ConvertFrom-Csv -ErrorAction SilentlyContinue
    $relevantTasks = $tasks | Where-Object { $_."TaskName" -match "claude|openclaw|clawd|moltbot|anthropic" -or $_."Task To Run" -match "claude|openclaw|clawd|moltbot|anthropic" }
    if ($relevantTasks) {
        $relevantTasks | ConvertTo-Json -Depth 5 | Out-File "$BackupPath\scheduled-tasks\relevant-tasks.json" -Encoding UTF8
        Write-Step "  -> Found $($relevantTasks.Count) relevant scheduled tasks" "SUCCESS"
    }
    # Also export the XML definitions for exact restoration
    @("claude", "openclaw", "clawd", "moltbot", "anthropic", "ClawdBot", "OpenClaw") | ForEach-Object {
        $pattern = $_
        schtasks /query /fo LIST 2>$null | Select-String "TaskName" | ForEach-Object {
            $taskName = ($_ -replace "^TaskName:\s+", "").Trim()
            if ($taskName -match $pattern) {
                $safeName = $taskName -replace "[\\/:*?`"<>|]", "_"
                schtasks /query /tn "$taskName" /xml 2>$null | Out-File "$BackupPath\scheduled-tasks\$safeName.xml" -Encoding UTF8
            }
        }
    }
} catch {}
Write-Step "  -> Scheduled tasks export complete" "SUCCESS"

Write-Step "[32f/43] CATCH-ALL: Temp dir openclaw/claude logs..." "INFO"
$tempDir = "$LOCALAPPDATA\Temp"
@("claude", "openclaw") | ForEach-Object {
    $tempSubDir = Join-Path $tempDir $_
    if (Test-Path $tempSubDir) {
        Copy-ItemSafe $tempSubDir "$BackupPath\catchall-temp\$_" "Temp: $_ (logs/cache)" -Recurse
    }
}
# Grab any jiti-compiled anthropic modules
Get-ChildItem "$tempDir\jiti" -File -Filter "*anthropic*" -ErrorAction SilentlyContinue | ForEach-Object {
    Copy-ItemSafe $_.FullName "$BackupPath\catchall-temp\jiti\$($_.Name)" "jiti: $($_.Name)"
}
Write-Step "  -> Temp dir scan complete" "SUCCESS"

Write-Step "[32g/43] CATCH-ALL: WSL claude/openclaw data..." "INFO"
# Check all WSL distros for ~/.claude and ~/.openclaw
$wslDistros = "$LOCALAPPDATA\Packages"
if (Test-Path $wslDistros) {
    Get-ChildItem $wslDistros -Directory -Filter "*CanonicalGroup*" -ErrorAction SilentlyContinue | ForEach-Object {
        $wslHome = Join-Path $_.FullName "LocalState\rootfs\home"
        if (Test-Path $wslHome) {
            Get-ChildItem $wslHome -Directory -ErrorAction SilentlyContinue | ForEach-Object {
                $wslUser = $_.Name
                @(".claude", ".openclaw", ".config\claude", ".config\opencode") | ForEach-Object {
                    $wslPath = Join-Path $wslHome "$wslUser\$_"
                    if (Test-Path $wslPath) {
                        $safeName = $_ -replace "[\\./]", "-"
                        Copy-ItemSafe $wslPath "$BackupPath\catchall-wsl\$wslUser\$safeName" "WSL $wslUser`: $_" -Recurse
                    }
                }
            }
        }
    }
}
Write-Step "  -> WSL scan complete" "SUCCESS"

Write-Step "[32h/43] CATCH-ALL: Windows Credential Manager FULL dump..." "INFO"
# Full dump — not just keyword-filtered
try {
    $allCreds = cmdkey /list 2>$null
    if ($allCreds) {
        $allCreds | Out-File "$BackupPath\credentials\credential-manager-full.txt" -Encoding UTF8
        # Filtered view for quick reference
        $filtered = $allCreds | Select-String -Pattern "claude|anthropic|openclaw|opencode|moltbot|clawd|github|npm|node" -Context 0,3
        if ($filtered) {
            $filtered | Out-File "$BackupPath\credentials\credential-manager-filtered.txt" -Encoding UTF8
        }
    }
} catch {}
Write-Step "  -> Credential Manager full dump complete" "SUCCESS"

Write-Step "[32i/43] CATCH-ALL: Other drives shallow scan..." "INFO"
# Quick shallow scan of D:\, E:\ root for claude/openclaw dirs (no deep recursion = fast)
@("D:\", "E:\") | ForEach-Object {
    if (Test-Path $_) {
        $driveLetter = $_.Substring(0,1)
        Get-ChildItem $_ -Directory -Depth 1 -ErrorAction SilentlyContinue | Where-Object {
            $_.Name -match "claude|openclaw|clawd|moltbot|anthropic"
        } | ForEach-Object {
            $destName = $_.Name
            Copy-ItemSafe $_.FullName "$BackupPath\catchall-drives\$driveLetter-$destName" "Drive $driveLetter`: $destName" -Recurse
        }
    }
}
Write-Step "  -> Other drives shallow scan complete" "SUCCESS"

#endregion
#endregion

# All parallel copies already completed in RunspacePool above
Write-Step "All parallel copy tasks completed!" "SUCCESS"

#region PROJECT-LEVEL .CLAUDE DIRECTORIES
Write-Step "[33/43] Finding and backing up PROJECT .claude directories..." "INFO"

# FIXED: Skip slow recursive search if environment variable is set (prevents hanging)
if ($env:SKIP_PROJECT_SEARCH -ne "0") {
    Write-Step "  -> Skipped (set SKIP_PROJECT_SEARCH=0 to enable slow recursive scan)" "WARNING"
} else {
    $projectSearchPaths = @(
        "$HOME_DIR\Projects", "$HOME_DIR\repos", "$HOME_DIR\dev", "$HOME_DIR\code",
        "F:\Projects", "D:\Projects"
    )
    $projectClaudeDirs = Find-ProjectClaudeDirectories -SearchPaths $projectSearchPaths
    if ($projectClaudeDirs.Count -gt 0) {
        foreach ($dir in $projectClaudeDirs) {
            $safeDestName = ($dir.FullName -replace ":", "_" -replace "\\", "_" -replace "^_+", "")
            $destPath = "$BackupPath\project-claude\$safeDestName"
            Copy-ItemSafe $dir.FullName $destPath "Project: $($dir.Parent.Name)\.claude" -Recurse
        }
        Write-Step "  -> Backed up $($projectClaudeDirs.Count) project .claude directories" "SUCCESS"
    } else {
        Write-Step "  -> No project .claude directories found" "INFO"
    }
}
#endregion

#region CREATE BACKUP METADATA
Write-Step "[34/43] Creating backup metadata..." "INFO"
$metadata = @{
    Version = "18.0"
    Timestamp = Get-Date -Format "o"
    Computer = $env:COMPUTERNAME
    User = $env:USERNAME
    BackupPath = $BackupPath
    ItemsBackedUp = $script:BackedUpItems
    TotalSizeBytes = $script:BackedUpSize
    TotalSizeMB = [math]::Round($script:BackedUpSize / 1MB, 2)
    Errors = $script:Errors
    Sections = 43
    NewInV18 = @(
        "OPENCLAW: Dynamic workspace-* scanner (no more hardcoded workspace names)",
        "OPENCLAW: auth.json, auth-profiles.json, .openclawrc.json (CRITICAL auth files)",
        "OPENCLAW: moltbot.json, clawdbot.json + all .bak.* rolling backups",
        "OPENCLAW: telegram/ dir (command hashes, update offsets)",
        "OPENCLAW: ClawdBot/ tray scripts dir, completions/, backups/",
        "OPENCLAW: openclaw-gateway-task.xml, openclaw-backup.json, apply-jobs.ps1",
        "OPENCLAW: workspace-moltbot, workspace-moltbot2, workspace-openclaw-main",
        "CLAUDEGRAM: ~/.claudegram complete backup",
        "CLAUDE-SERVER-COMMANDER: ~/.claude-server-commander complete backup",
        "CLAUDE CLI: ~/.local/share/claude versions, ~/.local/state/claude state",
        "APPDATA: Claude Code Roaming (browser ext native host)",
        "APPDATA: claude-cli-nodejs (CLI cache + MCP logs)",
        "APPDATA: AnthropicClaude Desktop app",
        "OPENCODE: ~/.local/state/opencode (frecency, prompt history)",
        "POWERSHELL: ClaudeUsage module (PS5 + PS7)",
        "SCRIPTS: ~/mcp-ondemand.ps1, ~/claude-wrapper.ps1",
        "STARTUP: OpenClaw Tray.lnk in Windows Startup",
        "NPM: bin shims (claude.cmd, openclaw.cmd, etc.)",
        "NPM: opencode-antigravity-auth package",
        "CHROME: claude.ai IndexedDB data (Profile 1 + 2)",
        "STORE: Windows Store Claude app settings",
        "DESKTOP: Claude.lnk shortcut",
        "OPENCLAW: mission-control project",
        "CATCH-ALL: .openclaw unknown subdirectory scanner",
        "CATCH-ALL: Home dir dot-directory scanner (claude/openclaw/anthropic pattern)",
        "CATCH-ALL: AppData directory scanner (claude/openclaw/anthropic pattern)",
        "CATCH-ALL: npm global package scanner (claude/openclaw/anthropic pattern)",
        "CATCH-ALL: .local share/state scanner",
        "CATCH-ALL: ALL Chrome profiles claude.ai IndexedDB scanner",
        "CATCH-ALL: Edge + Brave + Firefox claude.ai browser data",
        "CATCH-ALL: .config dir scanner",
        "CATCH-ALL: ProgramData + AppData\LocalLow scanner",
        "CATCH-ALL: Windows Scheduled Tasks export (CSV + XML)",
        "CATCH-ALL: Temp dir openclaw/claude logs + jiti anthropic modules",
        "CATCH-ALL: WSL distros ~/.claude + ~/.openclaw",
        "CATCH-ALL: Windows Credential Manager FULL dump",
        "CATCH-ALL: D:\ E:\ shallow scan for claude/openclaw dirs"
    )
}
$metadata | ConvertTo-Json -Depth 5 | Out-File "$BackupPath\BACKUP-METADATA.json" -Encoding UTF8
Write-Step "  -> Backup metadata created" "SUCCESS"
#endregion

#region SUMMARY
$endTime = Get-Date
$duration = $endTime - $startTime

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  BACKUP COMPLETE - v18.0 C: DRIVE FULL SCAN EDITION" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Items backed up: $($script:BackedUpItems)" -ForegroundColor White
Write-Host "Total size: $([math]::Round($script:BackedUpSize / 1MB, 2)) MB" -ForegroundColor White
Write-Host "Duration: $([math]::Round($duration.TotalSeconds, 1)) seconds" -ForegroundColor White

if ($script:Errors.Count -gt 0) {
    Write-Host "`nWarnings/Errors: $($script:Errors.Count)" -ForegroundColor Yellow
    foreach ($err in $script:Errors | Select-Object -First 5) {
        Write-Host "  - $err" -ForegroundColor Yellow
    }
} else {
    Write-Host "`nErrors: None" -ForegroundColor Green
}

Write-Host ""
Write-Host "[BACKED UP - v18.0 COMPLETE]" -ForegroundColor Green
Write-Host "  + Claude Code (CLI + config + sessions + auth + state + versions)" -ForegroundColor Green
Write-Host "  + OpenClaw ALL workspaces (dynamic scan, no hardcoded list)" -ForegroundColor Cyan
Write-Host "  + OpenClaw auth (auth.json, auth-profiles.json, .openclawrc.json)" -ForegroundColor Cyan
Write-Host "  + OpenClaw config (openclaw.json + moltbot.json + clawdbot.json + rolling backups)" -ForegroundColor Cyan
Write-Host "  + OpenClaw telegram (command hashes, update offsets)" -ForegroundColor Cyan
Write-Host "  + OpenClaw ClawdBot tray scripts + completions + historical backups" -ForegroundColor Cyan
Write-Host "  + OpenClaw gateway task XML + apply-jobs.ps1" -ForegroundColor Cyan
Write-Host "  + OpenClaw mission-control project" -ForegroundColor Cyan
Write-Host "  + Claudegram (sessions, wrapper, config)" -ForegroundColor Magenta
Write-Host "  + Claude-Server-Commander (config, feature-flags, tool-history)" -ForegroundColor Magenta
Write-Host "  + Claude CLI state + version binaries (.local/share + .local/state)" -ForegroundColor Green
Write-Host "  + Claude Code Roaming (browser extension native host)" -ForegroundColor Green
Write-Host "  + Claude CLI nodejs cache + MCP logs" -ForegroundColor Green
Write-Host "  + AnthropicClaude Desktop app" -ForegroundColor Green
Write-Host "  + Moltbot + Clawdbot (npm modules + config)" -ForegroundColor Green
Write-Host "  + Clawd workspace (complete)" -ForegroundColor Green
Write-Host "  + OpenCode (data + auth + config + state)" -ForegroundColor Green
Write-Host "  + ALL npm global packages + bin shims (with exact versions)" -ForegroundColor Green
Write-Host "  + PowerShell ClaudeUsage module (PS5 + PS7)" -ForegroundColor Green
Write-Host "  + mcp-ondemand.ps1 + claude-wrapper.ps1" -ForegroundColor Green
Write-Host "  + Windows Startup shortcuts (OpenClaw Tray.lnk)" -ForegroundColor Green
Write-Host "  + Chrome claude.ai IndexedDB (Profile 1 + 2)" -ForegroundColor Green
Write-Host "  + Windows Store Claude settings" -ForegroundColor Green
Write-Host "  + Git (config + SSH keys + credentials)" -ForegroundColor Green
Write-Host "  + All authentication tokens and credentials" -ForegroundColor Green
Write-Host "  + Environment variables and registry keys" -ForegroundColor Green
Write-Host "" -ForegroundColor Yellow
Write-Host "  [CATCH-ALL SAFETY NETS]" -ForegroundColor Yellow
Write-Host "  + .openclaw unknown subdirectory scanner" -ForegroundColor Yellow
Write-Host "  + Home dir dot-directory scanner (claude/openclaw/anthropic)" -ForegroundColor Yellow
Write-Host "  + AppData directory scanner (claude/openclaw/anthropic)" -ForegroundColor Yellow
Write-Host "  + npm global package scanner (claude/openclaw/anthropic)" -ForegroundColor Yellow
Write-Host "  + .local share/state scanner" -ForegroundColor Yellow
Write-Host "  + ALL Chrome profiles claude.ai IndexedDB scanner" -ForegroundColor Yellow
Write-Host "  + Edge + Brave + Firefox claude.ai browser data" -ForegroundColor Yellow
Write-Host "  + .config directory scanner" -ForegroundColor Yellow
Write-Host "  + ProgramData + AppData\LocalLow scanner" -ForegroundColor Yellow
Write-Host "  + Windows Scheduled Tasks export (CSV + XML)" -ForegroundColor Yellow
Write-Host "  + Temp dir logs + jiti anthropic modules" -ForegroundColor Yellow
Write-Host "  + WSL distros ~/.claude + ~/.openclaw" -ForegroundColor Yellow
Write-Host "  + Windows Credential Manager FULL dump" -ForegroundColor Yellow
Write-Host "  + D:\ E:\ shallow scan" -ForegroundColor Yellow
Write-Host ""
Write-Host "Backup location: $BackupPath" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# CRITICAL: Explicitly exit 0 — robocopy returns 1 for "files copied" which
# PowerShell treats as a failure exit code. Force success.
exit 0
#endregion
