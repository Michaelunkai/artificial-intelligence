# Development Environment Backup & Restore System

**Location:** `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup`

This system provides comprehensive backup and restore functionality for ALL development environments in the `F:\study` directory tree.

---

## 📋 What Gets Backed Up

### 1. **Python Virtual Environments**
- All venv/env/.venv directories found recursively
- Extracts `requirements.txt` from each venv using `pip freeze`
- Preserves `pyvenv.cfg` configuration
- **Current count:** 4 venvs in F:\study

### 2. **Node.js Projects**
- All `package.json` files found recursively
- Preserves `package-lock.json` (npm dependency lock)
- Preserves `yarn.lock` (yarn dependency lock)
- Optionally includes `node_modules` size metadata
- **Current count:** 135 Node projects in F:\study

### 3. **Git Repository Metadata**
- Repository `.git/config` files
- Current branch, remote URL, and HEAD commit
- Full git config preservation (not full clone)
- **Current count:** 0 git repos (can be added)

### 4. **Tool Configurations**
- VSCode: `.vscode`, `.vscode-insiders`
- JetBrains: `.idea`, `.jetbrains`
- Vim/Neovim: `.vim`, `.nvim`, `.config/nvim`
- Emacs: `.emacs.d`, `.config/emacs`
- Terminal: `.bash_profile`, `.bashrc`, `.zshrc`, `.profile`
- EditorConfig: `.editorconfig`

### 5. **Build Artifacts** (Optional)
- `node_modules` directory information
- Size metrics for verification
- Can be included with `-IncludeArtifacts` flag

---

## 🔧 Scripts

### **backup-dev-environments.ps1**

Creates a complete snapshot of all development environments.

#### Usage:
```powershell
# Basic backup (default: compress to .zip)
.\backup-dev-environments.ps1

# Backup with artifacts included
.\backup-dev-environments.ps1 -IncludeArtifacts

# Custom backup location
.\backup-dev-environments.ps1 -BackupPath "D:\my-backups"

# No compression
.\backup-dev-environments.ps1 -Compress:$false
```

#### Parameters:
- **BackupPath** - Target directory (default: `F:\study\...\backup`)
- **IncludeArtifacts** - Include build artifacts like `node_modules` [default: false]
- **Compress** - Compress to .zip file [default: true]

#### Output Structure:
```
dev-backup-20231215-143022/
├── python-venvs/
│   ├── venv1/
│   │   ├── requirements.txt
│   │   └── pyvenv.cfg
│   └── venv2/
│       ├── requirements.txt
│       └── pyvenv.cfg
├── node-projects/
│   ├── project1/
│   │   ├── package.json
│   │   ├── package-lock.json
│   │   └── .node_modules_info
│   └── project2/
│       ├── package.json
│       └── yarn.lock
├── git-repos/
│   ├── repo1/
│   │   ├── config
│   │   └── metadata.json
│   └── repo2/
│       ├── config
│       └── metadata.json
├── tool-configs/
│   ├── VSCode/
│   ├── JetBrains/
│   └── Vim/
└── MANIFEST.json
```

#### MANIFEST.json Example:
```json
{
  "BackupDate": "2023-12-15 14:30:22",
  "BackupPath": "F:\\study\\...\\backup\\dev-backup-20231215-143022",
  "PythonVenvs": 4,
  "NodeProjects": 135,
  "GitRepos": 0,
  "ToolConfigs": 12,
  "IncludeArtifacts": false,
  "SourcePath": "F:\\study"
}
```

---

### **restore-dev-environments.ps1**

Restores development environments from a backup.

#### Usage:
```powershell
# Full restore from backup
.\restore-dev-environments.ps1 -BackupPath "F:\study\...\backup\dev-backup-20231215-143022"

# Validation only (no restore)
.\restore-dev-environments.ps1 -BackupPath "..." -ValidateOnly

# Skip npm install (only restore package.json)
.\restore-dev-environments.ps1 -BackupPath "..." -SkipNodeModules

# Skip Python venv recreation
.\restore-dev-environments.ps1 -BackupPath "..." -SkipVenvRecreate
```

#### Parameters:
- **BackupPath** [REQUIRED] - Path to backup directory from backup script
- **ValidateOnly** - Verify backup integrity without restoring [default: false]
- **SkipNodeModules** - Restore configs only, skip npm install [default: false]
- **SkipVenvRecreate** - Restore requirements.txt only, skip venv creation [default: false]

#### Restore Process:
1. **Validates** backup path and manifest
2. **Scans** backup contents
3. **Recreates** Python venvs (if needed)
4. **Installs** pip requirements from requirements.txt
5. **Restores** Node project configs (package.json, locks)
6. **Runs** npm/yarn install
7. **Restores** Git metadata
8. **Restores** tool configurations
9. **Tests** project access
10. **Generates** RESTORE_REPORT.json

#### RESTORE_REPORT.json Example:
```json
{
  "RestoreDate": "2023-12-15 14:45:30",
  "BackupPath": "F:\\study\\...\\backup\\dev-backup-20231215-143022",
  "TargetPath": "F:\\study",
  "Results": {
    "PythonVenvs": 4,
    "NodeProjects": 135,
    "GitRepos": 0,
    "ToolConfigs": 12,
    "Errors": 0
  }
}
```

---

## 📊 Backup Performance

