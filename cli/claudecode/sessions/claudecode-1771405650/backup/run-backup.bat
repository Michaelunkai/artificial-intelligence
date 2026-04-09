@echo off
title Claude Code Backup v15.3 ULTRAHYPER
color 0A
echo ================================================================================
echo                    CLAUDE CODE ULTRAHYPER BACKUP v15.3
echo                    128 Parallel Jobs ^| MT:64 ^| EVERY SECOND PROGRESS
echo ================================================================================
echo.
echo This will backup your Claude Code environment to F:\backup\claudecode
echo.
echo Press any key to start backup, or Ctrl+C to cancel...
pause > nul
echo.

cd /d "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "backup-claudecode.ps1"

echo.
echo ================================================================================
if %ERRORLEVEL% EQU 0 (
    echo                           BACKUP COMPLETED SUCCESSFULLY!
    color 0A
) else (
    echo                           BACKUP FINISHED WITH EXIT CODE: %ERRORLEVEL%
    color 0C
)
echo ================================================================================
echo.
echo Press any key to close...
pause > nul
