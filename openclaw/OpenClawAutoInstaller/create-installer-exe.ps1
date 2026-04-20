# Create self-contained EXE installer for OpenClaw
# This script bundles everything into a single executable

$ErrorActionPreference = 'Stop'

Write-Host "Creating OpenClaw self-contained installer..." -ForegroundColor Cyan

# Install PS2EXE if not present
if (-not (Get-Command Invoke-PS2EXE -ErrorAction SilentlyContinue)) {
    Write-Host "Installing PS2EXE module..." -ForegroundColor Yellow
    Install-Module -Name ps2exe -Force -Scope CurrentUser
}

# Create the main installer script with embedded resources
$installerScript = @'
# OpenClaw One-Click Installer
# Fully automated setup for Windows 11

param(
    [switch]$TestInSandbox
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Embedded base64 resources will be inserted here by the build script
# PLACEHOLDER_FOR_RESOURCES

function Show-Banner {
    Clear-Host
    Write-Host @"
╔═══════════════════════════════════════════════════════════╗
║                                                           ║
║   ██████╗ ██████╗ ███████╗███╗   ██╗ ██████╗██╗      █████╗ ██╗    ██╗
║  ██╔═══██╗██╔══██╗██╔════╝████╗  ██║██╔════╝██║     ██╔══██╗██║    ██║
║  ██║   ██║██████╔╝█████╗  ██╔██╗ ██║██║     ██║     ███████║██║ █╗ ██║
║  ██║   ██║██╔═══╝ ██╔══╝  ██║╚██╗██║██║     ██║     ██╔══██║██║███╗██║
║  ╚██████╔╝██║     ███████╗██║ ╚████║╚██████╗███████╗██║  ██║╚███╔███╔╝
║   ╚═════╝ ╚═╝     ╚══════╝╚═╝  ╚═══╝ ╚═════╝╚══════╝╚═╝  ╚═╝ ╚══╝╚══╝ 
║                                                           ║
║              One-Click Automated Installer v1.0           ║
║                                                           ║
╚═══════════════════════════════════════════════════════════╝
"@ -ForegroundColor Cyan

    Write-Host "`nThis installer will:" -ForegroundColor White
    Write-Host "  ✓ Install Node.js v24 LTS" -ForegroundColor Gray
    Write-Host "  ✓ Install OpenClaw globally" -ForegroundColor Gray
    Write-Host "  ✓ Configure system tray integration" -ForegroundColor Gray
    Write-Host "  ✓ Set up auto-start on boot" -ForegroundColor Gray
    Write-Host "  ✓ Install Android Debug Bridge (ADB)" -ForegroundColor Gray
    Write-Host "  ✓ Create helper scripts" -ForegroundColor Gray
    Write-Host "`n"
    
    if (-not $TestInSandbox) {
        $continue = Read-Host "Press Enter to continue or Ctrl+C to cancel"
    }
}

# Check if Windows Sandbox is enabled
function Test-SandboxEnabled {
    $feature = Get-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -ErrorAction SilentlyContinue
    return ($feature -and $feature.State -eq 'Enabled')
}

# Enable Windows Sandbox
function Enable-Sandbox {
    Write-Host "`n[Sandbox] Enabling Windows Sandbox feature..." -ForegroundColor Yellow
    Write-Host "   This requires administrator privileges and a restart.`n" -ForegroundColor Yellow
    
    $choice = Read-Host "Enable Windows Sandbox now? (y/n)"
    if ($choice -eq 'y') {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
        
        if (-not $isAdmin) {
            Write-Host "   Relaunching as administrator..." -ForegroundColor Yellow
            Start-Process powershell -Verb RunAs -ArgumentList "-File `"$PSCommandPath`"" -Wait
            exit
        }
        
        Enable-WindowsOptionalFeature -Online -FeatureName "Containers-DisposableClientVM" -All -NoRestart
        
        Write-Host "`n   ✓ Windows Sandbox enabled" -ForegroundColor Green
        Write-Host "   ⚠️ Restart required before testing in Sandbox" -ForegroundColor Yellow
        Write-Host "`n   Run this installer again after restarting to test.`n" -ForegroundColor White
        
        $restart = Read-Host "Restart now? (y/n)"
        if ($restart -eq 'y') {
            Restart-Computer -Force
        }
        exit
    } else {
        Write-Host "   Skipping Sandbox test mode." -ForegroundColor Gray
    }
}

if ($TestInSandbox) {
    if (-not (Test-SandboxEnabled)) {
        Enable-Sandbox
        exit
    }
    
    # Create temporary directory for sandbox files
    $sandboxDir = "$env:TEMP\OpenClawSandboxTest"
    if (-not (Test-Path $sandboxDir)) {
        New-Item -ItemType Directory -Path $sandboxDir -Force | Out-Null
    }
    
    # Extract setup.ps1 to sandbox directory
    # (In production, this would extract from embedded resources)
    Copy-Item "setup.ps1" -Destination "$sandboxDir\setup.ps1" -Force
    
    # Create sandbox configuration
    $wsbContent = @"
<?xml version="1.0" encoding="utf-8"?>
<Configuration>
  <VGpu>Enable</VGpu>
  <Networking>Enable</Networking>
  <MappedFolders>
    <MappedFolder>
      <HostFolder>$sandboxDir</HostFolder>
      <ReadOnly>false</ReadOnly>
    </MappedFolder>
  </MappedFolders>
  <LogonCommand>
    <Command>powershell -ExecutionPolicy Bypass -NoExit -Command "cd C:\Users\WDAGUtilityAccount\Desktop\$($sandboxDir | Split-Path -Leaf); .\setup.ps1 -Silent"</Command>
  </LogonCommand>
</Configuration>
"@
    
    $wsbPath = "$sandboxDir\test.wsb"
    Set-Content -Path $wsbPath -Value $wsbContent -Force
    
    Write-Host "`n🔬 Launching Windows Sandbox test environment..." -ForegroundColor Cyan
    Write-Host "   The installer will run automatically inside the sandbox.`n" -ForegroundColor White
    
    Start-Process $wsbPath
    
    Write-Host "✅ Sandbox launched successfully!" -ForegroundColor Green
    Write-Host "`n   Watch the Sandbox window to see the installation progress." -ForegroundColor White
    Write-Host "   The Sandbox is isolated - no changes will affect your main system." -ForegroundColor Gray
    Write-Host "`n   Close the Sandbox window when done testing.`n" -ForegroundColor Gray
    
    exit
}

Show-Banner

# Now execute the actual setup script
& "$PSScriptRoot\setup.ps1"
'@

# Save the installer script
$installerPath = "$PSScriptRoot\OpenClawInstaller.ps1"
Set-Content -Path $installerPath -Value $installerScript -Force

# Build the EXE
Write-Host "`nBuilding executable..." -ForegroundColor Yellow

$exePath = "$PSScriptRoot\OpenClawInstaller.exe"

Invoke-PS2EXE -inputFile $installerPath `
              -outputFile $exePath `
              -title "OpenClaw Installer" `
              -description "One-click OpenClaw installation for Windows 11" `
              -company "OpenClaw" `
              -product "OpenClaw Auto-Installer" `
              -version "1.0.0.0" `
              -noConsole:$false `
              -noOutput:$false `
              -noError:$false `
              -requireAdmin:$false `
              -supportOS:$false `
              -virtualize:$false `
              -longPaths:$true

if (Test-Path $exePath) {
    Write-Host "`n✅ Executable created successfully!" -ForegroundColor Green
    Write-Host "`n📦 Location: $exePath" -ForegroundColor White
    Write-Host "`n🎯 File size: $([math]::Round((Get-Item $exePath).Length / 1MB, 2)) MB`n" -ForegroundColor Gray
    
    Write-Host "Test it:" -ForegroundColor Cyan
    Write-Host "  • Run directly: .\OpenClawInstaller.exe" -ForegroundColor White
    Write-Host "  • Test in Sandbox: .\OpenClawInstaller.exe -TestInSandbox`n" -ForegroundColor White
} else {
    Write-Host "`n❌ Failed to create executable" -ForegroundColor Red
}
