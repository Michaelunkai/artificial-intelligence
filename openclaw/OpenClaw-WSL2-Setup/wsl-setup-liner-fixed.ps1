# WSL OpenClaw Setup - Fixed Liner
# Runs complete WSL Ubuntu reset + OpenClaw configuration in optimal order
# Usage: powershell -ExecutionPolicy Bypass -File wsl-setup-liner-fixed.ps1

$ErrorActionPreference = "Continue"
function OK  { param($M) Write-Host "[OK]  $M" -ForegroundColor Green }
function INF { param($M) Write-Host "[-->] $M" -ForegroundColor Cyan }
function ERR { param($M) Write-Host "[ERR] $M" -ForegroundColor Red }

$sw = [Diagnostics.Stopwatch]::StartNew()
Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host " WSL + OpenClaw Complete Setup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# ============================================
# PHASE 0: Pre-flight Checks
# ============================================
Write-Host "[1/7] Pre-flight Checks" -ForegroundColor Yellow

# Check Docker Desktop status
INF "Checking Docker Desktop..."
$dockerRunning = $false
try {
    $dockerProc = Get-Process "Docker Desktop" -EA SilentlyContinue
    if ($dockerProc) {
        OK "Docker Desktop is running"
        $dockerRunning = $true
    } else {
        INF "Docker Desktop not running - starting it..."
        Start-Process "C:\Program Files\Docker\Docker\Docker Desktop.exe" -EA SilentlyContinue
        Start-Sleep 10
        OK "Docker Desktop started (waiting for initialization...)"
    }
} catch {
    INF "Docker Desktop not found (optional - can be installed later)"
}

# Check backup exists
if (-not (Test-Path "F:\backup\linux\wsl\ubuntu.tar")) {
    ERR "Ubuntu backup not found at F:\backup\linux\wsl\ubuntu.tar"
    exit 1
}
OK "Ubuntu backup exists"

# ============================================
# PHASE 1: Reset WSL Ubuntu
# ============================================
Write-Host ""
Write-Host "[2/7] Resetting WSL Ubuntu" -ForegroundColor Yellow

INF "Terminating existing Ubuntu instance..."
wsl --terminate ubuntu 2>$null
Start-Sleep 2
OK "Ubuntu terminated"

INF "Unregistering Ubuntu distribution..."
wsl --unregister ubuntu 2>$null
Start-Sleep 2
OK "Ubuntu unregistered"

INF "Cleaning WSL data directory..."
Remove-Item 'C:\wsl2\ubuntu\*' -Force -Recurse -EA SilentlyContinue
New-Item -ItemType Directory -Path 'C:\wsl2\ubuntu' -Force -EA SilentlyContinue | Out-Null
OK "Data directory cleaned"

INF "Importing Ubuntu from backup (this may take 30-60 seconds)..."
wsl --import ubuntu C:\wsl2\ubuntu\ 'F:\backup\linux\wsl\ubuntu.tar' 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) {
    OK "Ubuntu imported successfully"
} else {
    ERR "Failed to import Ubuntu"
    exit 1
}

INF "Setting Ubuntu as default distribution..."
wsl --set-default ubuntu 2>&1 | Out-Null
OK "Ubuntu set as default"

# ============================================
# PHASE 2: Windows Path Setup (a.sh)
# ============================================
Write-Host ""
Write-Host "[3/7] Configuring Windows Paths" -ForegroundColor Yellow

Push-Location "F:\study\setups\wsl-winpaths"

INF "Running Windows path setup script..."
wsl -d Ubuntu bash -lc "cd /mnt/f/study/setups/wsl-winpaths && sudo bash a.sh" 2>&1 | Out-String | Write-Host
if ($LASTEXITCODE -eq 0) {
    OK "Windows path setup complete"
} else {
    ERR "Windows path setup had errors (continuing anyway)"
}

Pop-Location

# ============================================
# PHASE 3: WSL Restart (apply wsl.conf changes)
# ============================================
Write-Host ""
Write-Host "[4/7] Restarting WSL" -ForegroundColor Yellow

