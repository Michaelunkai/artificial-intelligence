# Minimal test script
Write-Host "TEST START"
Write-Host "PS Version: $($PSVersionTable.PSVersion)"

# Test 1: Basic output
Write-Host "[TEST 1] Basic output works"

# Test 2: Variable
$x = 10
Write-Host "[TEST 2] Variable x = $x"

# Test 3: Get-Date
Write-Host "[TEST 3] Date: $(Get-Date)"

# Test 4: Test-Path
Write-Host "[TEST 4] Test-Path C:\: $(Test-Path 'C:\')"

# Test 5: Start-Job
$job = Start-Job -ScriptBlock { return "HELLO FROM JOB" }
$result = $job | Wait-Job -Timeout 5 | Receive-Job
Remove-Job -Job $job -Force
Write-Host "[TEST 5] Job result: $result"

Write-Host "TEST END - ALL PASSED"
