# OpenClaw Installation Verification Script
# Run this after installation to verify everything is working

$ErrorActionPreference = 'Continue'

Write-Host "`n╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║       OpenClaw Installation Verification v1.0            ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝`n" -ForegroundColor Cyan

$checks = @()
$passed = 0
$failed = 0

# Check 1: Node.js
Write-Host "[1/10] Checking Node.js..." -ForegroundColor White
try {
    $nodeVersion = node --version 2>$null
    if ($nodeVersion -match "v(\d+)\.") {
        $major = [int]$matches[1]
        if ($major -ge 18) {
            Write-Host "   ✅ Node.js $nodeVersion installed" -ForegroundColor Green
            $passed++
        } else {
            Write-Host "   ❌ Node.js version too old ($nodeVersion, need >= v18)" -ForegroundColor Red
            $failed++
        }
    } else {
        throw "Invalid version format"
    }
} catch {
    Write-Host "   ❌ Node.js not found or not in PATH" -ForegroundColor Red
    $failed++
}

# Check 2: npm
Write-Host "[2/10] Checking npm..." -ForegroundColor White
try {
    $npmVersion = npm --version 2>$null
    if ($npmVersion) {
        Write-Host "   ✅ npm $npmVersion installed" -ForegroundColor Green
        $passed++
    } else {
        throw "npm not found"
    }
} catch {
    Write-Host "   ❌ npm not found or not in PATH" -ForegroundColor Red
    $failed++
}

# Check 3: OpenClaw CLI
Write-Host "[3/10] Checking OpenClaw CLI..." -ForegroundColor White
try {
    $openclawCmd = Get-Command openclaw -ErrorAction Stop
    $version = (npm list -g openclaw --depth=0 2>$null) -match "openclaw@([\d\.\-]+)"
    if ($version) {
        Write-Host "   ✅ OpenClaw $($matches[1]) installed at $($openclawCmd.Source)" -ForegroundColor Green
        $passed++
    } else {
        Write-Host "   ✅ OpenClaw installed but version unknown" -ForegroundColor Green
        $passed++
    }
} catch {
    Write-Host "   ❌ OpenClaw CLI not found" -ForegroundColor Red
    $failed++
}

# Check 4: Config directory
Write-Host "[4/10] Checking config directory..." -ForegroundColor White
$configDir = "$env:USERPROFILE\.openclaw"
if (Test-Path $configDir) {
    $items = Get-ChildItem -Path $configDir -Force | Measure-Object
    Write-Host "   ✅ Config directory exists: $configDir ($($items.Count) items)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "   ❌ Config directory not found: $configDir" -ForegroundColor Red
    $failed++
}

# Check 5: OpenClaw config file
Write-Host "[5/10] Checking OpenClaw configuration..." -ForegroundColor White
$configFile = "$configDir\openclaw.json"
if (Test-Path $configFile) {
    try {
        $config = Get-Content $configFile -Raw | ConvertFrom-Json
        Write-Host "   ✅ Config file exists and is valid JSON" -ForegroundColor Green
        $passed++
    } catch {
        Write-Host "   ⚠️ Config file exists but has invalid JSON" -ForegroundColor Yellow
        $failed++
    }
} else {
    Write-Host "   ❌ Config file not found: $configFile" -ForegroundColor Red
    $failed++
}

# Check 6: Workspace
Write-Host "[6/10] Checking workspace..." -ForegroundColor White
$workspaceDir = "$configDir\workspace"
if (Test-Path $workspaceDir) {
    $files = Get-ChildItem -Path $workspaceDir -File -Force
    Write-Host "   ✅ Workspace exists: $workspaceDir ($($files.Count) files)" -ForegroundColor Green
    $passed++
} else {
    Write-Host "   ❌ Workspace not found: $workspaceDir" -ForegroundColor Red
    $failed++
}

# Check 7: System tray script
Write-Host "[7/10] Checking system tray integration..." -ForegroundColor White
$trayDir = "$configDir\tray"
$trayVbs = "$trayDir\OpenClawTray.vbs"
$trayPs1 = "$trayDir\OpenClawTray.ps1"

