$start = Get-Date
Write-Host "`n=== RUNNING STEEP ===" -ForegroundColor Cyan
steep
$end = Get-Date
$duration = ($end - $start).TotalMinutes
Write-Host "`nSteep completed in $([math]::Round($duration, 2)) minutes" -ForegroundColor Green
if ($duration -gt 10) {
    Write-Host "WARNING: Steep took longer than 10 minutes!" -ForegroundColor Red
}
