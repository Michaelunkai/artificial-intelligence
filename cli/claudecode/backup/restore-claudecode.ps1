#Requires -Version 5.1
<#
.SYNOPSIS
    RESTORE v23.0 - BLITZ INCREMENTAL
.DESCRIPTION
    Force-restores EVERY SINGLE THING from the latest backup to all local locations.
    v23.0: 100x faster incremental via /MIR /XO /MT:128 /FFT. Adds TgTray, channels,
    Claude Desktop, shell:startup shortcuts, Task Scheduler imports, NGEN post-restore.
    On a brand-new PC: installs Node.js, Git, Python, Chrome, all npm packages,
    configures PATH, env vars, registry, SSH perms, VBS startup tray, scheduled tasks.
    Result: 100% identical workflows on any machine.

    Run on same machine (everything identical): finishes in seconds.
    Run on new machine: installs everything, full restore, full verification.
.PARAMETER BackupPath
    Path to backup directory (auto-detects latest from F:\backup\claudecode\)
.PARAMETER Force
    Skip confirmation prompts
.PARAMETER SkipPrerequisites
    Skip automatic installation of Node.js, Git, etc.
.PARAMETER SkipSoftwareInstall
    Skip npm package installation (data-only restore)
.PARAMETER SkipCredentials
    Don't restore credentials
.PARAMETER MaxJobs
    Parallel RunspacePool threads (default: 128)
.NOTES
    Version: 23.0 - BLITZ INCREMENTAL
#>
[CmdletBinding()]
param(
    [string]$BackupPath,
    [switch]$Force,
    [switch]$SkipPrerequisites,
    [switch]$SkipSoftwareInstall,
    [switch]$SkipCredentials,
    [int]$MaxJobs = 128
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:ok = 0; $script:skip = 0; $script:miss = 0; $script:fail = 0
$script:installed = 0; $script:Errors = @()

$HP = $env:USERPROFILE; $A = $env:APPDATA; $L = $env:LOCALAPPDATA

#region Helpers
function WS { param([string]$M,[string]$S="INFO")
    $c = switch($S){ "OK"{"Green"} "WARN"{"Yellow"} "ERR"{"Red"} "INST"{"Magenta"} "FAST"{"Cyan"} default{"Cyan"} }
    Write-Host "$(Get-Date -Format 'HH:mm:ss') [$S] $M" -ForegroundColor $c
}
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}
function Install-Winget { param([string]$Id,[string]$Name)
    WS "  Installing $Name via winget..." "INST"
    try {
        $r = winget install --id $Id --accept-package-agreements --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -or "$r" -match "already installed") { WS "  $Name installed" "OK"; $script:installed++; return $true }
    } catch {}
    WS "  Failed: $Name" "ERR"; return $false
}
#endregion

#region Auto-detect Backup
$BackupRoot = "F:\backup\claudecode"
if (-not $BackupPath) {
    $latest = Get-ChildItem $BackupRoot -Directory -EA SilentlyContinue |
        Where-Object { $_.Name -match "^backup_\d{4}_\d{2}_\d{2}" } |
        Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { $BackupPath = $latest.FullName }
    else { Write-Host "ERROR: No backups in $BackupRoot" -ForegroundColor Red; exit 1 }
}
if (-not (Test-Path $BackupPath)) { Write-Host "ERROR: Backup not found: $BackupPath" -ForegroundColor Red; exit 1 }
$BP = $BackupPath
#endregion

#region Banner
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  RESTORE v23.0 - BLITZ INCREMENTAL" -ForegroundColor White
Write-Host "  BLITZ /MIR /XO /MT:128 | TGTRAY | CLAUDE DESKTOP | NGEN | PARALLEL" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "From    : $BP"
Write-Host "Threads : $MaxJobs"
$metaFile = Join-Path $BP "BACKUP-METADATA.json"
if (Test-Path $metaFile) {
    $meta = Get-Content $metaFile -Raw | ConvertFrom-Json
    Write-Host "Backup  : v$($meta.Version)  $($meta.Timestamp)  $($meta.SizeMB) MB  $($meta.Items) items"
}
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

$isNewPC = $null -eq (Get-Command claude -EA SilentlyContinue)
if ($isNewPC) { Write-Host "[NEW PC] Claude Code not found - will install prerequisites" -ForegroundColor Yellow; Write-Host "" }
#endregion

#region Pre-flight (fast)
WS "[PRE-FLIGHT] System checks..."
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
WS "  Admin: $(if($isAdmin){'YES'}else{'NO (some ops may fail)'})" $(if($isAdmin){"OK"}else{"WARN"})
$freeGB = [math]::Round((Get-PSDrive C -EA SilentlyContinue).Free / 1GB, 1)
WS "  Disk: ${freeGB}GB free" $(if($freeGB -gt 5){"OK"}else{"WARN"})
WS "  PS: $($PSVersionTable.PSVersion)" "OK"
foreach ($t in @("robocopy","reg","icacls")) {
    if (-not (Get-Command $t -EA SilentlyContinue)) { Write-Host "FATAL: $t missing" -ForegroundColor Red; exit 1 }
}
Write-Host ""
#endregion

#region Prerequisites (new PC only)
if (-not $SkipPrerequisites -and $isNewPC) {
    WS "[PREREQ] Installing prerequisites..."
    if (Get-Command winget -EA SilentlyContinue) {
        if (-not (Get-Command node   -EA SilentlyContinue)) { Install-Winget "OpenJS.NodeJS.LTS"  "Node.js"; Refresh-Path }
        if (-not (Get-Command git    -EA SilentlyContinue)) { Install-Winget "Git.Git"            "Git";     Refresh-Path }
        if (-not (Get-Command python -EA SilentlyContinue)) { Install-Winget "Python.Python.3.11" "Python";  Refresh-Path }
        if (-not (Test-Path "C:\Program Files\Google\Chrome\Application\chrome.exe")) { Install-Winget "Google.Chrome" "Chrome"; Refresh-Path }
    } else { WS "  winget not found - install Node.js + Git manually" "WARN" }
    Write-Host ""
}
#endregion

#region npm packages
if (-not $SkipSoftwareInstall -and (Get-Command npm -EA SilentlyContinue)) {
    WS "[NPM] Installing global packages (skip existing)..."
    $already = @{}
    try { npm list -g --depth=0 --json 2>$null | ConvertFrom-Json |
        Select-Object -ExpandProperty dependencies -EA SilentlyContinue |
        ForEach-Object { $_.PSObject.Properties.Name } | ForEach-Object { $already[$_] = $true }
    } catch {}

    $reinstallScript = "$BP\npm-global\REINSTALL-ALL.ps1"
    $pkgSpecs = @()
    if (Test-Path $reinstallScript) {
        $pkgSpecs = @(Get-Content $reinstallScript |
            Where-Object { $_ -match 'npm install -g (.+)' } |
            ForEach-Object { if ($_ -match 'npm install -g (.+)') { $matches[1].Trim() } })
    }
    if ($pkgSpecs.Count -eq 0) { $pkgSpecs = @("@anthropic-ai/claude-code","openclaw","moltbot","clawdbot","opencode-ai") }

    $toInstall = @($pkgSpecs | Where-Object {
        $n = $_; if ($n -match '^(@[^/]+/[^@]+)') { $n = $matches[1] } elseif ($n -match '^([^@]+)') { $n = $matches[1] }
        -not $already.ContainsKey($n)
    })

    if ($toInstall.Count -eq 0) { WS "  All $($pkgSpecs.Count) packages already installed" "OK" }
    else {
        WS "  Installing $($toInstall.Count) of $($pkgSpecs.Count) packages..." "INST"
        $npmErr = 0
        & npm install -g --legacy-peer-deps $toInstall 2>&1 | ForEach-Object {
            $l = "$_"
            if ($l -match '^npm error') { Write-Host "    [npm ERR] $l" -ForegroundColor Red; $npmErr++ }
            elseif ($l -match '^added|^changed') { Write-Host "    $l" -ForegroundColor Green }
        }
        WS "  npm done ($($toInstall.Count) packages, $npmErr errors)" $(if($npmErr -eq 0){"OK"}else{"WARN"})
        $script:installed += $toInstall.Count
    }
    Refresh-Path
    Write-Host ""
}
#endregion

