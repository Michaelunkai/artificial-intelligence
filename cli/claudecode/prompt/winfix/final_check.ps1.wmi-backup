# Final Verification Script
$ErrorActionPreference = "SilentlyContinue"
$d = (Get-Date).AddDays(-7)

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "POST-FIX ERROR COUNTS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

$sE = (Get-WinEvent -FilterHashtable @{LogName='System';Level=2;StartTime=$d} -ErrorAction SilentlyContinue | Measure-Object).Count
$sW = (Get-WinEvent -FilterHashtable @{LogName='System';Level=3;StartTime=$d} -ErrorAction SilentlyContinue | Measure-Object).Count
$sC = (Get-WinEvent -FilterHashtable @{LogName='System';Level=1;StartTime=$d} -ErrorAction SilentlyContinue | Measure-Object).Count

Write-Host "System Log:" -ForegroundColor Yellow
Write-Host "  Critical: $sC  Errors: $sE  Warnings: $sW"

$aE = (Get-WinEvent -FilterHashtable @{LogName='Application';Level=2;StartTime=$d} -ErrorAction SilentlyContinue | Measure-Object).Count
$aW = (Get-WinEvent -FilterHashtable @{LogName='Application';Level=3;StartTime=$d} -ErrorAction SilentlyContinue | Measure-Object).Count
$aC = (Get-WinEvent -FilterHashtable @{LogName='Application';Level=1;StartTime=$d} -ErrorAction SilentlyContinue | Measure-Object).Count

Write-Host "Application Log:" -ForegroundColor Yellow
Write-Host "  Critical: $aC  Errors: $aE  Warnings: $aW"

$totalC = $sC + $aC
$totalE = $sE + $aE
$totalW = $sW + $aW

Write-Host ""
Write-Host "POST-FIX TOTALS:" -ForegroundColor Green
Write-Host "  Critical: $totalC  Errors: $totalE  Warnings: $totalW"

# Load baseline for comparison
$baselinePath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\prompt\winfix\baseline.json"
if (Test-Path $baselinePath) {
    $baseline = Get-Content $baselinePath | ConvertFrom-Json
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "COMPARISON (Baseline vs Now)" -ForegroundColor Magenta
    Write-Host "========================================" -ForegroundColor Magenta
    Write-Host "Critical: $($baseline.TotalCritical) -> $totalC"
    Write-Host "Errors: $($baseline.TotalErrors) -> $totalE"
    Write-Host "Warnings: $($baseline.TotalWarnings) -> $totalW"
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "FIXED SERVICES VERIFICATION" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
$services = @('LanmanWorkstation', 'BITS', 'W32Time')
foreach ($svc in $services) {
    $service = Get-Service $svc
    $color = if ($service.Status -eq 'Running') { 'Green' } else { 'Red' }
    Write-Host "$($svc): $($service.Status)" -ForegroundColor $color
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "SYSTEM HEALTH SUMMARY" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Check all critical services
$critServices = @('wuauserv','BITS','Dnscache','Winmgmt','AudioSrv','Spooler','EventLog','LanmanWorkstation','RpcSs')
$runningCount = 0
foreach ($svc in $critServices) {
    $s = Get-Service $svc -ErrorAction SilentlyContinue
    if ($s.Status -eq 'Running') { $runningCount++ }
}
Write-Host "Critical Services Running: $runningCount / $($critServices.Count)" -ForegroundColor $(if ($runningCount -eq $critServices.Count) { 'Green' } else { 'Yellow' })

# Memory
$os = Get-WmiObject Win32_OperatingSystem
$usedPct = [math]::Round((($os.TotalVisibleMemorySize - $os.FreePhysicalMemory) / $os.TotalVisibleMemorySize) * 100, 1)
Write-Host "Memory Usage: $usedPct%" -ForegroundColor $(if ($usedPct -lt 80) { 'Green' } else { 'Yellow' })

# Disk
$c = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='C:'"
$diskFreePct = [math]::Round(($c.FreeSpace / $c.Size) * 100, 1)
Write-Host "C: Drive Free: $diskFreePct%" -ForegroundColor $(if ($diskFreePct -gt 20) { 'Green' } else { 'Yellow' })

Write-Host ""
Write-Host "Final check complete!" -ForegroundColor Green
