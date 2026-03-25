$netTest = Test-NetConnection google.com -InformationLevel Quiet -WarningAction SilentlyContinue
if ($netTest) {
    Write-Host "Network: WORKING" -ForegroundColor Green
} else {
    Write-Host "Network: ISSUE - Cannot reach Internet" -ForegroundColor Red
}