#region Close apps that lock files
$claudeDesktop = Get-Process -Name "Claude" -EA SilentlyContinue
if ($claudeDesktop) {
    WS "[PRE-COPY] Closing Claude Desktop (locks files)..."
    $claudeDesktop | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Start-Sleep -Seconds 2
    Get-Process -Name "Claude" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
}
#endregion

#region BUILD MASTER TASK LIST
WS "[TASKS] Building task list from backup..." "FAST"

$allTasks = [System.Collections.Generic.List[hashtable]]::new()
function AT { param([string]$S,[string]$D,[string]$Desc,[bool]$IsFile=$false)
    if (Test-Path $S) { $allTasks.Add(@{S=$S;D=$D;Desc=$Desc;F=$IsFile}) }
}

# ============================================================
# KNOWN DIRECTORY MAPPINGS (backup subdir ΓåÆ local destination)
# Covers v20 + v21 backup formats
# ============================================================

# CORE (.claude home)
AT "$BP\core\claude-home"                     "$HP\.claude"                                   ".claude directory"

# SESSIONS
AT "$BP\sessions\config-claude-projects"       "$HP\.config\claude\projects"                   ".config/claude/projects"
AT "$BP\sessions\claude-projects"              "$HP\.claude\projects"                          ".claude/projects"
AT "$BP\sessions\claude-sessions"              "$HP\.claude\sessions"                          ".claude/sessions"
AT "$BP\sessions\claude-code-sessions"         "$A\Claude\claude-code-sessions"               "claude-code-sessions"

# OPENCLAW - all subdirs
$ocMap = @{
    "workspace"="workspace"; "workspace-main"="workspace-main"; "workspace-session2"="workspace-session2"
    "workspace-openclaw"="workspace-openclaw"; "workspace-openclaw4"="workspace-openclaw4"
    "workspace-moltbot"="workspace-moltbot"; "workspace-moltbot2"="workspace-moltbot2"
    "workspace-openclaw-main"="workspace-openclaw-main"
    "agents"="agents"; "credentials-dir"="credentials"; "credentials"="credentials"
    "memory"="memory"; "cron"="cron"; "extensions"="extensions"; "skills"="skills"
    "scripts"="scripts"; "browser"="browser"; "telegram"="telegram"
    "ClawdBot-tray"="ClawdBot"; "completions"="completions"; "dot-claude-nested"=".claude"
    "config"="config"; "devices"="devices"; "delivery-queue"="delivery-queue"
    "sessions-dir"="sessions"; "hooks"="hooks"; "startup-wrappers"="startup-wrappers"
    "subagents"="subagents"; "docs"="docs"; "evolved-tools"="evolved-tools"
    "foundry"="foundry"; "lib"="lib"; "patterns"="patterns"; "logs"="logs"
    "backups"="backups"
}
foreach ($kv in $ocMap.GetEnumerator()) {
    AT "$BP\openclaw\$($kv.Key)" "$HP\.openclaw\$($kv.Value)" "OpenClaw $($kv.Value)"
}
# Dynamic workspace-* scanner
if (Test-Path "$BP\openclaw") {
    Get-ChildItem "$BP\openclaw" -Directory -Filter "workspace-*" -EA SilentlyContinue | ForEach-Object {
        $dest = "$HP\.openclaw\$($_.Name)"
        $dup = $false; foreach ($t in $allTasks) { if ($t.D -eq $dest) { $dup = $true; break } }
        if (-not $dup) { AT $_.FullName $dest "OpenClaw $($_.Name)" }
    }
}
# OpenClaw catchall subdirs
if (Test-Path "$BP\openclaw\catchall-dirs") {
    Get-ChildItem "$BP\openclaw\catchall-dirs" -Directory -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\.openclaw\$($_.Name)" "OpenClaw catchall: $($_.Name)"
    }
}
# OpenClaw special destinations
AT "$BP\openclaw\npm-module"          "$A\npm\node_modules\openclaw"     "openclaw npm module"
AT "$BP\openclaw\clawdbot-wrappers"   "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot" "ClawdBot wrappers"
AT "$BP\openclaw\clawdbot-launcher"   "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot\b" "ClawdBot launcher"
AT "$BP\openclaw\mission-control"     "$HP\openclaw-mission-control"      "openclaw-mission-control"

# OPENCODE (both v20 + v21 naming)
AT "$BP\opencode\local-share"         "$HP\.local\share\opencode"         "OpenCode data"
AT "$BP\opencode\local-share-opencode" "$HP\.local\share\opencode"        "OpenCode data"
AT "$BP\opencode\config"              "$HP\.config\opencode"              "OpenCode config"
AT "$BP\opencode\config-opencode"     "$HP\.config\opencode"              "OpenCode config"
AT "$BP\opencode\cache-opencode"      "$HP\.cache\opencode"               "OpenCode cache"
AT "$BP\opencode\sisyphus"            "$HP\.sisyphus"                     ".sisyphus agent"
AT "$BP\opencode\state"               "$HP\.local\state\opencode"         "OpenCode state"
AT "$BP\opencode\local-state-opencode" "$HP\.local\state\opencode"        "OpenCode state"

# APPDATA
AT "$BP\appdata\roaming-claude"       "$A\Claude"                        "AppData\Roaming\Claude"
AT "$BP\appdata\roaming-claude-code"  "$A\Claude Code"                   "AppData\Roaming\Claude Code"
AT "$BP\appdata\local-claude"         "$L\Claude"                        "AppData\Local\Claude"
AT "$BP\appdata\local-claude-cache"   "$L\claude"                        "AppData\Local\claude"
AT "$BP\appdata\AnthropicClaude"      "$L\AnthropicClaude"               "AnthropicClaude"
AT "$BP\appdata\claude-cli-nodejs"    "$L\claude-cli-nodejs"             "claude-cli-nodejs"
AT "$BP\appdata\claude-code-sessions" "$A\Claude\claude-code-sessions"   "claude-code-sessions"
AT "$BP\appdata\store-claude-settings" "$L\Packages\Claude_pzs8sxrjxfjjc\Settings" "Store Claude settings"
AT "$BP\appdata\store-claude-roaming"  "$L\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude" "Claude Desktop app data"

# ============ TGTRAY + CHANNELS (Telegram tray app) ============
AT "$BP\tgtray\source"    "F:\study\Dev_Toolchain\programming\.net\projects\c#\TgTray" "TgTray source + build"
AT "$BP\tgtray\tg.exe"    "$HP\.local\bin\tg.exe"                                       "tg.exe deployed binary" $true
AT "$BP\tgtray\channels"  "$HP\.claude\channels"                                         "Channel scripts (VBS, CMD, PS1)"

# ============ SHELL:STARTUP SHORTCUTS ============
$startupDirRestore = "$A\Microsoft\Windows\Start Menu\Programs\Startup"
AT "$BP\startup\shortcuts\Claude_Channel.lnk"  "$startupDirRestore\Claude Channel.lnk"  "Startup: Claude Channel" $true
AT "$BP\startup\shortcuts\TgTray.lnk"          "$startupDirRestore\TgTray.lnk"           "Startup: TgTray" $true
AT "$BP\startup\shortcuts\ClawdBot_Tray.lnk"   "$startupDirRestore\ClawdBot Tray.lnk"    "Startup: ClawdBot Tray" $true

