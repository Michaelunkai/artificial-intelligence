# =============================================================================
# setup-openclaw-hyperv.ps1  —  PowerShell v5 compatible
# Full OpenClaw setup on Windows using Docker Desktop (Hyper-V, no WSL2)
# Run as Administrator: powershell -ExecutionPolicy Bypass -File setup-openclaw-hyperv.ps1
# =============================================================================

$ErrorActionPreference = "Stop"

$ANTHROPIC_API_KEY = "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"
$GATEWAY_TOKEN     = "moltbot-local-token-2026"
$GATEWAY_PORT      = 18789
$OPENCLAW_DIR      = "C:\Users\micha\.openclaw"
$REPO_DIR          = "C:\Users\micha\openclaw-repo"
$WORK_DIR          = "C:\Users\micha\.openclaw-docker"

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  OpenClaw Setup -- Windows / Docker Desktop / Hyper-V" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

# ── 1. Admin check ────────────────────────────────────────────────
Write-Host ""
Write-Host "[1/9] Checking admin rights..."
$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
$isAdmin = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    Write-Host "  ERROR: Must run as Administrator." -ForegroundColor Red
    exit 1
}
Write-Host "  OK: Running as administrator" -ForegroundColor Green

# ── 2. Hyper-V ────────────────────────────────────────────────────
Write-Host ""
Write-Host "[2/9] Checking Hyper-V..."
$hvFeature = Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -ErrorAction SilentlyContinue
if ($hvFeature -and $hvFeature.State -eq "Enabled") {
    Write-Host "  OK: Hyper-V already enabled" -ForegroundColor Green
} else {
    Write-Host "  Enabling Hyper-V..."
    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V-All -All -NoRestart | Out-Null
    Write-Host "  Hyper-V enabled (reboot needed eventually, continuing now)" -ForegroundColor Yellow
}

# ── 3. Docker ─────────────────────────────────────────────────────
Write-Host ""
Write-Host "[3/9] Checking Docker..."
$dockerPath = Get-Command docker -ErrorAction SilentlyContinue
if ($dockerPath) {
    $dockerVer = docker --version 2>&1
    Write-Host "  OK: $dockerVer" -ForegroundColor Green
} else {
    $installerPath = "$env:TEMP\DockerDesktopInstaller.exe"
    if (Test-Path $installerPath) {
        Write-Host "  OK: Installer already downloaded, skipping download" -ForegroundColor Green
    } else {
        Write-Host "  Downloading Docker Desktop..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe" -OutFile $installerPath -UseBasicParsing
    }
    Write-Host "  Installing Docker Desktop (Hyper-V, no WSL2)..."
    Start-Process -FilePath $installerPath -ArgumentList "install --quiet --accept-license --backend=hyper-v --no-wsl2" -Wait
    Write-Host "  Waiting 30s for Docker to initialize..."
    Start-Sleep -Seconds 30
}

# ── 4. Wait for Docker daemon ─────────────────────────────────────
Write-Host ""
Write-Host "[4/9] Waiting for Docker daemon..."
$dockerReady = $false
$attempt = 0
while (-not $dockerReady -and $attempt -lt 12) {
    $attempt++
    $testResult = docker info 2>&1
    if ($LASTEXITCODE -eq 0) {
        $dockerReady = $true
    } else {
        Write-Host "  Waiting... ($attempt/12)"
        Start-Sleep -Seconds 5
    }
}
if (-not $dockerReady) {
    $dockerExe = "C:\Program Files\Docker\Docker\Docker Desktop.exe"
    if (Test-Path $dockerExe) {
        Write-Host "  Starting Docker Desktop..."
        Start-Process $dockerExe
        Write-Host "  Waiting 40s..."
        Start-Sleep -Seconds 40
    } else {
        Write-Host "  ERROR: Docker not responding and exe not found. Start Docker Desktop manually then re-run." -ForegroundColor Red
        exit 1
    }
}
Write-Host "  OK: Docker daemon is running" -ForegroundColor Green

# ── 5. Git ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "[5/9] Checking Git..."
$gitPath = Get-Command git -ErrorAction SilentlyContinue
if ($gitPath) {
    $gitVer = git --version 2>&1
    Write-Host "  OK: $gitVer" -ForegroundColor Green
} else {
    $gitInstaller = "$env:TEMP\GitInstaller.exe"
    if (Test-Path $gitInstaller) {
        Write-Host "  OK: Git installer already downloaded" -ForegroundColor Green
    } else {
        Write-Host "  Downloading Git for Windows..."
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        Invoke-WebRequest -Uri "https://github.com/git-for-windows/git/releases/download/v2.44.0.windows.1/Git-2.44.0-64-bit.exe" -OutFile $gitInstaller -UseBasicParsing
    }
    Write-Host "  Installing Git..."
    Start-Process -FilePath $gitInstaller -ArgumentList "/VERYSILENT /NORESTART" -Wait
    $env:PATH = $env:PATH + ";C:\Program Files\Git\cmd"
    Write-Host "  OK: Git installed" -ForegroundColor Green
}

