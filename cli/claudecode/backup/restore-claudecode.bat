@echo off
:: UAC elevation check - re-launch as admin if not elevated
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Requesting administrator privileges...
    powershell -NoProfile -Command "Start-Process -FilePath '%~f0' -ArgumentList '%*' -Verb RunAs"
    exit /b
)

echo [INFO] Running as administrator.

:: Pre-check: winget available
where winget >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: winget not found. Install App Installer from the Microsoft Store or use Windows Update.
    echo          Some packages may not install correctly without winget.
) else (
    echo [OK] winget is available.
)

:: Pre-check: Node.js available
node --version >nul 2>&1
if %errorlevel% neq 0 (
    echo WARNING: Node.js not found. Claude Code requires Node.js to run.
    echo          Download Node.js from https://nodejs.org before continuing.
) else (
    for /f "tokens=*" %%v in ('node --version 2^>nul') do echo [OK] Node.js %%v is available.
)

echo.
echo [INFO] Launching restore-claudecode.ps1 ...
echo.

:: Run restore script with elevated privileges and ExecutionPolicy Bypass
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0restore-claudecode.ps1" %*

echo.
pause