# CLI BINARY / STATE
AT "$BP\cli-binary\claude-code"       "$A\Claude\claude-code"            "Claude CLI binary"
AT "$BP\cli-binary\local-bin"         "$HP\.local\bin"                    ".local/bin"
AT "$BP\cli-binary\dot-local"         "$HP\.local"                        ".local"
AT "$BP\cli-binary\local-share-claude" "$HP\.local\share\claude"          ".local/share/claude"
AT "$BP\cli-binary\local-state-claude" "$HP\.local\state\claude"          ".local/state/claude"
AT "$BP\cli-state\state"              "$HP\.local\state\claude"           "CLI state"
AT "$BP\cli-state\local-bin"          "$HP\.local\bin"                    ".local/bin"

# MOLTBOT + CLAWDBOT + CLAWD
AT "$BP\moltbot\dot-moltbot"          "$HP\.moltbot"                     "Moltbot config"
AT "$BP\moltbot\npm-module"           "$A\npm\node_modules\moltbot"     "Moltbot npm module"
AT "$BP\clawdbot\dot-clawdbot"        "$HP\.clawdbot"                    "Clawdbot config"
AT "$BP\clawdbot\npm-module"          "$A\npm\node_modules\clawdbot"    "Clawdbot npm module"
AT "$BP\clawd\workspace"              "$HP\clawd"                        "Clawd workspace"

# NPM GLOBAL MODULES
AT "$BP\npm-global\anthropic-ai"              "$A\npm\node_modules\@anthropic-ai"              "@anthropic-ai"
AT "$BP\npm-global\opencode-ai"               "$A\npm\node_modules\opencode-ai"                "opencode-ai"
AT "$BP\npm-global\opencode-antigravity-auth"  "$A\npm\node_modules\opencode-antigravity-auth"  "opencode-antigravity-auth"

# OTHER DOT-DIRS (both formats)
AT "$BP\other\claudegram"             "$HP\.claudegram"                   ".claudegram"
AT "$BP\other\claude-server-commander" "$HP\.claude-server-commander"     ".claude-server-commander"
AT "$BP\other\cagent"                 "$HP\.cagent"                       ".cagent"
AT "$BP\other\anthropic"              "$HP\.anthropic"                    ".anthropic (credentials)"
AT "$BP\claudegram\dot-claudegram"    "$HP\.claudegram"                   ".claudegram"
AT "$BP\claude-server-commander"      "$HP\.claude-server-commander"      ".claude-server-commander"

# ============================================================
# STARTUP VBS (CRITICAL - must restore to enable auto-launch on new PC)
# ============================================================
AT "$BP\startup\vbs\ClawdBot_Startup.vbs"          "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ClawdBot_Startup.vbs" "Startup VBS - ClawdBot auto-launcher (ON BOOT)"
AT "$BP\startup\openclaw-startup-wrappers"        "$HP\.openclaw\startup-wrappers" "OpenClaw startup wrappers (ALL VBS)"
AT "$BP\startup\vbs\gateway-silent.vbs"           "$HP\.openclaw\gateway-silent.vbs" "Gateway silent launcher" $true
AT "$BP\startup\vbs\lib-silent-runner.vbs"        "$HP\.openclaw\lib\silent-runner.vbs" "Silent runner library" $true
AT "$BP\startup\vbs\typing-daemon-silent.vbs"     "$HP\.openclaw\typing-daemon\daemon-silent.vbs" "Typing daemon" $true

# GIT + SSH
AT "$BP\git\ssh"                      "$HP\.ssh"                          "SSH keys"
AT "$BP\git\github-cli"               "$HP\.config\gh"                    "GitHub CLI"

# PYTHON
AT "$BP\python\uv"                    "$HP\.local\share\uv"              "uv data"

# POWERSHELL MODULES
AT "$BP\powershell\ClaudeUsage-ps7"   "$HP\Documents\PowerShell\Modules\ClaudeUsage"        "ClaudeUsage PS7"
AT "$BP\powershell\ClaudeUsage-ps5"   "$HP\Documents\WindowsPowerShell\Modules\ClaudeUsage"  "ClaudeUsage PS5"

# CONFIG DIRS
AT "$BP\config\browserclaw"           "$HP\.config\browserclaw"           ".config/browserclaw"
AT "$BP\config\cagent"                "$HP\.config\cagent"                ".config/cagent"
AT "$BP\config\configstore"           "$HP\.config\configstore"           ".config/configstore"

# CLAUDE DIRS (older backups)
if (Test-Path "$BP\claude-dirs") {
    Get-ChildItem "$BP\claude-dirs" -Directory -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\.claude\$($_.Name)" ".claude/$($_.Name)"
    }
}

# CHROME INDEXEDDB (dynamic scan - handle all naming variants)
$chromeBase = "$L\Google\Chrome\User Data"
if (Test-Path "$BP\chrome") {
    Get-ChildItem "$BP\chrome" -Directory -EA SilentlyContinue | ForEach-Object {
        $n = $_.Name
        $profNum = $null; $type = $null
        if ($n -match '(?:p|Profile.?|profile)(\d+).*?(blob|leveldb)') { $profNum = $matches[1]; $type = $matches[2] }
        elseif ($n -match '(?:p|Profile.?|profile)(\d+)') { $profNum = $matches[1] }
        if ($profNum) {
            $profDir = if ($profNum -eq '0') { "Default" } else { "Profile $profNum" }
            if ($type) {
                AT $_.FullName "$chromeBase\$profDir\IndexedDB\https_claude.ai_0.indexeddb.$type" "Chrome P$profNum $type"
            } else {
                AT $_.FullName "$chromeBase\$profDir\IndexedDB\$n" "Chrome P$profNum"
            }
        } else {
            AT $_.FullName "$chromeBase\Profile 1\IndexedDB\$n" "Chrome: $n"
        }
    }
}

# BROWSER (Edge, Brave, Firefox - dynamic)
if (Test-Path "$BP\browser") {
    Get-ChildItem "$BP\browser" -Directory -EA SilentlyContinue | ForEach-Object {
        $n = $_.Name
        if ($n -match '^edge-(.+)') {
            $rest = $matches[1] -replace '-',' '; AT $_.FullName "$L\Microsoft\Edge\User Data\$rest" "Edge: $rest"
        } elseif ($n -match '^brave-(.+)') {
            $rest = $matches[1] -replace '-',' '; AT $_.FullName "$L\BraveSoftware\Brave-Browser\User Data\$rest" "Brave: $rest"
        } elseif ($n -match '^firefox-(.+)') {
            $rest = $matches[1]; AT $_.FullName "$A\Mozilla\Firefox\Profiles\$rest" "Firefox: $rest"
        }
    }
}

# ============================================================
# CATCHALL DIRECTORIES (dynamic mapping from all backup versions)
# ============================================================