### Typical Backup Times:
- **Python venvs (4):** ~10-20 seconds
- **Node projects (135):** ~30-60 seconds (depends on package-lock.json sizes)
- **Git repos:** ~5 seconds
- **Tool configs:** ~5-10 seconds
- **Compression:** ~20-40 seconds (depends on size)

**Total estimated time:** 2-3 minutes for full backup

### Typical Backup Sizes:
- **Python venvs:** ~500 MB (uncompressed requirements only)
- **Node projects:** ~2-5 GB (package-lock.json files)
- **Git metadata:** ~5-10 MB
- **Tool configs:** ~50-100 MB
- **Compressed:** ~500 MB - 1 GB

---

## 🚀 Quick Start

### Step 1: Create Initial Backup
```powershell
cd "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
.\backup-dev-environments.ps1
```

Expected output:
```
[HH:MM:SS] ========== DEV ENVIRONMENT BACKUP STARTED ==========

[HH:MM:SS] Scanning for Python virtual environments...
[HH:MM:SS] Found 4 Python virtual environments

[HH:MM:SS] Scanning for Node.js projects...
[HH:MM:SS] Found 135 Node.js projects

...

[HH:MM:SS] ========== BACKUP COMPLETED ==========
[HH:MM:SS] Location: F:\study\...\backup\dev-backup-20231215-143022
[HH:MM:SS] Backup compressed: F:\study\...\backup\dev-backup-20231215-143022.zip
```

### Step 2: Verify Backup
```powershell
.\restore-dev-environments.ps1 -BackupPath "F:\study\...\backup\dev-backup-20231215-143022" -ValidateOnly
```

### Step 3: Schedule Regular Backups (Optional)
Create a scheduled task in Windows Task Scheduler:

**Trigger:** Daily at 2:00 AM  
**Action:** `powershell.exe -ExecutionPolicy Bypass -File "F:\study\...\backup\backup-dev-environments.ps1"`  
**Frequency:** Daily

---

## ⚙️ Advanced Usage

### Backup with Artifacts
Includes node_modules information for size verification:
```powershell
.\backup-dev-environments.ps1 -IncludeArtifacts
```

### Selective Restore
Restore only specific components:
```powershell
# Only restore Node configs (skip npm install)
.\restore-dev-environments.ps1 -BackupPath "..." -SkipNodeModules

# Only restore Python venv requirements (skip recreation)
.\restore-dev-environments.ps1 -BackupPath "..." -SkipVenvRecreate
```

### Custom Backup Location
```powershell
# Back up to external drive
.\backup-dev-environments.ps1 -BackupPath "E:\backup-archives"
```

### No Compression
```powershell
# Keep as uncompressed directory
.\backup-dev-environments.ps1 -Compress:$false
```

---

## 📋 Integration with Full System Backup

This dev environment backup can be triggered as part of a comprehensive system backup:

```powershell
# In your main backup orchestrator
.\backup-dev-environments.ps1 | Tee-Object -FilePath "backup-log.txt"

# Then trigger other backups
.\backup-claudecode.ps1
.\backup-databases.ps1
# ... etc
```

---

## 🛠️ Troubleshooting

### Python venv not found
- **Cause:** Venv may be named differently (not `venv`, `env`, or `.venv`)
- **Solution:** Manually add custom venv names to the search patterns in the script

### npm install fails during restore
- **Cause:** npm version mismatch or package compatibility
- **Solution:** Use `npm install --legacy-peer-deps` or manually update packages

### Large backup size
- **Cause:** package-lock.json files can be 5-50 MB each
- **Solution:** Use `-IncludeArtifacts` only when necessary, or compress manually

### Restore to different location
- **Cause:** Venvs must be recreated in the target location
- **Solution:** Edit the script to change target paths for specific projects

### Permission denied errors
- **Cause:** Files locked by running processes
- **Solution:** Close all IDE/editor windows, Python processes, and npm before backing up

---

## 📌 Notes

1. **Venv Recreation:** Python venvs are NOT directly backed up (would be too large). Instead, we backup `requirements.txt` and `pyvenv.cfg`, then recreate during restore.

2. **Node Modules:** By default, `node_modules` are NOT backed up (too large ~100+ GB). Only `package.json` and lock files are backed up. Dependencies are reinstalled during restore.

3. **Git Repos:** Only metadata is backed up, not full repository clones. For that, use `git clone` directly.

4. **Tool Configs:** These are application-specific and may require manual path adjustments after restore.

5. **Backup Integrity:** Always run validation after backup to ensure all data was captured.

---

## 📁 Related Scripts

This is a **SEPARATE** backup system from the Claude Code backups. It focuses ONLY on development environments in F:\study.

Related scripts in same directory:
- `backup-claudecode.ps1` - Claude Code backup
- `backup-databases.ps1` - Database backups
- `backup-orchestrator.ps1` - Orchestrate multiple backup systems
- `validate-backup.ps1` - Validate backup integrity

---

## 📞 Support

For issues or questions:
1. Check the RESTORE_REPORT.json for detailed restore results
2. Review the console output for specific error messages
3. Verify backup MANIFEST.json for backup inventory
4. Run `-ValidateOnly` before restore to check backup integrity

---

**Last Updated:** 2026-03-23  
**Version:** 1.0  
**Status:** Production Ready
