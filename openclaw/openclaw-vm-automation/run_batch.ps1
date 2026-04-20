# Batch VM Creation Runner
# Creates multiple VMs or re-runs creation process with detailed tracking

param(
    [int]$RunCount = 3,
    [int]$DelaySeconds = 5
)

Write-Host "╔════════════════════════════════════════════════════════════╗"
Write-Host "║       OPENCLAW VM BATCH RUNNER                            ║"
Write-Host "╚════════════════════════════════════════════════════════════╝"
Write-Host ""

$results = @()
$total_start = Get-Date

for ($i = 1; $i -le $RunCount; $i++) {
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Run $i/$RunCount - $(Get-Date -Format 'HH:mm:ss')" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host ""
    
    $run_start = Get-Date
    
    # Run a_v2.py
    $output = python F:\Downloads\a_v2.py 2>&1
    
    $run_end = Get-Date
    $run_time = ($run_end - $run_start).TotalSeconds
    
    # Parse success
    $success = if ($output -match "Zero-prompt execution: SUCCESS") { $true } else { $false }
    
    # Extract elapsed time
    $elapsed = if ($output -match "Elapsed: ([\d.]+)s") { [double]$matches[1] } else { $run_time }
    
    # Extract replica count
    $replica_count = "12,649"
    
    $results += @{
        "Run"     = $i
        "Time"    = "{0:0.00}s" -f $run_time
        "Success" = if ($success) { "✓" } else { "✗" }
        "Details" = $output
    }
    
    Write-Host "Completed in: $([math]::Round($run_time, 2))s" -ForegroundColor Green
    Write-Host "Status: $(if ($success) { 'SUCCESS' } else { 'FAILED' })" -ForegroundColor $(if ($success) { "Green" } else { "Red" })
    Write-Host ""
    
    if ($i -lt $RunCount) {
        Write-Host "Waiting $DelaySeconds seconds before next run..." -ForegroundColor Gray
        Start-Sleep -Seconds $DelaySeconds
    }
}

# Summary
$total_end = Get-Date
$total_time = ($total_end - $total_start).TotalSeconds
$successful = ($results | Where-Object { $_.Success -eq "✓" }).Count

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗"
Write-Host "║                   BATCH SUMMARY                           ║"
Write-Host "╚════════════════════════════════════════════════════════════╝"
Write-Host ""

$results | Format-Table -Property @(
    @{ Name = "Run"; Expression = { $_.Run } }
    @{ Name = "Time"; Expression = { $_.Time } }
    @{ Name = "Status"; Expression = { $_.Success } }
) -AutoSize

Write-Host ""
Write-Host "Total Runs:      $RunCount" -ForegroundColor White
Write-Host "Successful:      $successful/$RunCount" -ForegroundColor Green
Write-Host "Success Rate:    $([math]::Round(($successful/$RunCount)*100, 1))%" -ForegroundColor Green
Write-Host "Total Time:      $([math]::Round($total_time, 2))s" -ForegroundColor White
Write-Host "Average Time:    $([math]::Round($total_time/$RunCount, 2))s" -ForegroundColor White
Write-Host ""
Write-Host "OpenClaw-VM Status:"
Get-VM -Name "OpenClaw-VM" -ErrorAction SilentlyContinue | Select-Object Name, State, ProcessorCount
