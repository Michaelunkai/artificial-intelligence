<#
.SYNOPSIS
    Launch ClawdBot gateway and expose it globally via Cloudflare tunnel
.USAGE
    .\ClawdBotGlobal.ps1          # Start gateway + tunnel
    .\ClawdBotGlobal.ps1 -Stop    # Stop everything
    .\ClawdBotGlobal.ps1 -Status  # Check status
#>
param(
    [switch]$Stop,
    [switch]$Status
)

$ErrorActionPreference = 'Stop'
$GATEWAY_PORT = 18789
$VBS_PATH = Join-Path $PSScriptRoot "ClawdbotTray.vbs"
$CF_DIR = "$env:LOCALAPPDATA\cloudflared"
$CF_EXE = "$CF_DIR\cloudflared.exe"
$STATE_FILE = "$env:TEMP\clawdbot-global.json"
$CF_LOG = "$env:TEMP\clawdbot-cf.log"
$OC_CONFIG = "C:\users\micha\.openclaw\openclaw.json"

function Write-Step([string]$msg) { Write-Host "[ClawdBot] $msg" -ForegroundColor Cyan }
function Write-OK([string]$msg)   { Write-Host "[OK] $msg" -ForegroundColor Green }
function Write-Err([string]$msg)  { Write-Host "[ERROR] $msg" -ForegroundColor Red }

# ── READ TOKEN FROM CONFIG ──
$GW_TOKEN = $null
if (Test-Path $OC_CONFIG) {
    try {
        $GW_TOKEN = (Get-Content -Raw $OC_CONFIG | ConvertFrom-Json).gateway.auth.token
    } catch {}
}
if (-not $GW_TOKEN) {
    Write-Err "Could not read gateway token from $OC_CONFIG"
    exit 1
}
Write-OK "Token loaded from config"

# ── STATUS ──
if ($Status) {
    if (!(Test-Path $STATE_FILE)) { Write-Host "Not running." -ForegroundColor Yellow; exit 0 }
    $state = Get-Content $STATE_FILE -Raw | ConvertFrom-Json
    $gwAlive = $false; $cfAlive = $false
    try { $gwAlive = !!(Get-Process -Id $state.gw_pid -ErrorAction SilentlyContinue) } catch {}
    try { $cfAlive = !!(Get-Process -Id $state.cf_pid -ErrorAction SilentlyContinue) } catch {}
    Write-Host "`n=== CLAWDBOT GLOBAL ===" -ForegroundColor Cyan
    $tag = if ($gwAlive) { "[RUNNING]" } else { "[DEAD]" }
    $color = if ($gwAlive) { "Green" } else { "Red" }
    Write-Host "  Gateway: $tag PID $($state.gw_pid)" -ForegroundColor $color
    $tag = if ($cfAlive) { "[RUNNING]" } else { "[DEAD]" }
    $color = if ($cfAlive) { "Green" } else { "Red" }
    Write-Host "  Tunnel:  $tag PID $($state.cf_pid)" -ForegroundColor $color
    Write-Host "  Local:   http://localhost:$GATEWAY_PORT/#token=$GW_TOKEN" -ForegroundColor White
    Write-Host "  Global:  $($state.url)" -ForegroundColor Yellow
    if ($state.short_url) {
        Write-Host "  Short:   $($state.short_url)" -ForegroundColor Cyan
    }
    Write-Host "  Started: $($state.started)" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

# ── STOP ──
if ($Stop) {
    $killed = 0
    Get-Process -Name "cloudflared" -ErrorAction SilentlyContinue | ForEach-Object {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; $killed++
    }
    $conns = Get-NetTCPConnection -LocalPort $GATEWAY_PORT -ErrorAction SilentlyContinue
    if ($conns) {
        $conns | Select-Object -ExpandProperty OwningProcess -Unique | ForEach-Object {
            Stop-Process -Id $_ -Force -ErrorAction SilentlyContinue; $killed++
        }
    }
    if (Test-Path $STATE_FILE) { Remove-Item $STATE_FILE -Force }
    if (Test-Path $CF_LOG) { Remove-Item $CF_LOG -Force }
    Write-OK "Stopped $killed processes."
    exit 0
}

# ── MAIN: START GATEWAY + TUNNEL ──
Write-Host ""
Write-Host "  =======================================" -ForegroundColor Magenta
Write-Host "  CLAWDBOT - Gateway with Global URL" -ForegroundColor Magenta
Write-Host "  =======================================" -ForegroundColor Magenta
Write-Host ""

# Check if gateway is already running on the port
$alreadyRunning = $false
try {
    $tcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $GATEWAY_PORT)
    $tcp.Close()
    $alreadyRunning = $true
    Write-OK "Gateway already running on port $GATEWAY_PORT"
} catch {
    # Not running, need to start it
}

if (!$alreadyRunning) {
    if (!(Test-Path $VBS_PATH)) {
        Write-Err "VBS launcher not found: $VBS_PATH"
        exit 1
    }
    Write-Step "Starting gateway via VBS launcher..."
    Start-Process "wscript.exe" -ArgumentList """$VBS_PATH""" -WindowStyle Hidden

    Write-Step "Waiting for gateway on port $GATEWAY_PORT..."
    $ready = $false
    for ($i = 0; $i -lt 120; $i++) {
        Start-Sleep -Milliseconds 500
        try {
            $tcp = New-Object System.Net.Sockets.TcpClient("127.0.0.1", $GATEWAY_PORT)
            $tcp.Close()
            $ready = $true
            break
        } catch {}
    }
    if (!$ready) {
        Write-Err "Gateway not responding on port $GATEWAY_PORT after 60s"
        exit 1
    }
    Write-OK "Gateway is listening on port $GATEWAY_PORT"
}

