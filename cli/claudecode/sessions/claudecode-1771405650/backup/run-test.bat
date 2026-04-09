@echo off
echo Running test...
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "Write-Host 'Hello from PowerShell'"
echo Exit code: %ERRORLEVEL%
echo Done!
