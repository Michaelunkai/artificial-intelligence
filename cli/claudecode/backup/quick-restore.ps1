<#
.SYNOPSIS
    Quick-Restore Script for Claude Code - One-liner for fresh Windows installs
.DESCRIPTION
    Minimal script designed to be run as a single command on fresh Windows installations.
    Automatically downloads and runs the full restore from a network/USB backup location.
.PARAMETER BackupPath
    Path to the backup directory (local, network, or USB)
.PARAMETER Force
    Skip all confirmation prompts
.EXAMPLE
    .\quick-restore.ps1 -BackupPath "F:\backup\claudecode"
.NOTES
    Version: 1.0
    Requires: PowerShell 5.0+, Windows 10/11
#>

param(
    [Parameter(Position=0)]
    [string]$BackupPath = "F:\backup\claudecode",
    [switch]$Force,
    [switch]$Verbose
)

$ErrorActionPreference = "Stop"
$script:StartTime = Get-Date

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor $Color
}

function Write-Error-Status {
    param([string]$Message)
    Write-Status $Message "Red"
}

function Write-Success {
    param([string]$Message)
    Write-Status $Message "Green"
}

# Banner
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "          Claude Code Quick-Restore v1.0                       " -ForegroundColor Cyan
Write-Host "          One-liner for Fresh Windows Installs                 " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Validate backup path
Write-Status "Validating backup path: $BackupPath"

if (-not (Test-Path $BackupPath)) {
    $commonPaths = @(
        "F:\backup\claudecode",
        "E:\backup\claudecode",
        "D:\backup\claudecode",
        "$env:USERPROFILE\backup\claudecode"
    )

    foreach ($path in $commonPaths) {
        if (Test-Path $path) {
            $BackupPath = $path
            Write-Status "Found backup at: $BackupPath" "Yellow"
            break
        }
    }

    if (-not (Test-Path $BackupPath)) {
        Write-Error-Status "No backup found. Please specify path with -BackupPath"
        exit 1
    }
}

# Step 2: Find latest backup
Write-Status "Searching for latest backup..."

$latestBackup = Get-ChildItem -Path $BackupPath -Directory -Filter "backup_*" -ErrorAction SilentlyContinue |
    Sort-Object Name -Descending |
    Select-Object -First 1

if (-not $latestBackup) {
    Write-Error-Status "No backup directories found in $BackupPath"
    exit 1
}

$backupDir = $latestBackup.FullName
Write-Success "Found backup: $($latestBackup.Name)"

# Step 3: Check for restore script
$restoreScript = Join-Path $BackupPath "restore-claudecode.ps1"
if (-not (Test-Path $restoreScript)) {
    $restoreScript = Join-Path (Split-Path $BackupPath -Parent) "restore-claudecode.ps1"
}

if (-not (Test-Path $restoreScript)) {
    $foundScript = Get-ChildItem -Path $BackupPath -Recurse -Filter "restore-claudecode.ps1" -ErrorAction SilentlyContinue |
        Select-Object -First 1
    if ($foundScript) {
        $restoreScript = $foundScript.FullName
    }
}

# Step 4: Pre-flight checks
Write-Status "Running pre-flight checks..."

$psVersion = $PSVersionTable.PSVersion.Major
if ($psVersion -lt 5) {
    Write-Error-Status "PowerShell 5.0+ required. Current: $psVersion"
    exit 1
}
Write-Status "  PowerShell version: $psVersion [OK]" "DarkGray"

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Status "  Running without admin rights (some features may be limited)" "Yellow"
} else {
    Write-Status "  Administrator rights: [OK]" "DarkGray"
}

