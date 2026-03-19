# Baseline Error Counts
Write-Host "=== BASELINE ERROR COUNTS (Last 7 Days) ===" -ForegroundColor Cyan
$d = (Get-Date).AddDays(-7)

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

Write-Host "TOTALS:" -ForegroundColor Green
Write-Host "  Critical: $totalC  Errors: $totalE  Warnings: $totalW"

# Save baseline to file
$baseline = @{
    Date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    SystemCritical = $sC
    SystemErrors = $sE
    SystemWarnings = $sW
    AppCritical = $aC
    AppErrors = $aE
    AppWarnings = $aW
    TotalCritical = $totalC
    TotalErrors = $totalE
    TotalWarnings = $totalW
}
$baseline | ConvertTo-Json | Out-File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\prompt\winfix\baseline.json"
Write-Host "`nBaseline saved to baseline.json" -ForegroundColor Gray
