#!/usr/bin/env bash
# =============================================================================
# openclaw-docker-setup.sh
# Full OpenClaw VPS setup — all 4 Telegram bots, real credentials, full host access
# Skips anything already installed. Run as root: bash openclaw-docker-setup.sh
# =============================================================================
set -euo pipefail

OPENCLAW_DIR="/root/.openclaw"
REPO_DIR="/root/openclaw"
GATEWAY_TOKEN="moltbot-local-token-2026"
ANTHROPIC_API_KEY="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"
GATEWAY_PORT=18789

echo "============================================================"
echo "  OpenClaw Full Setup — 4 Bots, Full Host Access"
echo "============================================================"

# ── 1. System deps (skip if already present) ─────────────────────
echo ""
echo "[1/9] Checking system dependencies..."
NEED_PKGS=()
for pkg in git curl ca-certificates jq unzip; do
  if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
    NEED_PKGS+=("$pkg")
  else
    echo "  ✓ $pkg already installed"
  fi
done
if [ ${#NEED_PKGS[@]} -gt 0 ]; then
  echo "  Installing: ${NEED_PKGS[*]}"
  apt-get update -qq
  apt-get install -y -qq "${NEED_PKGS[@]}"
else
  echo "  ✓ All system deps present — skipping apt-get update"
fi

# ── 2. Docker (skip if already present) ──────────────────────────
echo ""
echo "[2/9] Checking Docker..."
if command -v docker &>/dev/null && docker compose version &>/dev/null 2>&1; then
  echo "  ✓ Docker already installed: $(docker --version)"
  echo "  ✓ Docker Compose: $(docker compose version)"
else
  echo "  Installing Docker..."
  curl -fsSL https://get.docker.com | sh
  echo "  ✓ Docker installed: $(docker --version)"
fi

# ── 3. Clone / update OpenClaw repo ──────────────────────────────
echo ""
echo "[3/9] OpenClaw repository..."
if [ -d "$REPO_DIR/.git" ]; then
  echo "  ✓ Repo already cloned — pulling latest..."
  git -C "$REPO_DIR" pull --ff-only 2>/dev/null || echo "  (already up to date)"
else
  echo "  Cloning openclaw/openclaw..."
  git clone https://github.com/openclaw/openclaw.git "$REPO_DIR"
fi

# ── 4. Persistent directories (skip existing) ────────────────────
echo ""
echo "[4/9] Creating persistent directories..."
for dir in \
  "$OPENCLAW_DIR" \
  "$OPENCLAW_DIR/workspace" \
  "$OPENCLAW_DIR/workspace-openclaw-main" \
  "$OPENCLAW_DIR/workspace-moltbot2" \
  "$OPENCLAW_DIR/workspace-moltbot" \
  "$OPENCLAW_DIR/workspace-openclaw" \
  "$OPENCLAW_DIR/telegram" \
  "$OPENCLAW_DIR/credentials" \
  "$OPENCLAW_DIR/extensions" \
  "$OPENCLAW_DIR/skills" \
  "$OPENCLAW_DIR/sessions" \
  "$OPENCLAW_DIR/logs"; do
  if [ -d "$dir" ]; then
    echo "  ✓ $dir exists"
  else
    mkdir -p "$dir"
    echo "  + created $dir"
  fi
done

# ── 5. Credentials ────────────────────────────────────────────────
echo ""
echo "[5/9] Writing credentials..."
echo -n "$ANTHROPIC_API_KEY" > "$OPENCLAW_DIR/credentials/anthropic-backup.txt"
echo "  ✓ Anthropic API key written"

# ── 6. openclaw.json ──────────────────────────────────────────────
echo ""
echo "[6/9] Writing openclaw.json..."
cat > "$OPENCLAW_DIR/openclaw.json" << 'CONFIGEOF'
{
  "meta": { "lastTouchedVersion": "2026.3.24" },
  "browser": { "enabled": false },
  "auth": {
    "profiles": {
      "anthropic:default": { "provider": "anthropic", "mode": "token" }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "anthropic/claude-sonnet-4-6",
        "fallbacks": ["anthropic/claude-sonnet-4-6", "anthropic/claude-opus-4-5", "anthropic/claude-opus-4-6"]
      },
      "workspace": "/root/.openclaw/workspace",
      "skipBootstrap": false,
      "bootstrapMaxChars": 999999,
      "envelopeTimestamp": "on",
      "envelopeElapsed": "on",
      "contextPruning": {
        "mode": "cache-ttl",
        "ttl": "4320m",
        "keepLastAssistants": 999,
        "softTrimRatio": 0.15,
        "hardClearRatio": 0.2
      },
      "compaction": {
        "mode": "safeguard",
        "reserveTokensFloor": 80000
      },
      "thinkingDefault": "minimal",
      "verboseDefault": "off",
      "elevatedDefault": "full",
      "timeoutSeconds": 2147483,
      "typingIntervalSeconds": 3,
      "typingMode": "instant",
      "heartbeat": { "every": "596h" },
      "maxConcurrent": 999,
      "subagents": { "maxConcurrent": 999 }
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
  "messages": {
    "queue": { "byChannel": { "telegram": "queue" }, "cap": 999, "drop": "summarize" },
    "inbound": { "debounceMs": 0 }
  },
  "session": {
    "dmScope": "main",
    "reset": { "mode": "idle", "idleMinutes": 999999 }
  },
  "approvals": { "exec": { "enabled": false, "mode": "both" } },
  "gateway": {
    "port": 18789,
    "mode": "local",
    "bind": "lan",
    "auth": { "mode": "token", "token": "moltbot-local-token-2026" }
  },
  "channels": {
    "telegram": {
      "enabled": true,
      "dmPolicy": "open",
      "replyToMode": "all",
      "allowFrom": ["*"],
      "groupAllowFrom": ["*"],
      "groupPolicy": "open",
      "mediaMaxMb": 100,
      "timeoutSeconds": 2147483,
      "retry": { "attempts": 99999, "minDelayMs": 100, "maxDelayMs": 2000, "jitter": 0.1 },
      "streaming": "partial",
      "reconnect": {
        "enabled": true,
        "maxAttempts": 99999,
        "delayMs": 1000,
        "backoffMultiplier": 1.5,
        "maxDelayMs": 30000
      },
      "accounts": {
        "bot1": {
          "name": "Main Bot",
          "dmPolicy": "open",
          "botToken": "7928400430:AAEx7l-CsLmX6xXsQdYhcaa6vyYCSoeuiGE",
          "allowFrom": "*", "groupAllowFrom": "*", "groupPolicy": "open",
          "mediaMaxMb": 100, "timeoutSeconds": 2147483, "streaming": "partial"
        },
        "bot2": {
          "name": "Session 2",
          "dmPolicy": "open",
          "botToken": "8560812377:AAHbTE-KNGxGYTi9ocGtspsdPmZoYAik6MU",
          "allowFrom": "*", "groupAllowFrom": "*", "groupPolicy": "open",
          "mediaMaxMb": 100, "timeoutSeconds": 2147483, "streaming": "partial"
        },
        "openclaw": {
          "name": "OpenClaw",
          "dmPolicy": "open",
          "botToken": "8527881897:AAGIh-9-fYbwA3cpILHq4RmUL_TkOhIzSWk",
          "allowFrom": "*", "groupAllowFrom": "*", "groupPolicy": "open",
          "mediaMaxMb": 100, "timeoutSeconds": 2147483, "streaming": "partial"
        },
        "openclaw4": {
          "name": "OpenClaw 4",
          "dmPolicy": "open",
          "botToken": "8293951296:AAGWriSeJEgpZzl9kAj-4rnPt2BWZr5n1aU",
          "allowFrom": "*", "groupAllowFrom": "*", "groupPolicy": "open",
          "mediaMaxMb": 100, "timeoutSeconds": 2147483, "streaming": "partial"
        }
      }
    }
  },
  "plugins": {
    "allow": ["telegram","memory-context-bridge","typing-indicator","stop-enforcer","voice-handler"],
    "entries": {
      "telegram":              { "enabled": true },
      "memory-context-bridge": { "enabled": true },
      "typing-indicator":      { "enabled": true },
      "stop-enforcer":         { "enabled": true },
      "voice-handler":         { "enabled": true }
    }
  },
  "skills": {
    "allowBundled": ["done","ccc","net","todoist","gate","fixer"],
    "entries": {
      "done":    { "enabled": true },
      "ccc":     { "enabled": true },
      "net":     { "enabled": true },
      "todoist": { "enabled": true },
      "gate":    { "enabled": true },
      "fixer":   { "enabled": true }
    }
  }
}
CONFIGEOF
echo "  ✓ openclaw.json written"

# ── 7. .openclawrc.json ───────────────────────────────────────────
cat > "$OPENCLAW_DIR/.openclawrc.json" << 'RCEOF'
{
  "telegram": {
    "reconnect": { "enabled": true, "maxAttempts": 99999, "delayMs": 1000, "backoffMultiplier": 1.5, "maxDelayMs": 30000 },
    "timeout": { "connection": 2147483647, "request": 2147483647, "longPolling": 2147483647 },
    "keepAlive": { "enabled": true, "intervalMs": 15000 }
  },
  "gateway": { "reconnectOnDisconnect": true, "healthCheckInterval": 15000 }
}
RCEOF
echo "  ✓ .openclawrc.json written"

# ── 8. Dockerfile ─────────────────────────────────────────────────
echo ""
echo "[7/9] Writing Dockerfile..."
cat > "$REPO_DIR/Dockerfile.moltbot" << 'DOCKEREOF'
FROM node:24-slim

RUN apt-get update && apt-get install -y \
    git curl wget ca-certificates \
    procps psmisc python3 \
    && rm -rf /var/lib/apt/lists/*

RUN npm install -g openclaw@latest

RUN mkdir -p /var/tmp/openclaw-compile-cache

ENV NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
ENV OPENCLAW_NO_RESPAWN=1
ENV NODE_ENV=production
ENV HOME=/root

WORKDIR /root
EXPOSE 18789

CMD ["openclaw", "gateway", "start", "--bind", "lan", "--port", "18789", "--allow-unconfigured"]
DOCKEREOF
echo "  ✓ Dockerfile.moltbot written"

# ── 9. docker-compose.yml ─────────────────────────────────────────
echo ""
echo "[8/9] Writing docker-compose.yml..."
cat > "$REPO_DIR/docker-compose.moltbot.yml" << COMPOSEEOF
services:
  openclaw:
    build:
      context: .
      dockerfile: Dockerfile.moltbot
    image: openclaw-moltbot:latest
    container_name: openclaw-moltbot
    restart: unless-stopped
    privileged: true
    pid: host
    network_mode: host
    ipc: host
    environment:
      - HOME=/root
      - NODE_ENV=production
      - NODE_COMPILE_CACHE=/var/tmp/openclaw-compile-cache
      - OPENCLAW_NO_RESPAWN=1
      - ANTHROPIC_API_KEY=$ANTHROPIC_API_KEY
      - OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
    volumes:
      - /root/.openclaw:/root/.openclaw
      - /:/host
      - /var/run/docker.sock:/var/run/docker.sock
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
COMPOSEEOF
echo "  ✓ docker-compose.moltbot.yml written"

# ── 10. Build — skip if image already exists and up to date ───────
echo ""
echo "[9/9] Building and starting Docker container..."
cd "$REPO_DIR"

EXISTING_IMAGE=$(docker images -q openclaw-moltbot:latest 2>/dev/null || true)
CONTAINER_RUNNING=$(docker ps -q -f name=openclaw-moltbot 2>/dev/null || true)

if [ -n "$CONTAINER_RUNNING" ]; then
  echo "  ✓ Container already running — restarting to apply config..."
  docker compose -f docker-compose.moltbot.yml restart
else
  if [ -n "$EXISTING_IMAGE" ]; then
    echo "  ✓ Image exists — skipping build, starting container..."
    docker compose -f docker-compose.moltbot.yml up -d
  else
    echo "  Building image (first time, takes ~2-3 min)..."
    docker compose -f docker-compose.moltbot.yml build --no-cache
    docker compose -f docker-compose.moltbot.yml up -d
  fi
fi

# ── 11. Verify ────────────────────────────────────────────────────
echo ""
echo "  Waiting 12s for gateway to start..."
sleep 12

VPS_IP=$(curl -sf https://api.ipify.org 2>/dev/null || echo "<YOUR_VPS_IP>")

echo ""
echo "============================================================"
echo "  Container status:"
docker ps --filter "name=openclaw-moltbot" --format "  {{.Names}}  |  {{.Status}}  |  {{.Ports}}"

echo ""
if curl -sf "http://127.0.0.1:$GATEWAY_PORT/" -o /dev/null 2>&1; then
  echo "  ✅ Gateway responding on port $GATEWAY_PORT"
else
  echo "  ⚠️  Gateway not yet ready (check logs below if needed)"
  docker logs openclaw-moltbot --tail 20 2>/dev/null || true
fi

echo ""
echo "============================================================"
echo "  ✅ SETUP COMPLETE"
echo ""
echo "  Control UI:  http://$VPS_IP:$GATEWAY_PORT"
echo "  Auth token:  $GATEWAY_TOKEN"
echo ""
echo "  Bots active:"
echo "    bot1      (Main Bot)   — 7928400430"
echo "    bot2      (Session 2)  — 8560812377"
echo "    openclaw  (OpenClaw)   — 8527881897"
echo "    openclaw4 (OpenClaw4)  — 8293951296"
echo ""
echo "  Useful commands:"
echo "    docker logs -f openclaw-moltbot         # live logs"
echo "    docker restart openclaw-moltbot         # restart"
echo "    bash $0                                 # re-run (skips what exists)"
echo "============================================================"
