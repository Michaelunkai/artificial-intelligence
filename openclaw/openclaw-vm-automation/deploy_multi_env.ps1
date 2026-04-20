# Multi-Environment VM Deployment Orchestrator
# Deploys OpenClaw VMs across dev, staging, and production

param(
    [ValidateSet('dev', 'staging', 'prod')]
    [string]$Environment = 'dev',
    
    [int]$VMCount = 1,
    [switch]$RunTests,
    [switch]$CreateCheckpoint,
    [switch]$DryRun
)

Write-Host "╔════════════════════════════════════════════════════════════╗"
Write-Host "║    Multi-Environment VM Deployment Orchestrator            ║"
Write-Host "╚════════════════════════════════════════════════════════════╝"
Write-Host ""

$config = @{
    'dev' = @{
        'prefix' = 'DEV'
        'vcpu' = 4
        'memory' = 8GB
        'stress_test_runs' = 3
        'checkpoint' = $false
    }
    'staging' = @{
        'prefix' = 'STAGING'
        'vcpu' = 8
        'memory' = 16GB
        'stress_test_runs' = 5
        'checkpoint' = $true
    }
    'prod' = @{
        'prefix' = 'PROD'
        'vcpu' = 8
        'memory' = 16GB
        'stress_test_runs' = 10
        'checkpoint' = $true
    }
}

$env_config = $config[$Environment]

Write-Host "Environment: $Environment" -ForegroundColor Cyan
Write-Host "VM Count: $VMCount"
Write-Host "Run Tests: $RunTests"
Write-Host "Create Checkpoint: $CreateCheckpoint"
Write-Host ""

if ($DryRun) {
    Write-Host "[DRY RUN MODE] - No changes will be made" -ForegroundColor Yellow
    Write-Host ""
}

# Deployment phases
$phases = @(
    @{ name = 'Pre-Check'; action = { Write-Host "[*] Running pre-deployment checks..." } }
    @{ name = 'Create VMs'; action = { 
        Write-Host "[*] Creating $VMCount OpenClaw VM(s)..."
        1..$VMCount | ForEach-Object {
            Write-Host "    [$_/$VMCount] Running: python F:\Downloads\a_v2.py"
            if (-not $DryRun) {
                $start = Get-Date
                python F:\Downloads\a_v2.py 2>&1 | Select-Object -Last 3
                $elapsed = ((Get-Date) - $start).TotalSeconds
                Write-Host "    Completed in $([math]::Round($elapsed, 2))s" -ForegroundColor Green
            }
        }
    } }
    @{ name = 'Validation'; action = { 
        Write-Host "[*] Validating deployments..."
        if (-not $DryRun) {
            powershell -ExecutionPolicy Bypass -File F:\Downloads\test_vm.ps1
        }
    } }
    @{ name = 'Health Check'; action = { 
        Write-Host "[*] Running health checks..."
        if (-not $DryRun) {
            python F:\Downloads\vm_manager.py health
        }
    } }
    @{ name = 'Stress Tests'; action = { 
        if ($RunTests) {
            $runs = $env_config.stress_test_runs
            Write-Host "[*] Running stress tests ($runs iterations)..."
            if (-not $DryRun) {
                powershell -ExecutionPolicy Bypass -File F:\Downloads\batch_test.ps1 -Runs $runs
            }
        } else {
            Write-Host "[*] Stress tests skipped (use -RunTests to enable)"
        }
    } }
    @{ name = 'Checkpoint'; action = { 
        if ($CreateCheckpoint -or $env_config.checkpoint) {
            Write-Host "[*] Creating checkpoint..."
            if (-not $DryRun) {
                python F:\Downloads\vm_manager.py checkpoint
            }
        }
    } }
)

# Execute phases
$start_time = Get-Date
foreach ($phase in $phases) {
    Write-Host ""
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    Write-Host "Phase: $($phase.name)" -ForegroundColor Cyan
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Cyan
    
    try {
        & $phase.action
        Write-Host "[OK] $($phase.name) completed" -ForegroundColor Green
    } catch {
        Write-Host "[ERROR] $($phase.name) failed: $_" -ForegroundColor Red
    }
}

# Summary
$total_time = ((Get-Date) - $start_time).TotalSeconds

Write-Host ""
Write-Host "╔════════════════════════════════════════════════════════════╗"
Write-Host "║                  DEPLOYMENT SUMMARY                       ║"
Write-Host "╚════════════════════════════════════════════════════════════╝"
Write-Host ""
Write-Host "Environment: $Environment" -ForegroundColor Cyan
Write-Host "VMs Created: $VMCount"
Write-Host "Tests Run: $(if ($RunTests) { 'Yes' } else { 'No' })"
Write-Host "Checkpoint Created: $(if ($CreateCheckpoint -or $env_config.checkpoint) { 'Yes' } else { 'No' })"
Write-Host "Total Time: $([math]::Round($total_time, 2))s"
Write-Host ""

if ($DryRun) {
    Write-Host "DRY RUN completed. Use without -DryRun to deploy." -ForegroundColor Yellow
} else {
    Write-Host "Deployment completed successfully!" -ForegroundColor Green
}

# Post-deployment info
Write-Host ""
Write-Host "Next steps:"
if ($Environment -eq 'dev') {
    Write-Host "1. Test locally: Get-VM -Name 'OpenClaw-VM'"
    Write-Host "2. Promote to staging: .\deploy_multi_env.ps1 -Environment staging -RunTests"
}
elseif ($Environment -eq 'staging') {
    Write-Host "1. Review test results above"
    Write-Host "2. Promote to production: .\deploy_multi_env.ps1 -Environment prod -RunTests"
}
else {
    Write-Host "1. Production deployment complete"
    Write-Host "2. Monitor: python F:\Downloads\vm_manager.py health"
    Write-Host "3. View logs: cat C:\Temp\vm_manager.log"
}
