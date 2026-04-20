@echo off
:: OpenClaw FULLY AUTOMATIC Sandbox Installer
:: Just double-click this file - it does EVERYTHING automatically

setlocal
cd /d "%~dp0"

echo.
echo ╔═══════════════════════════════════════════════════════════╗
echo ║                                                           ║
echo ║     OpenClaw FULLY AUTOMATIC Installer v1.0               ║
echo ║                                                           ║
echo ║              ZERO CLICKS REQUIRED                         ║
echo ║                                                           ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.
echo This will:
echo   ✓ Enable Windows Sandbox (if needed)
echo   ✓ Launch isolated environment
echo   ✓ Install OpenClaw automatically
echo   ✓ Show you the entire process
echo   ✓ Discard everything when you close it
echo.
echo Starting in 3 seconds...
timeout /t 3 >nul

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0AutoInstallInSandbox.ps1"

if errorlevel 1 (
    echo.
    echo ❌ Failed to launch!
    echo.
    pause
    exit /b 1
)

exit /b 0
