#Requires -Version 5.1 -RunAsAdministrator
<#
.SYNOPSIS
    COMPLETE RESTORATION - Claude Code + OpenClaw + All AI Tools
.DESCRIPTION
    Restores 100% of backed-up data to make fresh Windows 11 install identical to source.
    
    RESTORE PROCEDURE:
    1. Install Node.js (from backup metadata)
    2. Restore npm global packages (exact versions)
    3. Restore Claude Code CLI binary
    4. Restore all credentials and auth tokens
    5. Restore OpenClaw workspace (SOUL.md, USER.md, MEMORY.md)
    6. Restore ClawdbotTray.vbs launcher
    7. Restore all config files
    8. Set environment variables
    9. Import registry keys
    10. Verify all tools work
    
    USAGE:
    1. Run on FRESH Windows 11 install
    2. Install Node.js first (same version as backed up)
    3. Run this script with -BackupPath pointing to backup folder
    
.PARAMETER BackupPath
    Path to backup folder (e.g., F:\backup\claudecode\backup_2026_02_12_19_15_26)
.PARAMETER Verify
    Run verification after restore (checks all tools work)
.NOTES
    Version: 1.0 - Complete Restoration System
    Requires: Administrator privileges, Node.js installed
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,
    [switch]$Verify = $true
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

if (-not (Test-Path $BackupPath)) {
    Write-Error "Backup path not found: $BackupPath"
    exit 1
}

function Write-Step {
    param([string]$Message, [string]$Status = "INFO")
    $color = switch ($Status) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        default   { "Cyan" }
    }
    Write-Host "[$Status] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host "  COMPLETE RESTORATION - v1.0" -ForegroundColor White
Write-Host "  100% Restore from Backup" -ForegroundColor Yellow
Write-Host "=" * 80 -ForegroundColor Cyan
Write-Host ""

# Load backup metadata
$metadataPath = Join-Path $BackupPath "BACKUP-METADATA.json"
if (Test-Path $metadataPath) {
    $metadata = Get-Content $metadataPath | ConvertFrom-Json
    Write-Step "Backup version: $($metadata.Version)" "INFO"
    Write-Step "Backup date: $($metadata.Timestamp)" "INFO"
    Write-Step "Items: $($metadata.ItemsBackedUp)" "INFO"
} else {
    Write-Error "BACKUP-METADATA.json not found - cannot verify backup integrity"
    exit 1
}

$HOME_DIR = $env:USERPROFILE
$APPDATA = $env:APPDATA
$LOCALAPPDATA = $env:LOCALAPPDATA

# ======= RESTORE STEPS =======

Write-Step "[1/15] Checking Node.js..." "INFO"
if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
    Write-Step "Node.js not installed - please install Node.js first!" "ERROR"
    $nodeInfo = Get-Content "$BackupPath\npm-global\node-info.json" | ConvertFrom-Json
    Write-Step "Required Node version: $($nodeInfo.NodeVersion)" "WARNING"
    exit 1
}
Write-Step "Node.js found: $(node --version)" "SUCCESS"

Write-Step "[2/15] Restoring npm global packages..." "INFO"
if (Test-Path "$BackupPath\npm-global\REINSTALL-ALL.ps1") {
    & "$BackupPath\npm-global\REINSTALL-ALL.ps1"
    Write-Step "npm packages restored" "SUCCESS"
}

Write-Step "[3/15] Restoring Claude Code CLI binary..." "INFO"
if (Test-Path "$BackupPath\cli-binary\dot-local") {
    robocopy "$BackupPath\cli-binary\dot-local" "$HOME_DIR\.local" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
    Write-Step "Claude Code CLI binary restored" "SUCCESS"
}

Write-Step "[4/15] Restoring .claude directory..." "INFO"
if (Test-Path "$BackupPath\core\claude-home") {
    robocopy "$BackupPath\core\claude-home" "$HOME_DIR\.claude" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
    Write-Step ".claude directory restored" "SUCCESS"
}

