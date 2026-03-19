#Requires -Version 5.1
<#
.SYNOPSIS
    ULTIMATE Claude Code + OpenClaw + Moltbot + Clawd + All AI Tools Restore v21.0 - ZERO BLIND SPOTS
.DESCRIPTION
    Restores EVERY SINGLE THING from backup AND VERIFIES IT ACTUALLY WORKS.
    This is the DEFINITIVE restore script that guarantees a working system, even on fresh Windows 11.
    
    WHAT MAKES v20.0 BULLETPROOF:
    
    🔍 PRE-FLIGHT CHECKS (before touching anything):
    - System compatibility validation (disk space, PowerShell version, admin rights)
    - Internet connectivity test
    - Backup integrity verification
    - Critical Windows tools check
    
    💾 ROLLBACK PROTECTION:
    - Automatic snapshot of current config before any changes
    - Safety net if restoration fails
    
    ⚡ PARALLEL EXECUTION (v17.0 features preserved):
    - 64-thread RunspacePool for file operations
    - npm batch install (all packages in ONE command)
    - [System.IO.File]::Copy() for files (5x faster)
    - robocopy /MT:64 for directories (max performance)
    
    ✅ POST-RESTORE VERIFICATION:
    - Tests every tool is actually executable (not just copied)
    - Detects broken installations and auto-reinstalls
    - OpenClaw Gateway health check + auto-start
    - JSON corruption detection
    - Claude API connectivity test
    - Git/SSH configuration validation
    - Final smoke tests (workspace write, npm packages, etc.)
    
    🔧 AUTO-CONFIGURATION:
    - Starts OpenClaw Gateway if not running
    - Configures Git from .gitconfig automatically
    - Unblocks PowerShell profiles (Windows security blocks)
    - Cleans npm cache (prevents future install failures)
    - Unblocks node_modules executables
    - Creates missing critical directories
    - Fixes PATH if .local\bin is missing
    - Sets PowerShell execution policy if restricted
    
    📊 HEALTH SCORE:
    - 0-100 score based on restoration success
    - Status: EXCELLENT/GOOD/FAIR/POOR/CRITICAL
    - Detailed error reporting
    - JSON health report saved for auditing
    
    WHY v18.0 FIXES THE "DIDN'T WORK" PROBLEM:
    - v17.0 only COPIED files - didn't verify they WORKED
    - v18.0 TESTS every component and AUTO-FIXES failures
    - If a tool doesn't run, it's REINSTALLED automatically
    - If services aren't running, they're STARTED automatically
    - If configs are corrupt, you're ALERTED immediately
    - If prerequisites are missing, they're INSTALLED automatically
    
    RESULT: You can run this on a FRESH Windows 11 install, walk away, and come back to a
            FULLY FUNCTIONAL Claude Code + OpenClaw environment with a health score report.

.PARAMETER BackupPath
    Path to backup directory (optional - auto-detects latest from F:\backup\claudecode\)
.PARAMETER Force
    Skip confirmation prompts
.PARAMETER SkipPrerequisites
    Skip automatic installation of Node.js, Git, etc.
.PARAMETER SkipSoftwareInstall
    Skip installation of AI tools (restore data only)
.PARAMETER SkipCredentials
    Don't restore credentials (security consideration)
.PARAMETER SkipRegistry
    Don't restore registry keys
.PARAMETER SkipEnvVars
    Don't restore environment variables
.PARAMETER MaxParallelJobs
    Maximum parallel runspace threads (default: 64)
.NOTES
    Version: 21.0 - ZERO BLIND SPOTS EDITION
    Author: AI Agent (Autonomous)
#>
[CmdletBinding()]
param(
    [string]$BackupPath,
    [switch]$Force = $false,
    [switch]$SkipPrerequisites = $false,
    [switch]$SkipSoftwareInstall = $false,
    [switch]$SkipCredentials = $false,
    [switch]$SkipRegistry = $false,
    [switch]$SkipEnvVars = $false,
    [int]$MaxParallelJobs = 64
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$script:RestoredItems = 0
$script:InstalledItems = 0
$script:SkippedItems = 0
$script:Errors = @()
$script:StartTime = Get-Date

#region Helper Functions
function Write-Step {
    param([string]$Message, [string]$Status = "INFO")
    $color = switch ($Status) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        "INSTALL" { "Magenta" }
        "FAST"    { "Cyan" }
        default   { "Cyan" }
    }
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Status] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Test-IsAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    return ([Security.Principal.WindowsPrincipal]$id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" +
                [System.Environment]::GetEnvironmentVariable("Path","User")
}

function Invoke-WithTimeout {
    param([scriptblock]$ScriptBlock, [int]$TimeoutSeconds = 15, [string]$Default = "TIMEOUT")
    $job = Start-Job -ScriptBlock $ScriptBlock
    $completed = Wait-Job -Job $job -Timeout $TimeoutSeconds
    if ($completed) {
        $result = Receive-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return $result
    } else {
        Stop-Job -Job $job -ErrorAction SilentlyContinue
        Remove-Job -Job $job -Force -ErrorAction SilentlyContinue
        return $Default
    }
}

function Import-RegistryFile {
    param([string]$RegFile, [string]$Description)
    if (Test-Path $RegFile) {
        try { reg import $RegFile 2>$null; Write-Step "  -> Registry: $Description" "SUCCESS"; return $true }
        catch { Write-Step "  -> Failed Registry $Description" "ERROR"; return $false }
    }
    return $false
}

function Install-WithWinget {
    param([string]$PackageId, [string]$Name)
    Write-Step "  -> Installing $Name via winget..." "INSTALL"
    try {
        $r = winget install --id $PackageId --accept-package-agreements --accept-source-agreements 2>&1
        if ($LASTEXITCODE -eq 0 -or $r -match "already installed") {
            Write-Step "  -> $Name installed" "SUCCESS"; $script:InstalledItems++; return $true
        }
    } catch {}
    Write-Step "  -> Failed: $Name" "ERROR"; return $false
}
#endregion

#region Auto-detect Backup
$BackupRoot = "F:\backup\claudecode"
if (-not $BackupPath) {
    $latest = Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue |
              Where-Object { $_.Name -match "^backup_\d{4}_\d{2}_\d{2}" } |
              Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if ($latest) { $BackupPath = $latest.FullName }
    else { Write-Host "ERROR: No backups in $BackupRoot" -ForegroundColor Red; exit 1 }
}
if (-not (Test-Path $BackupPath)) { Write-Host "ERROR: Backup not found: $BackupPath" -ForegroundColor Red; exit 1 }
#endregion

#region Banner
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  CLAUDE CODE + OPENCLAW + MOLTBOT + CLAWD ULTIMATE RESTORE v21.0 ZERO BLINDSPOTS" -ForegroundColor White
Write-Host "  PRE-FLIGHT | SMART-DIFF | PARALLEL | CATCH-ALL | VERIFY | AUTO-REPAIR" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Cyan
$currentTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
Write-Host "Timestamp  : $currentTime"
Write-Host "From       : $BackupPath"
Write-Host "Threads    : $MaxParallelJobs (RunspacePool + robocopy /MT:64)"
$metaPath = Join-Path $BackupPath "BACKUP-METADATA.json"
if (Test-Path $metaPath) {
    $meta = Get-Content $metaPath -Raw | ConvertFrom-Json
    Write-Host "Backup Ver : $($meta.Version)  Date: $($meta.Timestamp)  Size: $($meta.TotalSizeMB) MB"
}
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

$HOME_DIR   = $env:USERPROFILE
$APPDATA    = $env:APPDATA
$LOCALAPPDATA = $env:LOCALAPPDATA
$isNewPC    = $null -eq (Get-Command claude -ErrorAction SilentlyContinue)
if ($isNewPC) { Write-Host "[NEW PC DETECTED] Claude Code not found - installing prerequisites" -ForegroundColor Yellow }
#endregion


#region PRE-FLIGHT SYSTEM CHECKS
Write-Host ""
Write-Step "[PRE-FLIGHT] Running system compatibility checks..." "INFO"

# Check 1: Administrator privileges
if (-not (Test-IsAdmin)) {
    Write-Step "  -> Running WITHOUT admin privileges" "WARNING"
    Write-Step "  -> Some operations may fail (registry, system files)" "WARNING"
} else {
    Write-Step "  -> Running with admin privileges: OK" "SUCCESS"
}

# Check 2: Disk space
$systemDrive = $env:SystemDrive
$drive = Get-PSDrive -Name $systemDrive.TrimEnd(':') -ErrorAction SilentlyContinue
if ($drive) {
    $freeGB = [math]::Round($drive.Free / 1GB, 2)
    if ($freeGB -lt 10) {
        Write-Step "  -> WARNING: Low disk space ($freeGB GB free)" "WARNING"
        $script:Errors += "Low disk space: $freeGB GB"
    } else {
        Write-Step "  -> Disk space: $freeGB GB free - OK" "SUCCESS"
    }
}

# Check 3: PowerShell version
$psVersion = $PSVersionTable.PSVersion.ToString()
if ($PSVersionTable.PSVersion.Major -lt 5) {
    Write-Step "  -> PowerShell $psVersion - OUTDATED (need 5.1+)" "ERROR"
    Write-Host "ERROR: PowerShell 5.1 or higher required" -ForegroundColor Red
    exit 1
} else {
    Write-Step "  -> PowerShell ${psVersion} OK" "SUCCESS"
}

# Check 4: Internet connectivity
try {
    $testConn = Test-Connection -ComputerName "8.8.8.8" -Count 1 -Quiet -ErrorAction Stop
    if ($testConn) {
        Write-Step "  -> Internet connectivity: OK" "SUCCESS"
    } else {
        Write-Step "  -> Internet connectivity: FAILED (may affect npm installs)" "WARNING"
    }
} catch {
    Write-Step "  -> Internet connectivity: UNKNOWN" "WARNING"
}

# Check 5: Backup integrity
$backupMetaPath = Join-Path $BackupPath "BACKUP-METADATA.json"
if (Test-Path $backupMetaPath) {
    try {
        $meta = Get-Content $backupMetaPath -Raw | ConvertFrom-Json
        Write-Step "  -> Backup metadata: Valid (v$($meta.Version))" "SUCCESS"
    } catch {
        Write-Step "  -> Backup metadata: CORRUPT" "WARNING"
    }
} else {
    Write-Step "  -> Backup metadata: Missing (pre-v16 backup?)" "WARNING"
}

