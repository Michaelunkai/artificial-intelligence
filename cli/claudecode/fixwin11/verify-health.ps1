Write-Host "`n=== CURRENT DEVICE STATUS VERIFICATION ===" -ForegroundColor Cyan

$currentErrors = Get-PnpDevice | Where-Object {$_.Status -eq 'Error'}
$currentDegraded = Get-PnpDevice | Where-Object {$_.Status -eq 'Degraded'}

Write-Host "`nDevices with ERROR status: $($currentErrors.Count)"
if ($currentErrors) {
    Write-Host "WARNING: System currently has device ERRORS - these must be fixed FIRST" -ForegroundColor Red
    $currentErrors | Format-Table FriendlyName, Status, Class -AutoSize
}

Write-Host "`nDevices with DEGRADED status: $($currentDegraded.Count)"
if ($currentDegraded) {
    Write-Host "WARNING: System has DEGRADED devices" -ForegroundColor Yellow
    $currentDegraded | Format-Table FriendlyName, Status, Class -AutoSize
}

if (-not $currentErrors -and -not $currentDegraded) {
    Write-Host "`nPASS: No ERROR or DEGRADED devices found" -ForegroundColor Green
    Write-Host "System is HEALTHY - safe to proceed with optimizations" -ForegroundColor Green
}
