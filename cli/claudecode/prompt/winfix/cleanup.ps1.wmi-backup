# Cleanup and Maintenance Script
$ErrorActionPreference = "SilentlyContinue"

Write-Host "=== CLEANING TEMP FILES ===" -ForegroundColor Cyan

# User temp folder
$userTemp = $env:TEMP
$beforeUser = (Get-ChildItem $userTemp -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
Remove-Item "$userTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
$afterUser = (Get-ChildItem $userTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "User Temp: Freed $([math]::Round($beforeUser - $afterUser, 2)) MB"

# Windows temp folder
$winTemp = "C:\Windows\Temp"
$beforeWin = (Get-ChildItem $winTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
Remove-Item "$winTemp\*" -Recurse -Force -ErrorAction SilentlyContinue
$afterWin = (Get-ChildItem $winTemp -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Windows Temp: Freed $([math]::Round($beforeWin - $afterWin, 2)) MB"

# Software Distribution Download
$suDist = "C:\Windows\SoftwareDistribution\Download"
$beforeSD = (Get-ChildItem $suDist -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
Remove-Item "$suDist\*" -Recurse -Force -ErrorAction SilentlyContinue
$afterSD = (Get-ChildItem $suDist -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "SoftwareDistribution Download: Freed $([math]::Round($beforeSD - $afterSD, 2)) MB"

# Prefetch (optional - can slow startup temporarily)
# $prefetch = "C:\Windows\Prefetch"
# Remove-Item "$prefetch\*" -Force -ErrorAction SilentlyContinue
# Write-Host "Prefetch: Cleared"

Write-Host ""
Write-Host "=== CLEARING DNS CACHE ===" -ForegroundColor Cyan
ipconfig /flushdns
Write-Host ""

Write-Host "=== CHECKING WINDOWS UPDATE STATUS ===" -ForegroundColor Cyan
$updateSession = New-Object -ComObject Microsoft.Update.Session
$updateSearcher = $updateSession.CreateUpdateSearcher()
$pendingUpdates = $updateSearcher.Search("IsInstalled=0")
Write-Host "Pending updates: $($pendingUpdates.Updates.Count)"
if ($pendingUpdates.Updates.Count -gt 0) {
    Write-Host "Updates available:" -ForegroundColor Yellow
    foreach ($update in $pendingUpdates.Updates) {
        Write-Host "  - $($update.Title)"
    }
}

Write-Host ""
Write-Host "=== CHECKING WSL STATUS ===" -ForegroundColor Cyan
$wslStatus = wsl --status 2>&1
if ($LASTEXITCODE -eq 0) {
    Write-Host $wslStatus
} else {
    Write-Host "WSL not installed or not configured" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "=== CPU/THERMAL CHECK ===" -ForegroundColor Cyan
$cpu = Get-WmiObject Win32_Processor
Write-Host "CPU: $($cpu.Name)"
Write-Host "Current Clock: $($cpu.CurrentClockSpeed) MHz / Max: $($cpu.MaxClockSpeed) MHz"
$loadPct = $cpu.LoadPercentage
Write-Host "Load: $loadPct%"

# Check for thermal throttling events
$thermalEvents = Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-Kernel-Power','Microsoft-Windows-Kernel-Processor-Power';Level=2,3;StartTime=(Get-Date).AddDays(-1)} -MaxEvents 5 -ErrorAction SilentlyContinue
if ($thermalEvents) {
    Write-Host "Thermal/Power events (last 24h):" -ForegroundColor Yellow
    $thermalEvents | ForEach-Object { Write-Host "  $($_.TimeCreated): $($_.Message.Substring(0, [Math]::Min(80, $_.Message.Length)))..." }
} else {
    Write-Host "No thermal/power issues detected (good!)" -ForegroundColor Green
}

Write-Host ""
Write-Host "=== USB SELECTIVE SUSPEND CHECK ===" -ForegroundColor Cyan
$usbSuspend = powercfg /query SCHEME_CURRENT SUB_USB | Select-String "Current AC Power Setting Index|Current DC Power Setting Index"
Write-Host $usbSuspend

Write-Host ""
Write-Host "Cleanup complete!" -ForegroundColor Green
