# ClawdBotGlobal — OpenClaw Gateway Global Exposer

## What this does
Exposes the local OpenClaw gateway (port 18789) to the internet via a Cloudflare quick tunnel, with auto-pairing and a shortened URL.

## How it works
1. **Reads the gateway auth token** from `C:\users\micha\.openclaw\openclaw.json` → `gateway.auth.token`
2. **Starts the gateway** via the VBS launcher at `C:\users\micha\.openclaw\ClawdBot\ClawdbotTray.vbs` (skips if already running)
3. **Creates a Cloudflare tunnel** using `cloudflared tunnel --url http://localhost:18789`
4. **Embeds the token in the URL** as a `#token=` fragment — this auto-pairs the dashboard so no manual pairing is needed
5. **Shortens the URL** via ulvis.net with a custom alias like `claw0324` (HHmm timestamp)
6. **Copies the shortest available URL** to clipboard

## The pairing problem this solves
Without the `#token=` fragment, the OpenClaw dashboard shows "pairing required" when accessed remotely. The gateway's `openclaw dashboard --no-open` command outputs `http://127.0.0.1:18789/#token=<token>` — this script replicates that pattern on the public tunnel URL.

## Files
- **ClawdBotGlobal.ps1** — main script (also lives at `C:\users\micha\.openclaw\ClawdBot\ClawdBotGlobal.ps1`)
- **VBS launcher** — `C:\users\micha\.openclaw\ClawdBot\ClawdbotTray.vbs` (starts gateway + tray icon)
- **Config** — `C:\users\micha\.openclaw\openclaw.json` (gateway.auth.token)

## Usage
```powershell
# Start gateway + tunnel + get global URL
powershell -ExecutionPolicy Bypass -File "F:\study\hosting\tunneling\cloudflared\projects\openclaw\gateway\global-expose\ClawdBotGlobal.ps1"

# Check status
.\ClawdBotGlobal.ps1 -Status

# Stop everything (tunnel + gateway)
.\ClawdBotGlobal.ps1 -Stop
```

## Key config values
- **Gateway port**: 18789
- **Token source**: `(Get-Content -Raw 'C:\users\micha\.openclaw\openclaw.json' | ConvertFrom-Json).gateway.auth.token`
- **Current token**: `moltbot-local-token-2026`
- **Tunnel state file**: `$env:TEMP\clawdbot-global.json`
- **Tunnel log**: `$env:TEMP\clawdbot-cf.log`

## Dependencies
- `cloudflared.exe` — auto-installed to `$env:LOCALAPPDATA\cloudflared\` if missing
- OpenClaw gateway (`openclaw.cmd` in `%APPDATA%\npm\`)
- Internet connection for Cloudflare tunnel + ulvis.net URL shortener

## Notes
- Cloudflare quick tunnels generate random 4-word subdomains each time (not controllable without a paid Cloudflare domain)
- The ulvis.net short URL alias uses format `claw` + current time (HHmm) to avoid collisions
- Running the script does NOT restart an already-running gateway — it only adds the tunnel layer
- `-Stop` kills both the tunnel AND the gateway processes
