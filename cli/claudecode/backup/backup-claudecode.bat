@echo off

:: Admin elevation check
net session >nul 2>&1
if %errorlevel% neq 0 (
    echo [ERROR] This script requires administrator privileges.
    echo Please right-click and select "Run as administrator".
    pause
    exit /b 1
)

:: Verify PS1 script exists
if not exist "%~dp0backup-claudecode.ps1" (
    echo [ERROR] backup-claudecode.ps1 not found in %~dp0
    pause
    exit /b 1
)

:: Generate timestamp using PowerShell for reliable cross-locale formatting
for /f %%t in ('powershell -NoProfile -Command "Get-Date -Format 'yyyy_MM_dd_HH_mm_ss'"') do set _TS=%%t

set _BACKUPPATH=F:\backup\claudecode\backup_%_TS%

echo [INFO] Starting backup to: %_BACKUPPATH%

powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0backup-claudecode.ps1" -BackupPath "%_BACKUPPATH%" %*
set _EXIT=%errorlevel%

if %_EXIT% neq 0 (
    echo [ERROR] Backup script exited with code %_EXIT%.
    pause
)

exit /b %_EXIT%
