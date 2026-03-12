@echo off
echo Reversing Ollama installation...

REM Stop any running Ollama processes
echo Stopping Ollama processes...
taskkill /f /im ollama.exe 2>nul

REM Remove the Ollama installation directory
echo Removing Ollama directory...
rmdir /s /q "F:\backup\ollama" 2>nul

REM Remove environment variables from registry
echo Removing environment variables...
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v OLLAMA_MODELS /f 2>nul
reg delete "HKLM\SYSTEM\CurrentControlSet\Control\Session Manager\Environment" /v OLLAMA_HOME /f 2>nul

REM Remove from user environment as well (optional)
reg delete "HKCU\Environment" /v OLLAMA_MODELS /f 2>nul
reg delete "HKCU\Environment" /v OLLAMA_HOME /f 2>nul

echo.
echo Ollama installation has been reversed.
echo Directory removed, processes stopped, and environment variables cleared.
pause
