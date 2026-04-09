<#
.SYNOPSIS
    clawd - Start ClawdBot tray daemon silently in background
#>
$vbs = 'C:\Users\micha\.openclaw\ClawdBot\ClawdbotTray.vbs'
if (-not (Test-Path $vbs)) {
    Write-Warning "clawd: ClawdBot VBS not found at $vbs"
    return
}
# Check if already running
$running = Get-WmiObject Win32_Process -Filter "Name = 'wscript.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'ClawdbotTray' }
if ($running) {
    Write-Host "clawd: ClawdBot already running [PID $($running.ProcessId)]" -ForegroundColor DarkGray
    return
}
Start-Process -FilePath 'wscript.exe' -ArgumentList "`"$vbs`"" -WindowStyle Hidden
Write-Host "clawd: ClawdBot tray started" -ForegroundColor Green