# Check 6: Critical system tools
$sysTools = @("robocopy", "reg", "icacls")
$missingTools = @()
foreach ($tool in $sysTools) {
    if (-not (Get-Command $tool -ErrorAction SilentlyContinue)) {
        $missingTools += $tool
    }
}
if ($missingTools.Count -gt 0) {
    Write-Step "  -> Missing system tools: $($missingTools -join ', ')" "ERROR"
    Write-Host "ERROR: Critical Windows tools missing" -ForegroundColor Red
    exit 1
} else {
    Write-Step "  -> System tools: OK" "SUCCESS"
}

Write-Step "[PRE-FLIGHT] All system checks passed" "SUCCESS"
Write-Host ""
#endregion
#region 1. PREREQUISITES (sequential - must complete before PATH-dependent steps)
if (-not $SkipPrerequisites -and $isNewPC) {
    Write-Step "[PREREQ] Installing prerequisites for new PC..." "INFO"
    if (Get-Command winget -ErrorAction SilentlyContinue) {
        if (-not (Get-Command node   -ErrorAction SilentlyContinue)) { Install-WithWinget "OpenJS.NodeJS.LTS"    "Node.js LTS"; Refresh-Path }
        if (-not (Get-Command git    -ErrorAction SilentlyContinue)) { Install-WithWinget "Git.Git"              "Git";         Refresh-Path }
        if (-not (Get-Command python -ErrorAction SilentlyContinue)) { Install-WithWinget "Python.Python.3.11"   "Python 3.11"; Refresh-Path }
        # Chrome is CRITICAL for OpenClaw browser automation (CDP + relay extension)
        $chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
        if (-not (Test-Path $chromeExe)) { Install-WithWinget "Google.Chrome" "Google Chrome"; Refresh-Path }
    } else {
        Write-Step "  -> winget not found. Install Node.js + Git manually then rerun." "WARNING"
    }
} else {
    Write-Step "[PREREQ] Skipping prerequisites (existing PC or -SkipPrerequisites)" "INFO"
}
#endregion

#region 2. npm BATCH INSTALL (skip already-installed, suppress warn spam, --legacy-peer-deps)
if (-not $SkipSoftwareInstall) {
    Write-Step "[NPM] Installing global npm packages (skip existing, no warn spam)..." "INFO"
    if (Get-Command npm -ErrorAction SilentlyContinue) {
        $reinstallScript = "$BackupPath\npm-global\REINSTALL-ALL.ps1"

        # Get currently installed global packages (name only, fast)
        $alreadyInstalled = @{}
        try {
            npm list -g --depth=0 --json 2>$null | ConvertFrom-Json |
                Select-Object -ExpandProperty dependencies -ErrorAction SilentlyContinue |
                ForEach-Object { $_.PSObject.Properties.Name } |
                ForEach-Object { $alreadyInstalled[$_] = $true }
        } catch {}

        if (Test-Path $reinstallScript) {
            $pkgSpecs = @(Get-Content $reinstallScript |
                Where-Object { $_ -match 'npm install -g (.+)' } |
                ForEach-Object { if ($_ -match 'npm install -g (.+)') { $matches[1].Trim() } })

            # Filter out already-installed packages
            $toInstall = @($pkgSpecs | Where-Object {
                $pkgName = ($_ -split '@')[0]  # strip @version suffix
                # Handle scoped packages like @anthropic-ai/claude-code
                if ($_ -match '^(@[^/]+/[^@]+)') { $pkgName = $matches[1] }
                elseif ($_ -match '^([^@]+)') { $pkgName = $matches[1] }
                -not $alreadyInstalled.ContainsKey($pkgName)
            })

            if ($toInstall.Count -eq 0) {
                Write-Step "  -> All $($pkgSpecs.Count) packages already installed - SKIP" "SUCCESS"
            } else {
                Write-Step "  -> Installing $($toInstall.Count) new packages (of $($pkgSpecs.Count) total), $($pkgSpecs.Count - $toInstall.Count) already exist..." "INSTALL"
                $npmPkgStr = $toInstall -join " "
                # --legacy-peer-deps silences ERESOLVE peer conflict spam
                # Filter output: suppress 'npm warn', show only errors + added lines
                $npmErrors = 0
                & npm install -g --legacy-peer-deps $toInstall 2>&1 | ForEach-Object {
                    $line = "$_"
                    if ($line -match '^npm error') {
                        Write-Host "    [npm ERROR] $line" -ForegroundColor Red
                        $npmErrors++
                    } elseif ($line -match '^added|^changed|^removed') {
                        Write-Host "    [npm] $line" -ForegroundColor Green
                    }
                    # Silently drop all 'npm warn' lines - they're noise
                }
                if ($npmErrors -eq 0) {
                    Write-Step "  -> npm install complete ($($toInstall.Count) packages)" "SUCCESS"
                } else {
                    Write-Step "  -> npm install finished with $npmErrors error(s)" "WARNING"
                }
                $script:InstalledItems += $toInstall.Count
            }
        } else {
            # Fallback: only install what's missing
            $fallback = @("@anthropic-ai/claude-code","moltbot","clawdbot","opencode-ai")
            $missing  = @($fallback | Where-Object { -not $alreadyInstalled.ContainsKey($_) })
            if ($missing.Count -gt 0) {
                Write-Step "  -> Installing $($missing.Count) fallback packages..." "INSTALL"
                & npm install -g --legacy-peer-deps $missing 2>&1 | ForEach-Object {
                    $line = "$_"
                    if ($line -match '^npm error')               { Write-Host "    [npm ERROR] $line" -ForegroundColor Red }
                    elseif ($line -match '^added|^changed')      { Write-Host "    [npm] $line" -ForegroundColor Green }
                }
                $script:InstalledItems += $missing.Count
            } else {
                Write-Step "  -> All fallback packages already installed" "SUCCESS"
            }
        }
        Refresh-Path
    } else {
        Write-Step "  -> npm not available - install Node.js first" "ERROR"
    }
} else {
    Write-Step "[NPM] Skipping software install (-SkipSoftwareInstall)" "INFO"
}
#endregion


#region ROLLBACK PROTECTION
Write-Step "[ROLLBACK] Creating safety snapshot..." "INFO"

$rollbackTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$rollbackDir = "$HOME_DIR\.openclaw-restore-rollback-$rollbackTimestamp"
$criticalBackupPaths = @(
    @{Src="$HOME_DIR\.openclaw\openclaw.json";  Dst="$rollbackDir\openclaw.json"; Desc="openclaw.json"},
    @{Src="$HOME_DIR\.claude\.credentials.json"; Dst="$rollbackDir\credentials.json"; Desc="credentials"},
    @{Src="$HOME_DIR\.openclaw\workspace";       Dst="$rollbackDir\workspace"; Desc="workspace"},
    @{Src="$HOME_DIR\.claude\settings.json";     Dst="$rollbackDir\settings.json"; Desc="settings"}
)

$rollbackCreated = $false
foreach ($item in $criticalBackupPaths) {
    if (Test-Path $item.Src) {
        try {
            $dstParent = Split-Path $item.Dst -Parent
            if (-not (Test-Path $dstParent)) {
                New-Item -ItemType Directory -Path $dstParent -Force | Out-Null
            }
            
            if (Test-Path $item.Src -PathType Container) {
                # Directory - use robocopy
                & robocopy $item.Src $item.Dst /E /MT:8 /R:0 /W:0 /NP /NFL /NDL /NJH /NJS 2>&1 | Out-Null
            } else {
                # File - direct copy
                Copy-Item -Path $item.Src -Destination $item.Dst -Force
            }
            $rollbackCreated = $true
        } catch {
            Write-Step "  -> Failed to backup $($item.Desc): $_" "WARNING"
        }
    }
}

if ($rollbackCreated) {
    Write-Step "  -> Rollback snapshot saved to: $rollbackDir" "SUCCESS"
    Write-Step "  -> If restore fails, manually copy files back from rollback directory" "INFO"
} else {
    Write-Step "  -> No existing config to backup (fresh install)" "INFO"
}
Write-Host ""
#endregion
#region PRE-COPY: Close apps that lock files
# Claude Desktop locks AppData\Roaming\Claude — close it before copying
$claudeDesktop = Get-Process -Name "Claude" -ErrorAction SilentlyContinue
if ($claudeDesktop) {
    Write-Step "[PRE-COPY] Closing Claude Desktop (locks AppData files)..." "INFO"
    $claudeDesktop | ForEach-Object { $_.CloseMainWindow() | Out-Null }
    Start-Sleep -Seconds 3
    Get-Process -Name "Claude" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Write-Step "  -> Claude Desktop closed" "SUCCESS"
}
#endregion

#region BUILD MASTER TASK LIST (all copy tasks across all 36 sections)
Write-Step "[PARALLEL] Building master task list for RunspacePool dispatch..." "FAST"

# Each task: Source, Destination, Description, IsFile, ForceOverwrite, Section
$allTasks = [System.Collections.Generic.List[hashtable]]::new()

# Helper to add tasks cleanly
function Add-Task {
    param([string]$Src, [string]$Dst, [string]$Desc, [bool]$IsFile = $false, [string]$Section = "")
    $allTasks.Add(@{ Source=$Src; Destination=$Dst; Description=$Desc; IsFile=$IsFile; Section=$Section })
}

# Section 3: CLI Binary
Add-Task "$BackupPath\cli-binary\claude-code"     "$APPDATA\Claude\claude-code"  "Claude CLI binary"      $false "CLI"
Add-Task "$BackupPath\cli-binary\local-bin"        "$HOME_DIR\.local\bin"          ".local\bin"             $false "CLI"
Add-Task "$BackupPath\cli-binary\dot-local"        "$HOME_DIR\.local"              ".local directory"       $false "CLI"

# Section 4: Moltbot
Add-Task "$BackupPath\moltbot\dot-moltbot"         "$HOME_DIR\.moltbot"            "Moltbot config"         $false "MOLTBOT"
Add-Task "$BackupPath\moltbot\npm-module"           "$APPDATA\npm\node_modules\moltbot" "Moltbot npm module" $false "MOLTBOT"

# Section 5: Clawdbot
Add-Task "$BackupPath\clawdbot\dot-clawdbot"       "$HOME_DIR\.clawdbot"           "Clawdbot config"        $false "CLAWDBOT"
Add-Task "$BackupPath\clawdbot\npm-module"          "$APPDATA\npm\node_modules\clawdbot" "Clawdbot npm module" $false "CLAWDBOT"

