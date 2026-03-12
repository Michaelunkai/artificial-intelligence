@echo off
cd /d "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "validate-and-run.ps1"
echo.
echo ========================================
echo Exit code: %ERRORLEVEL%
echo ========================================
pause
