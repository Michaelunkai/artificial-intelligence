# rlpprog - Show RLP progress
$statePath = "$env:USERPROFILE\.claude\rlp-state.json"
if (-not (Test-Path $statePath)) { Write-Host "No RLP state found" -ForegroundColor Yellow; return }
$state = Get-Content $statePath -Raw | ConvertFrom-Json
$total = $state.todos.Count
$done = ($state.todos | Where-Object { $_.status -eq 'completed' }).Count
$pending = $total - $done
$pct = if ($total -gt 0) { [math]::Round(($done / $total) * 100, 1) } else { 0 }
Write-Host "=== RLP Progress ===" -ForegroundColor Cyan
Write-Host "  Task: $($state.task)" -ForegroundColor White
Write-Host "  Done: $done/$total ($pct%)" -ForegroundColor $(if ($pct -ge 100) { 'Green' } elseif ($pct -ge 50) { 'Yellow' } else { 'Red' })
Write-Host "  Pending: $pending" -ForegroundColor Gray
$bar = ('#' * [math]::Floor($pct / 5)) + ('-' * (20 - [math]::Floor($pct / 5)))
Write-Host "  [$bar] $pct%" -ForegroundColor Cyan