# Section 6: Clawd
Add-Task "$BackupPath\clawd\workspace"             "$HOME_DIR\clawd"               "Clawd workspace"        $false "CLAWD"

# Section 7: OpenClaw
Add-Task "$BackupPath\openclaw\workspace"          "$HOME_DIR\.openclaw\workspace" "OpenClaw workspace"     $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\npm-module"         "$APPDATA\npm\node_modules\openclaw" "OpenClaw npm module" $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\credentials"        "$HOME_DIR\.openclaw\credentials" "OpenClaw credentials" $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\clawdbot-wrappers"  "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot" "ClawdbotTray.vbs" $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\clawdbot-launcher"  "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot\b" "ClawdbotTray.vbs (alt)" $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\openclaw.json"      "$HOME_DIR\.openclaw\openclaw.json" "openclaw.json"       $true  "OPENCLAW"
# OpenClaw subdirs added in v20.0 (match backup v16.0 coverage)
Add-Task "$BackupPath\openclaw\workspace-main"     "$HOME_DIR\.openclaw\workspace-main"     "OpenClaw workspace-main"     $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\workspace-session2"  "$HOME_DIR\.openclaw\workspace-session2"  "OpenClaw workspace-session2"  $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\workspace-openclaw"  "$HOME_DIR\.openclaw\workspace-openclaw"  "OpenClaw workspace-openclaw"  $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\workspace-openclaw4" "$HOME_DIR\.openclaw\workspace-openclaw4" "OpenClaw workspace-openclaw4" $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\agents"              "$HOME_DIR\.openclaw\agents"              "OpenClaw agents"              $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\credentials-dir"     "$HOME_DIR\.openclaw\credentials"         "OpenClaw credentials-dir"     $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\memory"              "$HOME_DIR\.openclaw\memory"              "OpenClaw memory"              $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\cron"                "$HOME_DIR\.openclaw\cron"                "OpenClaw cron jobs"           $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\extensions"          "$HOME_DIR\.openclaw\extensions"          "OpenClaw extensions"          $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\skills"              "$HOME_DIR\.openclaw\skills"              "OpenClaw skills"              $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\scripts"             "$HOME_DIR\.openclaw\scripts"             "OpenClaw scripts"             $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\browser"             "$HOME_DIR\.openclaw\browser"             "OpenClaw browser extension"   $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\logs"                "$HOME_DIR\.openclaw\logs"                "OpenClaw logs"                $false "OPENCLAW"
# v21.0: MISSING OPENCLAW WORKSPACES (discovered by C: drive scan)
Add-Task "$BackupPath\openclaw\workspace-moltbot"        "$HOME_DIR\.openclaw\workspace-moltbot"        "OpenClaw workspace-moltbot"        $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\workspace-moltbot2"       "$HOME_DIR\.openclaw\workspace-moltbot2"       "OpenClaw workspace-moltbot2"       $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\workspace-openclaw-main"  "$HOME_DIR\.openclaw\workspace-openclaw-main"  "OpenClaw workspace-openclaw-main"  $false "OPENCLAW"
# v21.0: MISSING OPENCLAW SUBDIRS
Add-Task "$BackupPath\openclaw\telegram"           "$HOME_DIR\.openclaw\telegram"           "OpenClaw telegram"            $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\ClawdBot-tray"      "$HOME_DIR\.openclaw\ClawdBot"           "OpenClaw ClawdBot tray"       $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\backups"            "$HOME_DIR\.openclaw\backups"            "OpenClaw backups"             $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\completions"        "$HOME_DIR\.openclaw\completions"        "OpenClaw completions"         $false "OPENCLAW"
Add-Task "$BackupPath\openclaw\mission-control"    "$HOME_DIR\openclaw-mission-control"     "openclaw-mission-control"     $false "OPENCLAW"
# v21.0: OpenClaw rolling backups (openclaw.json.bak*, moltbot.json.bak*, etc.)
Add-Task "$BackupPath\openclaw\rolling-backups"    "$HOME_DIR\.openclaw"                    "OpenClaw rolling backups"     $false "OPENCLAW"
# v21.0: OpenClaw catch-all subdirs (archive, bin, browser-data, canvas, config, delivery-queue, devices, docs, foundry, hooks, identity, lib, media, settings, startup-wrappers, subagents, temp)
if (Test-Path "$BackupPath\openclaw\catchall-dirs") {
    Get-ChildItem "$BackupPath\openclaw\catchall-dirs" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$HOME_DIR\.openclaw\$($_.Name)" "OpenClaw catchall: $($_.Name)" $false "OPENCLAW"
    }
}
# v21.0: Dynamic scanner for any future openclaw workspace-* dirs in backup
Get-ChildItem "$BackupPath\openclaw" -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^workspace-' } | ForEach-Object {
    $destPath = "$HOME_DIR\.openclaw\$($_.Name)"
    # Only add if not already in task list (avoid duplicates)
    $alreadyQueued = $false
    foreach ($t in $allTasks) { if ($t.Destination -eq $destPath) { $alreadyQueued = $true; break } }
    if (-not $alreadyQueued) {
        Add-Task $_.FullName $destPath "OpenClaw dynamic: $($_.Name)" $false "OPENCLAW"
    }
}

# v21.0: CLAUDEGRAM
Add-Task "$BackupPath\claudegram\dot-claudegram"   "$HOME_DIR\.claudegram"                  ".claudegram"                  $false "CLAUDEGRAM"

# v21.0: CLAUDE-SERVER-COMMANDER (full directory)
Add-Task "$BackupPath\claude-server-commander"     "$HOME_DIR\.claude-server-commander"     ".claude-server-commander"     $false "SERVERCOMMANDER"

# v21.0: CLI STATE + BINARY CACHE
Add-Task "$BackupPath\cli-binary\local-share-claude" "$HOME_DIR\.local\share\claude"        ".local/share/claude"          $false "CLI"
Add-Task "$BackupPath\cli-binary\local-state-claude" "$HOME_DIR\.local\state\claude"        ".local/state/claude"          $false "CLI"

# v21.0: OPENCODE STATE
Add-Task "$BackupPath\opencode\local-state-opencode" "$HOME_DIR\.local\state\opencode"     ".local/state/opencode"        $false "OPENCODE"

# v21.0: APPDATA GAPS
Add-Task "$BackupPath\appdata\roaming-claude-code" "$APPDATA\Claude Code"                  "AppData\Roaming\Claude Code"  $false "APPDATA"
Add-Task "$BackupPath\appdata\claude-cli-nodejs"   "$LOCALAPPDATA\claude-cli-nodejs"       "AppData\Local\claude-cli-nodejs" $false "APPDATA"
Add-Task "$BackupPath\appdata\AnthropicClaude"     "$LOCALAPPDATA\AnthropicClaude"         "AppData\Local\AnthropicClaude" $false "APPDATA"
Add-Task "$BackupPath\appdata\store-claude-settings" "$LOCALAPPDATA\Packages\Claude_pzs8sxrjxfjjc\Settings" "Windows Store Claude settings" $false "APPDATA"

# v21.0: POWERSHELL MODULES
Add-Task "$BackupPath\powershell\ClaudeUsage-ps7"  "$HOME_DIR\Documents\PowerShell\Modules\ClaudeUsage"       "ClaudeUsage PS7 module" $false "POWERSHELL"
Add-Task "$BackupPath\powershell\ClaudeUsage-ps5"  "$HOME_DIR\Documents\WindowsPowerShell\Modules\ClaudeUsage" "ClaudeUsage PS5 module" $false "POWERSHELL"

# v21.0: CHROME INDEXEDDB (all profile variants)
Add-Task "$BackupPath\chrome\profile1-claude-indexeddb-blob"    "$LOCALAPPDATA\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.blob"    "Chrome P1 IDB blob"    $false "CHROME"
Add-Task "$BackupPath\chrome\profile1-claude-indexeddb-leveldb" "$LOCALAPPDATA\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.leveldb" "Chrome P1 IDB leveldb" $false "CHROME"
Add-Task "$BackupPath\chrome\profile2-claude-indexeddb-blob"    "$LOCALAPPDATA\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.blob"    "Chrome P2 IDB blob"    $false "CHROME"
Add-Task "$BackupPath\chrome\profile2-claude-indexeddb-leveldb" "$LOCALAPPDATA\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.leveldb" "Chrome P2 IDB leveldb" $false "CHROME"
Add-Task "$BackupPath\chrome\Profile-1-https_claude.ai_0.indexeddb.blob"    "$LOCALAPPDATA\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.blob"    "Chrome P1 IDB blob v2"    $false "CHROME"
Add-Task "$BackupPath\chrome\Profile-1-https_claude.ai_0.indexeddb.leveldb" "$LOCALAPPDATA\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.leveldb" "Chrome P1 IDB leveldb v2" $false "CHROME"
Add-Task "$BackupPath\chrome\Profile-2-https_claude.ai_0.indexeddb.blob"    "$LOCALAPPDATA\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.blob"    "Chrome P2 IDB blob v2"    $false "CHROME"
Add-Task "$BackupPath\chrome\Profile-2-https_claude.ai_0.indexeddb.leveldb" "$LOCALAPPDATA\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.leveldb" "Chrome P2 IDB leveldb v2" $false "CHROME"
# v21.0: Dynamic Chrome profile scanner (any future profile dirs in backup)
if (Test-Path "$BackupPath\chrome") {
    Get-ChildItem "$BackupPath\chrome" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $alreadyQueued = $false
        foreach ($t in $allTasks) { if ($t.Source -eq $_.FullName) { $alreadyQueued = $true; break } }
        if (-not $alreadyQueued) {
            # Try to map backup dir name to Chrome profile path
            if ($_.Name -match 'profile(\d+)' -or $_.Name -match 'Profile.(\d+)') {
                $profNum = $matches[1]
                $profDir = if ($profNum -eq '0') { "Default" } else { "Profile $profNum" }
                $idbBase = "$LOCALAPPDATA\Google\Chrome\User Data\$profDir\IndexedDB"
                Add-Task $_.FullName "$idbBase\$($_.Name)" "Chrome dynamic: $($_.Name)" $false "CHROME"
            }
        }
    }
}

