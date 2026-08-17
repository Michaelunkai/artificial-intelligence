# PS5 `backher` / `resher` live-progress mission archive

This repository packages the artifacts from the completed Telegram `/ps5` mission that updated the Windows PowerShell 5 profile functions `backher` and `resher`.

The mission outcome was:

- `backher` and `resher` in the PS5 profile are thin wrappers.
- Their heavy logic lives in standalone scripts under the Hermes AutoBackRes tool folder.
- Both standalone scripts show live progress starting at second 2 and then every second until the WSL archive/restore validation work finishes.
- The implementation was verified using Windows PowerShell 5.1 only.

## Production locations

The live production files remain in their original locations so the user's shell functions keep working:

- PS5 profile: `C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1`
- Backup script: `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backher-fast.ps1`
- Restore script: `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\resher-fast.ps1`

This repository contains copies/snapshots of those files and the verification scripts used during the mission.

## What this repository contains

- `artifacts/live-scripts/backher-fast.ps1` — snapshot of the standalone backup implementation with live progress.
- `artifacts/live-scripts/resher-fast.ps1` — snapshot of the standalone restore/validation implementation with live progress.
- `artifacts/profile/Microsoft.PowerShell_profile.ps1` — snapshot of the allowed Windows PowerShell 5 profile after the wrapper changes.
- `artifacts/backups/` — safety backups created before profile/script edits.
- `artifacts/verification-scripts/` — PS5 verification scripts created during the mission and moved here from `/tmp`.
- `artifacts/metadata/mission-artifacts.json` — machine-readable summary of what was collected and what live production paths were intentionally left in place.
- `artifacts/metadata/claude-learned.md` — context log snapshot containing the recorded pitfall/fix.

## Prerequisites

- Windows with WSL installed.
- Windows PowerShell 5.1 at:
  - `C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe`
  - WSL path: `/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe`
- WSL distro named `ubuntu` unless passing another `-Distro` value.
- Existing Hermes AutoBackRes folder at:
  - `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes`

## Setup / install

This repository is an archive and documentation repo. It does not install automatically.

To manually restore these snapshots into the production locations, copy them carefully:

```powershell
Copy-Item -LiteralPath "artifacts\live-scripts\backher-fast.ps1" -Destination "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backher-fast.ps1" -Force
Copy-Item -LiteralPath "artifacts\live-scripts\resher-fast.ps1" -Destination "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\resher-fast.ps1" -Force
```

Do **not** replace the PowerShell profile from this repo unless you intentionally want that exact snapshot. The profile is copied here for audit/reference.

## Usage examples

Run in Windows PowerShell 5.1:

```powershell
# Show the wrapper functions loaded from the profile
cfun backher
cfun resher

# Non-destructive backup discovery check
backher -PlanOnly

# Full Hermes backup with progress every second after second 2
backher

# Validate latest backup is readable/restorable without performing a destructive restore
resher -ValidateOnly

# Show planned restore paths without restoring
resher -PlanOnly
```

Expected progress output looks like:

```text
PROGRESS backher-wsl-archive: starting
PROGRESS backher-wsl-archive: elapsed=2s archive=122.2 MB
PROGRESS backher-wsl-archive: elapsed=3s archive=218.3 MB
...
PROGRESS backher-wsl-archive: finished elapsed=59.4s exit=0
```

For restore validation:

```text
PROGRESS resher-wsl-restore: starting
PROGRESS resher-wsl-restore: elapsed=2s archive=2,096.2 MB
...
Restore input verified: 163747 archive entries
PROGRESS resher-wsl-restore: finished elapsed=32.2s exit=0
```

## Inputs and outputs

### `backher`

Inputs:

- WSL Hermes homes discovered under `/home/*/.hermes*`, `/root/.hermes*`, live `HERMES_HOME` values, and related CLI/cache/state paths.
- Optional parameters: `-Distro`, `-BackupRoot`, `-PlanOnly`, `-RestartGateway`, `-NoRestartGateway`, `-Legacy`.

Outputs:

- Timestamped backup folder under the backup root.
- `hermes-wsl-data.tar.gz`
- `hermes-wsl-data.paths.txt`
- `hermes-wsl-data.summary.txt`
- `manifest.json`
- `LATEST.txt` in the backup root.

### `resher`

Inputs:

- A backup ID or `latest`.
- Existing backup archive and manifest.
- Optional parameters: `-BackupId`, `-Distro`, `-BackupRoot`, `-ValidateOnly`, `-PlanOnly`, `-SlashCommandsOnly`, `-Legacy`.

Outputs:

- With `-ValidateOnly`: verifies archive readability and path safety without restoring.
- Without `-ValidateOnly` or `-PlanOnly`: performs an overlay restore of archived Hermes data.

## Verification performed during the mission

All verification used Windows PowerShell 5.1 only:

- Parsed the PS5 profile and both standalone scripts: `0` parser errors.
- Dot-sourced the profile successfully.
- Confirmed function count stayed `55`.
- Confirmed `cfun backher` and `cfun resher` point to the standalone scripts.
- Confirmed the functions still point to standalone scripts after `Load-FullPowerShellProfile`.
- Ran a full `backher` backup and observed progress every second from second 2 to completion.
- Ran `resher -ValidateOnly` and observed progress every second from second 2 to completion.

## Troubleshooting

### Progress does not show

Open a fresh Windows PowerShell 5.1 window or reload the profile:

```powershell
. $PROFILE
cfun backher
cfun resher
```

Both functions should point to `backher-fast.ps1` and `resher-fast.ps1`.

### A backup reports live file changes

Running Hermes bots may modify files while `tar` reads them. The script accepts tar exit code `1` only after archive listing succeeds. Real tar errors greater than `1` still fail.

### `Start-Process` exit code is blank

The mission found that Windows PowerShell 5.1 can return a blank `ExitCode` when using `Start-Process -PassThru` with redirected streams. The current scripts use `[System.Diagnostics.Process]` directly instead.

### Full restore warning

`resher -ValidateOnly` is safe and non-destructive. Running `resher` without `-ValidateOnly` or `-PlanOnly` performs a real overlay restore of Hermes data. Use it only when intentionally restoring.
