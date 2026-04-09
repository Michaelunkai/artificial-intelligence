# rlpnext - Show and execute next pending RLP todo
$statePath = "$env:USERPROFILE\.claude\rlp-state.json"
if (-not (Test-Path $statePath)) { Write-Host "No RLP state found" -ForegroundColor Yellow; return }
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$next = $state.todos | Where-Object { $_.status -eq 'pending' } | Select-Object -First 1
if ($next) {
    Write-Host "Next: #$($next.id) - $($next.text)" -ForegroundColor Cyan
} else {
    Write-Host "All todos complete!" -ForegroundColor Green
}