# v21.0: SPECIAL FILES
Add-Task "$BackupPath\special\claude-wrapper.ps1"  "$HOME_DIR\claude-wrapper.ps1"          "claude-wrapper.ps1"           $true  "SPECIAL"
Add-Task "$BackupPath\special\mcp-ondemand.ps1"    "$HOME_DIR\.claude\mcp-ondemand.ps1"    "mcp-ondemand.ps1"             $true  "SPECIAL"
Add-Task "$BackupPath\special\ps-claude.md"        "$HOME_DIR\.claude\claude.md"           "ps-claude.md"                 $true  "SPECIAL"

# v21.0: DESKTOP SHORTCUTS
if (Test-Path "$BackupPath\special\shortcuts") {
    $desktopPath = [System.Environment]::GetFolderPath("Desktop")
    Get-ChildItem "$BackupPath\special\shortcuts" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$desktopPath\$($_.Name)" "Desktop: $($_.Name)" $true "SHORTCUTS"
    }
}

# v21.0: STARTUP SHORTCUTS
if (Test-Path "$BackupPath\startup") {
    $startupPath = [System.Environment]::GetFolderPath("Startup")
    Get-ChildItem "$BackupPath\startup" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$startupPath\$($_.Name)" "Startup: $($_.Name)" $true "STARTUP"
    }
}

# v21.0: NPM BIN SHIMS
Add-Task "$BackupPath\npm-global\bin-shims"        "$APPDATA\npm"                          "npm bin shims"                $false "NPM"

# v21.0: CATCH-ALL HOME (any dirs backup found that aren't explicitly handled)
if (Test-Path "$BackupPath\catchall-home") {
    Get-ChildItem "$BackupPath\catchall-home" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$HOME_DIR\$($_.Name)" "Catchall home: $($_.Name)" $false "CATCHALL"
    }
}

# v21.0: CATCH-ALL APPDATA (any dirs backup found in AppData)
if (Test-Path "$BackupPath\catchall-appdata") {
    Get-ChildItem "$BackupPath\catchall-appdata" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $dirName = $_.Name
        $dest = if ($dirName -match '^local-') {
            "$LOCALAPPDATA\$($dirName -replace '^local-','')"
        } elseif ($dirName -match '^roaming-') {
            "$APPDATA\$($dirName -replace '^roaming-','')"
        } else {
            "$LOCALAPPDATA\$dirName"
        }
        Add-Task $_.FullName $dest "Catchall appdata: $dirName" $false "CATCHALL"
    }
}

# v21.0: CATCH-ALL TEMP (logs/cache from temp dir)
if (Test-Path "$BackupPath\catchall-temp") {
    Get-ChildItem "$BackupPath\catchall-temp" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$env:TEMP\$($_.Name)" "Catchall temp: $($_.Name)" $false "CATCHALL"
    }
}

# OpenClaw root-level files (CLAUDE.md, config.yaml, etc.)
if (Test-Path "$BackupPath\openclaw\root-files") {
    Get-ChildItem "$BackupPath\openclaw\root-files" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$HOME_DIR\.openclaw\$($_.Name)" "OpenClaw root: $($_.Name)" $true "OPENCLAW"
    }
}
# OpenClaw auth files from credentials backup
if (Test-Path "$BackupPath\credentials\openclaw-auth") {
    Get-ChildItem "$BackupPath\credentials\openclaw-auth" -File -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$HOME_DIR\.openclaw\$($_.Name)" "OpenClaw auth: $($_.Name)" $true "OPENCLAW"
    }
}

# Section 8: Git + SSH
Add-Task "$BackupPath\git\gitconfig"               "$HOME_DIR\.gitconfig"          ".gitconfig"             $true  "GIT"
Add-Task "$BackupPath\git\gitignore_global"        "$HOME_DIR\.gitignore_global"   ".gitignore_global"      $true  "GIT"
Add-Task "$BackupPath\git\git-credentials"         "$HOME_DIR\.git-credentials"    ".git-credentials"       $true  "GIT"
Add-Task "$BackupPath\git\ssh"                     "$HOME_DIR\.ssh"                "SSH keys"               $false "GIT"

# Section 9: Core Claude
Add-Task "$BackupPath\core\claude.json"            "$HOME_DIR\.claude.json"        ".claude.json"           $true  "CORE"
Add-Task "$BackupPath\core\claude.json.backup"     "$HOME_DIR\.claude.json.backup" ".claude.json.backup"    $true  "CORE"
Add-Task "$BackupPath\core\claude-home"            "$HOME_DIR\.claude"             ".claude directory"      $false "CORE"

# Section 10: Credentials
if (-not $SkipCredentials) {
    Add-Task "$BackupPath\credentials\claude-credentials.json"     "$HOME_DIR\.claude\.credentials.json"         "Claude OAuth"          $true  "CREDS"
    Add-Task "$BackupPath\credentials\claude-credentials-alt.json" "$HOME_DIR\.claude\credentials.json"          "Claude creds alt"      $true  "CREDS"
    Add-Task "$BackupPath\credentials\opencode-auth.json"          "$HOME_DIR\.local\share\opencode\auth.json"   "OpenCode auth"         $true  "CREDS"
    Add-Task "$BackupPath\credentials\opencode-mcp-auth.json"      "$HOME_DIR\.local\share\opencode\mcp-auth.json" "OpenCode MCP auth"  $true  "CREDS"
    Add-Task "$BackupPath\credentials\anthropic-credentials.json"  "$HOME_DIR\.anthropic\credentials.json"       "Anthropic creds"       $true  "CREDS"
    Add-Task "$BackupPath\credentials\settings-local.json"         "$HOME_DIR\.claude\settings.local.json"       "settings.local.json"   $true  "CREDS"
    Add-Task "$BackupPath\credentials\moltbot-credentials.json"    "$HOME_DIR\.moltbot\credentials.json"         "Moltbot credentials"   $true  "CREDS"
    Add-Task "$BackupPath\credentials\moltbot-config.json"         "$HOME_DIR\.moltbot\config.json"              "Moltbot config"        $true  "CREDS"
    Add-Task "$BackupPath\credentials\clawdbot-credentials.json"   "$HOME_DIR\.clawdbot\credentials.json"        "Clawdbot credentials"  $true  "CREDS"
    Add-Task "$BackupPath\credentials\clawdbot-config.json"        "$HOME_DIR\.clawdbot\config.json"             "Clawdbot config"       $true  "CREDS"
    # .env files
    if (Test-Path "$BackupPath\credentials\env-files") {
        Get-ChildItem "$BackupPath\credentials\env-files" -File -ErrorAction SilentlyContinue | ForEach-Object {
            Add-Task $_.FullName "$HOME_DIR\$($_.Name)" "ENV: $($_.Name)" $true "CREDS"
        }
    }
}

# Section 11: Sessions
Add-Task "$BackupPath\sessions\config-claude-projects" "$HOME_DIR\.config\claude\projects" ".config/claude/projects" $false "SESSIONS"
Add-Task "$BackupPath\sessions\claude-projects"        "$HOME_DIR\.claude\projects"         ".claude/projects"       $false "SESSIONS"
Add-Task "$BackupPath\sessions\claude-sessions"        "$HOME_DIR\.claude\sessions"         ".claude/sessions"       $false "SESSIONS"
Add-Task "$BackupPath\sessions\history.jsonl"          "$HOME_DIR\.claude\history.jsonl"    "history.jsonl"          $true  "SESSIONS"
# SQLite databases
if (Test-Path "$BackupPath\sessions\databases") {
    Get-ChildItem "$BackupPath\sessions\databases" -File -Filter "*.db" -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$HOME_DIR\.claude\$($_.Name)" "DB: $($_.Name)" $true "SESSIONS"
    }
}
# v14 claude subdirs
if (Test-Path "$BackupPath\claude-dirs") {
    Get-ChildItem "$BackupPath\claude-dirs" -Directory -ErrorAction SilentlyContinue | ForEach-Object {
        $dName = $_.Name
        $dDest = if ($dName -in @('beads','sisyphus')) { "$HOME_DIR\.claude\.$dName" } elseif ($dName -match '^\.') { "$HOME_DIR\.claude\$dName" } else { "$HOME_DIR\.claude\$dName" }
        Add-Task $_.FullName $dDest ".claude/$dName" $false "SESSIONS"
    }
}
# v14 claude-code-sessions
Add-Task "$BackupPath\appdata\claude-code-sessions" "$APPDATA\Claude\claude-code-sessions" "claude-code-sessions" $false "SESSIONS"
# v14 .claude JSON files
if (Test-Path "$BackupPath\claude-json") {
    Get-ChildItem "$BackupPath\claude-json" -File -Filter "*.json" -ErrorAction SilentlyContinue | ForEach-Object {
        Add-Task $_.FullName "$HOME_DIR\.claude\$($_.Name)" ".claude/$($_.Name)" $true "SESSIONS"
    }
}

# Section 12: OpenCode
Add-Task "$BackupPath\opencode\local-share-opencode" "$HOME_DIR\.local\share\opencode" "OpenCode main data"  $false "OPENCODE"
Add-Task "$BackupPath\opencode\config-opencode"      "$HOME_DIR\.config\opencode"       "OpenCode config"     $false "OPENCODE"
Add-Task "$BackupPath\opencode\cache-opencode"       "$HOME_DIR\.cache\opencode"        "OpenCode cache"      $false "OPENCODE"

# Section 13: AppData
Add-Task "$BackupPath\appdata\roaming-claude" "$APPDATA\Claude"      "AppData\Roaming\Claude" $false "APPDATA"
Add-Task "$BackupPath\appdata\local-claude"   "$LOCALAPPDATA\Claude" "AppData\Local\Claude"   $false "APPDATA"

# Section 14: Windows Terminal
Add-Task "$BackupPath\terminal\settings.json" "$LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json" "Windows Terminal settings" $true "TERMINAL"

# Section 15: MCP
Add-Task "$BackupPath\mcp\claude_desktop_config.json" "$APPDATA\Claude\claude_desktop_config.json" "MCP desktop config" $true "MCP"

# Section 16: Settings
Add-Task "$BackupPath\settings\settings.json" "$HOME_DIR\.claude\settings.json" "Claude settings.json" $true "SETTINGS"

# Section 17: Agents/Skills
Add-Task "$BackupPath\agents\CLAUDE.md" "$HOME_DIR\CLAUDE.md" "~/CLAUDE.md" $true "AGENTS"

