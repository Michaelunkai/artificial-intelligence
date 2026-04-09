# rlp1 - Run RLP with 1 todo step
param([string]$Task)
if ($Task) { claude "/rlp1 $Task" } else { claude "/rlp1" }