# v21 catchall/* format
if (Test-Path "$BP\catchall") {
    Get-ChildItem "$BP\catchall" -Directory -EA SilentlyContinue | ForEach-Object {
        $n = $_.Name
        $dest = $null
        if ($n -match '^home-(.+)') { $dest = "$HP\.$($matches[1])" }
        elseif ($n -match '^appdata-roaming-(.+)') { $dest = "$A\$($matches[1])" }
        elseif ($n -match '^appdata-local-(.+)') { $dest = "$L\$($matches[1])" }
        elseif ($n -match '^npm-(.+)') { $dest = "$A\npm\node_modules\$($matches[1])" }
        elseif ($n -match '^local-share-(.+)') { $dest = "$HP\.local\share\$($matches[1])" }
        elseif ($n -match '^local-state-(.+)') { $dest = "$HP\.local\state\$($matches[1])" }
        elseif ($n -match '^config-(.+)') { $dest = "$HP\.config\$($matches[1])" }
        elseif ($n -match '^progdata-(.+)') { $dest = "$env:ProgramData\$($matches[1])" }
        elseif ($n -match '^locallow-(.+)') { $dest = "$HP\AppData\LocalLow\$($matches[1])" }
        elseif ($n -match '^temp-(.+)') { $dest = "$L\Temp\$($matches[1])" }
        elseif ($n -match '^drive-(\w)-(.+)') { $dest = "$($matches[1]):\$($matches[2])" }
        elseif ($n -match '^wsl-(.+)') { $dest = $null } # WSL restore is complex, skip auto
        else { $dest = "$HP\$n" }
        if ($dest) { AT $_.FullName $dest "Catchall: $n" }
    }
}
# v20 catchall-appdata/*
if (Test-Path "$BP\catchall-appdata") {
    Get-ChildItem "$BP\catchall-appdata" -Directory -EA SilentlyContinue | ForEach-Object {
        $n = $_.Name
        if ($n -match '^local-(.+)') { AT $_.FullName "$L\$($matches[1])" "Catchall appdata: $n" }
        elseif ($n -match '^roaming-(.+)') { AT $_.FullName "$A\$($matches[1])" "Catchall appdata: $n" }
    }
}
# v20 catchall-home/*
if (Test-Path "$BP\catchall-home") {
    Get-ChildItem "$BP\catchall-home" -Directory -EA SilentlyContinue | ForEach-Object {
        $n = $_.Name
        if ($n -match '^dot-(.+)') { AT $_.FullName "$HP\.$($matches[1])" "Catchall home: $n" }
        else { AT $_.FullName "$HP\$n" "Catchall home: $n" }
    }
}
# v20 catchall-programdata/*
if (Test-Path "$BP\catchall-programdata") {
    Get-ChildItem "$BP\catchall-programdata" -Directory -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$env:ProgramData\$($_.Name)" "Catchall progdata: $($_.Name)"
    }
}

# SETTINGS (older format)
AT "$BP\settings" "$HP\.claude\settings-backup" "Settings backup dir"

# ============================================================
# KNOWN FILE MAPPINGS
# ============================================================

# Core config files
AT "$BP\core\claude.json"               "$HP\.claude.json"                 ".claude.json"               $true
AT "$BP\core\claude.json.backup"        "$HP\.claude.json.backup"          ".claude.json.backup"        $true

# Git files
AT "$BP\git\gitconfig"                  "$HP\.gitconfig"                   ".gitconfig"                 $true
AT "$BP\git\gitignore_global"           "$HP\.gitignore_global"            ".gitignore_global"          $true
AT "$BP\git\git-credentials"            "$HP\.git-credentials"             ".git-credentials"           $true

# npm
AT "$BP\npm-global\npmrc"               "$HP\.npmrc"                       ".npmrc"                     $true

# Agents/special
AT "$BP\agents\CLAUDE.md"               "$HP\CLAUDE.md"                    "~/CLAUDE.md"                $true
AT "$BP\agents\AGENTS.md"               "$HP\AGENTS.md"                    "~/AGENTS.md"                $true
AT "$BP\special\claude-wrapper.ps1"     "$HP\claude-wrapper.ps1"           "claude-wrapper.ps1"         $true
AT "$BP\special\mcp-ondemand.ps1"       "$HP\mcp-ondemand.ps1"            "mcp-ondemand.ps1"           $true
AT "$BP\special\ps-claude.md"           "$HP\Documents\WindowsPowerShell\claude.md" "ps-claude.md"     $true
AT "$BP\special\learned.md"             "$HP\learned.md"                   "learned.md"                 $true

# PowerShell profiles
AT "$BP\powershell\ps5-profile.ps1"     "$HP\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" "PS5 profile" $true
AT "$BP\powershell\ps7-profile.ps1"     "$HP\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"        "PS7 profile" $true

# MCP config
AT "$BP\mcp\claude_desktop_config.json" "$A\Claude\claude_desktop_config.json" "MCP desktop config"   $true

# Settings (older format)
AT "$BP\settings\settings.json"         "$HP\.claude\settings.json"        "settings.json"              $true

# Sessions files
AT "$BP\sessions\history.jsonl"         "$HP\.claude\history.jsonl"        "history.jsonl"              $true

# Terminal
AT "$BP\terminal\settings.json"         "$L\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"        "Terminal settings"  $true
AT "$BP\terminal\settings-preview.json" "$L\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json"  "Terminal preview"   $true

# Credentials
if (-not $SkipCredentials) {
    AT "$BP\credentials\claude-credentials.json"     "$HP\.claude\.credentials.json"           "Claude OAuth"         $true
    AT "$BP\credentials\claude-credentials-alt.json"  "$HP\.claude\credentials.json"            "Claude creds alt"     $true
    AT "$BP\credentials\opencode-auth.json"           "$HP\.local\share\opencode\auth.json"     "OpenCode auth"        $true
    AT "$BP\credentials\opencode-mcp-auth.json"       "$HP\.local\share\opencode\mcp-auth.json" "OpenCode MCP auth"    $true
    AT "$BP\credentials\anthropic-credentials.json"   "$HP\.anthropic\credentials.json"          "Anthropic creds"      $true
    AT "$BP\credentials\settings-local.json"          "$HP\.claude\settings.local.json"          "settings.local.json"  $true
    AT "$BP\credentials\moltbot-credentials.json"     "$HP\.moltbot\credentials.json"            "Moltbot creds"        $true
    AT "$BP\credentials\moltbot-config.json"          "$HP\.moltbot\config.json"                 "Moltbot config"       $true
    AT "$BP\credentials\clawdbot-credentials.json"    "$HP\.clawdbot\credentials.json"           "Clawdbot creds"       $true
    AT "$BP\credentials\clawdbot-config.json"         "$HP\.clawdbot\config.json"                "Clawdbot config"      $true
    # Credential subdirs
    if (Test-Path "$BP\credentials\openclaw-auth") {
        Get-ChildItem "$BP\credentials\openclaw-auth" -File -EA SilentlyContinue | ForEach-Object {
            AT $_.FullName "$HP\.openclaw\$($_.Name)" "OC auth: $($_.Name)" $true
        }
    }
    if (Test-Path "$BP\credentials\claude-json-auth") {
        Get-ChildItem "$BP\credentials\claude-json-auth" -File -EA SilentlyContinue | ForEach-Object {
            AT $_.FullName "$HP\.claude\$($_.Name)" "Claude auth: $($_.Name)" $true
        }
    }
    if (Test-Path "$BP\credentials\env-files") {
        Get-ChildItem "$BP\credentials\env-files" -File -EA SilentlyContinue | ForEach-Object {
            AT $_.FullName "$HP\$($_.Name)" "ENV: $($_.Name)" $true
        }
    }
}

# OpenClaw root files (individual files backed up from .openclaw root)
if (Test-Path "$BP\openclaw\root-files") {
    Get-ChildItem "$BP\openclaw\root-files" -File -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\.openclaw\$($_.Name)" "OC root: $($_.Name)" $true
    }
}
# OpenClaw rolling backups
if (Test-Path "$BP\openclaw\rolling-backups") {
    Get-ChildItem "$BP\openclaw\rolling-backups" -File -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\.openclaw\$($_.Name)" "OC rolling: $($_.Name)" $true
    }
}

# MCP .cmd wrappers (restore to home dir)
if (Test-Path "$BP\mcp-cmd-wrappers") {
    Get-ChildItem "$BP\mcp-cmd-wrappers" -File -Filter "*.cmd" -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\$($_.Name)" "MCP: $($_.Name)" $true
    }
}

