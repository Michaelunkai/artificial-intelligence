@echo off
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0restore-claudecode.ps1" -Force %*
pause
