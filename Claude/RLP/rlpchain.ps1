# rlpchain - Chain execute all pending RLP todos
$statePath = "$env:USERPROFILE\.claude\rlp-state.json"
if (-not (Test-Path $statePath)) { Write-Host "No RLP state found" -ForegroundColor Yellow; return }
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$pending = $state.todos | Where-Object { $_.status -eq 'pending' }
Write-Host "Chaining $($pending.Count) pending todos..." -ForegroundColor Cyan
foreach ($todo in $pending) {
    Write-Host "  Executing #$($todo.id): $($todo.text)" -ForegroundColor White
    claude "/rlp1 $($todo.text)"
}