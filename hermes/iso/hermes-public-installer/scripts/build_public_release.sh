#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="$ROOT/release"
mkdir -p "$REL" "$ROOT/iso-root/templates"
rm -f "$REL/hermes-public-installer.iso" "$REL/SHA256SUMS" "$REL/manifest.txt"
cat > "$ROOT/iso-root/templates/.env.example" <<'EOF'
# Copy to .env and fill with your own secrets. Do not commit .env.
OPENAI_API_KEY=
ANTHROPIC_API_KEY=
OPENROUTER_API_KEY=
GITHUB_TOKEN=
TELEGRAM_BOT_TOKEN=
EOF
cat > "$ROOT/iso-root/README.txt" <<'EOF'
Hermes Public Installer ISO
Run install-public.ps1 from the mounted ISO.
No private credentials are included. Add your own credentials after install.
EOF
cat > "$ROOT/iso-root/install-public.ps1" <<'PS1'
param([switch]$Install)
$ErrorActionPreference='Stop'
$root=Join-Path $env:LOCALAPPDATA 'HermesPublicBootstrap'
New-Item -ItemType Directory -Force -Path $root | Out-Null
$envExample=Join-Path $root '.env.example'
Copy-Item -Force -Path (Join-Path $PSScriptRoot 'templates\.env.example') -Destination $envExample
$readme=Join-Path $root 'README.txt'
Set-Content -Path $readme -Value @'
Hermes public bootstrap installed.
Next steps:
1. Copy .env.example to .env.
2. Add your own provider keys, Telegram bot tokens, GitHub token, and MCP credentials.
3. Install Hermes Agent from https://github.com/NousResearch/hermes-agent or your preferred source.
4. Run your normal Hermes setup/verification commands.
'@
Write-Host "Installed public Hermes bootstrap to $root"
Write-Host "Credentials template: $envExample"
PS1
genisoimage -quiet -J -R -V HERMES_PUB -o "$REL/hermes-public-installer.iso" "$ROOT/iso-root"
( cd "$REL" && sha256sum hermes-public-installer.iso > SHA256SUMS )
{
  echo "Built: $(date -Is)"
  ls -lh "$REL"
} > "$REL/manifest.txt"
printf 'Public release built at %s\n' "$REL"
