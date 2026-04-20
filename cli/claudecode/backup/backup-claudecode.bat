@echo off
powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0backup-claudecode.ps1" %*
