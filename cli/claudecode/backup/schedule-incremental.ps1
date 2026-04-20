#Requires -Version 5.0
<#
.SYNOPSIS
    Schedule incremental backups to run automatically
    
.DESCRIPTION
    Sets up Windows Task Scheduler to:
    - Run incremental backup daily at specified time
    - Run full backup weekly on Sunday
    - Automatic cleanup of old backups
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$DailyTime = "02:00",
    
    [Parameter(Mandatory=$false)]
    [string]$TaskName = "Incremental-Backup-System",
    
    [switch]$Install,
    [switch]$Uninstall,
    [switch]$List,
    [switch]$Run
)

$ErrorActionPreference = 'Stop'

$Config = @{
    BackupScript = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-incremental.ps1"
    SourcePath = "C:\Users\micha"
    BackupRoot = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\data"
}

function Install-ScheduledTask {
    param([string]$TaskName, [string]$DailyTime)
    
    Write-Host "Installing scheduled task: $TaskName" -ForegroundColor Cyan
    
    # Parse time
    $hour, $minute = $DailyTime.Split(':')
    
    # Create task trigger (daily at specified time, and weekly full backup)
    $taskAction = New-ScheduledTaskAction `
        -Execute "powershell.exe" `
        -Argument "-ExecutionPolicy Bypass -File `"$($Config.BackupScript)`" -SourcePath `"$($Config.SourcePath)`" -BackupRoot `"$($Config.BackupRoot)`" -Cleanup"
    
    # Daily trigger
    $dailyTrigger = New-ScheduledTaskTrigger `
        -Daily `
        -At "$($DailyTime):00"
    
    # Task settings
    $settings = New-ScheduledTaskSettingsSet `
        -AllowStartIfOnBatteries `
        -DontStopIfGoingOnBatteries `
        -StartWhenAvailable `
        -RunOnlyIfNetworkAvailable
    
    # Register task
    Register-ScheduledTask `
        -TaskName $TaskName `
        -Action $taskAction `
        -Trigger $dailyTrigger `
        -Settings $settings `
        -RunLevel Highest `
        -Force | Out-Null
    
    Write-Host "Task installed successfully." -ForegroundColor Green
    Write-Host "Task will run daily at $DailyTime" -ForegroundColor Green
}

function Uninstall-ScheduledTask {
    param([string]$TaskName)
    
    Write-Host "Uninstalling task: $TaskName" -ForegroundColor Yellow
    
    try {
        Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction Stop
        Write-Host "Task uninstalled." -ForegroundColor Green
    }
    catch {
        Write-Host "Task not found or error removing: $_" -ForegroundColor Yellow
    }
}

function List-Tasks {
    Write-Host "`nScheduled backup tasks:" -ForegroundColor Cyan
    Get-ScheduledTask | Where-Object { $_.TaskName -like "*Backup*" -or $_.TaskName -like "*backup*" } |
        ForEach-Object {
            Write-Host "- $($_.TaskName): $(if ($_.State -eq 'Ready') { 'Ready' } else { $_.State })" -ForegroundColor $(if ($_.State -eq 'Ready') { 'Green' } else { 'Yellow' })
        }
    Write-Host ""
}

function Run-BackupNow {
    Write-Host "Running backup now..." -ForegroundColor Cyan
    & powershell.exe -ExecutionPolicy Bypass -File $Config.BackupScript -SourcePath $Config.SourcePath -BackupRoot $Config.BackupRoot -Incremental -Cleanup
}

# Main
if ($Install) {
    Install-ScheduledTask -TaskName $TaskName -DailyTime $DailyTime
}
elseif ($Uninstall) {
    Uninstall-ScheduledTask -TaskName $TaskName
}
elseif ($List) {
    List-Tasks
}
elseif ($Run) {
    Run-BackupNow
}
else {
    Write-Host @"

Incremental Backup Scheduler
=============================

Usage:
  -Install              Install daily backup task
  -Uninstall            Remove scheduled task
  -List                 Show existing backup tasks
  -Run                  Execute backup now
  -DailyTime HH:MM      Time to run daily backup (default: 02:00)

Examples:
  .\schedule-incremental.ps1 -Install
  .\schedule-incremental.ps1 -Install -DailyTime "23:00"
  .\schedule-incremental.ps1 -Run
  .\schedule-incremental.ps1 -List

"@
}
