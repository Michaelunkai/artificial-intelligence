@echo off
echo Killing existing processes...
taskkill /f /im electron.exe 2>nul
taskkill /f /im node.exe 2>nul
taskkill /f /im vite.exe 2>nul

echo Starting Vite dev server...
start "Vite Dev Server" cmd /c "npm run dev:react"

echo Waiting for Vite to start...
timeout /t 3 /nobreak >nul

echo Starting Electron app...
start "Electron App" cmd /c "npm run dev:electron"

echo App started! Check the Electron window.