if ((Test-Path $trayVbs) -and (Test-Path $trayPs1)) {
    Write-Host "   ✅ Tray scripts found" -ForegroundColor Green
    $passed++
} else {
    Write-Host "   ❌ Tray scripts missing" -ForegroundColor Red
    $failed++
}

# Check 8: Startup shortcut
Write-Host "[8/10] Checking auto-start configuration..." -ForegroundColor White
$startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
$shortcut = "$startupFolder\OpenClawTray.lnk"

if (Test-Path $shortcut) {
    Write-Host "   ✅ Startup shortcut exists" -ForegroundColor Green
    $passed++
} else {
    Write-Host "   ❌ Startup shortcut not found" -ForegroundColor Red
    $failed++
}

# Check 9: Gateway process/port
Write-Host "[9/10] Checking OpenClaw Gateway..." -ForegroundColor White
$gatewayRunning = $false
$portOpen = $false

# Check if port 18789 is listening
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect('127.0.0.1', 18789)
    $tcp.Close()
    $portOpen = $true
} catch {}

# Check for node process running openclaw gateway
$gatewayProcess = Get-Process -Name "node" -ErrorAction SilentlyContinue | Where-Object {
    try {
        $cmd = (Get-CimInstance Win32_Process -Filter "ProcessId=$($_.Id)" -ErrorAction SilentlyContinue).CommandLine
        $cmd -like "*openclaw*gateway*"
    } catch { $false }
}

if ($portOpen) {
    Write-Host "   ✅ Gateway is running on port 18789" -ForegroundColor Green
    $passed++
} elseif ($gatewayProcess) {
    Write-Host "   ⚠️ Gateway process found but port 18789 not responding (may be starting...)" -ForegroundColor Yellow
    $passed++
} else {
    Write-Host "   ❌ Gateway is not running" -ForegroundColor Red
    Write-Host "      Start it with: openclaw gateway" -ForegroundColor Gray
    $failed++
}

# Check 10: API Key
Write-Host "[10/10] Checking Anthropic API key..." -ForegroundColor White
$apiKey = $env:ANTHROPIC_API_KEY
if ($apiKey) {
    $keyPreview = $apiKey.Substring(0, [Math]::Min(8, $apiKey.Length)) + "..." + $apiKey.Substring([Math]::Max(0, $apiKey.Length - 4))
    Write-Host "   ✅ API key is set: $keyPreview" -ForegroundColor Green
    $passed++
} else {
    Write-Host "   ⚠️ API key not set in environment" -ForegroundColor Yellow
    Write-Host "      Set it with: [System.Environment]::SetEnvironmentVariable('ANTHROPIC_API_KEY', 'your-key', 'User')" -ForegroundColor Gray
    $failed++
}

# Summary
Write-Host "`n" + ("="*60) -ForegroundColor Cyan
Write-Host "VERIFICATION SUMMARY" -ForegroundColor Cyan
Write-Host ("="*60) -ForegroundColor Cyan

$total = $passed + $failed
$percentage = [math]::Round(($passed / $total) * 100)

Write-Host "`nPassed: $passed/$total ($percentage%)" -ForegroundColor $(if ($passed -eq $total) { "Green" } else { "Yellow" })
Write-Host "Failed: $failed/$total" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

if ($passed -eq $total) {
    Write-Host "`n🎉 All checks passed! OpenClaw is ready to use." -ForegroundColor Green
    Write-Host "`nNext steps:" -ForegroundColor White
    Write-Host "  • Run: openclaw chat" -ForegroundColor Gray
    Write-Host "  • Check status: openclaw status" -ForegroundColor Gray
    Write-Host "  • View logs: openclaw logs`n" -ForegroundColor Gray
} elseif ($failed -eq 0) {
    Write-Host "`n✅ Installation complete with warnings." -ForegroundColor Yellow
    Write-Host "   Review warnings above and fix if needed.`n" -ForegroundColor White
} else {
    Write-Host "`n❌ Installation incomplete or has errors." -ForegroundColor Red
    Write-Host "   Review failed checks above and re-run the installer.`n" -ForegroundColor White
}

# Offer to open documentation
$openDocs = Read-Host "`nOpen OpenClaw documentation? (y/n)"
if ($openDocs -eq 'y') {
    Start-Process "https://docs.openclaw.ai"
}