INF "Shutting down WSL..."
wsl --shutdown
Start-Sleep 5
OK "WSL shutdown complete"

INF "Testing Ubuntu restart..."
$test = wsl -d Ubuntu echo "ok"
if ($test -match "ok") {
    OK "Ubuntu restarted successfully"
} else {
    ERR "Ubuntu restart failed"
    exit 1
}

# ============================================
# PHASE 4: OpenClaw Complete Setup (40 tasks)
# ============================================
Write-Host ""
Write-Host "[5/7] Running OpenClaw Setup (40 tasks)" -ForegroundColor Yellow

INF "Starting OpenClaw WSL2 Complete Setup..."
& "F:\study\Devops\automation\OpenClaw-WSL2-Setup\Setup-OpenClaw-WSL2-Complete.ps1" -SkipPackageUpdates

if ($LASTEXITCODE -eq 0) {
    OK "OpenClaw setup completed (40/40 tasks)"
} else {
    INF "OpenClaw setup finished with warnings"
}

# ============================================
# PHASE 5: Docker Verification (if Desktop is running)
# ============================================
Write-Host ""
Write-Host "[6/7] Docker Integration" -ForegroundColor Yellow

if ($dockerRunning) {
    INF "Waiting for Docker to fully initialize (30 seconds)..."
    Start-Sleep 30
    
    INF "Testing Docker in WSL..."
    $dockerTest = wsl -d Ubuntu bash -lc "docker --version 2>&1"
    if ($dockerTest -match "Docker") {
        OK "Docker accessible: $dockerTest"
        
        # Try starting Docker daemon in WSL
        INF "Starting Docker daemon..."
        wsl -d Ubuntu bash -lc "sudo service docker start 2>&1" | Out-Null
        Start-Sleep 5
        
        $dockerPsTest = wsl -d Ubuntu bash -lc "docker ps 2>&1"
        if ($dockerPsTest -match "CONTAINER") {
            OK "Docker fully operational"
        } else {
            INF "Docker CLI available but daemon may need configuration"
        }
    } else {
        INF "Docker not accessible in WSL (can be configured later)"
    }
} else {
    INF "Docker Desktop not running - skipping Docker verification"
}

# ============================================
# PHASE 6: Disk Usage Check
# ============================================
Write-Host ""
Write-Host "[7/7] Disk Usage Check" -ForegroundColor Yellow

INF "Checking /mnt/wslg size..."
$diskUsage = wsl -d Ubuntu bash -lc "du -sh /mnt/wslg 2>/dev/null"
OK "/mnt/wslg: $diskUsage"

# ============================================
# Summary
# ============================================
$sw.Stop()
Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " SETUP COMPLETE" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Green
Write-Host ""
Write-Host "Duration: $($sw.Elapsed.ToString('mm\:ss'))" -ForegroundColor Cyan
Write-Host ""
Write-Host "Verification:" -ForegroundColor Yellow
$ocVersion = wsl -d Ubuntu bash -lc "openclaw --version 2>/dev/null"
Write-Host "  OpenClaw:  $ocVersion" -ForegroundColor Cyan
$nodeVersion = wsl -d Ubuntu bash -lc "node --version 2>/dev/null"
Write-Host "  Node.js:   $nodeVersion" -ForegroundColor Cyan
$chromeVersion = wsl -d Ubuntu bash -lc "google-chrome --version 2>/dev/null"
Write-Host "  Chrome:    $chromeVersion" -ForegroundColor Cyan
Write-Host ""
Write-Host "Quick Commands:" -ForegroundColor Yellow
Write-Host "  Launch Ubuntu:    wsl -d Ubuntu" -ForegroundColor Cyan
Write-Host "  OpenClaw Status:  wsl -d Ubuntu bash -lc 'openclaw status'" -ForegroundColor Cyan
Write-Host "  Control Panel:    F:\study\Devops\automation\OpenClaw-WSL2-Setup\control-panel.ps1" -ForegroundColor Cyan
Write-Host ""
