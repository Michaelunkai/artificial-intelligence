@echo off
:: OpenClaw One-Click Installer Launcher
:: This CMD file launches the PowerShell installer with proper execution policy

setlocal
cd /d "%~dp0"

echo.
echo ╔═══════════════════════════════════════════════════════════╗
echo ║         OpenClaw One-Click Installer v1.0                 ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.
echo Starting installer...
echo.

powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0setup.ps1"

if errorlevel 1 (
    echo.
    echo ❌ Installation failed!
    echo.
    pause
    exit /b 1
)

echo.
echo ✅ Installation completed successfully!
echo.
echo Press any key to exit...
pause >nul
exit /b 0