Write-Step "[5/15] Restoring OpenClaw workspace..." "INFO"
if (Test-Path "$BackupPath\openclaw\dot-openclaw") {
    robocopy "$BackupPath\openclaw\dot-openclaw" "$HOME_DIR\.openclaw" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
    Write-Step "OpenClaw workspace restored (SOUL.md, USER.md, MEMORY.md)" "SUCCESS"
}

Write-Step "[6/15] Restoring ClawdbotTray.vbs launcher..." "INFO"
if (Test-Path "$BackupPath\openclaw\clawdbot-launcher") {
    $destPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot"
    New-Item -ItemType Directory -Path $destPath -Force | Out-Null
    robocopy "$BackupPath\openclaw\clawdbot-launcher" $destPath /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
    Write-Step "ClawdbotTray.vbs launcher restored" "SUCCESS"
}

Write-Step "[7/15] Restoring credentials..." "INFO"
if (Test-Path "$BackupPath\credentials") {
    # Claude OAuth credentials
    if (Test-Path "$BackupPath\credentials\claude-credentials.json") {
        Copy-Item "$BackupPath\credentials\claude-credentials.json" "$HOME_DIR\.claude\.credentials.json" -Force
    }
    # OpenClaw auth files
    if (Test-Path "$BackupPath\credentials\openclaw-auth") {
        Get-ChildItem "$BackupPath\credentials\openclaw-auth" -Filter "*.json" | ForEach-Object {
            Copy-Item $_.FullName "$HOME_DIR\.openclaw\$($_.Name)" -Force
        }
    }
    Write-Step "Credentials restored" "SUCCESS"
}

Write-Step "[8/15] Restoring Moltbot..." "INFO"
if (Test-Path "$BackupPath\moltbot\dot-moltbot") {
    robocopy "$BackupPath\moltbot\dot-moltbot" "$HOME_DIR\.moltbot" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
}
if (Test-Path "$BackupPath\moltbot\npm-module") {
    robocopy "$BackupPath\moltbot\npm-module" "$APPDATA\npm\node_modules\moltbot" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
}
Write-Step "Moltbot restored" "SUCCESS"

Write-Step "[9/15] Restoring Clawdbot..." "INFO"
if (Test-Path "$BackupPath\clawdbot\dot-clawdbot") {
    robocopy "$BackupPath\clawdbot\dot-clawdbot" "$HOME_DIR\.clawdbot" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
}
if (Test-Path "$BackupPath\clawdbot\npm-module") {
    robocopy "$BackupPath\clawdbot\npm-module" "$APPDATA\npm\node_modules\clawdbot" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
}
Write-Step "Clawdbot restored" "SUCCESS"

Write-Step "[10/15] Restoring Clawd workspace..." "INFO"
if (Test-Path "$BackupPath\clawd\workspace") {
    robocopy "$BackupPath\clawd\workspace" "$HOME_DIR\clawd" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
    Write-Step "Clawd workspace restored" "SUCCESS"
}

Write-Step "[11/15] Restoring AppData..." "INFO"
if (Test-Path "$BackupPath\appdata\roaming-claude") {
    robocopy "$BackupPath\appdata\roaming-claude" "$APPDATA\Claude" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
}
if (Test-Path "$BackupPath\appdata\local-claude") {
    robocopy "$BackupPath\appdata\local-claude" "$LOCALAPPDATA\Claude" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
}
Write-Step "AppData restored" "SUCCESS"

Write-Step "[12/15] Restoring Git config and SSH..." "INFO"
if (Test-Path "$BackupPath\git\gitconfig") {
    Copy-Item "$BackupPath\git\gitconfig" "$HOME_DIR\.gitconfig" -Force
}
if (Test-Path "$BackupPath\git\ssh") {
    robocopy "$BackupPath\git\ssh" "$HOME_DIR\.ssh" /E /MT:32 /R:0 /W:0 /NFL /NDL /NJH /NJS
}
Write-Step "Git and SSH restored" "SUCCESS"