# ── 6. Clone / update repo ────────────────────────────────────────
Write-Host ""
Write-Host "[6/9] OpenClaw repository..."
if (Test-Path "$REPO_DIR\.git") {
    Write-Host "  OK: Already cloned, pulling latest..." -ForegroundColor Green
    Push-Location $REPO_DIR
    git pull --ff-only 2>&1 | Out-Null
    Pop-Location
} else {
    Write-Host "  Cloning openclaw/openclaw..."
    git clone https://github.com/openclaw/openclaw.git $REPO_DIR
}

# ── 7. Directories ────────────────────────────────────────────────
Write-Host ""
Write-Host "[7/9] Creating directories..."
$dirs = @(
    $OPENCLAW_DIR,
    "$OPENCLAW_DIR\workspace",
    "$OPENCLAW_DIR\workspace-openclaw-main",
    "$OPENCLAW_DIR\workspace-moltbot2",
    "$OPENCLAW_DIR\workspace-moltbot",
    "$OPENCLAW_DIR\workspace-openclaw",
    "$OPENCLAW_DIR\telegram",
    "$OPENCLAW_DIR\credentials",
    "$OPENCLAW_DIR\sessions",
    "$OPENCLAW_DIR\logs",
    $WORK_DIR
)
foreach ($d in $dirs) {
    if (Test-Path $d) {
        Write-Host "  OK: $d" -ForegroundColor Green
    } else {
        New-Item -ItemType Directory -Force -Path $d | Out-Null
        Write-Host "  + created $d"
    }
}

# ── 8. Config files ───────────────────────────────────────────────
Write-Host ""
Write-Host "[8/9] Writing config files..."

[System.IO.File]::WriteAllText("$OPENCLAW_DIR\credentials\anthropic-backup.txt", $ANTHROPIC_API_KEY, [System.Text.Encoding]::UTF8)
Write-Host "  OK: Anthropic key written" -ForegroundColor Green

