# Hermes Public Installer ISO

A public, credential-free Hermes bootstrap ISO for setting up a fresh Windows 11 + WSL machine.

This is the shareable version. It intentionally contains **no** private tokens, account sessions, bot tokens, browser cookies, SSH keys, API keys, or local credentials. Anyone can use it, but they must add their own provider keys, Telegram bot tokens, GitHub token, and login/session data.

## What it installs

- A clean Hermes workspace layout.
- Bootstrap scripts for Windows PowerShell and WSL.
- A template `.env.example` and configuration checklist.
- Post-install verification commands.

## Public one-liner installer

Paste this into Windows PowerShell. It always downloads the latest release ISO from this repository, mounts it, and runs the installer.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$repo='Michaelunkai/hermes-public-installer'; $api='https://api.github.com/repos/'+$repo+'/releases/latest'; $rel=Invoke-RestMethod -Uri $api -Headers @{'User-Agent'='HermesPublicInstaller'}; $asset=$rel.assets | Where-Object { $_.name -match '\.iso$' } | Select-Object -First 1; if(-not $asset){ throw 'No .iso asset found in latest release for '+$repo }; $iso=Join-Path $env:TEMP $asset.name; Invoke-WebRequest -Uri $asset.browser_download_url -OutFile $iso; $img=Mount-DiskImage -ImagePath $iso -PassThru; try { $drive=(($img | Get-Volume).DriveLetter + ':'); powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $drive 'install-public.ps1') -Install } finally { Dismount-DiskImage -ImagePath $iso }"
```

## After installation

1. Open the generated workspace.
2. Copy `.env.example` to `.env`.
3. Add your own credentials:
   - LLM provider API keys
   - Telegram bot tokens
   - GitHub token if using GitHub automation
   - Any MCP server credentials
4. Run the verification script.
5. Start Hermes using your preferred interface.

## What is deliberately excluded

- No private credentials or keys.
- No logged-in browser profile/session data.
- No user-specific local database dumps.
- No private bot tokens.

## ISO contents

- `install-public.ps1` — Windows-side installer entrypoint.
- `templates/.env.example` — credentials template.
- `README.txt` — quick offline instructions inside the mounted ISO.

## Security model

The public package is safe to inspect and fork. It bootstraps structure and tools only; users provide their own secrets after install.
