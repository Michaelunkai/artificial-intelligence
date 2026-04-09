# openclaw-stop - Stop all OpenClaw/ClawdBot processes
$killed = 0
Get-WmiObject Win32_Process -Filter "Name = 'wscript.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'ClawdbotTray' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $killed++ }
Get-WmiObject Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue |
    Where-Object { $_.CommandLine -match 'openclaw|clawdbot' } |
    ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue; $killed++ }
Write-Host "OpenClaw stopped ($killed processes killed)" -ForegroundColor Yellow
