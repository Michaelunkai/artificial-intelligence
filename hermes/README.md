# Hermes WSL2 Automation Tools

Windows and WSL2 helper scripts for installing, resuming, backing up, restoring, and monitoring a Hermes Agent gateway connected to Telegram. The project is designed for a Windows host running Ubuntu in WSL2, with Hermes installed inside WSL.

## What This Includes

- `AutoSetupHermes/a.sh` installs or repairs the complete Hermes WSL2 setup, including system packages, Hermes Agent, provider configuration, Telegram gateway wiring, and verification checks.
- `AutoSetupHermes/resume.sh` reconnects the Hermes gateway without deleting data.
- `AutoSetupHermes/enable-windows-startup.ps1` creates a Windows startup task for the setup/gateway flow.
- `AutoBackRes/backup-hermes-wsl2.ps1` creates Hermes-only WSL data backups.
- `AutoBackRes/restore-hermes-wsl2.ps1` validates or restores Hermes-only WSL data backups.
- `AutoBackRes/purge-backups-fast.ps1` deletes local backup payloads from the backups folder when explicitly run.
- `AutoBackRes/HermesTray.exe` is a no-console Windows tray app that runs the WSL resume flow and monitors Hermes.
- `AutoBackRes/run-HermesTray.ps1` starts the tray app without creating duplicate instances.
- `AutoBackRes/HermesTray.cs` and `AutoBackRes/build-HermesTray.ps1` rebuild the tray app.

## Secret Safety

Real tokens, auth files, logs, and backup archives are intentionally ignored by Git. Keep your real values only in local secret files such as:

- `C:\Users\<you>\.codex\secrets\hermes-telegram.env`
- `/home/ubuntu/.config/hermes-setup/telegram.env`
- `/home/ubuntu/.codex/auth.json`
- `/home/ubuntu/.hermes/.env`

Use `.env.example` only as a template. Never commit real bot tokens, OpenAI/Codex auth files, or backup archives.

`AutoSetupHermes/a.sh` is safe to keep in the repository because it contains installer logic and placeholder/template handling only. It does not include your real Telegram bot token, OpenAI/Codex auth JSON, or Hermes `.env` values. Running it can read or seed credentials from your local machine when those local secret files already exist, but publishing this repository does not remove, change, or expose those local credentials.

## Requirements

- Windows 10/11 with WSL2 enabled.
- Ubuntu distro registered as `ubuntu`.
- Windows PowerShell 5 for the PowerShell scripts.
- Ubuntu packages installed by `AutoSetupHermes/a.sh`.
- GitHub publishing only needs Git/GitHub CLI on the Windows side.

## Clone

Clone anywhere. The commands below discover the repository location automatically, so they do not depend on this project living on a specific drive or folder.

```powershell
git clone https://github.com/Michaelunkai/hermes.git; cd hermes
```

```bash
git clone https://github.com/Michaelunkai/hermes.git && cd hermes
```

## Location-Independent One-Liners

Run these from anywhere inside the cloned repository. They use Git to find the project root.

### Windows PowerShell With WSL2

Run the full setup in Ubuntu WSL2:

```powershell
$r=(git rev-parse --show-toplevel); $w=(wsl wslpath -a "$r").Trim(); wsl -d ubuntu -u root -- bash "$w/AutoSetupHermes/a.sh"
```

Run only the safe resume/reconnect flow:

```powershell
$r=(git rev-parse --show-toplevel); $w=(wsl wslpath -a "$r").Trim(); wsl -d ubuntu -u root -- bash "$w/AutoSetupHermes/resume.sh"
```

Enable the Windows startup task:

```powershell
$r=(git rev-parse --show-toplevel); powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$r\AutoSetupHermes\enable-windows-startup.ps1"
```

Run the standalone tray app:

```powershell
$r=(git rev-parse --show-toplevel); & "$r\AutoBackRes\HermesTray.exe"
```

Run the helper launcher when you want duplicate-instance protection:

```powershell
$r=(git rev-parse --show-toplevel); powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$r\AutoBackRes\run-HermesTray.ps1"
```

Rebuild the tray app:

```powershell
$r=(git rev-parse --show-toplevel); powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$r\AutoBackRes\build-HermesTray.ps1"
```

Create a Hermes-only WSL backup:

```powershell
$r=(git rev-parse --show-toplevel); powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$r\AutoBackRes\backup-hermes-wsl2.ps1"
```

Validate the latest backup without changing files:

```powershell
$r=(git rev-parse --show-toplevel); powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$r\AutoBackRes\restore-hermes-wsl2.ps1" -ValidateOnly
```

Restore the latest backup:

```powershell
$r=(git rev-parse --show-toplevel); powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "$r\AutoBackRes\restore-hermes-wsl2.ps1"
```

Restore overwrites current Hermes-scoped WSL data from the selected backup. Validate first when possible.

### Linux

These commands are useful when the repository is cloned directly inside the Linux machine that runs Hermes. Set `HERMES_WSL_USER` if your Hermes Linux user is not `ubuntu`.

Run the safe resume/reconnect flow:

```bash
r="$(git rev-parse --show-toplevel)" && sudo -E HERMES_WSL_USER="${HERMES_WSL_USER:-ubuntu}" bash "$r/AutoSetupHermes/resume.sh"
```

Run the full setup script:

```bash
r="$(git rev-parse --show-toplevel)" && sudo -E HERMES_WSL_USER="${HERMES_WSL_USER:-ubuntu}" bash "$r/AutoSetupHermes/a.sh"
```

### macOS

The Hermes gateway scripts are Linux/WSL oriented and expect a Linux Hermes user, tmux, and Linux paths. On macOS, use these commands to clone, inspect, and edit the project. Run the gateway itself on Linux or Windows WSL2.

Clone anywhere:

```bash
git clone https://github.com/Michaelunkai/hermes.git && cd hermes
```

Open the project in your editor from any subfolder:

```bash
r="$(git rev-parse --show-toplevel)" && open "$r"
```

## Tray App

Tray icon colors:

- Green: gateway connected and healthy.
- Yellow: connecting or running an action.
- Red: error, failed, broken, or not healthy.
- Purple: manually paused or stopped.

## Project Structure

```text
AutoSetupHermes/   WSL setup, resume, and Windows startup helpers
AutoBackRes/       Hermes-only backup/restore scripts and tray app
Dockerfile         Minimal placeholder container file
.env.example       Safe example of required local secret values
.gitignore         Protection for local credentials, logs, and backups
```

## Notes

The README one-liners are location-independent, but the gateway runtime still needs a real Linux/WSL Hermes installation, Telegram credentials, and the expected Hermes user. Use `.env.example` as a template and keep real secrets local.