$openclawJson = '{
  "meta": { "lastTouchedVersion": "2026.3.24" },
  "browser": { "enabled": false },
  "auth": { "profiles": { "anthropic:default": { "provider": "anthropic", "mode": "token" } } },
  "agents": {
    "defaults": {
      "model": { "primary": "anthropic/claude-sonnet-4-6", "fallbacks": ["anthropic/claude-sonnet-4-6","anthropic/claude-opus-4-5","anthropic/claude-opus-4-6"] },
      "workspace": "/root/.openclaw/workspace",
      "skipBootstrap": false, "bootstrapMaxChars": 999999,
      "envelopeTimestamp": "on", "envelopeElapsed": "on",
      "contextPruning": { "mode": "cache-ttl", "ttl": "4320m", "keepLastAssistants": 999 },
      "compaction": { "mode": "safeguard", "reserveTokensFloor": 80000 },
      "thinkingDefault": "minimal", "verboseDefault": "off", "elevatedDefault": "full",
      "timeoutSeconds": 2147483, "typingIntervalSeconds": 3, "typingMode": "instant",
      "heartbeat": { "every": "596h" }, "maxConcurrent": 999, "subagents": { "maxConcurrent": 999 }
    },
    "list": [
      { "id": "main",      "workspace": "/root/.openclaw/workspace-openclaw-main", "model": { "primary": "anthropic/claude-sonnet-4-6" } },
      { "id": "session2",  "workspace": "/root/.openclaw/workspace-moltbot2",      "model": { "primary": "anthropic/claude-sonnet-4-6" } },
      { "id": "openclaw",  "workspace": "/root/.openclaw/workspace-moltbot",       "model": { "primary": "anthropic/claude-sonnet-4-6" } },
      { "id": "openclaw4", "workspace": "/root/.openclaw/workspace-openclaw",      "model": { "primary": "anthropic/claude-sonnet-4-6" } }
    ]
  },
  "tools": {
    "profile": "full",
    "allow": ["exec","read","write","edit","web_search","web_fetch","browser","canvas","nodes","cron","gateway","sessions_spawn","sessions_yield","subagents","session_status","agents_list"],
    "agentToAgent": { "enabled": true }
  },
  "bindings": [
    { "agentId": "main",      "match": { "channel": "telegram", "accountId": "bot1"      } },
    { "agentId": "session2",  "match": { "channel": "telegram", "accountId": "bot2"      } },
    { "agentId": "openclaw",  "match": { "channel": "telegram", "accountId": "openclaw"  } },
    { "agentId": "openclaw4", "match": { "channel": "telegram", "accountId": "openclaw4" } }
  ],
  "messages": { "queue": { "byChannel": { "telegram": "queue" }, "cap": 999, "drop": "summarize" }, "inbound": { "debounceMs": 0 } },
  "session": { "dmScope": "main", "reset": { "mode": "idle", "idleMinutes": 999999 } },
  "approvals": { "exec": { "enabled": false } },
  "gateway": { "port": 18789, "mode": "local", "bind": "lan", "auth": { "mode": "token", "token": "moltbot-local-token-2026" } },
  "channels": {
    "telegram": {
      "enabled": true, "dmPolicy": "open", "replyToMode": "all",
      "allowFrom": ["*"], "groupAllowFrom": ["*"], "groupPolicy": "open",
      "mediaMaxMb": 100, "timeoutSeconds": 2147483,
      "retry": { "attempts": 99999, "minDelayMs": 100, "maxDelayMs": 2000, "jitter": 0.1 },
      "streaming": "partial",
      "reconnect": { "enabled": true, "maxAttempts": 99999, "delayMs": 1000, "backoffMultiplier": 1.5, "maxDelayMs": 30000 },
      "accounts": {
        "bot1":      { "name": "Main Bot",   "dmPolicy": "open", "botToken": "7928400430:AAEx7l-CsLmX6xXsQdYhcaa6vyYCSoeuiGE", "allowFrom": "*", "groupAllowFrom": "*", "groupPolicy": "open", "mediaMaxMb": 100, "timeoutSeconds": 2147483, "streaming": "partial" },
        "bot2":      { "name": "Session 2",  "dmPolicy": "open", "botToken": "8560812377:AAHbTE-KNGxGYTi9ocGtspsdPmZoYAik6MU", "allowFrom": "*", "groupAllowFrom": "*", "groupPolicy": "open", "mediaMaxMb": 100, "timeoutSeconds": 2147483, "streaming": "partial" },
        "openclaw":  { "name": "OpenClaw",   "dmPolicy": "open", "botToken": "8527881897:AAGIh-9-fYbwA3cpILHq4RmUL_TkOhIzSWk", "allowFrom": "*", "groupAllowFrom": "*", "groupPolicy": "open", "mediaMaxMb": 100, "timeoutSeconds": 2147483, "streaming": "partial" },
        "openclaw4": { "name": "OpenClaw 4", "dmPolicy": "open", "botToken": "8293951296:AAGWriSeJEgpZzl9kAj-4rnPt2BWZr5n1aU", "allowFrom": "*", "groupAllowFrom": "*", "groupPolicy": "open", "mediaMaxMb": 100, "timeoutSeconds": 2147483, "streaming": "partial" }
      }
    }
  },
  "plugins": {
    "allow": ["telegram","memory-context-bridge","typing-indicator","stop-enforcer","voice-handler"],
    "entries": {
      "telegram": { "enabled": true }, "memory-context-bridge": { "enabled": true },
      "typing-indicator": { "enabled": true }, "stop-enforcer": { "enabled": true }, "voice-handler": { "enabled": true }
    }
  },
  "skills": {
    "allowBundled": ["done","ccc","net","todoist","gate","fixer"],
    "entries": { "done": { "enabled": true }, "ccc": { "enabled": true }, "net": { "enabled": true }, "todoist": { "enabled": true }, "gate": { "enabled": true }, "fixer": { "enabled": true } }
  }
}'
[System.IO.File]::WriteAllText("$OPENCLAW_DIR\openclaw.json", $openclawJson, [System.Text.Encoding]::UTF8)
Write-Host "  OK: openclaw.json written" -ForegroundColor Green

$rcJson = '{
  "telegram": {
    "reconnect": { "enabled": true, "maxAttempts": 99999, "delayMs": 1000, "backoffMultiplier": 1.5, "maxDelayMs": 30000 },
    "timeout": { "connection": 2147483647, "request": 2147483647, "longPolling": 2147483647 },
    "keepAlive": { "enabled": true, "intervalMs": 15000 }
  },
  "gateway": { "reconnectOnDisconnect": true, "healthCheckInterval": 15000 }
}'
[System.IO.File]::WriteAllText("$OPENCLAW_DIR\.openclawrc.json", $rcJson, [System.Text.Encoding]::UTF8)
Write-Host "  OK: .openclawrc.json written" -ForegroundColor Green

