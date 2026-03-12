# Kill all OpenClaw/Clawdbot instances - NO WMI VERSION
Write-Host "Stopping OpenClaw/Clawdbot processes..." -ForegroundColor Yellow

# Kill tray app PowerShell processes (using Get-Process + MainModule check, NO WMI)
Get-Process powershell -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $isTraynApp = $false
        # Check if process has ClawdbotTray or OpenClawTray in loaded modules
        foreach ($module in $_.Modules) {
            if ($module.FileName -like "*ClawdbotTray*" -or $module.FileName -like "*OpenClawTray*") {
                $isTrayApp = $true
                break
            }
        }
        
        if ($isTrayApp) {
            Write-Host "Killing tray app PID $($_.Id)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

Start-Sleep -Seconds 1

# Kill gateway node processes by checking listening ports (NO WMI)
# OpenClaw gateway typically runs on port 18789, workspaces on 37778-37781
$netstatOutput = netstat -ano | Select-String "LISTENING"
$gatewayPorts = @(18789, 37778, 37779, 37780, 37781)

foreach ($port in $gatewayPorts) {
    $match = $netstatOutput | Where-Object { $_ -match ":$port\s+.*LISTENING\s+(\d+)" }
    if ($match -and $matches[1]) {
        $pid = [int]$matches[1]
        try {
            $proc = Get-Process -Id $pid -ErrorAction Stop
            if ($proc.Name -eq "node") {
                Write-Host "Killing gateway PID $pid (port $port)"
                Stop-Process -Id $pid -Force -ErrorAction SilentlyContinue
            }
        } catch {}
    }
}

# Also kill any node.exe with openclaw in path
Get-Process node -ErrorAction SilentlyContinue | ForEach-Object {
    try {
        $path = $_.Path
        if ($path -like "*openclaw*" -or $path -like "*node_modules*openclaw*") {
            Write-Host "Killing node PID $($_.Id)"
            Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        }
    } catch {}
}

# Clean up lock files
Remove-Item "$env:TEMP\OpenClawTray.lock" -Force -ErrorAction SilentlyContinue
Remove-Item "$env:TEMP\ClawdbotTray.lock" -Force -ErrorAction SilentlyContinue

Write-Host "Done" -ForegroundColor Green
