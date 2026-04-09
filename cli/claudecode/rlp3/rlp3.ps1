# rlp3 - Run RLP with 3 todo steps
param([string]$Task)
if ($Task) { claude "/rlp3 $Task" } else { claude "/rlp3" }