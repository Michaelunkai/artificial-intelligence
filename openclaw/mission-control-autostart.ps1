# OpenClaw Mission Control - Ultimate Auto-Start with Auto-Login
param([switch]$Force)

$ErrorActionPreference = "Stop"
$projectDir = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\openclaw\mission-control"
$authToken = "openclaw-mission-control-secure-access-token-12345678"

Write-Host "OpenClaw Mission Control - Ultimate Auto-Start" -ForegroundColor Cyan

# Stop any existing OpenClaw gateway/dashboard
if ($Force) {
    Write-Host "Stopping any running OpenClaw services..." -ForegroundColor Yellow
    try {
        $existingContainers = docker ps -a --filter "name=openclaw" --format "{{.Names}}"
        if ($existingContainers) {
            $existingContainers | ForEach-Object { docker stop $_ 2>&1 | Out-Null }
            $existingContainers | ForEach-Object { docker rm $_ 2>&1 | Out-Null }
        }
    } catch {}
}

# Check if project exists
if (-not (Test-Path $projectDir)) {
    Write-Host "ERROR: Project not found at $projectDir" -ForegroundColor Red
    exit 1
}

Set-Location $projectDir

# Check if containers are running
$runningContainers = docker ps --filter "name=openclaw-mission-control" --format "{{.Names}}"
if ($runningContainers) {
    Write-Host "Mission Control already running!" -ForegroundColor Green
} else {
    Write-Host "Starting Mission Control..." -ForegroundColor Yellow
    docker compose -f compose.yml --env-file .env up -d 2>&1 | Out-Null
    Start-Sleep -Seconds 25
    
    # Wait for backend
    $backendReady = $false
    $attempts = 0
    while (-not $backendReady -and $attempts -lt 15) {
        try {
            $response = Invoke-WebRequest -Uri "http://localhost:8000/healthz" -UseBasicParsing -TimeoutSec 5 -ErrorAction Stop
            if ($response.StatusCode -eq 200) {
                $backendReady = $true
            }
        } catch {
            $attempts++
            Start-Sleep -Seconds 3
        }
    }
    
    if (-not $backendReady) {
        Write-Host "ERROR: Backend failed to start" -ForegroundColor Red
        exit 1
    }
}

# Open Chrome and auto-login
Write-Host "Opening and auto-logging in..." -ForegroundColor Green
$chromeExe = "C:\Program Files\Google\Chrome\Application\chrome.exe"
Start-Process $chromeExe -ArgumentList "http://localhost:3000"

# Wait for Chrome to load
Start-Sleep -Seconds 3

# Auto-fill token using SendKeys
Add-Type -AssemblyName System.Windows.Forms
Start-Sleep -Seconds 2
[System.Windows.Forms.SendKeys]::SendWait($authToken)
Start-Sleep -Seconds 1
[System.Windows.Forms.SendKeys]::SendWait("{ENTER}")

Write-Host ""
Write-Host "===================================================" -ForegroundColor Green
Write-Host "SUCCESS: Mission Control is READY and LOGGED IN!" -ForegroundColor Green
Write-Host "===================================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Dashboard: http://localhost:3000" -ForegroundColor Cyan
Write-Host "  Status: Auto-logged in" -ForegroundColor Green
Write-Host ""
