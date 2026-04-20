<#
.SYNOPSIS
    listclau
#>
$backupRoot = "F:\backup\claudecode"
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "  Available Claude Code Backups" -ForegroundColor Cyan
    Write-Host "  Location: $backupRoot" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
    if (-not (Test-Path $backupRoot)) { Write-Host "No backups found." -ForegroundColor Yellow; return }
    $backups = Get-ChildItem -Path $backupRoot -Directory | Where-Object { $_.Name -match "^backup_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}$" } | Sort-Object Name -Descending
    if ($backups.Count -eq 0) { Write-Host "No backups found." -ForegroundColor Yellow; return }
    Write-Host "Found $($backups.Count) backup(s):`n" -ForegroundColor Green
    foreach ($backup in $backups) {
        $sizeResult = Get-ChildItem -Path $backup.FullName -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
        $size = if ($sizeResult.Sum) { $sizeResult.Sum } else { 0 }
        $sizeMB = [math]::Round($size/1MB, 2)
        if ($backup.Name -match "backup_(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})") { $dateStr = "$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6])" } else { $dateStr = $backup.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss") }
        Write-Host "  $($backup.Name)" -ForegroundColor White
        Write-Host "    Date: $dateStr | Size: $sizeMB MB" -ForegroundColor Gray
    }
    Write-Host "`n========================================`n" -ForegroundColor Cyan
