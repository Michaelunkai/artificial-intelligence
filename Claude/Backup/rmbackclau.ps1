#Requires -Version 5.1
<#
.SYNOPSIS
    rmbackclau - Force-delete ALL Claude Code backups then immediately re-run backclau.
.DESCRIPTION
    1. Deletes every backup_* folder under F:\backup\claudecode\ in parallel (fastest possible).
    2. Deletes backup-manifest.json and backup-status.txt.
    3. Immediately runs backclau to create a fresh backup.
    Zero prompts, zero delay.
#>

$ErrorActionPreference = 'Continue'
$backupRoot = 'F:\backup\claudecode'

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  RMBACKCLAU - PURGE ALL BACKUPS + FRESH BACKUP" -ForegroundColor White
Write-Host "============================================================" -ForegroundColor Cyan

if (-not (Test-Path $backupRoot)) {
    Write-Host "[INFO] $backupRoot not found - nothing to delete." -ForegroundColor Yellow
} else {
    # Force-delete all backup_* dirs in parallel via jobs
    $dirs = @(Get-ChildItem $backupRoot -Directory -Filter 'backup_*' -EA SilentlyContinue)
    if ($dirs.Count -gt 0) {
        Write-Host "[DEL] Removing $($dirs.Count) backup folder(s) in parallel..." -ForegroundColor Yellow
        $jobs = @()
        foreach ($d in $dirs) {
            $path = $d.FullName
            $jobs += Start-Job -ScriptBlock {
                param($p)
                try { Remove-Item $p -Recurse -Force -EA Stop; "OK: $p" } catch { "FAIL: $p - $_" }
            } -ArgumentList $path
        }
        $results = $jobs | Wait-Job | Receive-Job
        $jobs | Remove-Job -Force
        $results | ForEach-Object {
            $color = if ($_ -match '^OK') { 'Green' } else { 'Red' }
            Write-Host "  $_" -ForegroundColor $color
        }
    } else {
        Write-Host "[INFO] No backup_* folders found." -ForegroundColor DarkGray
    }

    # Delete sentinel files
    foreach ($f in @("$backupRoot\backup-manifest.json", "$backupRoot\backup-status.txt")) {
        if (Test-Path $f) {
            Remove-Item $f -Force -EA SilentlyContinue
            Write-Host "[DEL] $(Split-Path $f -Leaf)" -ForegroundColor DarkGray
        }
    }
}

Write-Host "[DONE] Purge complete. Starting fresh backup..." -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""

# Run backclau immediately
. 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1' -Force
