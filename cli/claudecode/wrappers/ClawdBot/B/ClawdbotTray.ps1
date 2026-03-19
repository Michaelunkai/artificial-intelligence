# OpenClaw Gateway System Tray - TURBO v2.0
# Optimized for 10x faster startup
# Key: Start gateway FIRST, setup GUI async

$ErrorActionPreference = 'SilentlyContinue'

# ============================================
# PHASE 1: IMMEDIATE GATEWAY START (< 100ms)
# ============================================

# Check if gateway is already running via port check (NO WMI, NO NETSTAT)
$existingGateway = $null
$portAlive = $false
try {
    $tcp = New-Object System.Net.Sockets.TcpClient
    $tcp.Connect('127.0.0.1', 18789)
    $tcp.Close()
    $portAlive = $true
    # Port is alive - gateway is running (we don't need the PID for tracking)
} catch {}

# Detect openclaw command (fast)
function Get-OpenClawCommand {
    $npmPath = "$env:APPDATA\npm"
    $cmd = "$npmPath\openclaw.cmd"
    if (Test-Path $cmd) { return @{ Type = "cmd"; Path = $cmd } }
    $mjs = "$npmPath\node_modules\openclaw\openclaw.mjs"
    if (Test-Path $mjs) { return @{ Type = "node"; Path = $mjs } }
    return @{ Type = "npx"; Path = "openclaw" }
}

$script:openclawInfo = Get-OpenClawCommand
$script:gatewayProcess = $null
$script:productName = "OpenClaw"

# Set environment (minimal)
$env:SHELL = "$env:COMSPEC"
$env:OPENCLAW_SHELL = "cmd"
$env:OPENCLAW_NO_WSL = "1"
$env:OPENCLAW_NO_PTY = "1"
$env:NODE_OPTIONS = "--max-old-space-size=4096"

