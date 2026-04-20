#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Install backup scheduler functions into PowerShell profile
.DESCRIPTION
    Adds backup-now, backup-schedule, backup-cancel, backup-status, 
    backup-configure, backup-enable, backup-disable functions to the
    PowerShell profile for easy access.
#>

# Get PowerShell profile path
$ProfilePath = $Profile.CurrentUserAllHosts
$ProfileDir = Split-Path -Parent $ProfilePath

# Ensure profile directory exists
if (-not (Test-Path $ProfileDir)) {
    New-Item -ItemType Directory -Path $ProfileDir -Force | Out-Null
}

# Ensure profile file exists
if (-not (Test-Path $ProfilePath)) {
    New-Item -ItemType File -Path $ProfilePath -Force | Out-Null
}

# Define backup function code
$BackupFunctionCode = @'
# ============================================
# BACKUP SCHEDULER FUNCTIONS
# ============================================
# Auto-loaded from backup-scheduler.ps1
# Commands: backup-now, backup-schedule, backup-cancel, backup-status
#           backup-configure, backup-enable, backup-disable

$BackupSchedulerScriptPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-scheduler.ps1"

if (Test-Path $BackupSchedulerScriptPath) {
    # Source the backup scheduler script (without executing main logic)
    . $BackupSchedulerScriptPath
}
else {
    Write-Warning "Backup scheduler script not found at $BackupSchedulerScriptPath"
}

# Quick help
function backup-help {
    Write-Host "`n=== BACKUP SCHEDULER QUICK HELP ===" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Available Commands:" -ForegroundColor Green
    Write-Host "  backup-now        - Start backup immediately"
    Write-Host "  backup-schedule   - View current schedule & status"
    Write-Host "  backup-status     - Show detailed status"
    Write-Host "  backup-cancel     - Cancel current backup"
    Write-Host "  backup-configure  - Show how to configure"
    Write-Host "  backup-enable     - Enable scheduled daily backups"
    Write-Host "  backup-disable    - Disable scheduled backups"
    Write-Host ""
    Write-Host "Configuration File:" -ForegroundColor Green
    Write-Host "  $env:APPDATA\BackupScheduler\config.json"
    Write-Host ""
    Write-Host "Log Directory:" -ForegroundColor Green
    Write-Host "  $env:APPDATA\BackupScheduler\logs\"
    Write-Host ""
}

# Auto-complete for backup commands
$BackupCommands = @(
    'backup-now',
    'backup-schedule',
    'backup-cancel',
    'backup-status',
    'backup-configure',
    'backup-enable',
    'backup-disable',
    'backup-help'
)

# ============================================
'@

# Check if backup functions are already in profile
$ProfileContent = Get-Content -Path $ProfilePath -Raw -ErrorAction SilentlyContinue

if ($ProfileContent -like "*BACKUP SCHEDULER FUNCTIONS*") {
    Write-Host "Backup functions already installed in profile" -ForegroundColor Yellow
    
    # Ask to reinstall
    $Response = Read-Host "Reinstall? (y/n)"
    if ($Response -ne "y") {
        exit
    }
    
    # Remove old installation
    $Start = $ProfileContent.IndexOf("# ============================================`n# BACKUP SCHEDULER FUNCTIONS")
    if ($Start -ge 0) {
        $End = $ProfileContent.IndexOf("# ============================================`n", $Start + 100)
        if ($End -ge 0) {
            $NewContent = $ProfileContent.Substring(0, $Start) + $ProfileContent.Substring($End + 50)
            Set-Content -Path $ProfilePath -Value $NewContent -Encoding UTF8
            Write-Host "Removed old installation" -ForegroundColor Yellow
        }
    }
}

# Add backup functions to profile
Add-Content -Path $ProfilePath -Value $BackupFunctionCode -Encoding UTF8

Write-Host "`n=== INSTALLATION COMPLETE ===" -ForegroundColor Green
Write-Host "Backup scheduler functions have been added to your PowerShell profile:" -ForegroundColor Green
Write-Host "  $ProfilePath" -ForegroundColor Gray
Write-Host ""
Write-Host "Available commands:" -ForegroundColor Cyan
Write-Host "  backup-now        - Start backup immediately" -ForegroundColor Green
Write-Host "  backup-schedule   - View schedule and status" -ForegroundColor Green
Write-Host "  backup-status     - Show detailed backup status" -ForegroundColor Green
Write-Host "  backup-cancel     - Cancel current backup" -ForegroundColor Green
Write-Host "  backup-configure  - View configuration options" -ForegroundColor Green
Write-Host "  backup-enable     - Enable scheduled daily backups" -ForegroundColor Green
Write-Host "  backup-disable    - Disable scheduled backups" -ForegroundColor Green
Write-Host "  backup-help       - Show this help" -ForegroundColor Green
Write-Host ""
Write-Host "Next steps:" -ForegroundColor Cyan
Write-Host "  1. Close and reopen PowerShell to load the functions" -ForegroundColor Yellow
Write-Host "  2. Run: backup-configure" -ForegroundColor Yellow
Write-Host "  3. Edit: $env:APPDATA\BackupScheduler\config.json" -ForegroundColor Yellow
Write-Host "  4. Run: backup-enable" -ForegroundColor Yellow
Write-Host "  5. Test with: backup-now" -ForegroundColor Yellow
Write-Host ""
Write-Host "Documentation:" -ForegroundColor Gray
Write-Host "  F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-scheduler.ps1" -ForegroundColor Gray
Write-Host ""
