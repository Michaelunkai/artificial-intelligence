# Hermes Private Encrypted Recovery ISO

Private disaster-recovery package for restoring this machine's Hermes setup after a clean Windows 11 reinstall.

## What this repo contains

- A latest-release ISO containing an installer script.
- Encrypted release assets (`hermes-backup.enc.part-*`) containing the local Hermes homes.
- No raw credentials, private keys, tokens, browser cookies, or session databases are stored in Git history. Sensitive data is only present inside the encrypted release parts.

## Included Hermes homes

The encrypted backup is designed to preserve the five local Hermes homes:

- `/home/ubuntu/.hermes`
- `/home/ubuntu/.hermes-michahermes5bot`
- `/home/ubuntu/.hermes-michaopenclawbot`
- `/home/ubuntu/.hermes-mmichael_moltbot_bot`
- `/home/ubuntu/.hermes-mmmoltbot_bot`

## Critical recovery key

A local recovery key file is generated during packaging and is intentionally ignored by Git:

`PRIVATE_RECOVERY_KEY_DO_NOT_UPLOAD.txt`

Keep that key somewhere safe. The encrypted release assets cannot be restored without it. Do **not** upload the key to GitHub.

## Private one-liner installer

Because this repository is private, the installer needs a GitHub token with permission to read releases. It prompts for the recovery key and restores the encrypted backup.

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$repo='Michaelunkai/hermes-private-encrypted-recovery'; $token=Read-Host 'GitHub token with repo read access'; $h=@{Authorization='Bearer '+$token; 'User-Agent'='HermesRecovery'}; $rel=Invoke-RestMethod -Headers $h -Uri ('https://api.github.com/repos/'+$repo+'/releases/latest'); $asset=$rel.assets|?{ $_.name -match '\.(iso)$' }|select -First 1; if(!$asset){throw 'No ISO asset found'}; $iso=Join-Path $env:TEMP $asset.name; Invoke-WebRequest -Headers @{Authorization='Bearer '+$token;Accept='application/octet-stream';'User-Agent'='HermesRecovery'} -Uri $asset.url -OutFile $iso; $img=Mount-DiskImage -ImagePath $iso -PassThru; try{$drive=(($img|Get-Volume).DriveLetter+':'); powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $drive 'install-private.ps1') -Repo $repo -GitHubToken $token} finally {Dismount-DiskImage -ImagePath $iso}"
```

## Build/release process

1. `scripts/build_private_release.sh` creates/updates the encrypted backup, ISO, checksum, and manifest.
2. Git is force-pushed to `main`.
3. GitHub Release `latest`/`vYYYYMMDD-HHMMSS` is created with the ISO and encrypted parts.

## Restore behavior

The installer:

1. Downloads all encrypted backup parts from the latest private release.
2. Prompts for the local recovery key.
3. Decrypts with OpenSSL AES-256-CBC/PBKDF2.
4. Extracts the Hermes homes back into `/home/ubuntu`.
5. Leaves service/tray startup verification to the restored Hermes tooling and documented post-restore checks.

## Security notes

- Never commit `PRIVATE_RECOVERY_KEY_DO_NOT_UPLOAD.txt`.
- Rotate GitHub tokens if they are ever pasted into an untrusted shell.
- Private GitHub repositories are not a replacement for encryption; this package uses both private visibility and encrypted artifacts.

## Million-percent automatic private recovery one-liner

Use this when you want to automatically download the latest private GitHub Release ISO and run the private recovery installer.

### Before running it

You need **one** of these GitHub authentication options on the Windows machine:

1. `GITHUB_TOKEN` environment variable set to a GitHub token that can read this private repository, **or**
2. GitHub CLI installed at `C:\Program Files\GitHub CLI\gh.exe` and already logged in with `gh auth login`.

You also need **one** of these recovery-key options:

1. `HERMES_RECOVERY_KEY` environment variable set to the recovery key, **or**
2. The local key file still present at:

`F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\iso\hermes-private-encrypted-recovery\PRIVATE_RECOVERY_KEY_DO_NOT_UPLOAD.txt`

### Run this in Windows PowerShell

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -Command "$ErrorActionPreference='Stop'; $repo='Michaelunkai/hermes-private-encrypted-recovery'; $token=$env:GITHUB_TOKEN; if(-not $token){ $gh='C:\Program Files\GitHub CLI\gh.exe'; if(Test-Path $gh){ $token=(& $gh auth token).Trim() } }; if(-not $token){ throw 'Set GITHUB_TOKEN or login with GitHub CLI first' }; $key=$env:HERMES_RECOVERY_KEY; if(-not $key -and (Test-Path 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\iso\hermes-private-encrypted-recovery\PRIVATE_RECOVERY_KEY_DO_NOT_UPLOAD.txt')){ $key=(Get-Content -Raw 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\iso\hermes-private-encrypted-recovery\PRIVATE_RECOVERY_KEY_DO_NOT_UPLOAD.txt').Trim() }; if(-not $key){ throw 'Set HERMES_RECOVERY_KEY or provide PRIVATE_RECOVERY_KEY_DO_NOT_UPLOAD.txt at the original F: path' }; $h=@{Authorization='Bearer '+$token;'User-Agent'='HermesRecovery'}; $rel=Invoke-RestMethod -Headers $h -Uri ('https://api.github.com/repos/'+$repo+'/releases/latest'); $asset=$rel.assets|Where-Object{ $_.name -match '\.iso$' }|Select-Object -First 1; if(-not $asset){ throw 'No ISO asset found' }; $iso=Join-Path $env:TEMP $asset.name; Invoke-WebRequest -Headers @{Authorization='Bearer '+$token;Accept='application/octet-stream';'User-Agent'='HermesRecovery'} -Uri $asset.url -OutFile $iso; $img=Mount-DiskImage -ImagePath $iso -PassThru; try{ $drive=(($img|Get-Volume).DriveLetter+':'); $src=Join-Path $drive 'install-private.ps1'; $tmp=Join-Path $env:TEMP 'install-private-auto.ps1'; Copy-Item -Force $src $tmp; (Get-Content -Raw $tmp).Replace('$recoveryKey=Read-Host ''Paste recovery key''','$recoveryKey=$env:HERMES_RECOVERY_KEY')|Set-Content -Path $tmp -Encoding UTF8; $env:HERMES_RECOVERY_KEY=$key; powershell.exe -NoProfile -ExecutionPolicy Bypass -File $tmp -Repo $repo -GitHubToken $token } finally { Dismount-DiskImage -ImagePath $iso }"
```

### What it does

1. Authenticates to GitHub using `GITHUB_TOKEN` or the installed GitHub CLI login.
2. Reads the local Hermes recovery key from `HERMES_RECOVERY_KEY` or the ignored local key file.
3. Queries `https://api.github.com/repos/Michaelunkai/hermes-private-encrypted-recovery/releases/latest`.
4. Downloads the latest `.iso` release asset.
5. Mounts the ISO.
6. Copies and patches the mounted `install-private.ps1` so it can use the recovery key non-interactively.
7. Runs the private restore installer.
8. Dismounts the ISO in a `finally` block.

### Important security note

Do not paste the recovery key into GitHub, chat, logs, screenshots, or any public place. This repo stores only encrypted release backup parts; the local recovery key is required to decrypt them.
