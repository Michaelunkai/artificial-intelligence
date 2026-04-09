# rlp2 - Run RLP with 30 todos or resume existing queue
param([string]$Task)
$stateFile = "C:\Users\micha\.claude\workspace\rlp-state.json"
if ($Task) {
    claude "/rlp2 $Task"
} elseif (Test-Path $stateFile) {
    $state = Get-Content $stateFile -Raw | ConvertFrom-Json
    $pending = @($state.todos | Where-Object { $_.status -eq 'pending' -or $_.status -eq 'in_progress' })
    if ($pending.Count -gt 0) {
        claude "/rlp continue"
    } else {
        claude "/rlp2"
    }
} else {
    claude "/rlp2"
}