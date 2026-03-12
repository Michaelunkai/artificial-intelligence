Write-Host "`n=== DISK CLEANUP (SAFE) ===" -ForegroundColor Cyan

Write-Host "`nCleaning user temp files..." -ForegroundColor Yellow
$tempCleaned = 0
try {
    $tempFiles = Get-ChildItem "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    $tempCleaned = ($tempFiles | Measure-Object -Property Length -Sum).Sum / 1MB
    Remove-Item "$env:TEMP\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned: $([math]::Round($tempCleaned, 2)) MB"
} catch {}

Write-Host "`nCleaning Windows temp files..." -ForegroundColor Yellow
$winTempCleaned = 0
try {
    $winTempFiles = Get-ChildItem "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    $winTempCleaned = ($winTempFiles | Measure-Object -Property Length -Sum).Sum / 1MB
    Remove-Item "C:\Windows\Temp\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned: $([math]::Round($winTempCleaned, 2)) MB"
} catch {}

Write-Host "`nCleaning Windows Update cache..." -ForegroundColor Yellow
$updateCacheCleaned = 0
try {
    $updateFiles = Get-ChildItem "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    $updateCacheCleaned = ($updateFiles | Measure-Object -Property Length -Sum).Sum / 1MB
    Remove-Item "C:\Windows\SoftwareDistribution\Download\*" -Recurse -Force -ErrorAction SilentlyContinue
    Write-Host "Cleaned: $([math]::Round($updateCacheCleaned, 2)) MB"
} catch {}

Write-Host "`nEmptying Recycle Bin..." -ForegroundColor Yellow
try {
    Clear-RecycleBin -Force -ErrorAction SilentlyContinue 2>&1 | Out-Null
    Write-Host "Recycle Bin emptied"
} catch {
    Write-Host "Recycle Bin already empty or access denied"
}

$totalCleaned = $tempCleaned + $winTempCleaned + $updateCacheCleaned
Write-Host "`nTotal space cleaned: $([math]::Round($totalCleaned, 2)) MB" -ForegroundColor Green