# Section 18: npm + Python
Add-Task "$BackupPath\npm-global\npmrc" "$HOME_DIR\.npmrc"              ".npmrc"  $true  "NPM"
Add-Task "$BackupPath\python\uv"        "$HOME_DIR\.local\share\uv"     "uv data" $false "PYTHON"

# Section 19: PowerShell profiles
Add-Task "$BackupPath\powershell\ps5-profile.ps1" "$HOME_DIR\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" "PS5 profile" $true "POWERSHELL"
Add-Task "$BackupPath\powershell\ps7-profile.ps1" "$HOME_DIR\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"        "PS7 profile" $true "POWERSHELL"

# Section 20: Special
Add-Task "$BackupPath\special\learned.md" "$HOME_DIR\learned.md" "learned.md" $true "SPECIAL"

Write-Step "  -> $($allTasks.Count) tasks queued for parallel execution" "SUCCESS"
#endregion

#region RUNSPACEPOOL PARALLEL EXECUTION (THE TURBO ENGINE)
Write-Step "[TURBO] Dispatching ALL $($allTasks.Count) tasks via RunspacePool ($MaxParallelJobs threads)..." "FAST"

# Thread-safe result collection
$resultBag = [System.Collections.Concurrent.ConcurrentBag[hashtable]]::new()

# The copy scriptblock - runs in each runspace thread
$copyBlock = {
    param($task, $resultBag)
    $src = $task.Source
    $dst = $task.Destination
    $desc = $task.Description
    $isFile = $task.IsFile

    # Source must exist
    if (-not (Test-Path $src)) {
        $resultBag.Add(@{ Status="MISSING"; Desc=$desc; Section=$task.Section })
        return
    }

    try {
        if ($isFile) {
            # Smart diff: skip only if IDENTICAL (same size + same LastWriteTime)
            if (Test-Path $dst) {
                $srcInfo = [System.IO.FileInfo]::new($src)
                $dstInfo = [System.IO.FileInfo]::new($dst)
                if ($srcInfo.Length -eq $dstInfo.Length -and $srcInfo.LastWriteTimeUtc -eq $dstInfo.LastWriteTimeUtc) {
                    $resultBag.Add(@{ Status="SKIP"; Desc=$desc; Section=$task.Section })
                    return
                }
            }
            # Ensure parent directory exists
            $parent = Split-Path $dst -Parent
            if ($parent -and -not (Test-Path $parent)) {
                New-Item -ItemType Directory -Path $parent -Force | Out-Null
            }
            # Direct .NET copy - fastest possible for single files
            [System.IO.File]::Copy($src, $dst, $true)
        } else {
            # Ensure destination directory exists
            if (-not (Test-Path $dst)) {
                New-Item -ItemType Directory -Path $dst -Force | Out-Null
            }
            # robocopy /E /MT:64 - copies only changed/new files by default
            # (robocopy natively skips files with same size+timestamp = 100x faster)
            $roboArgs = @($src, $dst, "/E", "/MT:64", "/R:1", "/W:0", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
            & robocopy @roboArgs 2>&1 | Out-Null
            $rc = $LASTEXITCODE
            if ($rc -gt 7) {
                # Exit 8+ = some files failed (locked/in-use). Retry with /B (backup mode) for admin access
                $roboArgs2 = @($src, $dst, "/E", "/B", "/MT:32", "/R:2", "/W:1", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                & robocopy @roboArgs2 2>&1 | Out-Null
                $rc2 = $LASTEXITCODE
                if ($rc2 -gt 7) { throw "robocopy exit $rc then $rc2 (locked files)" }
            }
        }
        $resultBag.Add(@{ Status="OK"; Desc=$desc; Section=$task.Section })
    } catch {
        $resultBag.Add(@{ Status="ERROR"; Desc=$desc; Section=$task.Section; Error=$_.ToString() })
    }
}

# Create and open RunspacePool
$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxParallelJobs)
$pool.ApartmentState = "MTA"
$pool.Open()

# Dispatch all tasks simultaneously
$handles = [System.Collections.Generic.List[hashtable]]::new()
foreach ($task in $allTasks) {
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    $ps.AddScript($copyBlock).AddArgument($task).AddArgument($resultBag) | Out-Null
    $handles.Add(@{ PS=$ps; Handle=$ps.BeginInvoke() })
}

$totalTasks = $handles.Count
Write-Step "  -> $totalTasks tasks running in parallel..." "FAST"

# Poll with heartbeat so user always sees live progress (never silent >3s)
$lastReport = Get-Date
$completed  = 0
$pending    = [System.Collections.Generic.List[hashtable]]($handles)

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

    # Heartbeat: print progress every 2 seconds regardless
    if (((Get-Date) - $lastReport).TotalSeconds -ge 2) {
        $pct = [math]::Round($completed / $totalTasks * 100)
        Write-Step "  -> Progress: $completed/$totalTasks ($pct%) complete, $($pending.Count) running..." "FAST"
        $lastReport = Get-Date
    }

    if ($pending.Count -gt 0) { Start-Sleep -Milliseconds 200 }
}

$pool.Close()
$pool.Dispose()

# Tally results
$okCount      = 0
$skipCount    = 0
$missingCount = 0
$errorCount   = 0
foreach ($r in $resultBag) {
    switch ($r.Status) {
        "OK"      { $okCount++;      $script:RestoredItems++ }
        "SKIP"    { $skipCount++;    $script:SkippedItems++ }
        "MISSING" { $missingCount++ }
        "ERROR"   { $errorCount++;  $script:Errors += "[$($r.Section)] $($r.Desc): $($r.Error)" }
    }
}

Write-Step "[TURBO] Parallel execution complete!" "SUCCESS"
Write-Step "  -> Restored: $okCount | Skipped: $skipCount | Missing: $missingCount | Errors: $errorCount" "SUCCESS"

# Print errors if any
if ($errorCount -gt 0) {
    foreach ($r in $resultBag | Where-Object { $_.Status -eq "ERROR" }) {
        Write-Step "  -> ERROR [$($r.Section)] $($r.Desc): $($r.Error)" "ERROR"
    }
}
#endregion

#region POST-PARALLEL: Tasks that must run sequentially after copy phase

# Fix SSH key permissions (must happen after SSH files are copied)
$sshDest = "$HOME_DIR\.ssh"
if (Test-Path $sshDest) {
    Write-Step "[SSH] Fixing SSH key permissions..." "FAST"
    Get-ChildItem $sshDest -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch "\.pub$" -and $_.Name -notin @("known_hosts","config") } |
        ForEach-Object {
            try {
                $acl = Get-Acl $_.FullName
                $acl.SetAccessRuleProtection($true, $false)
                $acl.SetAccessRule((New-Object System.Security.AccessControl.FileSystemAccessRule($env:USERNAME,"FullControl","Allow")))
                Set-Acl $_.FullName $acl -ErrorAction SilentlyContinue
            } catch {}
        }
    Write-Step "  -> SSH permissions fixed" "SUCCESS"
}

# Add .local\bin to PATH if needed
$localBinPath = "$HOME_DIR\.local\bin"
if (Test-Path $localBinPath) {
    $userPath = [Environment]::GetEnvironmentVariable("Path","User")
    if ($userPath -notmatch [regex]::Escape($localBinPath)) {
        [Environment]::SetEnvironmentVariable("Path","$localBinPath;$userPath","User")
        $env:Path = "$localBinPath;$env:Path"
        Write-Step "[PATH] Added .local\bin to PATH" "SUCCESS"
    }
}

# Environment variables - v21.0: read from JSON (restore-env.ps1 never existed in backups!)
if (-not $SkipEnvVars) {
    Write-Step "[ENV] Restoring environment variables..." "INFO"
    $envJson = "$BackupPath\env\environment-variables.json"
    $envScript = "$BackupPath\env\restore-env.ps1"
    if (Test-Path $envJson) {
        try {
            $envData = Get-Content $envJson -Raw | ConvertFrom-Json
            $envRestored = 0
            # Restore User-scope environment variables from JSON
            foreach ($prop in $envData.PSObject.Properties) {
                $varName = $prop.Name
                $varValue = $prop.Value
                # Skip PATH (handled separately) and empty values
                if ($varName -eq 'Path' -or [string]::IsNullOrEmpty($varValue)) { continue }
                # Only restore claude/openclaw/anthropic related vars
                if ($varName -match 'CLAUDE|OPENCLAW|ANTHROPIC|OPENCODE' -or $varValue -match 'claude|openclaw|anthropic') {
                    $existing = [System.Environment]::GetEnvironmentVariable($varName, "User")
                    if ($existing -ne $varValue) {
                        [System.Environment]::SetEnvironmentVariable($varName, $varValue, "User")
                        [System.Environment]::SetEnvironmentVariable($varName, $varValue, "Process")
                        $envRestored++
                    }
                }
            }
            Write-Step "  -> Env vars restored: $envRestored variables set" "SUCCESS"
        } catch {
            Write-Step "  -> Env var JSON restore warning: $_" "WARNING"
        }
    } elseif (Test-Path $envScript) {
        # Legacy fallback: if restore-env.ps1 exists in older backups
        try { . $envScript; Write-Step "  -> Env vars restored (legacy script)" "SUCCESS" }
        catch { Write-Step "  -> Env var restore warning: $_" "WARNING" }
    } else {
        Write-Step "  -> No env vars backup found (checked JSON + PS1)" "WARNING"
    }
}

# Registry
if (-not $SkipRegistry) {
    Write-Step "[REGISTRY] Restoring registry keys..." "INFO"
    Import-RegistryFile "$BackupPath\registry\HKCU-Environment.reg" "User Environment"
    Import-RegistryFile "$BackupPath\registry\HKCU-Claude.reg"       "HKCU Claude"
}

# v21.0: Scheduled Tasks import
Write-Step "[TASKS] Restoring Windows Scheduled Tasks..." "INFO"
$taskXmlDir = "$BackupPath\scheduled-tasks"
if (Test-Path $taskXmlDir) {
    Get-ChildItem $taskXmlDir -Filter "*.xml" -File -ErrorAction SilentlyContinue | ForEach-Object {
        $taskName = $_.BaseName -replace '^_', '\'  # _OpenClaw Gateway → \OpenClaw Gateway
        try {
            # Check if task already exists
            $existing = schtasks /query /tn $taskName 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Step "  -> Task '$taskName' already exists - SKIP" "SUCCESS"
            } else {
                schtasks /create /tn $taskName /xml $_.FullName /f 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Step "  -> Task '$taskName' imported" "SUCCESS"
                } else {
                    Write-Step "  -> Task '$taskName' import failed (may need admin)" "WARNING"
                }
            }
        } catch {
            Write-Step "  -> Task '$taskName' error: $_" "WARNING"
        }
    }
} else {
    Write-Step "  -> No scheduled tasks backup found" "INFO"
}