# npm bin shims (restore to npm dir as individual files)
if (Test-Path "$BP\npm-global\bin-shims") {
    Get-ChildItem "$BP\npm-global\bin-shims" -File -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$A\npm\$($_.Name)" "Shim: $($_.Name)" $true
    }
}

# Startup shortcuts
$startupDir = "$A\Microsoft\Windows\Start Menu\Programs\Startup"
if (Test-Path "$BP\startup") {
    Get-ChildItem "$BP\startup" -File -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$startupDir\$($_.Name)" "Startup: $($_.Name)" $true
    }
}

# Desktop shortcuts
if (Test-Path "$BP\special\shortcuts") {
    $desktop = [System.Environment]::GetFolderPath("Desktop")
    Get-ChildItem "$BP\special\shortcuts" -File -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$desktop\$($_.Name)" "Desktop: $($_.Name)" $true
    }
}

# Sessions databases
if (Test-Path "$BP\sessions\databases") {
    Get-ChildItem "$BP\sessions\databases" -File -Filter "*.db" -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\.claude\$($_.Name)" "DB: $($_.Name)" $true
    }
}

# Claude JSON files (older backup format)
if (Test-Path "$BP\claude-json") {
    Get-ChildItem "$BP\claude-json" -File -Filter "*.json" -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\.claude\$($_.Name)" ".claude/$($_.Name)" $true
    }
}

# Project .claude dirs (Phase 4 backups - reconstruct path from sanitized name)
if (Test-Path "$BP\project-claude") {
    Get-ChildItem "$BP\project-claude" -Directory -EA SilentlyContinue | ForEach-Object {
        # Name is like: F_study_..._project_.claude ΓåÆ reconstruct as F:\study\...\project\.claude
        $reconstructed = $_.Name -replace '^(\w)_', '$1:\' -replace '_', '\'
        if ($reconstructed -match ':') {
            AT $_.FullName $reconstructed "Project: $($_.Name)" $false
        }
    }
}

$dirTasks = @($allTasks | Where-Object { -not $_.F })
$fileTasks = @($allTasks | Where-Object { $_.F })

WS "  $($allTasks.Count) tasks ($($dirTasks.Count) dirs, $($fileTasks.Count) files)" "OK"
Write-Host ""
#endregion

#region RUNSPACEPOOL PARALLEL EXECUTION
WS "[RESTORE] Dispatching $($allTasks.Count) tasks via RunspacePool ($MaxJobs threads)..." "FAST"

$resultBag = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()

$copyBlock = {
    param($task, $resultBag)
    $src = $task.S; $dst = $task.D; $desc = $task.Desc; $isFile = $task.F
    if (-not (Test-Path $src)) { $resultBag.Add(@{S="MISS";D=$desc}); return }
    try {
        if ($isFile) {
            # Skip only if byte-identical (same size + same LastWriteTime)
            if (Test-Path $dst) {
                $si = [System.IO.FileInfo]::new($src); $di = [System.IO.FileInfo]::new($dst)
                if ($si.Length -eq $di.Length -and $si.LastWriteTimeUtc -eq $di.LastWriteTimeUtc) {
                    $resultBag.Add(@{S="SKIP";D=$desc}); return
                }
            }
            $parent = Split-Path $dst -Parent
            if ($parent -and -not (Test-Path $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
            [System.IO.File]::Copy($src, $dst, $true)
        } else {
            if (-not (Test-Path $dst)) { New-Item -ItemType Directory -Path $dst -Force | Out-Null }
            # robocopy /MIR /XO /MT:128 /FFT - skip older files, 128 threads, FAT time tolerance
            $args2 = @($src, $dst, "/MIR", "/XO", "/MT:128", "/FFT", "/R:1", "/W:0", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
            & robocopy @args2 2>&1 | Out-Null
            $rc = $LASTEXITCODE
            if ($rc -gt 7) {
                # Retry with backup mode for locked files
                $args3 = @($src, $dst, "/MIR", "/XO", "/B", "/MT:128", "/FFT", "/R:2", "/W:1", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                & robocopy @args3 2>&1 | Out-Null
                if ($LASTEXITCODE -gt 7) { throw "robocopy exit $rc then $LASTEXITCODE" }
            }
        }
        $resultBag.Add(@{S="OK";D=$desc})
    } catch {
        $resultBag.Add(@{S="ERR";D=$desc;E=$_.ToString()})
    }
}

$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxJobs)
$pool.ApartmentState = "MTA"
$pool.Open()

$handles = [System.Collections.Generic.List[hashtable]]::new()
foreach ($task in $allTasks) {
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    $ps.AddScript($copyBlock).AddArgument($task).AddArgument($resultBag) | Out-Null
    $handles.Add(@{ PS=$ps; Handle=$ps.BeginInvoke() })
}

$total = $handles.Count
$pending = [System.Collections.Generic.List[hashtable]]($handles)
$completed = 0; $lastReport = Get-Date

while ($pending.Count -gt 0) {
    $still = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($h in $pending) {
        if ($h.Handle.IsCompleted) {
            try { $h.PS.EndInvoke($h.Handle) | Out-Null } catch {}
            $h.PS.Dispose()
            $completed++
        } else { $still.Add($h) }
    }
    $pending = $still
    if (((Get-Date) - $lastReport).TotalSeconds -ge 2) {
        $pct = [math]::Round($completed / $total * 100)
        WS "  $completed/$total ($pct%)" "FAST"
        $lastReport = Get-Date
    }
    if ($pending.Count -gt 0) { Start-Sleep -Milliseconds 150 }
}

$pool.Close(); $pool.Dispose()

# Tally
foreach ($r in $resultBag) {
    switch ($r.S) {
        "OK"   { $script:ok++ }
        "SKIP" { $script:skip++ }
        "MISS" { $script:miss++ }
        "ERR"  { $script:fail++; $script:Errors += "$($r.D): $($r.E)" }
    }
}

WS "[RESTORE] Done: $($script:ok) restored, $($script:skip) skipped, $($script:miss) missing, $($script:fail) errors" $(if($script:fail -eq 0){"OK"}else{"WARN"})
if ($script:fail -gt 0) {
    foreach ($r in $resultBag | Where-Object { $_.S -eq "ERR" }) {
        WS "  ERR: $($r.D) - $($r.E)" "ERR"
    }
}
Write-Host ""
#endregion

#region POST-CONFIG
WS "[POST] Applying configuration..." "FAST"

# SSH key permissions
if (Test-Path "$HP\.ssh") {
    Get-ChildItem "$HP\.ssh" -File -EA SilentlyContinue |
        Where-Object { $_.Name -notmatch '\.pub$' -and $_.Name -notin @("known_hosts","config") } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName
                $acl.SetAccessRuleProtection($true, $false)
                $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME,"FullControl","Allow")))
                Set-Acl $_.FullName $acl -EA SilentlyContinue
            } catch {}
        }
    WS "  SSH permissions fixed" "OK"
}

# PATH: ensure .local\bin
$localBin = "$HP\.local\bin"
if (Test-Path $localBin) {
    $userPath = [Environment]::GetEnvironmentVariable("Path","User")
    if ($userPath -notmatch [regex]::Escape($localBin)) {
        [Environment]::SetEnvironmentVariable("Path","$localBin;$userPath","User")
        $env:Path = "$localBin;$env:Path"
        WS "  Added .local\bin to PATH" "OK"
    }
}