$dockerfileContent = "FROM node:24-slim

RUN apt-get update && apt-get install -y git curl wget ca-certificates procps psmisc python3 && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest
RUN mkdir -p /var/tmp/openclaw-compile-cache

ENV NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
ENV OPENCLAW_NO_RESPAWN=1
ENV NODE_ENV=production
ENV HOME=/root

WORKDIR /root
EXPOSE 18789

CMD [""openclaw"", ""gateway"", ""start"", ""--bind"", ""lan"", ""--port"", ""18789"", ""--allow-unconfigured""]"
[System.IO.File]::WriteAllText("$WORK_DIR\Dockerfile", $dockerfileContent, [System.Text.Encoding]::UTF8)
Write-Host "  OK: Dockerfile written" -ForegroundColor Green

# Build compose file using string concat (v5 safe, no interpolation inside single-quote blocks)
$composeContent = "services:`n" +
"  openclaw:`n" +
"    build:`n" +
"      context: .`n" +
"      dockerfile: Dockerfile`n" +
"    image: openclaw-moltbot:latest`n" +
"    container_name: openclaw-moltbot`n" +
"    restart: unless-stopped`n" +
"    environment:`n" +
"      - HOME=/root`n" +
"      - NODE_ENV=production`n" +
"      - NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache`n" +
"      - OPENCLAW_NO_RESPAWN=1`n" +
"      - ANTHROPIC_API_KEY=" + $ANTHROPIC_API_KEY + "`n" +
"      - OPENCLAW_GATEWAY_TOKEN=" + $GATEWAY_TOKEN + "`n" +
"    ports:`n" +
"      - `"" + $GATEWAY_PORT + ":18789`"`n" +
"    volumes:`n" +
"      - type: bind`n" +
"        source: C:/Users/micha/.openclaw`n" +
"        target: /root/.openclaw`n" +
"    logging:`n" +
"      driver: json-file`n" +
"      options:`n" +
"        max-size: `"50m`"`n" +
"        max-file: `"5`"`n"
[System.IO.File]::WriteAllText("$WORK_DIR\docker-compose.yml", $composeContent, [System.Text.Encoding]::UTF8)
Write-Host "  OK: docker-compose.yml written" -ForegroundColor Green

# ── 9. Build & launch ─────────────────────────────────────────────
Write-Host ""
Write-Host "[9/9] Building and launching container..."
Push-Location $WORK_DIR

$existingImage    = docker images -q openclaw-moltbot:latest 2>$null
$runningContainer = docker ps -q -f "name=openclaw-moltbot" 2>$null

if ($runningContainer) {
    Write-Host "  OK: Container already running -- restarting..." -ForegroundColor Green
    docker-compose restart
} elseif ($existingImage) {
    Write-Host "  OK: Image exists -- skipping build, starting container..." -ForegroundColor Green
    docker-compose up -d
} else {
    Write-Host "  Building Docker image (first time, ~3-5 min)..."
    docker-compose build --no-cache
    docker-compose up -d
}

Pop-Location

# ── Verify ────────────────────────────────────────────────────────
Write-Host ""
Write-Host "  Waiting 12s for gateway to start..."
Start-Sleep -Seconds 12

Write-Host ""
Write-Host "  Container status:"
docker ps --filter "name=openclaw-moltbot" --format "  {{.Names}}  |  {{.Status}}  |  {{.Ports}}"

Write-Host ""
try {
    $response = Invoke-WebRequest -Uri ("http://127.0.0.1:" + $GATEWAY_PORT + "/") -UseBasicParsing -TimeoutSec 5 -ErrorAction SilentlyContinue
    Write-Host ("  OK: Gateway responding on port " + $GATEWAY_PORT) -ForegroundColor Green
} catch {
    Write-Host "  WARNING: Gateway not yet ready -- check logs: docker logs openclaw-moltbot" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  SETUP COMPLETE" -ForegroundColor Green
Write-Host ""
Write-Host ("  Control UI:  http://localhost:" + $GATEWAY_PORT)
Write-Host ("  Auth token:  " + $GATEWAY_TOKEN)
Write-Host ""
Write-Host "  Bots active:"
Write-Host "    bot1      (Main Bot)   -- 7928400430"
Write-Host "    bot2      (Session 2)  -- 8560812377"
Write-Host "    openclaw  (OpenClaw)   -- 8527881897"
Write-Host "    openclaw4 (OpenClaw 4) -- 8293951296"
Write-Host ""
Write-Host ("  Logs: docker logs -f openclaw-moltbot")
Write-Host "============================================================" -ForegroundColor Cyan