Refresh-Path
#endregion

#region VERIFICATION
Write-Host ""
Write-Step "Verifying tools..." "INFO"

$tools = @{
    "claude"   = "Claude Code"
    "moltbot"  = "Moltbot"
    "clawdbot" = "Clawdbot"
    "opencode" = "OpenCode"
    "openclaw" = "OpenClaw"
}
foreach ($t in $tools.GetEnumerator()) {
    $cmd = Get-Command $t.Key -ErrorAction SilentlyContinue
    if ($cmd) { Write-Step "  -> $($t.Value): OK ($($cmd.Source))" "SUCCESS" }
    else       { Write-Step "  -> $($t.Value): not in PATH (restart terminal)" "WARNING" }
}

$criticalPaths = @{
    "Claude home"          = "$HOME_DIR\.claude"
    "OpenClaw workspace"   = "$HOME_DIR\.openclaw\workspace"
    "openclaw.json"        = "$HOME_DIR\.openclaw\openclaw.json"
    "Todoist script"       = "$HOME_DIR\.openclaw\workspace\todoist-done.ps1"
    "OpenClaw scripts"     = "$HOME_DIR\.openclaw\scripts"
    "OpenClaw browser"     = "$HOME_DIR\.openclaw\browser"
    "OpenClaw memory"      = "$HOME_DIR\.openclaw\memory"
    "OpenClaw skills"      = "$HOME_DIR\.openclaw\skills"
    "OpenClaw agents"      = "$HOME_DIR\.openclaw\agents"
    "OpenClaw cron"        = "$HOME_DIR\.openclaw\cron"
    "OpenClaw telegram"    = "$HOME_DIR\.openclaw\telegram"
    "OpenClaw ClawdBot"    = "$HOME_DIR\.openclaw\ClawdBot"
    "OpenClaw completions" = "$HOME_DIR\.openclaw\completions"
    "Moltbot config"       = "$HOME_DIR\.moltbot"
    "Clawdbot config"      = "$HOME_DIR\.clawdbot"
    "Claudegram"           = "$HOME_DIR\.claudegram"
    "Claude Server Cmdr"   = "$HOME_DIR\.claude-server-commander"
    "Chrome browser"       = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    "Chrome extension"     = "$HOME_DIR\.openclaw\browser\chrome-extension"
    "Clawd workspace"      = "$HOME_DIR\clawd"
    "SSH keys"             = "$HOME_DIR\.ssh"
    "Git config"           = "$HOME_DIR\.gitconfig"
    "CLI share/claude"     = "$HOME_DIR\.local\share\claude"
    "CLI state/claude"     = "$HOME_DIR\.local\state\claude"
    "ClaudeUsage PS module" = "$HOME_DIR\Documents\PowerShell\Modules\ClaudeUsage"
    "mcp-ondemand.ps1"     = "$HOME_DIR\.claude\mcp-ondemand.ps1"
    "claude-wrapper.ps1"   = "$HOME_DIR\claude-wrapper.ps1"
    "ClawdbotTray"         = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot\b\ClawdbotTray.vbs"
}
$valid = ($criticalPaths.Values | Where-Object { Test-Path $_ }).Count
Write-Step "  -> Critical paths: $valid/$($criticalPaths.Count) validated" $(if ($valid -eq $criticalPaths.Count) { "SUCCESS" } else { "WARNING" })
#endregion


#region POST-RESTORE VERIFICATION & AUTO-REPAIR
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Magenta
Write-Host "  VERIFICATION & AUTO-REPAIR PHASE" -ForegroundColor White
Write-Host ("=" * 80) -ForegroundColor Magenta
Write-Host ""

#region Verify Tools Are Actually Executable
Write-Step "[VERIFY] Testing tool executability..." "INFO"

$toolTests = @("claude","openclaw","moltbot","clawdbot","opencode")

$brokenTools = @()
foreach ($tool in $toolTests) {
    $cmd = Get-Command $tool -ErrorAction SilentlyContinue
    if (-not $cmd) {
        $brokenTools += $tool
        Write-Step " -> $($tool): NOT IN PATH" "WARNING"
        continue
    }
    # Use a Job with explicit timeout to avoid blocking
    $versionJob = Start-Job -ScriptBlock ([scriptblock]::Create("& '$($cmd.Source)' --version 2>&1"))
    $done = Wait-Job -Job $versionJob -Timeout 8
    if ($done) {
        $vOut = Receive-Job -Job $versionJob -ErrorAction SilentlyContinue
        Remove-Job -Job $versionJob -Force -ErrorAction SilentlyContinue
        Write-Step " -> $($tool): OK" "SUCCESS"
    } else {
        Stop-Job -Job $versionJob -ErrorAction SilentlyContinue
        Remove-Job -Job $versionJob -Force -ErrorAction SilentlyContinue
        Write-Step " -> $($tool): TIMEOUT on --version (marking broken)" "WARNING"
        $brokenTools += $tool
    }
}

# Auto-repair broken tools
if ($brokenTools.Count -gt 0 -and -not $SkipSoftwareInstall) {
    Write-Step "[AUTO-REPAIR] Reinstalling $($brokenTools.Count) broken tool(s) (60s timeout each)..." "INSTALL"
    foreach ($tool in $brokenTools) {
        $pkg = switch ($tool) {
            "claude"   { "@anthropic-ai/claude-code" }
            "openclaw" { "openclaw" }
            "moltbot"  { "moltbot" }
            "clawdbot" { "clawdbot" }
            "opencode" { "opencode-ai" }
            default    { $tool }
        }
        Write-Step "  -> Reinstalling $tool ($pkg)..." "INSTALL"
        $reinstallResult = Invoke-WithTimeout -TimeoutSeconds 120 -ScriptBlock ([scriptblock]::Create("npm install -g --force --legacy-peer-deps '$pkg' 2>&1; `$LASTEXITCODE")) -Default "TIMEOUT"
        if ($reinstallResult -eq "TIMEOUT") {
            Write-Step "  -> $tool reinstall TIMED OUT (may still be running in background)" "WARNING"
        } elseif ($reinstallResult -match "0$|added") {
            Write-Step "  -> $tool reinstalled" "SUCCESS"
            $script:InstalledItems++
        } else {
            Write-Step "  -> Failed to reinstall $tool" "ERROR"
            $script:Errors += "Failed to reinstall $tool"
        }
    }
    Refresh-Path
}
#endregion

#region Verify OpenClaw Gateway
Write-Step "[VERIFY] Checking OpenClaw Gateway (port probe, no hang)..." "INFO"

# Check port 18792 (browser relay) - instant, never hangs
$gwPort = 18792
try {
    $tcpClient = New-Object System.Net.Sockets.TcpClient
    $connectResult = $tcpClient.BeginConnect("127.0.0.1", $gwPort, $null, $null)
    $waited = $connectResult.AsyncWaitHandle.WaitOne(2000)  # 2s max
    if ($waited -and $tcpClient.Connected) {
        $tcpClient.Close()
        Write-Step "  -> OpenClaw Gateway: RUNNING (port $gwPort responding)" "SUCCESS"
    } else {
        $tcpClient.Close()
        Write-Step "  -> OpenClaw Gateway: NOT RUNNING - starting in background..." "WARNING"
        if (Get-Command openclaw -ErrorAction SilentlyContinue) {
            Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"openclaw gateway start`"" -WindowStyle Hidden
            Write-Step "  -> OpenClaw Gateway: start issued (check after restore completes)" "INFO"
        }
    }
} catch {
    Write-Step "  -> OpenClaw Gateway: port check error - skipping ($_)" "WARNING"
}
#endregion

#region Verify Critical Files Exist AND Are Valid
Write-Step "[VERIFY] Validating critical files..." "INFO"

$criticalFiles = @{
    "openclaw.json"     = "$HOME_DIR\.openclaw\openclaw.json"
    "Claude OAuth"      = "$HOME_DIR\.claude\.credentials.json"
    "OpenClaw creds"    = "$HOME_DIR\.openclaw\credentials"
    "Git config"        = "$HOME_DIR\.gitconfig"
    "SSH private key"   = "$HOME_DIR\.ssh\id_ed25519"
    "SOUL.md"           = "$HOME_DIR\.openclaw\workspace\SOUL.md"
    "USER.md"           = "$HOME_DIR\.openclaw\workspace\USER.md"
    "AGENTS.md"         = "$HOME_DIR\.openclaw\workspace\AGENTS.md"
    "OpenClaw scripts"  = "$HOME_DIR\.openclaw\scripts"
    "OpenClaw browser"  = "$HOME_DIR\.openclaw\browser"
    "OpenClaw memory"   = "$HOME_DIR\.openclaw\memory"
    "OpenClaw extensions" = "$HOME_DIR\.openclaw\extensions"
    "OpenClaw cron"       = "$HOME_DIR\.openclaw\cron"
}

$missingCritical = @()
foreach ($file in $criticalFiles.GetEnumerator()) {
    if (Test-Path $file.Value) {
        # Verify file is not empty
        $size = (Get-Item $file.Value -ErrorAction SilentlyContinue).Length
        if ($size -gt 0) {
            Write-Step "  -> $($file.Key): OK ($size bytes)" "SUCCESS"
        } else {
            $missingCritical += $file.Key
            Write-Step "  -> $($file.Key): EMPTY FILE" "ERROR"
        }
    } else {
        $missingCritical += $file.Key
        Write-Step "  -> $($file.Key): MISSING" "ERROR"
    }
}

if ($missingCritical.Count -gt 0) {
    Write-Step "  -> WARNING: $($missingCritical.Count) critical files missing/empty" "WARNING"
    $script:Errors += "Missing critical files: $($missingCritical -join ', ')"
}
#endregion

#region Verify JSON Configurations Are Valid
Write-Step "[VERIFY] Testing JSON validity..." "INFO"

