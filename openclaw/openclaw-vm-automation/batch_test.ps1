# Simple batch runner - runs a_v2.py multiple times

param([int]$Runs = 5)

Write-Host "==== BATCH TEST - $Runs Runs ===="
Write-Host ""

$times = @()
$successes = 0

for ($i = 1; $i -le $Runs; $i++) {
    Write-Host "Run $i..." -ForegroundColor Cyan
    $start = Get-Date
    
    $output = python F:\Downloads\a_v2.py 2>&1
    
    $end = Get-Date
    $elapsed = ($end - $start).TotalSeconds
    $times += $elapsed
    
    if ($output -match "SUCCESS") {
        Write-Host "  [OK] $([math]::Round($elapsed, 2))s" -ForegroundColor Green
        $successes++
    } else {
        Write-Host "  [FAIL] $([math]::Round($elapsed, 2))s" -ForegroundColor Red
    }
}

Write-Host ""
Write-Host "==== SUMMARY ===="
Write-Host "Total Runs: $Runs"
Write-Host "Successful: $successes/$Runs"
Write-Host "Success Rate: $([math]::Round(($successes/$Runs)*100, 1))%"
Write-Host "Avg Time: $([math]::Round(($times | Measure-Object -Average).Average, 2))s"
$minTime = ($times | Measure-Object -Minimum).Minimum
$maxTime = ($times | Measure-Object -Maximum).Maximum
Write-Host "Min Time: $([math]::Round($minTime, 2))s"
Write-Host "Max Time: $([math]::Round($maxTime, 2))s"