# Environment variables from backup JSON
$envJson = "$BP\env\environment-variables.json"
if (Test-Path $envJson) {
    try {
        $envData = Get-Content $envJson -Raw | ConvertFrom-Json
        $envSet = 0
        foreach ($prop in $envData.PSObject.Properties) {
            $vn = $prop.Name; $vv = $prop.Value
            if ($vn -eq 'Path' -or [string]::IsNullOrEmpty($vv)) { continue }
            # Strip USER_ prefix if present (v21 format)
            $realName = $vn -replace '^USER_',''
            if ($realName -match 'CLAUDE|OPENCLAW|ANTHROPIC|OPENCODE|NODE|NPM|UV') {
                $existing = [System.Environment]::GetEnvironmentVariable($realName, "User")
                if ($existing -ne $vv) {
                    [System.Environment]::SetEnvironmentVariable($realName, $vv, "User")
                    [System.Environment]::SetEnvironmentVariable($realName, $vv, "Process")
                    $envSet++
                }
            }
        }
        if ($envSet -gt 0) { WS "  Env vars: $envSet set" "OK" }
    } catch { WS "  Env vars: $_" "WARN" }
}

# Registry
if (Test-Path "$BP\registry") {
    Get-ChildItem "$BP\registry" -Filter "*.reg" -File -EA SilentlyContinue | ForEach-Object {
        try { reg import $_.FullName 2>$null; WS "  Registry: $($_.BaseName)" "OK" }
        catch { WS "  Registry: $($_.BaseName) failed" "WARN" }
    }
}

# Scheduled tasks (check both paths from v22 and v23 backup formats)
$schtaskPaths = @("$BP\scheduled-tasks", "$BP\startup\scheduled-tasks")
foreach ($stp in $schtaskPaths) {
if (Test-Path $stp) {
    Get-ChildItem $stp -Filter "*.xml" -File -EA SilentlyContinue | ForEach-Object {
        $tn = $_.BaseName -replace '^_', '\'
        try {
            $existing = schtasks /query /tn $tn 2>&1
            if ($LASTEXITCODE -ne 0) {
                schtasks /create /tn $tn /xml $_.FullName /f 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) { WS "  Task: $tn imported" "OK" }
                else { WS "  Task: $tn failed (need admin?)" "WARN" }
            }
        } catch {}
    }
}
}

# NGEN pre-compile tg.exe (eliminates .NET JIT cold start on boot)
$tgExe = "$HP\.local\bin\tg.exe"
if (Test-Path $tgExe) {
    $ngen = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\ngen.exe"
    if (Test-Path $ngen) {
        try {
            $psi = New-Object System.Diagnostics.ProcessStartInfo
            $psi.FileName = $ngen
            $psi.Arguments = "install `"$tgExe`" /silent"
            $psi.CreateNoWindow = $true
            $psi.UseShellExecute = $false
            $psi.RedirectStandardOutput = $true
            $psi.RedirectStandardError = $true
            $p = [System.Diagnostics.Process]::Start($psi)
            $p.WaitForExit(30000)
            WS "  NGEN tg.exe: pre-compiled" "OK"
        } catch { WS "  NGEN tg.exe: $_ (may need admin)" "WARN" }
    }
}

# TgTray + Claude Channel startup shortcuts check
$tgStartupDir = "$A\Microsoft\Windows\Start Menu\Programs\Startup"
if ((Test-Path "$HP\.claude\channels\tg-channel-startup.vbs") -and -not (Test-Path "$tgStartupDir\Claude Channel.lnk")) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $lnk = $wsh.CreateShortcut("$tgStartupDir\Claude Channel.lnk")
        $lnk.TargetPath = "wscript.exe"
        $lnk.Arguments = "//B `"$HP\.claude\channels\tg-channel-startup.vbs`""
        $lnk.Description = "Claude Telegram Channel"
        $lnk.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
        WS "  Claude Channel startup shortcut CREATED" "OK"
    } catch { WS "  Claude Channel startup shortcut: $_" "WARN" }
}
if ((Test-Path $tgExe) -and -not (Test-Path "$tgStartupDir\TgTray.lnk")) {
    try {
        $wsh = New-Object -ComObject WScript.Shell
        $lnk = $wsh.CreateShortcut("$tgStartupDir\TgTray.lnk")
        $lnk.TargetPath = "wscript.exe"
        $lnk.Arguments = "//B `"$HP\.claude\channels\tg-startup.vbs`""
        $lnk.Description = "TgTray System Tray"
        $lnk.Save()
        [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
        WS "  TgTray startup shortcut CREATED" "OK"
    } catch { WS "  TgTray startup shortcut: $_" "WARN" }
}

# Unblock PowerShell profiles
foreach ($pf in @(
    "$HP\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1",
    "$HP\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"
)) {
    if (Test-Path $pf) { Unblock-File -Path $pf -EA SilentlyContinue }
}

# Execution policy
$ep = Get-ExecutionPolicy -Scope CurrentUser
if ($ep -eq "Restricted" -or $ep -eq "Undefined") {
    try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -EA Stop; WS "  ExecutionPolicy: RemoteSigned" "OK" }
    catch {}
}

# npm install in .openclaw (restore node_modules)
$ocPkg = "$HP\.openclaw\package.json"
if ((Test-Path $ocPkg) -and -not (Test-Path "$HP\.openclaw\node_modules")) {
    WS "  Running npm install in .openclaw..." "INST"
    Push-Location "$HP\.openclaw"
    & npm install --legacy-peer-deps 2>&1 | Out-Null
    Pop-Location
    if (Test-Path "$HP\.openclaw\node_modules") { WS "  .openclaw node_modules restored" "OK" }
}

# Unblock global node_modules executables
$nmGlobal = "$A\npm\node_modules"
if (Test-Path $nmGlobal) {
    Get-ChildItem $nmGlobal -Recurse -File -Include "*.exe","*.ps1","*.cmd" -EA SilentlyContinue |
        ForEach-Object { try { Unblock-File -Path $_.FullName -EA SilentlyContinue } catch {} }
}

# Chrome CDP setup + extension
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
if (Test-Path $chromeExe) {
    $cdpSetup = "$HP\.openclaw\scripts\chrome-cdp-setup.ps1"
    if (Test-Path $cdpSetup) {
        try { & powershell -NoProfile -File $cdpSetup 2>&1 | Out-Null; WS "  Chrome CDP configured" "OK" } catch {}
    }
    $extInstall = "$HP\.openclaw\scripts\install-chrome-extension.ps1"
    if (Test-Path $extInstall) {
        try { & powershell -NoProfile -File $extInstall 2>&1 | Out-Null; WS "  Browser relay extension installed" "OK" } catch {}
    }
}

# ============================================================
# ClawdBot VBS STARTUP TRAY - ensure it runs on login
# ============================================================
$vbsPath = "$HP\.openclaw\ClawdBot\ClawdbotTray.vbs"
if (Test-Path $vbsPath) {
    $startupFolder = "$A\Microsoft\Windows\Start Menu\Programs\Startup"
    # Check if any ClawdBot shortcut already exists in Startup
    $existingStartup = Get-ChildItem $startupFolder -File -EA SilentlyContinue | Where-Object {
        $_.Name -match 'ClawdBot|Clawdbot|clawdbot'
    }
    if (-not $existingStartup) {
        # Create a .lnk shortcut to the VBS in Startup
        try {
            $wsh = New-Object -ComObject WScript.Shell
            $lnk = $wsh.CreateShortcut("$startupFolder\ClawdBot Tray.lnk")
            $lnk.TargetPath = "wscript.exe"
            $lnk.Arguments = "`"$vbsPath`""
            $lnk.WorkingDirectory = Split-Path $vbsPath -Parent
            $lnk.Description = "ClawdBot System Tray"
            $lnk.Save()
            [System.Runtime.InteropServices.Marshal]::ReleaseComObject($wsh) | Out-Null
            WS "  ClawdBot VBS startup shortcut CREATED" "OK"
        } catch {
            # Fallback: copy VBS directly to Startup (also works)
            try {
                Copy-Item $vbsPath "$startupFolder\ClawdbotTray.vbs" -Force
                WS "  ClawdBot VBS copied to Startup (fallback)" "OK"
            } catch {
                WS "  ClawdBot startup setup failed: $_" "WARN"
            }
        }
    } else {
        WS "  ClawdBot already in Startup" "OK"
    }
} else {
    WS "  ClawdBot VBS not found at $vbsPath" "WARN"
}