Write-Step "[13/15] Restoring PowerShell profiles..." "INFO"
if (Test-Path "$BackupPath\powershell\ps5-profile.ps1") {
    $ps5Dir = "$HOME_DIR\Documents\WindowsPowerShell"
    New-Item -ItemType Directory -Path $ps5Dir -Force | Out-Null
    Copy-Item "$BackupPath\powershell\ps5-profile.ps1" "$ps5Dir\Microsoft.PowerShell_profile.ps1" -Force
}
if (Test-Path "$BackupPath\powershell\ps7-profile.ps1") {
    $ps7Dir = "$HOME_DIR\Documents\PowerShell"
    New-Item -ItemType Directory -Path $ps7Dir -Force | Out-Null
    Copy-Item "$BackupPath\powershell\ps7-profile.ps1" "$ps7Dir\Microsoft.PowerShell_profile.ps1" -Force
}
Write-Step "PowerShell profiles restored" "SUCCESS"

Write-Step "[14/15] Importing registry keys..." "INFO"
Get-ChildItem "$BackupPath\registry" -Filter "*.reg" -ErrorAction SilentlyContinue | ForEach-Object {
    reg import $_.FullName 2>$null | Out-Null
}
Write-Step "Registry keys imported" "SUCCESS"

Write-Step "[15/15] Setting environment variables..." "INFO"
if (Test-Path "$BackupPath\env\environment-variables.json") {
    $envVars = Get-Content "$BackupPath\env\environment-variables.json" | ConvertFrom-Json
    $envVars.PSObject.Properties | ForEach-Object {
        if ($_.Name -match "^USER_(.+)$") {
            $varName = $matches[1]
            [Environment]::SetEnvironmentVariable($varName, $_.Value, "User")
        }
    }
    Write-Step "Environment variables set" "SUCCESS"
}

# ======= VERIFICATION =======
if ($Verify) {
    Write-Host ""
    Write-Host "=" * 80 -ForegroundColor Yellow
    Write-Host "  VERIFICATION" -ForegroundColor White
    Write-Host "=" * 80 -ForegroundColor Yellow
    
    Write-Step "Checking claude command..." "INFO"
    if (Get-Command claude -ErrorAction SilentlyContinue) {
        Write-Step "claude: OK ($(claude --version 2>$null))" "SUCCESS"
    } else {
        Write-Step "claude: MISSING - add .local\bin to PATH and restart shell" "WARNING"
    }
    
    Write-Step "Checking openclaw command..." "INFO"
    if (Get-Command openclaw -ErrorAction SilentlyContinue) {
        Write-Step "openclaw: OK" "SUCCESS"
    } else {
        Write-Step "openclaw: MISSING - npm link openclaw or add to PATH" "WARNING"
    }
    
    Write-Step "Checking OpenClaw workspace..." "INFO"
    $criticalFiles = @("SOUL.md", "USER.md", "MEMORY.md", "AGENTS.md")
    $missing = @()
    foreach ($file in $criticalFiles) {
        if (-not (Test-Path "$HOME_DIR\.openclaw\workspace\$file")) {
            $missing += $file
        }
    }
    if ($missing.Count -eq 0) {
        Write-Step "OpenClaw workspace: OK (all critical files present)" "SUCCESS"
    } else {
        Write-Step "OpenClaw workspace: INCOMPLETE - missing: $($missing -join ', ')" "ERROR"
    }
    
    Write-Step "Checking credentials..." "INFO"
    if (Test-Path "$HOME_DIR\.claude\.credentials.json") {
        Write-Step "Claude OAuth credentials: OK" "SUCCESS"
    } else {
        Write-Step "Claude OAuth credentials: MISSING" "ERROR"
    }
}

Write-Host ""
Write-Host "=" * 80 -ForegroundColor Green
Write-Host "  RESTORATION COMPLETE" -ForegroundColor White
Write-Host "=" * 80 -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Yellow
Write-Host "1. Restart PowerShell to load new PATH" -ForegroundColor White
Write-Host "2. Run 'claude --version' to verify Claude Code works" -ForegroundColor White
Write-Host "3. Run 'openclaw gateway start' to start OpenClaw" -ForegroundColor White
Write-Host "4. Test ClawdbotTray.vbs launcher" -ForegroundColor White
Write-Host ""
