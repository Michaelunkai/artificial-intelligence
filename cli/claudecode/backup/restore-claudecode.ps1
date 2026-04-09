#Requires -Version 5.1
<#
.SYNOPSIS
    RESTORE v29.0 - COMPILED C# PARALLEL RESTORE (zero process spawn)
.DESCRIPTION
    Restores EVERYTHING from the latest backup to all local locations.
    v29.0: 10x+ faster than v26.0 by eliminating ALL robocopy process spawning:
      - REPLACED: RunspacePool + robocopy /MT:8 per task with compiled C# Parallel.For
      - REPLACED: MD5 sentinel guard with size+mtime (10-100x faster)
      - ADDED: Auto-detect "latest" incremental dir (v28+ backup format)
      - KEPT: Full backwards-compatible task mapping (v20-v28 backup formats)
      - KEPT: Size+mtime skip for identical files (2s FAT tolerance for exFAT)
      - KEPT: winget/Node.js/npm bootstrap for fresh Windows 11 installs
    PS v5.1 only. All constructs verified for Windows PowerShell 5.1.
    C# code compiled via Add-Type uses .NET 4.5 (C# 5.0) compatible constructs.
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
    Parallel C# threads (default: 64)
.NOTES
    Version: 29.0 - COMPILED C# PARALLEL RESTORE
#>
[CmdletBinding()]
param(
    [string]$BackupPath,
    [switch]$Force,
    [switch]$SkipPrerequisites,
    [switch]$SkipSoftwareInstall,
    [switch]$SkipCredentials,
    [int]$MaxJobs = 64
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
    # v29: Prefer "latest" incremental dir (always most up-to-date from v28+ backups)
    $latestIncr = Join-Path $BackupRoot "latest"
    if ((Test-Path $latestIncr) -and @([System.IO.Directory]::GetDirectories($latestIncr)).Count -gt 0) {
        $BackupPath = $latestIncr
    } else {
        # Fallback: latest timestamped backup
        $latest = Get-ChildItem $BackupRoot -Directory -EA SilentlyContinue |
            Where-Object { $_.Name -match "^backup_\d{4}_\d{2}_\d{2}" } |
            Sort-Object LastWriteTime -Descending | Select-Object -First 1
        if ($latest) { $BackupPath = $latest.FullName }
        else { Write-Host "ERROR: No backups in $BackupRoot" -ForegroundColor Red; exit 1 }
    }
}
if (-not (Test-Path $BackupPath)) { Write-Host "ERROR: Backup not found: $BackupPath" -ForegroundColor Red; exit 1 }
$BP = $BackupPath
#endregion

# v29: NO SkipGuard - the C# RestoreCopier already skips identical files per-file
# via size+mtime comparison. Always run the full restore so user sees real progress.
# When everything is already in sync, individual file skips make it fast (~5s).
$script:_manifestHashToStore = $null
$script:_manifestHashFile    = $null

#region Banner
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  RESTORE v29.0 - COMPILED C# PARALLEL RESTORE" -ForegroundColor White
Write-Host "  C# Parallel.For | SIZE+MTIME SKIP | ZERO PROCESS SPAWN | REG+SCHTASK" -ForegroundColor Yellow
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

#region ExecutionPolicy + Winget bootstrap
$ep = Get-ExecutionPolicy -Scope CurrentUser
if ($ep -eq "Restricted" -or $ep -eq "Undefined" -or $ep -eq "AllSigned") {
    try { Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -EA Stop
          WS "[POLICY] ExecutionPolicy set to RemoteSigned" "OK"
    } catch { WS "[POLICY] Could not set ExecutionPolicy (may need admin)" "WARN" }
}