# Ensure log dir exists
$logDir = "$env:TEMP\openclaw"
if (!(Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }

# START GATEWAY (only if not already running)
if ($portAlive) {
    # Gateway already running on port 18789 - don't restart
    # We don't need to track the process object - port checks are sufficient
    $script:gatewayProcess = $null
} else {
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $info = $script:openclawInfo

    switch ($info.Type) {
        "cmd" { $psi.FileName = $info.Path; $psi.Arguments = "gateway --allow-unconfigured --auth token --token moltbot-local-token-2026" }
        "node" { $psi.FileName = "node"; $psi.Arguments = "`"$($info.Path)`" gateway --allow-unconfigured --auth token --token moltbot-local-token-2026" }
        "npx" { $psi.FileName = "npx"; $psi.Arguments = "openclaw gateway --allow-unconfigured --auth token --token moltbot-local-token-2026" }
    }

    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($env:CLAUDE_CODE_OAUTH_TOKEN) { $psi.EnvironmentVariables["CLAUDE_CODE_OAUTH_TOKEN"] = $env:CLAUDE_CODE_OAUTH_TOKEN }

    $script:gatewayProcess = New-Object System.Diagnostics.Process
    $script:gatewayProcess.StartInfo = $psi
    $script:gatewayProcess.EnableRaisingEvents = $true
    $script:gatewayProcess.Start() | Out-Null
    $script:gatewayProcess.BeginOutputReadLine()
    $script:gatewayProcess.BeginErrorReadLine()

    # Log output async
    $logFile = "$logDir\openclaw-$(Get-Date -Format 'yyyy-MM-dd').log"
    Register-ObjectEvent -InputObject $script:gatewayProcess -EventName OutputDataReceived -Action {
        if ($EventArgs.Data) { Add-Content -Path "$env:TEMP\openclaw\openclaw-$(Get-Date -Format 'yyyy-MM-dd').log" -Value $EventArgs.Data -ErrorAction SilentlyContinue }
    } | Out-Null
    Register-ObjectEvent -InputObject $script:gatewayProcess -EventName ErrorDataReceived -Action {
        if ($EventArgs.Data) { Add-Content -Path "$env:TEMP\openclaw\openclaw-$(Get-Date -Format 'yyyy-MM-dd').log" -Value $EventArgs.Data -ErrorAction SilentlyContinue }
    } | Out-Null
}

# ============================================
# PHASE 2: GUI SETUP (async, non-blocking)
# ============================================

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

# Global state
$script:enabled = $true
$script:oauthError = $false
$script:userStopped = $false

# Simple icon (fast)
function Create-Icon {
    param([string]$status = "normal")
    $bitmap = New-Object System.Drawing.Bitmap(16, 16)
    $g = [System.Drawing.Graphics]::FromImage($bitmap)
    $color = switch ($status) {
        "running" { [System.Drawing.Color]::LimeGreen }
        "error" { [System.Drawing.Color]::Red }
        default { [System.Drawing.Color]::Orange }
    }
    $g.FillEllipse((New-Object System.Drawing.SolidBrush($color)), 2, 2, 12, 12)
    $g.Dispose()
    return [System.Drawing.Icon]::FromHandle($bitmap.GetHicon())
}

# Create tray icon
$trayIcon = New-Object System.Windows.Forms.NotifyIcon
$trayIcon.Icon = Create-Icon -status "running"
$trayIcon.Text = "$script:productName Gateway"
$trayIcon.Visible = $true

# Context menu (simplified)
$contextMenu = New-Object System.Windows.Forms.ContextMenuStrip

$statusItem = New-Object System.Windows.Forms.ToolStripMenuItem
$statusItem.Text = "Status: Running"
$statusItem.Enabled = $false
$contextMenu.Items.Add($statusItem) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$restartItem = New-Object System.Windows.Forms.ToolStripMenuItem
$restartItem.Text = "Restart Gateway"
$contextMenu.Items.Add($restartItem) | Out-Null

$stopItem = New-Object System.Windows.Forms.ToolStripMenuItem
$stopItem.Text = "Stop Gateway"
$contextMenu.Items.Add($stopItem) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$terminalItem = New-Object System.Windows.Forms.ToolStripMenuItem
$terminalItem.Text = "Show Terminal"
$contextMenu.Items.Add($terminalItem) | Out-Null

$logItem = New-Object System.Windows.Forms.ToolStripMenuItem
$logItem.Text = "Open Log"
$contextMenu.Items.Add($logItem) | Out-Null

$contextMenu.Items.Add((New-Object System.Windows.Forms.ToolStripSeparator)) | Out-Null

$exitItem = New-Object System.Windows.Forms.ToolStripMenuItem
$exitItem.Text = "Exit"
$contextMenu.Items.Add($exitItem) | Out-Null

$trayIcon.ContextMenuStrip = $contextMenu

# Functions
function Update-Status {
    param([string]$status, [string]$iconStatus = "normal")
    $statusItem.Text = "Status: $status"
    $trayIcon.Text = "$script:productName - $status"
    $trayIcon.Icon = Create-Icon -status $iconStatus
}

function Stop-Gateway {
    $script:enabled = $false
    $script:userStopped = $true
    if ($script:gatewayProcess -and !$script:gatewayProcess.HasExited) {
        try { $script:gatewayProcess.Kill() } catch {}
    }
    $script:gatewayProcess = $null
    Update-Status "Stopped" "normal"
}

function Start-Gateway {
    # Always check port first — if it's alive, gateway is running (maybe new PID after self-restart)
    $portLive = $false
    try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect('127.0.0.1',18789); $t.Close(); $portLive = $true } catch {}
    if ($portLive) { Update-Status "Running" "running"; return }
    $script:enabled = $true
    $script:userStopped = $false

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $info = $script:openclawInfo
    switch ($info.Type) {
        "cmd" { $psi.FileName = $info.Path; $psi.Arguments = "gateway --allow-unconfigured --auth token --token moltbot-local-token-2026" }
        "node" { $psi.FileName = "node"; $psi.Arguments = "`"$($info.Path)`" gateway --allow-unconfigured --auth token --token moltbot-local-token-2026" }
        "npx" { $psi.FileName = "npx"; $psi.Arguments = "openclaw gateway --allow-unconfigured --auth token --token moltbot-local-token-2026" }
    }
    $psi.WindowStyle = [System.Diagnostics.ProcessWindowStyle]::Hidden
    $psi.CreateNoWindow = $true
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    if ($env:CLAUDE_CODE_OAUTH_TOKEN) { $psi.EnvironmentVariables["CLAUDE_CODE_OAUTH_TOKEN"] = $env:CLAUDE_CODE_OAUTH_TOKEN }
    
    $script:gatewayProcess = New-Object System.Diagnostics.Process
    $script:gatewayProcess.StartInfo = $psi
    $script:gatewayProcess.Start() | Out-Null
    $script:gatewayProcess.BeginOutputReadLine()
    $script:gatewayProcess.BeginErrorReadLine()
    
    Update-Status "Running" "running"
}

function Restart-Gateway {
    Stop-Gateway
    # Wait up to 5s for port to go dark before relaunching
    $waited = 0
    while ($waited -lt 5000) {
        $still = $false
        try { $t = New-Object System.Net.Sockets.TcpClient; $t.Connect('127.0.0.1',18789); $t.Close(); $still = $true } catch {}
        if (-not $still) { break }
        Start-Sleep -Milliseconds 500
        $waited += 500
    }
    Start-Sleep -Milliseconds 500
    Start-Gateway
}

# Event handlers
$restartItem.Add_Click({ Restart-Gateway })
$stopItem.Add_Click({ Stop-Gateway })
$terminalItem.Add_Click({
    $logPath = "$env:TEMP\openclaw\openclaw-$(Get-Date -Format 'yyyy-MM-dd').log"
    Start-Process powershell.exe -ArgumentList "-NoExit", "-Command", "Get-Content '$logPath' -Wait -Tail 50"
})
$logItem.Add_Click({
    $logPath = "$env:TEMP\openclaw\openclaw-$(Get-Date -Format 'yyyy-MM-dd').log"
    if (Test-Path $logPath) { Start-Process notepad.exe $logPath }
})
$exitItem.Add_Click({
    Stop-Gateway
    $trayIcon.Visible = $false
    Remove-Item "$env:TEMP\OpenClawTray.lock" -Force -ErrorAction SilentlyContinue
    [System.Windows.Forms.Application]::Exit()
})

# Health check timer (every 30 seconds) - port-based check, NOT process-based.
# This handles openclaw's internal self-restarts (SIGUSR1 spawns new PID) without
# triggering a false restart. Only relaunches if port 18789 is genuinely dead.
$script:portDeadCount = 0  # Require 2 consecutive dead checks before acting (60s)
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 30000
$timer.Add_Tick({
    if ($script:userStopped) { return }
    if (-not $script:enabled) { return }

    # Check if port 18789 is alive (true health signal, not process PID)
    $portAlive = $false
    try {
        $tcp = New-Object System.Net.Sockets.TcpClient
        $tcp.Connect('127.0.0.1', 18789)
        $tcp.Close()
        $portAlive = $true
    } catch {}

    if ($portAlive) {
        # Gateway is healthy - port check is the ONLY truth
        # We don't need process tracking - port alive = gateway alive
        $script:portDeadCount = 0
        Update-Status "Running" "running"
    } else {
        $script:portDeadCount++
        if ($script:portDeadCount -ge 2) {
            # Port has been dead for 60s+ — this is a real crash, not a self-restart
            $script:portDeadCount = 0
            Update-Status "Reconnecting..." "error"
            Start-Sleep -Milliseconds 2000
            Start-Gateway
        } else {
            # First dead check — could be mid-restart, wait for next tick
            Update-Status "Checking..." "normal"
        }
    }
})
$timer.Start()

# Initial status
Update-Status "Running" "running"

# Run message loop
[System.Windows.Forms.Application]::Run()
