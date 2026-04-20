# Simple VM Deployment Script for multiple environments

param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    [int]$VMCount = 1,
    [switch]$RunTests,
    [switch]$DryRun
)

Write-Host "=== Multi-Environment VM Deployment ===" -ForegroundColor Cyan
Write-Host "Environment: $Environment"
Write-Host "VM Count: $VMCount"
Write-Host "Run Tests: $RunTests"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE]" -ForegroundColor Yellow
}

# Phase 1: Create VMs
Write-Host "Phase 1: Creating VMs..." -ForegroundColor Cyan
for ($i = 1; $i -le $VMCount; $i++) {
    Write-Host "  [$i/$VMCount] Running a_v2.py..."
    if (-not $DryRun) {
        python F:\Downloads\a_v2.py 2>&1 | Select-Object -Last 1
    }
}

# Phase 2: Validate
Write-Host "`nPhase 2: Validation..." -ForegroundColor Cyan
if (-not $DryRun) {
    powershell -ExecutionPolicy Bypass -File F:\Downloads\test_vm.ps1
}

# Phase 3: Health Check
Write-Host "`nPhase 3: Health Check..." -ForegroundColor Cyan
if (-not $DryRun) {
    python F:\Downloads\vm_manager.py health
}

# Phase 4: Stress Tests (if requested)
if ($RunTests) {
    $test_runs = 3
    if ($Environment -eq 'staging') { $test_runs = 5 }
    if ($Environment -eq 'prod') { $test_runs = 10 }
    
    Write-Host "`nPhase 4: Stress Tests ($test_runs runs)..." -ForegroundColor Cyan
    if (-not $DryRun) {
        powershell -ExecutionPolicy Bypass -File F:\Downloads\batch_test.ps1 -Runs $test_runs
    }
}

# Summary
Write-Host "`n=== Summary ===" -ForegroundColor Green
Write-Host "Environment: $Environment"
Write-Host "VMs: $VMCount"
Write-Host "Status: Complete"
if ($DryRun) {
    Write-Host "Run without -DryRun to deploy"
}
