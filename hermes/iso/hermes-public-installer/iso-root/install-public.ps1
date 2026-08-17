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
