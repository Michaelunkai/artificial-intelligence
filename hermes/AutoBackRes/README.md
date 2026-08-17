# Hermes WSL2 Data Backup/Restore

These scripts back up and restore only Hermes-related data inside the existing Ubuntu WSL distro. They do not modify Windows profile functions, do not unregister/import WSL, and do not create a full Ubuntu export.

Backup now:

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backup-hermes-wsl2.ps1"
```

Restore latest backup:

```powershell
C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe -NoLogo -NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\restore-hermes-wsl2.ps1"
```

Each new backup contains:

- `hermes-wsl-data.tar.gz`: Hermes data/config/auth/runtime archive only.
- `hermes-wsl-data.paths.txt`: exact WSL paths included.
- `hermes-wsl-data.summary.txt`: size summary of included paths.
- `manifest.json`: archive hash, size, and restore metadata.
- `backup.log` and status files.

Current included WSL paths are Hermes-specific:

- `/home/ubuntu/.hermes`
- `/home/ubuntu/.codex`
- `/home/ubuntu/.config/hermes-setup`
- `/home/ubuntu/.config/uv`
- `/home/ubuntu/.local/bin/hermes`, `uv`, `uvx`
- `/home/ubuntu/.local/share/uv`
- `/home/ubuntu/.cache/ms-playwright`
- `/home/ubuntu/.cache/uv`
- `/home/ubuntu/.bashrc`, `.profile`, `.bash_profile`