# ── INSTALL / FIND CLOUDFLARED ──
$cfCheck = Get-Command cloudflared -ErrorAction SilentlyContinue
if ($cfCheck) { $CF_EXE = $cfCheck.Source }
if (!(Test-Path $CF_EXE)) {
    Write-Step "Installing cloudflared..."
    New-Item -ItemType Directory -Path $CF_DIR -Force | Out-Null
    Invoke-WebRequest -Uri "https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-windows-amd64.exe" -OutFile $CF_EXE -UseBasicParsing
    Write-OK "cloudflared installed"
} else {
    Write-OK "cloudflared ready"
}

# ── START TUNNEL ──
if (Test-Path $CF_LOG) { Remove-Item $CF_LOG -Force }
Write-Step "Creating Cloudflare tunnel to localhost:$GATEWAY_PORT..."
$cfProc = Start-Process -FilePath $CF_EXE `
    -ArgumentList @("tunnel", "--url", "http://localhost:$GATEWAY_PORT") `
    -WindowStyle Hidden -PassThru -RedirectStandardError $CF_LOG

if (!$cfProc -or $cfProc.HasExited) {
    Write-Err "Failed to start cloudflared!"
    exit 1
}

# ── GET PUBLIC URL ──
Write-Step "Waiting for public URL..."
$publicUrl = $null
for ($i = 0; $i -lt 60; $i++) {
    Start-Sleep -Milliseconds 500
    if (Test-Path $CF_LOG) {
        $log = Get-Content $CF_LOG -Raw -ErrorAction SilentlyContinue
        if ($log -match '(https://[a-zA-Z0-9-]+\.trycloudflare\.com)') {
            $publicUrl = $matches[1]
            break
        }
    }
}

# ── BUILD TOKENIZED URL (auto-pairs, no manual pairing needed) ──
$tokenizedUrl = $null
$shortUrl = $null
if ($publicUrl) {
    $tokenizedUrl = "$publicUrl/#token=$GW_TOKEN"

    # Shorten with ulvis.net (supports custom aliases)
    Write-Step "Creating short URL..."
    try {
        $alias = "claw" + (Get-Date -Format "HHmm")
        $apiUrl = "https://ulvis.net/API/write/get?url=$([System.Uri]::EscapeDataString($tokenizedUrl))&custom=$alias&type=json"
        $resp = Invoke-RestMethod -Uri $apiUrl -TimeoutSec 10
        if ($resp.success -eq $true) {
            $shortUrl = $resp.data.url
        }
    } catch {
        Write-Host "  (URL shortener unavailable, using full URL)" -ForegroundColor DarkGray
    }
}

# ── SAVE STATE ──
$gwPid = 0
$conns = Get-NetTCPConnection -LocalPort $GATEWAY_PORT -State Listen -ErrorAction SilentlyContinue
if ($conns) { $gwPid = ($conns | Select-Object -First 1).OwningProcess }

$finalUrl = if ($shortUrl) { $shortUrl } elseif ($tokenizedUrl) { $tokenizedUrl } else { "http://localhost:${GATEWAY_PORT}/#token=$GW_TOKEN" }

@{
    gw_pid    = $gwPid
    cf_pid    = $cfProc.Id
    port      = $GATEWAY_PORT
    url       = $tokenizedUrl
    short_url = $shortUrl
    started   = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
} | ConvertTo-Json | Set-Content $STATE_FILE -Encoding UTF8

$finalUrl | Set-Clipboard

Write-Host ""
Write-Host "  =============================================" -ForegroundColor Green
Write-Host "  CLAWDBOT GATEWAY IS LIVE!" -ForegroundColor Green
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Local:   http://localhost:${GATEWAY_PORT}/#token=$GW_TOKEN" -ForegroundColor White
if ($publicUrl) {
    Write-Host "  Tunnel:  $publicUrl" -ForegroundColor DarkGray
    Write-Host ""
    if ($shortUrl) {
        Write-Host "  SHORT URL (copied to clipboard):" -ForegroundColor Yellow
        Write-Host "  $shortUrl" -ForegroundColor Cyan
        Write-Host ""
        Write-Host "  Full:    $tokenizedUrl" -ForegroundColor DarkGray
    } else {
        Write-Host "  GLOBAL URL (copied to clipboard):" -ForegroundColor Yellow
        Write-Host "  $tokenizedUrl" -ForegroundColor Cyan
    }
} else {
    Write-Host "  Global URL failed - check $CF_LOG" -ForegroundColor Red
}
Write-Host ""
Write-Host "  Token auto-embedded - NO pairing needed!" -ForegroundColor Green
Write-Host ""
Write-Host "  Status:  .\ClawdBotGlobal.ps1 -Status" -ForegroundColor DarkGray
Write-Host "  Stop:    .\ClawdBotGlobal.ps1 -Stop" -ForegroundColor DarkGray
Write-Host "  =============================================" -ForegroundColor Green
Write-Host ""