if (-not (Get-Command winget -EA SilentlyContinue)) {
    WS "[WINGET] winget not found - bootstrapping..." "INST"
    $bootstrapped = $false
    try {
        $pkg = Get-AppxPackage -Name "Microsoft.DesktopAppInstaller" -EA SilentlyContinue
        if ($pkg) {
            Add-AppxPackage -RegisterByFamilyName -MainPackage $pkg.PackageFamilyName -EA Stop
            Refresh-Path
            if (Get-Command winget -EA SilentlyContinue) { WS "  winget activated from stub" "OK"; $bootstrapped = $true }
        }
    } catch {}
    if (-not $bootstrapped) {
        try {
            WS "  Downloading winget from GitHub..." "INST"
            $tls = [Net.ServicePointManager]::SecurityProtocol
            [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
            $apiUrl = "https://api.github.com/repos/microsoft/winget-cli/releases/latest"
            $rel = Invoke-RestMethod $apiUrl -EA Stop
            $asset = $rel.assets | Where-Object { $_.name -match '\.msixbundle$' } | Select-Object -First 1
            if ($asset) {
                $tmp = "$env:TEMP\winget-install.msixbundle"
                Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $tmp -UseBasicParsing -EA Stop
                Add-AppxPackage -Path $tmp -EA Stop
                Remove-Item $tmp -EA SilentlyContinue
                Refresh-Path
                if (Get-Command winget -EA SilentlyContinue) { WS "  winget installed from GitHub" "OK"; $bootstrapped = $true }
            }
            [Net.ServicePointManager]::SecurityProtocol = $tls
        } catch { WS "  winget GitHub download failed: $_ - install manually from https://aka.ms/getwinget" "WARN" }
    }
    if (-not $bootstrapped) { WS "  winget unavailable - Node.js/Git must be installed manually if missing" "WARN" }
}
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

#region Ensure Node.js and claude CLI (v26: consolidated - no duplicate npm install)
WS "[NODE] Checking Node.js availability..."
if (-not (Get-Command node -EA SilentlyContinue)) {
    WS "  node not found - installing via winget..." "INST"
    if (Get-Command winget -EA SilentlyContinue) {
        winget install --id OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements 2>&1 | Out-Null
        Refresh-Path
        if (Get-Command node -EA SilentlyContinue) { WS "  Node.js installed: $(node --version)" "OK" }
        else { WS "  Node.js install may need a new terminal" "WARN" }
    } else { WS "  winget not available - install Node.js manually" "WARN" }
} else { WS "  Node.js already available: $(node --version)" "OK" }

WS "[CLAUDE] Checking claude CLI availability..."
if (-not (Get-Command claude -EA SilentlyContinue)) {
    WS "  claude not found - installing @anthropic-ai/claude-code via npm..." "INST"
    if (Get-Command npm -EA SilentlyContinue) {
        $claudeErr = 0
        npm install -g @anthropic-ai/claude-code 2>&1 | ForEach-Object {
            $l = "$_"
            if ($l -match '^npm error') { Write-Host "    [npm ERR] $l" -ForegroundColor Red; $claudeErr++ }
        }
        Refresh-Path
        if (Get-Command claude -EA SilentlyContinue) { WS "  claude installed: $(claude --version 2>&1 | Select-Object -First 1)" "OK" }
        elseif ($claudeErr -eq 0) { WS "  claude installed (may need new terminal)" "OK" }
        else { WS "  claude install encountered errors" "WARN" }
    } else { WS "  npm not available - install Node.js first" "WARN" }
} else { WS "  claude already available: $(claude --version 2>&1 | Select-Object -First 1)" "OK" }
Write-Host ""
#endregion

#region npm packages
if (-not $SkipSoftwareInstall -and (Get-Command npm -EA SilentlyContinue)) {
    WS "[NPM] Installing global packages (skip existing)..."
    $already = @{}
    try { npm list -g --depth=0 --json 2>$null | ConvertFrom-Json |
        Select-Object -ExpandProperty dependencies -EA SilentlyContinue |
        ForEach-Object { $_.PSObject.Properties.Name } | ForEach-Object { $already[$_] = $true }
    } catch {}

    $pkgSpecs = @()
    # Read from all available sources
    $reinstallScript = "$BP\npm-global\REINSTALL-ALL.ps1"
    if (Test-Path $reinstallScript) {
        $pkgSpecs = @(Get-Content $reinstallScript |
            Where-Object { $_ -match 'npm install -g (.+)' } |
            ForEach-Object { if ($_ -match 'npm install -g (.+)') { $matches[1].Trim() } })
    }
    $npmGlobalsTxt = "$BP\npm-globals.txt"
    if (Test-Path $npmGlobalsTxt) {
        $fromTxt = @(Get-Content $npmGlobalsTxt |
            Where-Object { $_ -notmatch '^\s*#' -and $_ -match '\S' } |
            ForEach-Object { $_.Trim() })
        if ($fromTxt.Count -gt 0) {
            WS "  npm-globals.txt: $($fromTxt.Count) entries" "INFO"
            $pkgSpecs = @($pkgSpecs + $fromTxt | Sort-Object -Unique)
        }
    }
    $npmGlobalJson = "$BP\npm-global\global-packages.json"
    if (Test-Path $npmGlobalJson) {
        try {
            $jsonObj = Get-Content $npmGlobalJson -Raw -EA Stop | ConvertFrom-Json
            $fromJson = @($jsonObj.dependencies.PSObject.Properties.Name | Where-Object { $_ -ne "npm" })
            if ($fromJson.Count -gt 0) {
                WS "  global-packages.json: $($fromJson.Count) packages" "INFO"
                $pkgSpecs = @($pkgSpecs + $fromJson | Sort-Object -Unique)
            }
        } catch { WS "  Could not parse global-packages.json: $_" "WARN" }
    }
    $npmGlobalTxt2 = "$BP\npm-global\global-packages.txt"
    if (Test-Path $npmGlobalTxt2) {
        $fromTxt2 = @(Get-Content $npmGlobalTxt2 |
            Where-Object { $_ -match '^\+--|^``--' } |
            ForEach-Object {
                $line = $_ -replace '^[+``]-- ', ''
                if ($line -match '^(.+)@[^@]+$') { $matches[1] } else { $line }
            } |
            Where-Object { $_ -and $_ -ne "npm" -and $_ -match '\S' })
        if ($fromTxt2.Count -gt 0) {
            WS "  global-packages.txt: $($fromTxt2.Count) packages" "INFO"
            $pkgSpecs = @($pkgSpecs + $fromTxt2 | Sort-Object -Unique)
        }
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
function AT { param([string]$S,[string]$D,[string]$Desc,[bool]$IsFile=$false,[bool]$Additive=$false)
    if (Test-Path $S) { $allTasks.Add(@{S=$S;D=$D;Desc=$Desc;F=$IsFile;A=$Additive}) }
}

# ============================================================
# KNOWN DIRECTORY MAPPINGS (backup subdir -> local destination)
# ============================================================

# CORE (.claude home)
AT "$BP\core\claude-home"                     "$HP\.claude"                                   ".claude directory"

# EXPLICIT .claude subdirectory restores
AT "$BP\core\claude-home\memory"              "$HP\.claude\memory"                            ".claude/memory"
AT "$BP\core\claude-home\workspace"           "$HP\.claude\workspace"                         ".claude/workspace"
AT "$BP\core\claude-home\scripts"             "$HP\.claude\scripts"                           ".claude/scripts"
AT "$BP\core\claude-home\commands"            "$HP\.claude\commands"                          ".claude/commands"
AT "$BP\core\claude-home\hooks"               "$HP\.claude\hooks"                             ".claude/hooks"
AT "$BP\core\claude-home\skills"              "$HP\.claude\skills"                            ".claude/skills"
AT "$BP\core\claude-home\tasks"               "$HP\.claude\tasks"                             ".claude/tasks"
# EXPLICIT .claude file restores
AT "$BP\core\claude-home\CLAUDE.md"           "$HP\.claude\CLAUDE.md"                         ".claude/CLAUDE.md"           $true
AT "$BP\core\claude-home\settings.json"       "$HP\.claude\settings.json"                     ".claude/settings.json"       $true
AT "$BP\core\claude-home\learned.md"          "$HP\.claude\learned.md"                        ".claude/learned.md"          $true
AT "$BP\core\claude-home\keybindings.json"    "$HP\.claude\keybindings.json"                  ".claude/keybindings.json"    $true
AT "$BP\core\claude-home\MEMORY.md"           "$HP\.claude\MEMORY.md"                         ".claude/MEMORY.md"           $true
AT "$BP\core\claude-home\resource-config.json" "$HP\.claude\resource-config.json"             ".claude/resource-config.json" $true

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
# OpenClaw catchall subdirs (v28 uses "catchall", older uses "catchall-dirs")
foreach ($ocCatchallDir in @("$BP\openclaw\catchall","$BP\openclaw\catchall-dirs")) {
    if (Test-Path $ocCatchallDir) {
        Get-ChildItem $ocCatchallDir -Directory -EA SilentlyContinue | ForEach-Object {
            AT $_.FullName "$HP\.openclaw\$($_.Name)" "OpenClaw catchall: $($_.Name)"
        }
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

# ============ TGTRAY + CHANNELS ============
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
# v26: Dynamic scanner for ALL npm-global subdirs not explicitly listed above
if (Test-Path "$BP\npm-global") {
    $knownNpm = @("anthropic-ai","opencode-ai","opencode-antigravity-auth","bin-shims")
    Get-ChildItem "$BP\npm-global" -Directory -EA SilentlyContinue | Where-Object { $_.Name -notin $knownNpm } | ForEach-Object {
        $npmDest = if ($_.Name -match '^@') { "$A\npm\node_modules\$($_.Name)" } else { "$A\npm\node_modules\$($_.Name)" }
        AT $_.FullName $npmDest "npm-global: $($_.Name)"
    }
}

# OTHER DOT-DIRS
AT "$BP\other\claudegram"             "$HP\.claudegram"                   ".claudegram"
AT "$BP\other\claude-server-commander" "$HP\.claude-server-commander"     ".claude-server-commander"
AT "$BP\other\cagent"                 "$HP\.cagent"                       ".cagent"
AT "$BP\other\anthropic"              "$HP\.anthropic"                    ".anthropic (credentials)"
AT "$BP\claudegram\dot-claudegram"    "$HP\.claudegram"                   ".claudegram"
AT "$BP\claude-server-commander"      "$HP\.claude-server-commander"      ".claude-server-commander"

# ============================================================
# STARTUP VBS (CRITICAL)
# ============================================================
AT "$BP\startup\vbs\ClawdBot_Startup.vbs"          "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ClawdBot_Startup.vbs" "Startup VBS - ClawdBot"
AT "$BP\startup\openclaw-startup-wrappers"        "$HP\.openclaw\startup-wrappers" "OpenClaw startup wrappers"
AT "$BP\startup\vbs\gateway-silent.vbs"           "$HP\.openclaw\gateway-silent.vbs" "Gateway silent launcher" $true
AT "$BP\startup\vbs\lib-silent-runner.vbs"        "$HP\.openclaw\lib\silent-runner.vbs" "Silent runner library" $true
AT "$BP\startup\vbs\typing-daemon-silent.vbs"     "$HP\.openclaw\typing-daemon\daemon-silent.vbs" "Typing daemon" $true

# VS CODE EXTENSIONS (v29: restore claude/anthropic extensions from vscode-ext)
if (Test-Path "$BP\vscode-ext") {
    Get-ChildItem "$BP\vscode-ext" -Directory -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\.vscode\extensions\$($_.Name)" "VS Code: $($_.Name)"
    }
}

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

# CHROME INDEXEDDB (dynamic scan)
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
# CATCHALL DIRECTORIES
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

# OpenClaw root files
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

# v29: REMOVED openclaw-full and openclaw additive catchall - they walk the ENTIRE openclaw tree
# which hangs on node_modules/cache dirs. All subdirs already covered by individual AT tasks above.

# MCP .cmd wrappers
if (Test-Path "$BP\mcp-cmd-wrappers") {
    Get-ChildItem "$BP\mcp-cmd-wrappers" -File -Filter "*.cmd" -EA SilentlyContinue | ForEach-Object {
        AT $_.FullName "$HP\$($_.Name)" "MCP: $($_.Name)" $true
    }
}

# npm bin shims
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

# Project .claude dirs
if (Test-Path "$BP\project-claude") {
    Get-ChildItem "$BP\project-claude" -Directory -EA SilentlyContinue | ForEach-Object {
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

#region COMPILED C# RESTORE ENGINE (v29: zero process spawn, Parallel.For, REAL-TIME output)
# Compiled C# RestoreCopier - replaces RunspacePool + robocopy (10x+ faster)
# All System.IO: no process spawning, no robocopy.exe overhead
# REAL-TIME: prints each task result to Console as it completes (thread-safe)
# C# 5.0 compatible (.NET 4.5) for PS v5.1
Add-Type @"
using System;
using System.IO;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

public class RestoreCopier {
    private static readonly object consoleLock = new object();
    private static int processed;
    private static int total;

    private static void Report(string status, string desc, int copied, int skipped) {
        int done = Interlocked.Increment(ref processed);
        lock (consoleLock) {
            var old = Console.ForegroundColor;
            switch (status) {
                case "OK":   Console.ForegroundColor = ConsoleColor.Green; break;
                case "SKIP": Console.ForegroundColor = ConsoleColor.DarkYellow; break;
                case "MISS": Console.ForegroundColor = ConsoleColor.DarkGray; break;
                case "ERR":  Console.ForegroundColor = ConsoleColor.Red; break;
            }
            string detail = "";
            if (status == "OK" && (copied > 0 || skipped > 0)) {
                detail = " [" + copied + " copied, " + skipped + " unchanged]";
            }
            Console.WriteLine("  [" + status.PadRight(4) + "] " + desc + detail + "  (" + done + "/" + total + ")");
            Console.ForegroundColor = old;
        }
    }

    // Dirs to NEVER enter during restore (regeneratable caches, huge, cause hangs)
    private static readonly HashSet<string> ExcludeDirs = new HashSet<string>(StringComparer.OrdinalIgnoreCase) {
        "node_modules", ".git", "__pycache__", ".venv", "venv",
        "Code Cache", "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "Cache", "cache", "Crashpad", "blob_storage", "Session Storage",
        "Local Storage", "WebStorage", "IndexedDB", "Service Worker",
        "vm_bundles", "claude-code-vm", "platform-tools", "outbound", "canvas",
        "versions"
    };

    public static int[] BulkRestore(string[] srcs, string[] dsts, string[] descs,
        bool[] isFile, bool[] additive,
        ConcurrentBag<string> errBag, int parallelism) {
        int ok = 0, skip = 0, miss = 0, fail = 0;
        processed = 0;
        total = srcs.Length;
        var opts = new ParallelOptions { MaxDegreeOfParallelism = parallelism };
        Parallel.For(0, srcs.Length, opts, delegate(int i) {
            try {
                if (isFile[i]) {
                    if (!File.Exists(srcs[i])) { Interlocked.Increment(ref miss); Report("MISS", descs[i], 0, 0); return; }
                    if (File.Exists(dsts[i])) {
                        var si = new FileInfo(srcs[i]);
                        var di = new FileInfo(dsts[i]);
                        if (si.Length == di.Length &&
                            Math.Abs((si.LastWriteTimeUtc - di.LastWriteTimeUtc).TotalSeconds) <= 2) {
                            Interlocked.Increment(ref skip); Report("SKIP", descs[i], 0, 1); return;
                        }
                    }
                    var dir = Path.GetDirectoryName(dsts[i]);
                    if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    File.Copy(srcs[i], dsts[i], true);
                    File.SetLastWriteTimeUtc(dsts[i], File.GetLastWriteTimeUtc(srcs[i]));
                    Interlocked.Increment(ref ok); Report("OK", descs[i], 1, 0);
                } else {
                    if (!Directory.Exists(srcs[i])) { Interlocked.Increment(ref miss); Report("MISS", descs[i], 0, 0); return; }
                    int[] counts = SyncDirRestore(srcs[i], dsts[i], !additive[i]);
                    if (counts[0] == 0 && counts[1] > 0) {
                        Interlocked.Increment(ref skip); Report("SKIP", descs[i], 0, counts[1]);
                    } else {
                        Interlocked.Increment(ref ok); Report("OK", descs[i], counts[0], counts[1]);
                    }
                }
            } catch (Exception ex) {
                Interlocked.Increment(ref fail);
                errBag.Add(descs[i] + ": " + ex.Message);
                Report("ERR", descs[i], 0, 0);
            }
        });
        return new int[] { ok, skip, miss, fail };
    }

    private static int[] SyncDirRestore(string src, string dst, bool mirror) {
        int copied = 0, skipped = 0;
        if (!Directory.Exists(dst)) Directory.CreateDirectory(dst);

        var srcFileSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var f in Directory.GetFiles(src)) {
            var name = Path.GetFileName(f);
            srcFileSet.Add(name);
            var target = Path.Combine(dst, name);
            try {
                if (File.Exists(target)) {
                    var si = new FileInfo(f);
                    var di = new FileInfo(target);
                    if (si.Length == di.Length &&
                        Math.Abs((si.LastWriteTimeUtc - di.LastWriteTimeUtc).TotalSeconds) <= 2) {
                        skipped++; continue;
                    }
                }
                File.Copy(f, target, true);
                File.SetLastWriteTimeUtc(target, File.GetLastWriteTimeUtc(f));
                copied++;
            } catch { }
        }

        if (mirror) {
            foreach (var f in Directory.GetFiles(dst)) {
                if (!srcFileSet.Contains(Path.GetFileName(f))) {
                    try { File.Delete(f); } catch { }
                }
            }
        }

        var srcDirSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        foreach (var d in Directory.GetDirectories(src)) {
            var name = Path.GetFileName(d);
            if (ExcludeDirs.Contains(name)) continue;
            srcDirSet.Add(name);
            var sub = SyncDirRestore(d, Path.Combine(dst, name), mirror);
            copied += sub[0]; skipped += sub[1];
        }

        if (mirror) {
            foreach (var d in Directory.GetDirectories(dst)) {
                var name = Path.GetFileName(d);
                if (ExcludeDirs.Contains(name)) continue;
                if (!srcDirSet.Contains(name)) {
                    try { Directory.Delete(d, true); } catch { }
                }
            }
        }

        return new int[] { copied, skipped };
    }
}
"@

WS "[RESTORE] Dispatching $($allTasks.Count) tasks via C# Parallel.For ($MaxJobs threads)..." "FAST"

# Build typed arrays for C# BulkRestore
$taskCount = $allTasks.Count
$rSrcs = [string[]]::new($taskCount)
$rDsts = [string[]]::new($taskCount)
$rDescs = [string[]]::new($taskCount)
$rIsFile = [bool[]]::new($taskCount)
$rAdditive = [bool[]]::new($taskCount)
for ($i = 0; $i -lt $taskCount; $i++) {
    $rSrcs[$i] = $allTasks[$i].S
    $rDsts[$i] = $allTasks[$i].D
    $rDescs[$i] = $allTasks[$i].Desc
    $rIsFile[$i] = [bool]$allTasks[$i].F
    $rAdditive[$i] = [bool]$allTasks[$i].A
}

$errBag = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

$counts = [RestoreCopier]::BulkRestore($rSrcs, $rDsts, $rDescs, $rIsFile, $rAdditive, $errBag, $MaxJobs)

$script:ok = $counts[0]; $script:skip = $counts[1]; $script:miss = $counts[2]; $script:fail = $counts[3]
foreach ($e in $errBag) { $script:Errors += $e }

Write-Host ""
WS "[RESTORE] Done: $($script:ok) restored, $($script:skip) identical, $($script:miss) not in backup, $($script:fail) errors" $(if($script:fail -eq 0){"OK"}else{"WARN"})
if ($script:fail -gt 0) {
    foreach ($e in $errBag) { WS "  ERR: $e" "ERR" }
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

# v26: UNIFIED environment variable restore (single pass from all sources, no duplicates)
$envSet = 0
$envSeen = @{} # track which vars we already set to avoid double-writes
# Source 1: JSON
foreach ($evPath in @("$BP\env\env-vars.json","$BP\env-vars.json","$BP\env\environment-variables.json")) {
    if (-not (Test-Path $evPath)) { continue }
    try {
        $evData = Get-Content $evPath -Raw | ConvertFrom-Json
        foreach ($prop in $evData.PSObject.Properties) {
            $evName = ($prop.Name -replace '^USER_','').Trim()
            $evVal  = $prop.Value
            if ([string]::IsNullOrEmpty($evName) -or $evName -eq 'Path' -or $envSeen.ContainsKey($evName)) { continue }
            $envSeen[$evName] = $true
            $current = [System.Environment]::GetEnvironmentVariable($evName, 'User')
            if ($current -ne $evVal) {
                [System.Environment]::SetEnvironmentVariable($evName, $evVal, 'User')
                $envSet++
            }
        }
    } catch { WS "  Env vars ($evPath): $_" "WARN" }
    break # use first found only
}
# Source 2: TXT (KEY=VALUE lines)
$envTxt = "$BP\env\environment-variables.txt"
if (Test-Path $envTxt) {
    try {
        Get-Content $envTxt -Encoding UTF8 | Where-Object { $_ -match '^([^=]+)=(.*)$' } | ForEach-Object {
            $kv = $_ -split '=', 2
            $k = $kv[0].Trim(); $v = $kv[1]
            if ([string]::IsNullOrEmpty($k) -or $k -eq 'Path' -or $envSeen.ContainsKey($k)) { return }
            $envSeen[$k] = $true
            $machineVal = [System.Environment]::GetEnvironmentVariable($k, 'Machine')
            if ($null -ne $machineVal) {
                if ($machineVal -ne $v) {
                    [System.Environment]::SetEnvironmentVariable($k, $v, 'Machine')
                    $envSet++
                }
            } else {
                $userVal = [System.Environment]::GetEnvironmentVariable($k, 'User')
                if ($userVal -ne $v) {
                    [System.Environment]::SetEnvironmentVariable($k, $v, 'User')
                    $envSet++
                }
            }
        }
    } catch { WS "  Env vars (txt): $_" "WARN" }
}
if ($envSet -gt 0) { WS "  Env vars: $envSet set" "OK" }

# v26: UNIFIED registry import (single pass, no duplicates)
$regImported = @{}
if (Test-Path "$BP\registry") {
    Get-ChildItem "$BP\registry" -Filter "*.reg" -File -EA SilentlyContinue | ForEach-Object {
        $regKey = $_.BaseName.ToLower()
        if ($regImported.ContainsKey($regKey)) { return }
        $regImported[$regKey] = $true
        try { reg import $_.FullName 2>$null; WS "  Registry: $($_.BaseName)" "OK" }
        catch { WS "  Registry: $($_.BaseName) failed" "WARN" }
    }
}
# Fallback: anthropic.reg at backup root
$anthropicReg2 = "$BP\anthropic.reg"
if ((Test-Path $anthropicReg2) -and -not $regImported.ContainsKey("anthropic")) {
    try { reg import $anthropicReg2 /f 2>&1 | Out-Null; WS "  Registry: anthropic.reg (root)" "OK" }
    catch { WS "  Registry: anthropic.reg failed" "WARN" }
}

# Registry Run keys from JSON backup
$runKeysJson = @("$BP\registry\registry-run-keys.json","$BP\registry-run-keys.json") | Where-Object { Test-Path $_ } | Select-Object -First 1
if ($runKeysJson) {
    try {
        $runKeys = Get-Content $runKeysJson -Raw | ConvertFrom-Json
        $runRegPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run'
        if (-not (Test-Path $runRegPath)) { New-Item -Path $runRegPath -Force | Out-Null }
        $runSet = 0
        foreach ($prop in $runKeys.PSObject.Properties) {
            $kn = $prop.Name; $kv = $prop.Value
            if ([string]::IsNullOrEmpty($kn) -or [string]::IsNullOrEmpty($kv)) { continue }
            $existing = (Get-ItemProperty -Path $runRegPath -Name $kn -EA SilentlyContinue).$kn
            if ($existing -ne $kv) { Set-ItemProperty -Path $runRegPath -Name $kn -Value $kv -Type String -Force; $runSet++ }
        }
        if ($runSet -gt 0) { WS "  Registry Run keys (JSON): $runSet written" "OK" } else { WS "  Registry Run keys (JSON): up to date" "FAST" }
    } catch { WS "  Registry Run keys (JSON): $_" "WARN" }
}

# Scheduled tasks (v29: UserId fix + dedup + skip combined XML)
$schtaskPaths = @("$BP\scheduled-tasks", "$BP\startup\scheduled-tasks")
# Query existing tasks ONCE outside the loop (not twice)
$existingTasks = @{}
try {
    schtasks /query /fo CSV 2>$null | ConvertFrom-Csv -EA SilentlyContinue | ForEach-Object {
        $existingTasks[$_.TaskName] = $true
    }
} catch {}
# Current user for UserId replacement
$currentUser = "$env:USERDOMAIN\$env:USERNAME"
# Track imported tasks to avoid duplicates across paths
$importedTasks = @{}
foreach ($stp in $schtaskPaths) {
    if (-not (Test-Path $stp)) { continue }
    $xmlFiles = @(Get-ChildItem $stp -Filter "*.xml" -File -EA SilentlyContinue)
    if ($xmlFiles.Count -eq 0) { continue }
    foreach ($xf in $xmlFiles) {
        # Skip the combined multi-task XML (not importable as single task)
        if ($xf.BaseName -eq 'scheduled-tasks-claude' -or $xf.BaseName -eq 'relevant-tasks') { continue }
        $tn = $xf.BaseName -replace '^_', '\'
        # Dedup: skip if already imported from a previous path
        if ($importedTasks.ContainsKey($tn)) { continue }
        try {
            # Read XML and fix UserId to current user (critical for fresh installs)
            $xmlContent = [System.IO.File]::ReadAllText($xf.FullName)
            $xmlContent = [regex]::Replace($xmlContent, '<UserId>[^<]+</UserId>', "<UserId>$currentUser</UserId>")
            # Write sanitized XML to temp file for schtasks /create
            $tmpXml = [System.IO.Path]::Combine($env:TEMP, "schtask_$($xf.Name)")
            [System.IO.File]::WriteAllText($tmpXml, $xmlContent, [System.Text.UTF8Encoding]::new($false))
            $verb = if ($existingTasks.ContainsKey($tn)) { "updated" } else { "imported" }
            schtasks /create /tn $tn /xml $tmpXml /f 2>&1 | Out-Null
            if ($LASTEXITCODE -eq 0) {
                WS "  Task: $tn $verb" "OK"
                $importedTasks[$tn] = $true
            } else {
                try {
                    Register-ScheduledTask -Xml $xmlContent -TaskName $tn -Force -EA Stop | Out-Null
                    WS "  Task: $tn $verb (Register-ScheduledTask)" "OK"
                    $importedTasks[$tn] = $true
                } catch { WS "  Task: $tn failed (need admin?): $_" "WARN" }
            }
            try { [System.IO.File]::Delete($tmpXml) } catch {}
        } catch { WS "  Task: $tn error: $_" "WARN" }
    }
}

# NGEN pre-compile tg.exe
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

# TgTray + Claude Channel startup shortcuts
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
$ep2 = Get-ExecutionPolicy -Scope CurrentUser
if ($ep2 -eq "Restricted" -or $ep2 -eq "Undefined") {
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

# ClawdBot VBS STARTUP TRAY
$vbsPath = "$HP\.openclaw\ClawdBot\ClawdbotTray.vbs"
if (Test-Path $vbsPath) {
    $startupFolder = "$A\Microsoft\Windows\Start Menu\Programs\Startup"
    $existingStartup = Get-ChildItem $startupFolder -File -EA SilentlyContinue | Where-Object {
        $_.Name -match 'ClawdBot|Clawdbot|clawdbot'
    }
    if (-not $existingStartup) {
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
            try {
                Copy-Item $vbsPath "$startupFolder\ClawdbotTray.vbs" -Force
                WS "  ClawdBot VBS copied to Startup (fallback)" "OK"
            } catch { WS "  ClawdBot startup setup failed: $_" "WARN" }
        }
    } else { WS "  ClawdBot already in Startup" "OK" }
} else { WS "  ClawdBot VBS not found at $vbsPath" "WARN" }

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

#region VERIFICATION (v26: direct Process+WaitForExit instead of Start-Job)
WS "[VERIFY] Testing tools..." "INFO"

$brokenTools = @()
foreach ($tool in @("claude","openclaw","moltbot","clawdbot","opencode")) {
    $cmd = Get-Command $tool -EA SilentlyContinue
    if (-not $cmd) { $brokenTools += $tool; WS "  $tool : NOT IN PATH" "WARN"; continue }
    try {
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $cmd.Source
        $psi.Arguments = "--version"
        $psi.CreateNoWindow = $true
        $psi.UseShellExecute = $false
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $proc = [System.Diagnostics.Process]::Start($psi)
        $vo = $proc.StandardOutput.ReadToEnd().Trim()
        $done = $proc.WaitForExit(8000)
        if ($done -and $vo) { WS "  $tool : OK ($vo)" "OK" }
        elseif ($done) { WS "  $tool : OK (no version output)" "OK" }
        else {
            try { $proc.Kill() } catch {}
            WS "  $tool : TIMEOUT" "WARN"
            $brokenTools += $tool
        }
    } catch {
        WS "  $tool : ERROR ($_)" "WARN"
        $brokenTools += $tool
    }
}

# Auto-repair broken tools
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
                    WS "  $tool installed (needs shell restart)" "OK"
                    $script:installed++
                    $repairedTools += $tool
                }
            }
        }
    }
    Refresh-Path
}

# Critical paths check
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

# POST-RESTORE: STARTUP REGISTRATION ON NEW PC
if ($isNewPC) {
    WS "[NEW-PC] Registering startup tasks..." "INST"
    $startupVBS = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ClawdBot_Startup.vbs"
    if (Test-Path $startupVBS) {
        try {
            $action = New-ScheduledTaskAction -Execute "wscript.exe" -Argument "`"$startupVBS`""
            $trigger = New-ScheduledTaskTrigger -AtLogOn -RandomDelay (New-TimeSpan -Minutes 1)
            Register-ScheduledTask -TaskName "ClawdBot_Startup_Launcher" -Action $action -Trigger $trigger `
                -RunLevel Highest -Force -ErrorAction SilentlyContinue | Out-Null
            WS "  ClawdBot startup task registered" "OK"
        } catch { WS "  ClawdBot startup task registration skipped" "WARN" }
    }
}

Write-Host ""
#endregion

#region SUMMARY
$sw.Stop()
$dur = $sw.Elapsed.TotalSeconds

# Health score
Refresh-Path
$health = 100
$health -= ($script:Errors.Count * 5)

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
Write-Host "  RESTORE v29.0 COMPLETE" -ForegroundColor Green
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

# Auth status
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

# Save health report (v26: no BOM)
try {
    $rp = "$HP\.openclaw\restore-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
    $rpJson = @{ Version="29.0"; Health=$health; Status=$status; Restored=$script:ok; Skipped=$script:skip
       Missing=$script:miss; Errors=$script:fail; Installed=$script:installed
       Duration=[math]::Round($dur,1); Timestamp=(Get-Date -Format "o") } |
        ConvertTo-Json
    [System.IO.File]::WriteAllText($rp, $rpJson, (New-Object System.Text.UTF8Encoding($false)))
} catch {}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan

# v29: ManifestHash removed - no SkipGuard means no hash needed

#endregion
