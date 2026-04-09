# rlp4 - Run RLP with 4-5 todo steps
param([string]$Task)
if ($Task) { claude "/rlp4 $Task" } else { claude "/rlp4" }