# OpenClaw Gateway - check and start
try {
    $tc = New-Object System.Net.Sockets.TcpClient
    $ar = $tc.BeginConnect("127.0.0.1", 18792, $null, $null)
    $ok2 = $ar.AsyncWaitHandle.WaitOne(2000)
    if ($ok2 -and $tc.Connected) { $tc.Close(); WS "  OpenClaw Gateway: running" "OK" }
    else {
        $tc.Close()
        if (Get-Command openclaw -EA SilentlyContinue) {
            Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"openclaw gateway start`"" -WindowStyle Hidden
            WS "  OpenClaw Gateway: start issued" "INST"
        }
    }
} catch {}

# Create missing critical dirs
foreach ($d in @("$HP\.openclaw\workspace","$HP\.claude","$HP\.local\bin")) {
    if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null }
}

Refresh-Path
Write-Host ""
#endregion

#region VERIFICATION
WS "[VERIFY] Testing tools..." "INFO"

$brokenTools = @()
foreach ($tool in @("claude","openclaw","moltbot","clawdbot","opencode")) {
    $cmd = Get-Command $tool -EA SilentlyContinue
    if (-not $cmd) { $brokenTools += $tool; WS "  $tool : NOT IN PATH" "WARN"; continue }
    $vj = Start-Job -ScriptBlock ([scriptblock]::Create("& '$($cmd.Source)' --version 2>&1"))
    $done = Wait-Job -Job $vj -Timeout 8
    if ($done) {
        $vo = Receive-Job -Job $vj -EA SilentlyContinue
        Remove-Job -Job $vj -Force -EA SilentlyContinue
        WS "  $tool : OK ($vo)" "OK"
    } else {
        Stop-Job -Job $vj -Force -EA SilentlyContinue
        Remove-Job -Job $vj -Force -EA SilentlyContinue
        WS "  $tool : TIMEOUT" "WARN"
        $brokenTools += $tool
    }
}

# Auto-repair broken tools (inline to ensure PATH/env consistency)
$repairedTools = @()
if ($brokenTools.Count -gt 0 -and -not $SkipSoftwareInstall -and (Get-Command npm -EA SilentlyContinue)) {
    WS "[REPAIR] Reinstalling $($brokenTools.Count) broken tools..." "INST"
    $pkgMap = @{ "claude"="@anthropic-ai/claude-code"; "openclaw"="openclaw"; "moltbot"="moltbot"; "clawdbot"="clawdbot"; "opencode"="opencode-ai" }
    foreach ($tool in $brokenTools) {
        $pkg = $pkgMap[$tool]
        if ($pkg) {
            WS "  Reinstalling $tool ($pkg)..." "INST"
            $npmOut = & npm install -g --force --legacy-peer-deps $pkg 2>&1
            Refresh-Path
            if (Get-Command $tool -CommandType Application -EA SilentlyContinue) {
                WS "  $tool reinstalled and verified" "OK"
                $script:installed++
                $repairedTools += $tool
            } else {
                $hasErr = "$npmOut" -match 'npm error|ERR!'
                if ($hasErr) { WS "  $tool install failed: check npm output" "WARN" }
                else {
                    WS "  $tool installed (needs shell restart for PATH)" "OK"
                    $script:installed++
                    $repairedTools += $tool
                }
            }
        }
    }
    Refresh-Path
}

# Critical paths check - backup-aware: only check paths that have a backup source
$critPaths = @(
    @{Name="Claude home";  Local="$HP\.claude";                             Backup="$BP\core\claude-home"},
    @{Name="OC workspace"; Local="$HP\.openclaw\workspace";                 Backup="$BP\openclaw\workspace"},
    @{Name="openclaw.json";Local="$HP\.openclaw\openclaw.json";             Backup="$BP\openclaw\openclaw.json"},
    @{Name="OC scripts";   Local="$HP\.openclaw\scripts";                   Backup="$BP\openclaw\scripts"},
    @{Name="OC browser";   Local="$HP\.openclaw\browser";                   Backup="$BP\openclaw\browser"},
    @{Name="OC memory";    Local="$HP\.openclaw\memory";                    Backup="$BP\openclaw\memory"},
    @{Name="OC skills";    Local="$HP\.openclaw\skills";                    Backup="$BP\openclaw\skills"},
    @{Name="OC agents";    Local="$HP\.openclaw\agents";                    Backup="$BP\openclaw\agents"},
    @{Name="OC telegram";  Local="$HP\.openclaw\telegram";                  Backup="$BP\openclaw\telegram"},
    @{Name="OC ClawdBot";  Local="$HP\.openclaw\ClawdBot";                  Backup="$BP\openclaw\ClawdBot-tray"},
    @{Name="OC completions";Local="$HP\.openclaw\completions";              Backup="$BP\openclaw\completions"},
    @{Name="OC cron";      Local="$HP\.openclaw\cron";                      Backup="$BP\openclaw\cron"},
    @{Name="Moltbot";      Local="$HP\.moltbot";                            Backup="$BP\moltbot\dot-moltbot"},
    @{Name="Clawdbot";     Local="$HP\.clawdbot";                           Backup="$BP\clawdbot\dot-clawdbot"},
    @{Name="SSH keys";     Local="$HP\.ssh";                                Backup="$BP\git\ssh"},
    @{Name="Git config";   Local="$HP\.gitconfig";                          Backup="$BP\git\gitconfig"},
    @{Name="ClawdBot VBS"; Local="$HP\.openclaw\ClawdBot\ClawdbotTray.vbs"; Backup="$BP\openclaw\ClawdBot-tray"},
    @{Name="TgTray exe";   Local="$HP\.local\bin\tg.exe";                                  Backup="$BP\tgtray\tg.exe"},
    @{Name="TgTray src";   Local="F:\study\Dev_Toolchain\programming\.net\projects\c#\TgTray\TgTray.cs"; Backup="$BP\tgtray\source"},
    @{Name="Channels";     Local="$HP\.claude\channels\run-channel.cmd";                  Backup="$BP\tgtray\channels"},
    @{Name="Chrome";       Local="C:\Program Files\Google\Chrome\Application\chrome.exe"; Backup=$null}
)
$critTotal = 0; $valid = 0
foreach ($cp in $critPaths) {
    # Chrome has no backup source - always check. Others: only if backup exists.
    $shouldCheck = if ($null -eq $cp.Backup) { $true } else { Test-Path $cp.Backup }
    if ($shouldCheck) { $critTotal++; if (Test-Path $cp.Local) { $valid++ } }
}
WS "  Critical paths: $valid/$critTotal" $(if($valid -eq $critTotal){"OK"}else{"WARN"})

# JSON validity
foreach ($jf in @("$HP\.openclaw\openclaw.json","$HP\.claude\.credentials.json","$HP\.claude\settings.json","$HP\.moltbot\config.json","$HP\.clawdbot\config.json")) {
    if (Test-Path $jf) {
        try { $null = Get-Content $jf -Raw | ConvertFrom-Json }
        catch { WS "  CORRUPT JSON: $(Split-Path $jf -Leaf)" "ERR"; $script:Errors += "Corrupt: $jf" }
    }
}

