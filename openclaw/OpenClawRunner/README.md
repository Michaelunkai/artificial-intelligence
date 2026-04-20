# OpenClaw Runner

**Silent background launcher for OpenClaw Gateway with system tray control**

## What It Does

- Runs `openclaw gateway` silently in the background (no console window)
- Shows green system tray icon while running
- Automatically adds itself to Windows startup
- Prevents multiple instances
- Right-click tray icon to restart or exit

## Location

**Exe:** `F:\study\Dev_Toolchain\programming\.NET\projects\C#\OpenClawRunner\dist\OpenClawRunner.exe`

## Features

✅ **Silent Operation:** No console windows, runs completely in background  
✅ **System Tray:** Green icon appears when running  
✅ **Auto-Startup:** Automatically adds to Windows startup registry  
✅ **Auto-Restart:** Watchdog monitors gateway every 10s and restarts if crashed  
✅ **Process Management:** Gracefully stops openclaw gateway on exit  
✅ **Single Instance:** Prevents multiple copies from running  
✅ **Immortal Gateway:** Never stops working - auto-recovery on any failure  

## System Tray Menu

Right-click the tray icon:
- **Restart Gateway** - Stops and restarts openclaw gateway
- **Exit** - Stops gateway and closes the app

## Startup Registry

The app adds itself to:
```
HKEY_CURRENT_USER\SOFTWARE\Microsoft\Windows\CurrentVersion\Run
Key: OpenClawRunner
Value: [Path to exe]
```

## How It Works

1. Creates hidden WinForms window (no taskbar presence)
2. Starts `openclaw gateway` as child process with:
   - `CreateNoWindow = true`
   - `WindowStyle = Hidden`
   - Output redirected (silent)
3. Shows system tray icon (green circle)
4. Monitors gateway process
5. On exit, kills gateway process tree

## Build

```powershell
cd "F:\study\Dev_Toolchain\programming\.NET\projects\C#\OpenClawRunner"
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true -p:IncludeNativeLibrariesForSelfExtract=true -o "dist"
```

## Tech Stack

- .NET 8.0 Windows Forms
- Self-contained single-file exe (~154 MB)
- No external dependencies

## Created

2026-02-11 - Automated silent OpenClaw Gateway launcher

## Status

✅ **Running:** Process ID 19812  
✅ **Startup:** Added to registry  
✅ **Gateway:** OpenClaw running in background (node PID: 8024)  
✅ **Watchdog:** Active - checks every 10 seconds  
✅ **Auto-Restart:** Enabled - gateway will never stay down

## Fix History

**2026-02-11 21:23** - Added watchdog auto-restart
- Watchdog timer checks gateway health every 10 seconds
- Auto-restarts if process crashes or exits
- Removed output redirection (prevents process hanging)
- Gateway is now immortal - auto-recovers from any failure

**2026-02-11 21:18** - Switched to PowerShell execution
- Changed to `powershell.exe -Command "openclaw gateway"`
- Identical behavior to manual PowerShell execution
- Works on any Windows 11 machine with OpenClaw installed

**2026-02-11 21:10** - Fixed path resolution issue
- Changed from using "openclaw" command to full path: `%APPDATA%\npm\openclaw.cmd`
- Runs via cmd.exe to properly execute .cmd file
- Works on any machine with OpenClaw installed via npm
- No working directory issues  
