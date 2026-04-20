# OpenClaw Auto-Installer - FULL AUTOMATION
# Automatically enables Sandbox, launches it, runs installer, all zero interaction

param(
    [switch]$Force
)

$ErrorActionPreference = 'Stop'

function Write-Banner {
    Clear-Host
    Write-Host @"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║     OpenClaw FULLY AUTOMATIC Sandbox Installer v1.0       ║
║                                                           ║
║              ZERO INTERACTION REQUIRED                    ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan
    Write-Host ""
}

Write-Banner

# Check if running as admin
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

# Step 1: Check Windows Sandbox feature
Write-Host "[1/5] Checking Windows Sandbox feature..." -ForegroundColor Green

$feature = Get-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -ErrorAction SilentlyContinue

if (-not $feature -or $feature.State -ne 'Enabled') {
    Write-Host "   ⚠️ Windows Sandbox is NOT enabled" -ForegroundColor Yellow
    
    if (-not $isAdmin) {
        Write-Host "`n   Relaunching as Administrator to enable Sandbox..." -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        
        $scriptPath = $MyInvocation.MyCommand.Path
        Start-Process powershell.exe -Verb RunAs -ArgumentList "-ExecutionPolicy Bypass -File `"$scriptPath`" -Force" -Wait
        exit 0
    }
    
    Write-Host "   📦 Enabling Windows Sandbox (requires restart)..." -ForegroundColor Yellow
    Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All -NoRestart | Out-Null
    
    Write-Host "   ✅ Windows Sandbox enabled" -ForegroundColor Green
    Write-Host "`n   ⚠️ RESTART REQUIRED - Restarting in 10 seconds..." -ForegroundColor Yellow
    Write-Host "   (Press Ctrl+C to cancel)`n" -ForegroundColor Gray
    
    Start-Sleep -Seconds 10
    Restart-Computer -Force
    exit 0
} else {
    Write-Host "   ✅ Windows Sandbox is enabled" -ForegroundColor Green
}

# Step 2: Create sandbox staging directory
Write-Host "[2/5] Preparing sandbox environment..." -ForegroundColor Green

$sandboxStaging = "$env:TEMP\OpenClawSandboxInstall"
if (Test-Path $sandboxStaging) {
    Remove-Item -Path $sandboxStaging -Recurse -Force
}
New-Item -ItemType Directory -Path $sandboxStaging -Force | Out-Null

# Copy installer files to staging
$installerDir = Split-Path -Parent $MyInvocation.MyCommand.Path
Copy-Item -Path "$installerDir\setup.ps1" -Destination $sandboxStaging -Force
Copy-Item -Path "$installerDir\verify-installation.ps1" -Destination $sandboxStaging -Force

Write-Host "   ✅ Sandbox staging directory created: $sandboxStaging" -ForegroundColor Green

# Step 3: Create auto-run script for sandbox
Write-Host "[3/5] Creating auto-execution script..." -ForegroundColor Green

$sandboxAutoRun = @'
# OpenClaw Sandbox Auto-Installer
# This script runs automatically inside the sandbox

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'

# Banner
Clear-Host
Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║     OpenClaw Auto-Installer Running in Sandbox           ║" -ForegroundColor Cyan
Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""
Write-Host "This is a SAFE isolated environment." -ForegroundColor Green
Write-Host "All changes will be discarded when you close this window." -ForegroundColor Gray
Write-Host ""

# Find the mounted installer directory
$installerPath = $null
$possiblePaths = @(
    "C:\Users\WDAGUtilityAccount\Desktop\OpenClawSandboxInstall",
    "C:\Users\WDAGUtilityAccount\Downloads\OpenClawSandboxInstall",
    "\\?\GLOBALROOT\Device\HarddiskVolumeShadowCopy1\OpenClawSandboxInstall"
)

foreach ($path in $possiblePaths) {
    if (Test-Path "$path\setup.ps1") {
        $installerPath = $path
        break
    }
}

if (-not $installerPath) {
    # Search all drives
    Get-PSDrive -PSProvider FileSystem | ForEach-Object {
        $searchPath = "$($_.Root)OpenClawSandboxInstall"
        if (Test-Path "$searchPath\setup.ps1") {
            $installerPath = $searchPath
        }
    }
}

if ($installerPath) {
    Write-Host "✅ Installer found at: $installerPath" -ForegroundColor Green
    Write-Host ""
    Write-Host "Starting installation..." -ForegroundColor Yellow
    Write-Host "=" * 60 -ForegroundColor Gray
    Write-Host ""
    
    # Run the installer
    Set-Location $installerPath
    & "$installerPath\setup.ps1" -Silent
    
    Write-Host ""
    Write-Host "=" * 60 -ForegroundColor Gray
    Write-Host ""
    
    # Run verification
    Write-Host "Running verification checks..." -ForegroundColor Yellow
    & "$installerPath\verify-installation.ps1"
    
    Write-Host ""
    Write-Host "╔═══════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║              INSTALLATION COMPLETE                        ║" -ForegroundColor Green
    Write-Host "╚═══════════════════════════════════════════════════════════╝" -ForegroundColor Green
    Write-Host ""
    Write-Host "You can now:" -ForegroundColor White
    Write-Host "  • Test OpenClaw: openclaw status" -ForegroundColor Gray
    Write-Host "  • Start chat: openclaw chat" -ForegroundColor Gray
    Write-Host "  • Close this window when done (all changes will be discarded)" -ForegroundColor Gray
    Write-Host ""
} else {
    Write-Host "❌ ERROR: Could not find installer files" -ForegroundColor Red
    Write-Host "Expected location: C:\Users\WDAGUtilityAccount\Desktop\OpenClawSandboxInstall" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Available drives:" -ForegroundColor Yellow
    Get-PSDrive -PSProvider FileSystem | Select-Object Name, Root | Format-Table
}

# Keep window open
Write-Host ""
Write-Host "Press any key to close this window and exit the sandbox..." -ForegroundColor White
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
'@

Set-Content -Path "$sandboxStaging\AutoRun.ps1" -Value $sandboxAutoRun -Force
Write-Host "   ✅ Auto-run script created" -ForegroundColor Green

# Step 4: Create sandbox configuration file
Write-Host "[4/5] Creating sandbox configuration..." -ForegroundColor Green

$wsbConfig = @"
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
  <VGpu>Enable</VGpu>
  <Networking>Enable</Networking>
  <AudioInput>Disable</AudioInput>
  <VideoInput>Disable</VideoInput>
  <ProtectedClient>Disable</ProtectedClient>
  <PrinterRedirection>Disable</PrinterRedirection>
  <ClipboardRedirection>Enable</ClipboardRedirection>
  <MemoryInMB>4096</MemoryInMB>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$sandboxStaging</HostFolder>
      <SandboxFolder>C:\Users\WDAGUtilityAccount\Desktop\OpenClawSandboxInstall</SandboxFolder>
      <ReadOnly>true</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell.exe -ExecutionPolicy Bypass -NoExit -WindowStyle Maximized -File "C:\Users\WDAGUtilityAccount\Desktop\OpenClawSandboxInstall\AutoRun.ps1"</Command>
  </LogonCommand>
</Configuration>
"@

$wsbPath = "$sandboxStaging\OpenClawInstaller.wsb"
Set-Content -Path $wsbPath -Value $wsbConfig -Encoding UTF8 -Force
Write-Host "   ✅ Sandbox configuration created" -ForegroundColor Green

# Step 5: Launch sandbox
Write-Host "[5/5] Launching Windows Sandbox..." -ForegroundColor Green
Write-Host ""
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "  SANDBOX WILL OPEN IN A NEW WINDOW" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "The installer will run AUTOMATICALLY inside the sandbox." -ForegroundColor White
Write-Host "Watch the terminal window that appears." -ForegroundColor White
Write-Host ""
Write-Host "What you'll see:" -ForegroundColor Yellow
Write-Host "  1. Sandbox window opens (may take 30-60 seconds)" -ForegroundColor Gray
Write-Host "  2. PowerShell window appears automatically" -ForegroundColor Gray
Write-Host "  3. Installation runs step-by-step" -ForegroundColor Gray
Write-Host "  4. Verification checks run at the end" -ForegroundColor Gray
Write-Host "  5. Press any key in that window to close sandbox" -ForegroundColor Gray
Write-Host ""
Write-Host "The sandbox is 100% isolated - NOTHING affects your main system." -ForegroundColor Green
Write-Host ""
Write-Host "Launching in 3 seconds..." -ForegroundColor Yellow
Start-Sleep -Seconds 3

try {
    Start-Process -FilePath "WindowsSandbox.exe" -ArgumentList "`"$wsbPath`"" -ErrorAction Stop
    
    Write-Host ""
    Write-Host "✅ Sandbox launched successfully!" -ForegroundColor Green
    Write-Host ""
    Write-Host "📌 What to do now:" -ForegroundColor White
    Write-Host "   • Watch the Sandbox window (it's loading...)" -ForegroundColor Gray
    Write-Host "   • The installer will start automatically" -ForegroundColor Gray
    Write-Host "   • Review the installation output" -ForegroundColor Gray
    Write-Host "   • Test OpenClaw inside the sandbox if you want" -ForegroundColor Gray
    Write-Host "   • Close the Sandbox window when done" -ForegroundColor Gray
    Write-Host ""
    Write-Host "🗑️ When you close the Sandbox:" -ForegroundColor White
    Write-Host "   • All changes are automatically discarded" -ForegroundColor Gray
    Write-Host "   • No cleanup needed" -ForegroundColor Gray
    Write-Host "   • Your main system is untouched" -ForegroundColor Gray
    Write-Host ""
    
} catch {
    Write-Host ""
    Write-Host "❌ Failed to launch Windows Sandbox" -ForegroundColor Red
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host ""
    Write-Host "Troubleshooting:" -ForegroundColor Yellow
    Write-Host "  1. Make sure Windows Sandbox feature is enabled" -ForegroundColor White
    Write-Host "  2. Restart your computer if you just enabled it" -ForegroundColor White
    Write-Host "  3. Check if virtualization is enabled in BIOS" -ForegroundColor White
    Write-Host ""
}

Write-Host "Press any key to exit..." -ForegroundColor Gray
$null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