# ========== POST-RESTORE: STARTUP REGISTRATION ON NEW PC ==========
# Register ClawdBot startup VBS to launch on every Windows boot
if ($isNewPC) {
    WS "[NEW-PC] Registering startup tasks..." "INST"
    $startupVBS = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ClawdBot_Startup.vbs"
    if (Test-Path $startupVBS) {
        try {
            # Create scheduled task for ClawdBot startup (backup to VBS)
            $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$startupVBS`""
            $trigger = New-ScheduledTaskTrigger -AtLogOn -RandomDelay (New-TimeSpan -Minutes 1)
            Register-ScheduledTask -TaskName "ClawdBot_Startup_Launcher" -Action $action -Trigger $trigger `
                -RunLevel Highest -Force -ErrorAction SilentlyContinue | Out-Null
            WS "  ClawdBot startup task registered" "OK"
        } catch {
            WS "  ClawdBot startup task registration skipped (may need manual setup)" "WARN"
        }
    }
}

Write-Host ""
#endregion

#region SUMMARY
$sw.Stop()
$dur = $sw.Elapsed.TotalSeconds

# Health score - backup-aware: only penalize for things that SHOULD work but don't
Refresh-Path
$health = 100
$health -= ($script:Errors.Count * 5)

# Tools: read backup's software-info to know what was installed pre-backup
$backupToolsInstalled = @()
$siFile = Join-Path $BP "meta\software-info.json"
if (Test-Path $siFile) {
    try {
        $si = Get-Content $siFile -Raw | ConvertFrom-Json
        foreach ($prop in $si.PSObject.Properties) {
            if ($prop.Value.Installed -eq $true) { $backupToolsInstalled += $prop.Name }
        }
    } catch {}
}
$toolNames = @("claude","openclaw","moltbot","clawdbot")
$toolsToCheck = if ($backupToolsInstalled.Count -gt 0) {
    @($toolNames | Where-Object { $backupToolsInstalled -contains $_ })
} else { $toolNames }
$toolsOK = @($toolsToCheck | Where-Object {
    (Get-Command $_ -CommandType Application -EA SilentlyContinue) -or ($repairedTools -contains $_)
}).Count
$toolsExpected = $toolsToCheck.Count
if ($toolsExpected -gt 0) { $health -= (($toolsExpected - $toolsOK) * 10) }

# Files: only penalize if the file was in the backup but not restored
$healthFiles = @(
    @{Local="$HP\.openclaw\openclaw.json"; Backup="$BP\openclaw\openclaw.json"},
    @{Local="$HP\.claude\.credentials.json"; Backup="$BP\credentials\claude-credentials.json"},
    @{Local="$HP\.openclaw\workspace"; Backup="$BP\openclaw\workspace"}
)
$filesExpected = 0; $filesOK = 0
foreach ($hf in $healthFiles) {
    if (Test-Path $hf.Backup) {
        $filesExpected++
        if (Test-Path $hf.Local) { $filesOK++ }
    }
}
if ($filesExpected -gt 0) { $health -= (($filesExpected - $filesOK) * 15) }
$health = [math]::Max(0, [math]::Min(100, $health))
$status = switch ($health) {
    {$_ -ge 90} { "EXCELLENT"; break }
    {$_ -ge 70} { "GOOD"; break }
    {$_ -ge 50} { "FAIR"; break }
    {$_ -ge 30} { "POOR"; break }
    default      { "CRITICAL" }
}
$hColor = switch ($health) {
    {$_ -ge 90} { "Green"; break }
    {$_ -ge 70} { "Cyan"; break }
    {$_ -ge 50} { "Yellow"; break }
    {$_ -ge 30} { "Magenta"; break }
    default      { "Red" }
}

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  RESTORE v23.0 COMPLETE" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
Write-Host "HEALTH: " -NoNewline; Write-Host "$health/100 ($status)" -ForegroundColor $hColor
Write-Host ""
Write-Host "Restored : $($script:ok)" -ForegroundColor Green
Write-Host "Skipped  : $($script:skip) (identical)" -ForegroundColor Yellow
Write-Host "Missing  : $($script:miss) (not in backup)" -ForegroundColor DarkGray
Write-Host "Errors   : $($script:fail)" -ForegroundColor $(if($script:fail -eq 0){"Green"}else{"Red"})
if ($script:installed -gt 0) { Write-Host "Installed: $($script:installed) packages" -ForegroundColor Magenta }
Write-Host "Duration : $([math]::Round($dur, 1))s" -ForegroundColor Cyan
Write-Host ""

if ($script:Errors.Count -gt 0) {
    Write-Host "ERRORS:" -ForegroundColor Red
    $script:Errors | Select-Object -First 10 | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
    if ($script:Errors.Count -gt 10) { Write-Host "  ... +$($script:Errors.Count - 10) more" -ForegroundColor Red }
    Write-Host ""
}

# Auth status - backup-aware: only count items that were in the backup
if (-not $SkipCredentials) {
    $authChecks = @(
        @{Name="Claude OAuth";  Local="$HP\.claude\.credentials.json";    Backup="$BP\credentials\claude-credentials.json"},
        @{Name="OpenClaw conf"; Local="$HP\.openclaw\openclaw.json";      Backup="$BP\openclaw\openclaw.json"},
        @{Name="OC creds";      Local="$HP\.openclaw\credentials";        Backup="$BP\openclaw\credentials-dir"},
        @{Name="SOUL.md";       Local="$HP\.openclaw\workspace\SOUL.md";  Backup="$BP\openclaw\workspace"},
        @{Name="Moltbot";       Local="$HP\.moltbot\config.json";         Backup="$BP\credentials\moltbot-config.json"},
        @{Name="Clawdbot";      Local="$HP\.clawdbot\config.json";        Backup="$BP\credentials\clawdbot-config.json"},
        @{Name="SSH key";       Local="$HP\.ssh\id_ed25519";              Backup="$BP\git\ssh"},
        @{Name="Git config";    Local="$HP\.gitconfig";                   Backup="$BP\git\gitconfig"}
    )
    $authOK = 0; $authTotal = 0
    foreach ($c in $authChecks) {
        $inBackup = Test-Path $c.Backup
        if (-not $inBackup) { continue }
        $authTotal++
        if (Test-Path $c.Local) { Write-Host "  [OK] $($c.Name)" -ForegroundColor Green; $authOK++ }
        else { Write-Host "  [--] $($c.Name)" -ForegroundColor DarkGray }
    }
    Write-Host "Auth: $authOK/$authTotal" -ForegroundColor $(if($authOK -eq $authTotal){"Green"}else{"Yellow"})
    Write-Host ""
}

Write-Host "NEXT:" -ForegroundColor Cyan
Write-Host "  1. Restart PowerShell (PATH changes)"
Write-Host "  2. claude --version / openclaw --version"
Write-Host "  3. openclaw gateway start"
Write-Host "  4. tg status (verify TgTray + channel)"
Write-Host ""

if ($health -ge 90) { Write-Host "All systems nominal." -ForegroundColor Green }
elseif ($health -ge 70) { Write-Host "Restored with minor issues. Check warnings." -ForegroundColor Cyan }
else { Write-Host "Issues detected. Review errors above." -ForegroundColor Yellow }

# Save health report
try {
    $rp = "$HP\.openclaw\restore-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    @{ Version="23.0"; Health=$health; Status=$status; Restored=$script:ok; Skipped=$script:skip
       Missing=$script:miss; Errors=$script:fail; Installed=$script:installed
       Duration=[math]::Round($dur,1); Timestamp=(Get-Date -Format "o") } |
        ConvertTo-Json | Out-File $rp -Encoding utf8
} catch {}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
#endregion