$freeSpace = (Get-PSDrive -Name C).Free / 1GB
$backupSize = (Get-ChildItem -Path $backupDir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1GB

if ($freeSpace -lt ($backupSize * 1.5)) {
    $needed = [math]::Round($backupSize * 1.5, 2)
    $available = [math]::Round($freeSpace, 2)
    Write-Status "  Warning: Low disk space. Need: $needed GB, Available: $available GB" "Yellow"
} else {
    $available = [math]::Round($freeSpace, 2)
    Write-Status "  Disk space: $available GB available [OK]" "DarkGray"
}

# Step 5: Check/Install Node.js
Write-Status "Checking Node.js installation..."

$nodeInstalled = $false
try {
    $nodeVersion = & node --version 2>$null
    if ($nodeVersion) {
        Write-Status "  Node.js already installed: $nodeVersion" "DarkGray"
        $nodeInstalled = $true
    }
} catch {
    $nodeInstalled = $false
}

if (-not $nodeInstalled) {
    Write-Status "Node.js not found. Attempting installation..." "Yellow"

    $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
    if ($wingetAvailable) {
        Write-Status "  Installing via winget..."
        try {
            $null = & winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements 2>&1
            if ($LASTEXITCODE -eq 0) {
                Write-Success "  Node.js installed via winget"
                $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                $nodeInstalled = $true
            }
        } catch {
            Write-Status "  winget installation failed" "Yellow"
        }
    }

    if (-not $nodeInstalled) {
        $chocoAvailable = Get-Command choco -ErrorAction SilentlyContinue
        if ($chocoAvailable) {
            Write-Status "  Installing via chocolatey..."
            try {
                & choco install nodejs-lts -y 2>&1 | Out-Null
                if ($LASTEXITCODE -eq 0) {
                    Write-Success "  Node.js installed via chocolatey"
                    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
                    $nodeInstalled = $true
                }
            } catch {
                Write-Status "  chocolatey installation failed" "Yellow"
            }
        }
    }

    if (-not $nodeInstalled) {
        Write-Error-Status "Could not install Node.js automatically."
        Write-Host "Please install Node.js manually from: https://nodejs.org/" -ForegroundColor Yellow
        Write-Host "Then run this script again." -ForegroundColor Yellow
        exit 1
    }
}

# Step 6: Confirm restore
if (-not $Force) {
    Write-Host ""
    Write-Host "Ready to restore Claude Code from:" -ForegroundColor Cyan
    Write-Host "  Backup: $backupDir" -ForegroundColor White
    Write-Host ""
    Write-Host "This will:" -ForegroundColor Cyan
    Write-Host "  - Install Claude Code CLI globally" -ForegroundColor White
    Write-Host "  - Restore all settings and configurations" -ForegroundColor White
    Write-Host "  - Restore MCP servers" -ForegroundColor White
    Write-Host "  - Install required npm packages" -ForegroundColor White
    Write-Host ""

    $confirm = Read-Host "Continue? (Y/n)"
    if ($confirm -eq 'n' -or $confirm -eq 'N') {
        Write-Status "Restore cancelled by user" "Yellow"
        exit 0
    }
}

# Step 7: Execute restore
Write-Status "Starting restore process..."

if (Test-Path $restoreScript) {
    Write-Status "Using full restore script: $restoreScript"

    $restoreParams = @{
        BackupPath = $backupDir
        Force = $true
    }

    if ($Verbose) {
        $restoreParams.Verbose = $true
    }

    try {
        & $restoreScript @restoreParams
        $restoreExitCode = $LASTEXITCODE
    } catch {
        Write-Error-Status "Restore script failed: $_"
        $restoreExitCode = 1
    }
} else {
    Write-Status "No full restore script found. Performing minimal restore..."

    $claudeDir = "$env:USERPROFILE\.claude"
    $claudeJson = "$env:USERPROFILE\.claude.json"

    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    $backupClaudeDir = Join-Path $backupDir ".claude"
    if (Test-Path $backupClaudeDir) {
        Write-Status "Restoring .claude directory..."
        Copy-Item -Path "$backupClaudeDir\*" -Destination $claudeDir -Recurse -Force -ErrorAction SilentlyContinue
    }

    $backupClaudeJson = Join-Path $backupDir ".claude.json"
    if (Test-Path $backupClaudeJson) {
        Write-Status "Restoring .claude.json..."
        Copy-Item -Path $backupClaudeJson -Destination $claudeJson -Force
    }

    Write-Status "Installing Claude Code CLI..."
    try {
        & npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Claude Code CLI installed"
        } else {
            Write-Status "CLI installation may have issues" "Yellow"
        }
    } catch {
        Write-Status "CLI installation error: $_" "Yellow"
    }

    $restoreExitCode = 0
}

# Step 8: Verify installation
Write-Status "Verifying installation..."

$verifyOk = $true

try {
    $claudeVersion = & claude --version 2>$null
    if ($claudeVersion) {
        Write-Success "  Claude CLI: $claudeVersion [OK]"
    } else {
        Write-Status "  Claude CLI: Not responding" "Yellow"
        $verifyOk = $false
    }
} catch {
    Write-Status "  Claude CLI: Not found" "Yellow"
    $verifyOk = $false
}

if (Test-Path "$env:USERPROFILE\.claude\settings.json") {
    Write-Success "  Settings: [OK]"
} else {
    Write-Status "  Settings: Missing" "Yellow"
}

# Summary
$duration = (Get-Date) - $script:StartTime

Write-Host ""
Write-Host "================================================================" -ForegroundColor Green
Write-Host "                   Quick-Restore Complete                      " -ForegroundColor Green
Write-Host "================================================================" -ForegroundColor Green
Write-Host ""
$durationStr = "{0:D2}:{1:D2}" -f [int]$duration.TotalMinutes, $duration.Seconds
Write-Host "Duration: $durationStr" -ForegroundColor Cyan
Write-Host ""

if ($verifyOk) {
    Write-Host "Claude Code is ready to use!" -ForegroundColor Green
    Write-Host "Run 'claude' to start." -ForegroundColor Cyan
} else {
    Write-Host "Restore completed with warnings. You may need to:" -ForegroundColor Yellow
    Write-Host "  1. Open a new terminal window" -ForegroundColor White
    Write-Host "  2. Run 'npm install -g @anthropic-ai/claude-code'" -ForegroundColor White
    Write-Host "  3. Run 'claude' to verify" -ForegroundColor White
}

Write-Host ""
exit $restoreExitCode
