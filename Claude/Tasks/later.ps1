# later - Add task to deferred queue
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$Task)
$laterFile = "$env:USERPROFILE\.claude\later-tasks.txt"
if (-not $Task) {
    if (Test-Path $laterFile) {
        Write-Host "=== Deferred Tasks ===" -ForegroundColor Cyan
        Get-Content $laterFile | ForEach-Object { $i = [array]::IndexOf((Get-Content $laterFile), $_) + 1; Write-Host "  $i. $_" -ForegroundColor White }
    } else { Write-Host "No deferred tasks" -ForegroundColor Yellow }
    return
}
$text = $Task -join ' '
Add-Content $laterFile "[$((Get-Date).ToString('yyyy-MM-dd HH:mm'))] $text"
Write-Host "Deferred: $text" -ForegroundColor Green