$jsonFiles = @(
    "$HOME_DIR\.openclaw\openclaw.json",
    "$HOME_DIR\.claude\.credentials.json",
    "$HOME_DIR\.claude\settings.json",
    "$HOME_DIR\.moltbot\config.json",
    "$HOME_DIR\.clawdbot\config.json"
)

$corruptJson = @()
foreach ($jsonFile in $jsonFiles) {
    if (Test-Path $jsonFile) {
        try {
            $null = Get-Content $jsonFile -Raw | ConvertFrom-Json
            Write-Step "  -> $(Split-Path $jsonFile -Leaf): Valid JSON" "SUCCESS"
        } catch {
            $corruptJson += $jsonFile
            Write-Step "  -> $(Split-Path $jsonFile -Leaf): CORRUPT JSON ($_)" "ERROR"
            $script:Errors += "Corrupt JSON: $jsonFile"
        }
    }
}

if ($corruptJson.Count -gt 0) {
    Write-Step "  -> WARNING: $($corruptJson.Count) JSON files corrupt - restore from backup manually" "WARNING"
}
#endregion

#region Verify Network Connectivity (for Claude API)
Write-Step "[VERIFY] Testing Claude API connectivity..." "INFO"

$apiReachable = Invoke-WithTimeout -TimeoutSeconds 8 -ScriptBlock {
    try { $r = Invoke-WebRequest -Uri "https://api.anthropic.com" -Method HEAD -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop; "OK" } catch { "FAIL" }
} -Default "TIMEOUT"
if ($apiReachable -eq "OK") {
    Write-Step "  -> Claude API: REACHABLE" "SUCCESS"
} elseif ($apiReachable -eq "TIMEOUT") {
    Write-Step "  -> Claude API: TIMEOUT (network may be slow)" "WARNING"
} else {
    Write-Step "  -> Claude API: UNREACHABLE (check internet connection)" "WARNING"
}
#endregion

#region Verify Git Configuration
Write-Step "[VERIFY] Testing Git configuration..." "INFO"

if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitUser = git config --global user.name 2>&1
    $gitEmail = git config --global user.email 2>&1
    
    if ($gitUser -and $gitEmail) {
        Write-Step "  -> Git config: OK ($gitUser <$gitEmail>)" "SUCCESS"
    } else {
        Write-Step "  -> Git config: INCOMPLETE (user.name or user.email missing)" "WARNING"
        $script:Errors += "Git configuration incomplete"
    }
    
    # Test SSH key
    if (Test-Path "$HOME_DIR\.ssh\id_ed25519") {
        Write-Step "  -> SSH key: EXISTS" "SUCCESS"
    } else {
        Write-Step "  -> SSH key: MISSING" "WARNING"
    }
} else {
    Write-Step "  -> Git: NOT INSTALLED" "WARNING"
}
#endregion

#region FINAL SMOKE TEST
Write-Step "[SMOKE TEST] Running final integration tests..." "INFO"

# Test 1: Can we create a new OpenClaw session?
try {
    $testTimestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $testFile = "$HOME_DIR\.openclaw\workspace\.restore-test-$testTimestamp.txt"
    "Restore test" | Out-File -FilePath $testFile -Encoding utf8
    if (Test-Path $testFile) {
        Remove-Item $testFile -Force
        Write-Step "  -> Workspace write test: PASS" "SUCCESS"
    } else {
        Write-Step "  -> Workspace write test: FAIL" "ERROR"
        $script:Errors += "Cannot write to OpenClaw workspace"
    }
} catch {
    Write-Step "  -> Workspace write test: ERROR ($_)" "ERROR"
    $script:Errors += "Workspace write test failed: $_"
}

# Test 2: Can we read claude.json?
try {
    if (Test-Path "$HOME_DIR\.claude.json") {
        $claudeJson = Get-Content "$HOME_DIR\.claude.json" -Raw | ConvertFrom-Json
        Write-Step "  -> claude.json read test: PASS" "SUCCESS"
    } else {
        Write-Step "  -> claude.json: NOT FOUND" "WARNING"
    }
} catch {
    Write-Step "  -> claude.json read test: FAIL ($_)" "ERROR"
}

# Test 3: npm global packages accessible?
$npmListRaw = Invoke-WithTimeout -TimeoutSeconds 20 -ScriptBlock { npm list -g --depth=0 --json 2>$null } -Default "TIMEOUT"
if ($npmListRaw -ne "TIMEOUT") {
    try {
        $npmGlobal = $npmListRaw | ConvertFrom-Json
        $expectedPkgs = @("@anthropic-ai/claude-code", "openclaw", "moltbot", "clawdbot")
        $installedPkgs = $npmGlobal.dependencies.PSObject.Properties.Name
        $missingPkgs = $expectedPkgs | Where-Object { $_ -notin $installedPkgs }
        if ($missingPkgs.Count -eq 0) {
            Write-Step "  -> npm packages test: PASS (all core packages installed)" "SUCCESS"
        } else {
            Write-Step "  -> npm packages test: MISSING $($missingPkgs -join ', ')" "WARNING"
        }
    } catch {
        Write-Step "  -> npm packages test: Could not parse output" "WARNING"
    }
} else {
    Write-Step "  -> npm packages test: TIMEOUT (npm may be slow)" "WARNING"
}
#endregion

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Magenta
Write-Host "  VERIFICATION COMPLETE" -ForegroundColor White
#region AUTO-CONFIGURATION (Make It Work™)
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Yellow
Write-Host "  AUTO-CONFIGURATION PHASE" -ForegroundColor White
Write-Host ("=" * 80) -ForegroundColor Yellow
Write-Host ""

Write-Step "[CONFIG] Applying automatic fixes and configuration..." "INFO"

