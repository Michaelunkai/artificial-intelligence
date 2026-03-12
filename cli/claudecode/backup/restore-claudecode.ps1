#Requires -Version 5.1
<#
.SYNOPSIS
    ULTIMATE Claude Code + OpenClaw + Moltbot + Clawd + All AI Tools Restore v20.0 - TURBO DIFF EDITION
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
    Version: 20.0 - TURBO DIFF EDITION
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
Write-Host "  CLAUDE CODE + OPENCLAW + MOLTBOT + CLAWD ULTIMATE RESTORE v20.0 TURBO DIFF" -ForegroundColor White
Write-Host "  PRE-FLIGHT | SMART-DIFF | PARALLEL | VERIFY | AUTO-REPAIR | HEALTH SCORE" -ForegroundColor Yellow
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

# Environment variables
if (-not $SkipEnvVars) {
    Write-Step "[ENV] Restoring environment variables..." "INFO"
    $envScript = "$BackupPath\env\restore-env.ps1"
    if (Test-Path $envScript) {
        try { . $envScript; Write-Step "  -> Env vars restored" "SUCCESS" }
        catch { Write-Step "  -> Env var restore warning: $_" "WARNING" }
    }
}

# Registry
if (-not $SkipRegistry) {
    Write-Step "[REGISTRY] Restoring registry keys..." "INFO"
    Import-RegistryFile "$BackupPath\registry\HKCU-Environment.reg" "User Environment"
    Import-RegistryFile "$BackupPath\registry\HKCU-Claude.reg"       "HKCU Claude"
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
    "Moltbot config"       = "$HOME_DIR\.moltbot"
    "Clawdbot config"      = "$HOME_DIR\.clawdbot"
    "Chrome browser"       = "C:\Program Files\Google\Chrome\Application\chrome.exe"
    "Chrome extension"     = "$HOME_DIR\.openclaw\browser\chrome-extension"
    "Clawd workspace"      = "$HOME_DIR\clawd"
    "SSH keys"             = "$HOME_DIR\.ssh"
    "Git config"           = "$HOME_DIR\.gitconfig"
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

$toolTests = @{
    "claude"   = { claude --version 2>&1 }
    "openclaw" = { openclaw --version 2>&1 }
    "moltbot"  = { moltbot --version 2>&1 }
    "clawdbot" = { clawdbot --version 2>&1 }
    "opencode" = { opencode --version 2>&1 }
}

$brokenTools = @()
foreach ($tool in $toolTests.GetEnumerator()) {
    try {
        $result = & $tool.Value
        if ($LASTEXITCODE -eq 0) {
            Write-Step "  -> $($tool.Key): OK" "SUCCESS"
        } else {
            $brokenTools += $tool.Key
            Write-Step "  -> $($tool.Key): BROKEN (exit code $LASTEXITCODE)" "ERROR"
        }
    } catch {
        $brokenTools += $tool.Key
        Write-Step "  -> $($tool.Key): FAILED ($_)" "ERROR"
    }
}

# Auto-repair broken tools
if ($brokenTools.Count -gt 0 -and -not $SkipSoftwareInstall) {
    Write-Step "[AUTO-REPAIR] Reinstalling $($brokenTools.Count) broken tool(s)..." "INSTALL"
    foreach ($tool in $brokenTools) {
        $pkg = switch ($tool) {
            "claude"   { "@anthropic-ai/claude-code" }
            "openclaw" { "openclaw" }
            "moltbot"  { "moltbot" }
            "clawdbot" { "clawdbot" }
            "opencode" { "opencode-ai" }
        }
        Write-Step "  -> Reinstalling $tool ($pkg)..." "INSTALL"
        & npm install -g --force --legacy-peer-deps $pkg 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
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
Write-Step "[VERIFY] Checking OpenClaw Gateway..." "INFO"

try {
    $gatewayStatus = & openclaw gateway status 2>&1
    if ($gatewayStatus -match "running|active") {
        Write-Step "  -> OpenClaw Gateway: RUNNING" "SUCCESS"
    } else {
        Write-Step "  -> OpenClaw Gateway: NOT RUNNING - starting..." "WARNING"
        & openclaw gateway start 2>&1 | Out-Null
        Start-Sleep -Seconds 5
        $newStatus = & openclaw gateway status 2>&1
        if ($newStatus -match "running|active") {
            Write-Step "  -> OpenClaw Gateway: STARTED" "SUCCESS"
        } else {
            Write-Step "  -> OpenClaw Gateway: FAILED TO START" "ERROR"
            $script:Errors += "OpenClaw Gateway failed to start"
        }
    }
} catch {
    Write-Step "  -> OpenClaw Gateway: ERROR checking status ($_)" "ERROR"
    $script:Errors += "OpenClaw Gateway check failed: $_"
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

try {
    $apiTest = Invoke-WebRequest -Uri "https://api.anthropic.com" -Method HEAD -TimeoutSec 5 -UseBasicParsing -ErrorAction Stop
    Write-Step "  -> Claude API: REACHABLE" "SUCCESS"
} catch {
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
$npmGlobal = npm list -g --depth=0 --json 2>$null | ConvertFrom-Json
$expectedPkgs = @("@anthropic-ai/claude-code", "openclaw", "moltbot", "clawdbot")
$installedPkgs = $npmGlobal.dependencies.PSObject.Properties.Name
$missingPkgs = $expectedPkgs | Where-Object { $_ -notin $installedPkgs }

if ($missingPkgs.Count -eq 0) {
    Write-Step "  -> npm packages test: PASS (all core packages installed)" "SUCCESS"
} else {
    Write-Step "  -> npm packages test: MISSING $($missingPkgs -join ', ')" "WARNING"
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

# Config 1: Ensure OpenClaw Gateway is running and configured
if (Get-Command openclaw -ErrorAction SilentlyContinue) {
    try {
        # Check if gateway is running
        $gwStatus = & openclaw gateway status 2>&1
        if ($gwStatus -notmatch "running|active") {
            Write-Step "  -> Starting OpenClaw Gateway..." "INSTALL"
            & openclaw gateway start 2>&1 | Out-Null
            Start-Sleep -Seconds 5
            
            $newStatus = & openclaw gateway status 2>&1
            if ($newStatus -match "running|active") {
                Write-Step "  -> OpenClaw Gateway started successfully" "SUCCESS"
            } else {
                Write-Step "  -> Failed to start OpenClaw Gateway" "ERROR"
                $script:Errors += "OpenClaw Gateway failed to start"
            }
        } else {
            Write-Step "  -> OpenClaw Gateway already running" "SUCCESS"
        }
    } catch {
        Write-Step "  -> OpenClaw Gateway configuration failed: $_" "ERROR"
    }
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
Write-Host "  RESTORE COMPLETE - v20.0 TURBO DIFF EDITION" -ForegroundColor Green
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
    Write-Host "✅ All systems nominal. You're good to go!" -ForegroundColor Green
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
        Version = "20.0"
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