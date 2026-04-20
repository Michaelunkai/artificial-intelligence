# ============================================================
# OpenClaw Client Acquisition System — One-Click Local Launcher
# Run: powershell -ExecutionPolicy Bypass -File start.ps1
# ============================================================

$ErrorActionPreference = "Stop"
$ROOT = $PSScriptRoot

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  OpenClaw Client Acquisition System" -ForegroundColor Cyan
Write-Host "  Local Development Launcher" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ---- Backend Setup ----
Write-Host "[1/4] Setting up Python backend..." -ForegroundColor Yellow
Set-Location "$ROOT\backend"

if (-not (Test-Path "..\venv")) {
    Write-Host "      Creating virtual environment..." -ForegroundColor Gray
    python -m venv ..\venv
}

Write-Host "      Activating venv and installing dependencies..." -ForegroundColor Gray
& "..\venv\Scripts\Activate.ps1"
pip install -r requirements.txt --quiet

# Create data directory
if (-not (Test-Path "..\data")) {
    New-Item -ItemType Directory -Path "..\data" | Out-Null
}

# Create .env if not exists
if (-not (Test-Path "..\`.env")) {
    Copy-Item "..\`.env.example" "..\`.env"
    Write-Host "      Created .env from .env.example — edit it with your SMTP credentials!" -ForegroundColor Magenta
}

# ---- Start Backend ----
Write-Host "[2/4] Starting FastAPI backend (port 8000)..." -ForegroundColor Yellow
$backendJob = Start-Job -ScriptBlock {
    param($dir)
    Set-Location $dir
    & "..\venv\Scripts\python.exe" -m uvicorn main:app --reload --port 8000
} -ArgumentList "$ROOT\backend"

Write-Host "      Backend starting at http://localhost:8000" -ForegroundColor Green
Start-Sleep -Seconds 2

# ---- Frontend Setup ----
Write-Host "[3/4] Setting up React frontend..." -ForegroundColor Yellow
Set-Location "$ROOT\frontend"

if (-not (Test-Path "node_modules")) {
    Write-Host "      Installing npm dependencies (this may take a minute)..." -ForegroundColor Gray
    npm install
}

# Set VITE_API_URL for local dev
$envLocal = "VITE_API_URL=http://localhost:8000"
if (-not (Test-Path ".env.local") -or -not (Get-Content ".env.local" | Select-String "VITE_API_URL")) {
    $envLocal | Out-File ".env.local" -Encoding UTF8
}

# ---- Start Frontend ----
Write-Host "[4/4] Starting React frontend (port 3000)..." -ForegroundColor Yellow
$frontendJob = Start-Job -ScriptBlock {
    param($dir)
    Set-Location $dir
    npm run dev
} -ArgumentList "$ROOT\frontend"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host "  ✅ OpenClaw is running!" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "  🖥️  Dashboard:  http://localhost:3000" -ForegroundColor White
Write-Host "  📋  Intake:     http://localhost:3000/intake" -ForegroundColor White
Write-Host "  🔌  API Docs:   http://localhost:8000/docs" -ForegroundColor White
Write-Host ""
Write-Host "  Press Ctrl+C to stop all services" -ForegroundColor Gray
Write-Host ""

Start-Sleep -Seconds 3

# Open browser
Start-Process "http://localhost:3000"

# Wait for Ctrl+C
try {
    while ($true) {
        Start-Sleep -Seconds 5
        $backendOutput = Receive-Job $backendJob
        $frontendOutput = Receive-Job $frontendJob
        if ($backendOutput) { Write-Host "[Backend] $backendOutput" -ForegroundColor Gray }
    }
} finally {
    Write-Host ""
    Write-Host "Stopping services..." -ForegroundColor Yellow
    Stop-Job $backendJob, $frontendJob
    Remove-Job $backendJob, $frontendJob
    Write-Host "All services stopped." -ForegroundColor Green
}
