@echo off
:: Launch OpenClaw installer in Windows Sandbox for testing

setlocal
cd /d "%~dp0"

echo.
echo ╔═══════════════════════════════════════════════════════════╗
echo ║     Testing OpenClaw Installer in Windows Sandbox         ║
echo ╚═══════════════════════════════════════════════════════════╝
echo.

:: Check if Windows Sandbox is enabled
powershell -ExecutionPolicy Bypass -NoProfile -Command "$feature = Get-WindowsOptionalFeature -Online -FeatureName 'Containers-DisposableClientVM' -ErrorAction SilentlyContinue; if (-not $feature -or $feature.State -ne 'Enabled') { Write-Host '❌ Windows Sandbox is not enabled!' -ForegroundColor Red; Write-Host ''; Write-Host 'To enable:' -ForegroundColor Yellow; Write-Host '  1. Open PowerShell as Administrator' -ForegroundColor White; Write-Host '  2. Run: Enable-WindowsOptionalFeature -Online -FeatureName Containers-DisposableClientVM -All' -ForegroundColor White; Write-Host '  3. Restart your computer' -ForegroundColor White; Write-Host ''; exit 1 } else { Write-Host '✅ Windows Sandbox is enabled' -ForegroundColor Green; Write-Host ''; exit 0 }"

if errorlevel 1 (
    pause
    exit /b 1
)

echo Launching Sandbox with installer...
echo.
echo The installer will run automatically in the Sandbox.
echo Watch the Sandbox window to see progress.
echo.
echo NOTE: The Sandbox is isolated - no changes affect your main system.
echo.

start "" "%~dp0sandbox-test.wsb"

echo.
echo ✅ Sandbox launched!
echo.
echo Close the Sandbox window when you're done testing.
echo.
pause
exit /b 0