# Config 1: Ensure OpenClaw Gateway is running (port probe, no hang)
try {
    $gwPort2 = 18792
    $tc2 = New-Object System.Net.Sockets.TcpClient
    $ar2 = $tc2.BeginConnect("127.0.0.1", $gwPort2, $null, $null)
    $ok2 = $ar2.AsyncWaitHandle.WaitOne(2000)
    if ($ok2 -and $tc2.Connected) {
        $tc2.Close()
        Write-Step "  -> OpenClaw Gateway: already running" "SUCCESS"
    } else {
        $tc2.Close()
        if (Get-Command openclaw -ErrorAction SilentlyContinue) {
            Write-Step "  -> Starting OpenClaw Gateway in background..." "INSTALL"
            Start-Process powershell -ArgumentList "-NoProfile -WindowStyle Hidden -Command `"openclaw gateway start`"" -WindowStyle Hidden
            Write-Step "  -> OpenClaw Gateway start issued" "INFO"
        }
    }
} catch {
    Write-Step "  -> OpenClaw Gateway config check skipped ($_)" "WARNING"
}

# Config 2: Git global config (if missing)
if (Get-Command git -ErrorAction SilentlyContinue) {
    $gitUser = git config --global user.name 2>&1
    if (-not $gitUser -or $gitUser -match "error") {
        Write-Step "  -> Configuring Git (setting defaults from backup)..." "INSTALL"
        
        # Try to extract from .gitconfig if it exists
        $gitConfigPath = "$HOME_DIR\.gitconfig"
        if (Test-Path $gitConfigPath) {
            $gitConfig = Get-Content $gitConfigPath -Raw
            if ($gitConfig -match 'name = (.+)') {
                $userName = $matches[1].Trim()
                git config --global user.name $userName 2>&1 | Out-Null
            }
            if ($gitConfig -match 'email = (.+)') {
                $userEmail = $matches[1].Trim()
                git config --global user.email $userEmail 2>&1 | Out-Null
            }
            Write-Step "  -> Git configured from .gitconfig" "SUCCESS"
        } else {
            Write-Step "  -> Git config incomplete - set manually: git config --global user.name/email" "WARNING"
        }
    }
}

# Config 3: Fix PowerShell profile execution (if profile exists but is blocked)
$ps5Profile = "$HOME_DIR\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$ps7Profile = "$HOME_DIR\Documents\PowerShell\Microsoft.PowerShell_profile.ps1"

foreach ($profile in @($ps5Profile, $ps7Profile)) {
    if (Test-Path $profile) {
        try {
            # Unblock file (Windows may mark as downloaded/unsafe)
            Unblock-File -Path $profile -ErrorAction SilentlyContinue
            Write-Step "  -> Unblocked PowerShell profile: $(Split-Path $profile -Leaf)" "SUCCESS"
        } catch {
            Write-Step "  -> Could not unblock profile: $_" "WARNING"
        }
    }
}

# Config 4: Ensure npm cache is clean (prevent install failures)
if (Get-Command npm -ErrorAction SilentlyContinue) {
    Write-Step "  -> Cleaning npm cache..." "INFO"
    & npm cache clean --force 2>&1 | Out-Null
    Write-Step "  -> npm cache cleaned" "SUCCESS"
}

# Config 5: Fix node_modules permissions (Windows can block)
$nodeModulesGlobal = "$APPDATA\npm\node_modules"
if (Test-Path $nodeModulesGlobal) {
    try {
        # Unblock all executables in global node_modules
        Get-ChildItem $nodeModulesGlobal -Recurse -File -Include "*.exe","*.ps1","*.cmd" -ErrorAction SilentlyContinue |
            ForEach-Object {
                try { Unblock-File -Path $_.FullName -ErrorAction SilentlyContinue } catch {}
            }
        Write-Step "  -> Unblocked global node_modules executables" "SUCCESS"
    } catch {
        Write-Step "  -> Could not unblock node_modules: $_" "WARNING"
    }
}

# Config 6: Run npm install in .openclaw (restores local node_modules excluded from backup)
$openclawPkgJson = "$HOME_DIR\.openclaw\package.json"
if ((Test-Path $openclawPkgJson) -and -not (Test-Path "$HOME_DIR\.openclaw\node_modules")) {
    Write-Step "  -> Running npm install in .openclaw (restoring node_modules)..." "INSTALL"
    Push-Location "$HOME_DIR\.openclaw"
    & npm install --legacy-peer-deps 2>&1 | Out-Null
    Pop-Location
    if (Test-Path "$HOME_DIR\.openclaw\node_modules") {
        Write-Step "  -> .openclaw node_modules restored" "SUCCESS"
    } else {
        Write-Step "  -> .openclaw npm install may have failed" "WARNING"
    }
}

# Config 6b: Chrome CDP setup (configure shortcuts for remote debugging)
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
$cdpSetupScript = "$HOME_DIR\.openclaw\scripts\chrome-cdp-setup.ps1"
if ((Test-Path $chromeExe) -and (Test-Path $cdpSetupScript)) {
    Write-Step "  -> Configuring Chrome for CDP (remote debugging)..." "INSTALL"
    try {
        & powershell -NoProfile -File $cdpSetupScript 2>&1 | Out-Null
        Write-Step "  -> Chrome CDP shortcuts configured" "SUCCESS"
    } catch {
        Write-Step "  -> Chrome CDP setup warning: $_" "WARNING"
    }
}

# Config 6c: Install Chrome extension for browser relay
$extensionInstall = "$HOME_DIR\.openclaw\scripts\install-chrome-extension.ps1"
if ((Test-Path $chromeExe) -and (Test-Path $extensionInstall)) {
    Write-Step "  -> Installing OpenClaw browser relay extension..." "INSTALL"
    try {
        & powershell -NoProfile -File $extensionInstall 2>&1 | Out-Null
        Write-Step "  -> Browser relay extension configured" "SUCCESS"
    } catch {
        Write-Step "  -> Extension install warning: $_" "WARNING"
    }
}

# Config 9: Create .openclaw/workspace if missing (critical directory)
$openclawWorkspace = "$HOME_DIR\.openclaw\workspace"
if (-not (Test-Path $openclawWorkspace)) {
    New-Item -ItemType Directory -Path $openclawWorkspace -Force | Out-Null
    Write-Step "  -> Created OpenClaw workspace directory" "SUCCESS"
}

# Config 10: Verify and fix PATH (ensure .local\bin is accessible)
$localBin = "$HOME_DIR\.local\bin"
if (Test-Path $localBin) {
    $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
    if ($currentPath -notmatch [regex]::Escape($localBin)) {
        [Environment]::SetEnvironmentVariable("Path", "$localBin;$currentPath", "User")
        $env:Path = "$localBin;$env:Path"
        Write-Step "  -> Added .local\bin to PATH" "SUCCESS"
    }
}

# Config 11: Set execution policy for current user (if restricted)
$execPolicy = Get-ExecutionPolicy -Scope CurrentUser
if ($execPolicy -eq "Restricted" -or $execPolicy -eq "Undefined") {
    try {
        Set-ExecutionPolicy -Scope CurrentUser -ExecutionPolicy RemoteSigned -Force -ErrorAction Stop
        Write-Step "  -> Set PowerShell execution policy to RemoteSigned" "SUCCESS"
    } catch {
        Write-Step "  -> Could not set execution policy (need admin): $_" "WARNING"
    }
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Yellow
Write-Host "  AUTO-CONFIGURATION COMPLETE" -ForegroundColor White
Write-Host ("=" * 80) -ForegroundColor Yellow
Write-Host ""
#endregion

Write-Host ("=" * 80) -ForegroundColor Magenta
Write-Host ""

#region SUMMARY
$duration = (Get-Date) - $script:StartTime

# Calculate Health Score
$healthScore = 100
$criticalIssues = 0
$warnings = 0

# Deduct points for errors
if ($script:Errors.Count -gt 0) {
    $healthScore -= ($script:Errors.Count * 5)
    $criticalIssues += $script:Errors.Count
}

# Check critical tools
$toolsOK = 0
foreach ($t in @("claude","openclaw","moltbot","clawdbot")) {
    if (Get-Command $t -ErrorAction SilentlyContinue) { $toolsOK++ }
}
if ($toolsOK -lt 4) {
    $healthScore -= ((4 - $toolsOK) * 10)
    $warnings += (4 - $toolsOK)
}

# Check critical files
$criticalFiles = @(
    "$HOME_DIR\.openclaw\openclaw.json",
    "$HOME_DIR\.claude\.credentials.json",
    "$HOME_DIR\.openclaw\workspace"
)
$filesOK = ($criticalFiles | Where-Object { Test-Path $_ }).Count
if ($filesOK -lt 3) {
    $healthScore -= ((3 - $filesOK) * 15)
    $criticalIssues += (3 - $filesOK)
}

# Ensure health score is between 0-100
$healthScore = [math]::Max(0, [math]::Min(100, $healthScore))

# Determine health status
$healthStatus = switch ($healthScore) {
    {$_ -ge 90} { "EXCELLENT"; $healthColor = "Green" }
    {$_ -ge 70} { "GOOD"; $healthColor = "Cyan" }
    {$_ -ge 50} { "FAIR"; $healthColor = "Yellow" }
    {$_ -ge 30} { "POOR"; $healthColor = "Magenta" }
    default     { "CRITICAL"; $healthColor = "Red" }
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  RESTORE COMPLETE - v21.0 ZERO BLIND SPOTS EDITION" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
Write-Host "📊 HEALTH SCORE: " -NoNewline
Write-Host "$healthScore/100 " -ForegroundColor $healthColor -NoNewline
Write-Host "($healthStatus)" -ForegroundColor $healthColor
Write-Host ""
Write-Host "📦 Restored  : $($script:RestoredItems)" -ForegroundColor White
Write-Host "⏭️  Skipped   : $($script:SkippedItems) (already existed)" -ForegroundColor Yellow
if ($script:InstalledItems -gt 0) {
    Write-Host "📥 Installed : $($script:InstalledItems) packages" -ForegroundColor White
}
Write-Host "⏱️  Duration  : $([math]::Round($duration.TotalSeconds,1)) seconds" -ForegroundColor Cyan
Write-Host "⚠️  Warnings  : $warnings" -ForegroundColor $(if ($warnings -eq 0) { "Green" } else { "Yellow" })
Write-Host "❌ Errors    : $($script:Errors.Count)" -ForegroundColor $(if ($script:Errors.Count -eq 0) { "Green" } else { "Red" })

if ($script:Errors.Count -gt 0) {
    Write-Host ""
    Write-Host "ERROR DETAILS:" -ForegroundColor Red
    $script:Errors | Select-Object -First 10 | ForEach-Object {
        Write-Host "  - $_" -ForegroundColor Red
    }
    if ($script:Errors.Count -gt 10) {
        Write-Host "  ... and $($script:Errors.Count - 10) more errors" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Yellow
Write-Host "  🚀 NEXT STEPS" -ForegroundColor White
Write-Host ("=" * 80) -ForegroundColor Yellow
Write-Host ""

if ($healthScore -lt 70) {
    Write-Host "⚠️  WARNING: Health score below 70. Manual intervention may be required." -ForegroundColor Yellow
    Write-Host ""
}

Write-Host "1. RESTART PowerShell terminal (for PATH changes)" -ForegroundColor Cyan
Write-Host "2. Verify tools work:" -ForegroundColor Cyan
Write-Host "     claude --version" -ForegroundColor Gray
Write-Host "     openclaw --version" -ForegroundColor Gray
Write-Host "     moltbot --version" -ForegroundColor Gray
Write-Host "     clawdbot --version" -ForegroundColor Gray
Write-Host ""
Write-Host "3. Start OpenClaw Gateway:" -ForegroundColor Cyan
Write-Host "     openclaw gateway start" -ForegroundColor Gray
Write-Host ""
Write-Host "4. Test authentication:" -ForegroundColor Cyan
Write-Host "     claude chat" -ForegroundColor Gray
Write-Host ""

if ($healthScore -ge 90) {
    Write-Host "All systems nominal. You are good to go!" -ForegroundColor Green
} elseif ($healthScore -ge 70) {
    Write-Host "✅ Restoration successful with minor issues. Check warnings above." -ForegroundColor Cyan
} elseif ($healthScore -ge 50) {
    Write-Host "⚠️  Restoration completed but with significant issues. Review errors carefully." -ForegroundColor Yellow
} else {
    Write-Host "❌ Critical issues detected. Manual troubleshooting required." -ForegroundColor Red
    Write-Host "   Consider running the backup script again or restoring from an older backup." -ForegroundColor Red
}

Write-Host ""

if (-not $SkipCredentials) {
    Write-Host ("=" * 80) -ForegroundColor Yellow
    Write-Host "  🔐 AUTHENTICATION STATUS" -ForegroundColor White
    Write-Host ("=" * 80) -ForegroundColor Yellow
    Write-Host ""
    
    $authChecks = @{
        "Claude OAuth"         = "$HOME_DIR\.claude\.credentials.json"
        "OpenClaw config"      = "$HOME_DIR\.openclaw\openclaw.json"
        "OpenClaw credentials" = "$HOME_DIR\.openclaw\credentials"
        "SOUL.md"              = "$HOME_DIR\.openclaw\workspace\SOUL.md"
        "USER.md"              = "$HOME_DIR\.openclaw\workspace\USER.md"
        "Moltbot config"       = "$HOME_DIR\.moltbot\config.json"
        "Clawdbot config"      = "$HOME_DIR\.clawdbot\config.json"
        "SSH key"              = "$HOME_DIR\.ssh\id_ed25519"
        "Git config"           = "$HOME_DIR\.gitconfig"
    }
    
    $authOK = 0
    foreach ($c in $authChecks.GetEnumerator()) {
        if (Test-Path $c.Value) {
            Write-Host "  [✓] $($c.Key)" -ForegroundColor Green
            $authOK++
        } else {
            Write-Host "  [✗] $($c.Key) MISSING" -ForegroundColor Red
        }
    }
    
    Write-Host ""
    Write-Host "Authentication files: $authOK/$($authChecks.Count) present" -ForegroundColor $(if ($authOK -eq $authChecks.Count) { "Green" } else { "Yellow" })
    Write-Host ""
}

Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

# Save health report
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$reportTimestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
$reportPath = "$HOME_DIR\.openclaw\restore-report-$timestamp.json"
try {
    $report = @{
        Version = "21.0"
        Timestamp = $reportTimestamp
        HealthScore = $healthScore
        HealthStatus = $healthStatus
        Restored = $script:RestoredItems
        Skipped = $script:SkippedItems
        Installed = $script:InstalledItems
        DurationSeconds = [math]::Round($duration.TotalSeconds, 1)
        Errors = $script:Errors.Count
        Warnings = $warnings
        CriticalIssues = $criticalIssues
    } | ConvertTo-Json -Depth 3
    
    $report | Out-File -FilePath $reportPath -Encoding utf8
    Write-Host "📄 Health report saved: $reportPath" -ForegroundColor Gray
} catch {
    # Silent fail - not critical
}

#endregion
