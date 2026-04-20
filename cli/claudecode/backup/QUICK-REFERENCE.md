# Dev Environment Backup/Restore - Quick Reference

**Location:** `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup`

---

## 🚀 Quick Commands

### Basic Backup
```powershell
cd "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
.\backup-dev-environments.ps1
```
**Time:** 2-3 minutes | **Includes:** Python venvs, Node projects, Git metadata, Tool configs

### Validate Backup (Before Restore)
```powershell
.\restore-dev-environments.ps1 -BackupPath "PATH_TO_BACKUP" -ValidateOnly
```
**Time:** 30 seconds | **Risk:** None (read-only check)

### Full Restore
```powershell
.\restore-dev-environments.ps1 -BackupPath "PATH_TO_BACKUP"
```
**Time:** 5-10 minutes | **Includes:** Recreate venvs, npm install, restore configs

### Backup with Artifacts (includes node_modules info)
```powershell
.\backup-dev-environments.ps1 -IncludeArtifacts
```

### Restore Without npm Install
```powershell
.\restore-dev-environments.ps1 -BackupPath "..." -SkipNodeModules
```

---

## 📊 What Gets Backed Up

| Component | Count | Backed Up As |
|-----------|-------|--------------|
| Python venvs | 4 | `requirements.txt` + `pyvenv.cfg` |
| Node projects | 135 | `package.json`, `package-lock.json`, `yarn.lock` |
| Git repos | 0 | `.git/config`, branch, remote, HEAD commit |
| Tool configs | ? | VSCode, JetBrains, Vim, Emacs settings |

---

## 📁 Backup Structure

```
dev-backup-20231215-143022/
├── python-venvs/           (requirements.txt files)
├── node-projects/          (package.json + locks)
├── git-repos/              (metadata only)
├── tool-configs/           (IDE/editor settings)
├── MANIFEST.json           (backup inventory)
└── RESTORE_REPORT.json     (after restore)

dev-backup-20231215-143022.zip  (compressed)
```

---

## 🎯 Common Scenarios

### Scenario 1: Regular Daily Backup
```powershell
# Backup
.\backup-dev-environments.ps1

# Keep last 30 days, archive rest
Get-ChildItem -Path "." -Filter "dev-backup-*" -Directory | 
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-30) } |
    Move-Item -Destination "D:\archive"
```

### Scenario 2: Backup Before Update
```powershell
# Create backup
.\backup-dev-environments.ps1

# Perform update
npm update
pip install --upgrade -r requirements.txt

# If failed, restore:
.\restore-dev-environments.ps1 -BackupPath "LATEST_BACKUP"
```

### Scenario 3: New Machine Setup
```powershell
# Copy backup to new machine
Copy-Item "\\OLD-MACHINE\backup\dev-backup-*" -Destination "." -Recurse

# Restore everything
.\restore-dev-environments.ps1 -BackupPath "dev-backup-20231215-143022"
```

### Scenario 4: Check Backup Status
```powershell
# List recent backups
Get-ChildItem -Filter "dev-backup-*" -Directory | 
    Sort-Object LastWriteTime -Descending | 
    Select-Object Name, LastWriteTime, @{N='Size';E={"{0:N2} GB" -f ((Get-ChildItem $_.FullName -Recurse | Measure-Object -Sum Length).Sum/1GB)}}
```

---

## ⚠️ Important Notes

1. **Venv Recreation:** Venvs are not backed up directly. `requirements.txt` is extracted and venv is recreated on restore.

2. **node_modules:** NOT backed up by default (too large). Only `package.json` and lock files. Dependencies reinstalled on restore.

3. **Git Repos:** Only metadata backed up, not full clone. For full clones, use `git clone` directly.

4. **Tool Configs:** May need manual path adjustment after restore.

5. **Backup Compression:** Automatic by default, creates `.zip` file.

---

## 🔍 Troubleshooting Quick Fixes

| Issue | Quick Fix |
|-------|-----------|
| "Cannot access venv/Scripts/pip.exe" | Python not installed or venv corrupted. Close all IDEs first. |
| "npm not found" | Node.js not in PATH. Use `npm install --legacy-peer-deps` manually. |
| "yarn not found" | Install yarn: `npm install -g yarn` |
| "Backup too slow" | Close IDEs, reduce number of open projects, skip artifacts |
| "Backup too large" | Check `node_modules` size, remove old backups, compress manually |
| "Restore fails" | Run with `-ValidateOnly` first to check backup integrity |

---

## 📋 Pre-Backup Checklist

Before running backup:
- [ ] Close all IDEs (VSCode, PyCharm, etc.)
- [ ] Close all terminals with npm/pip processes
- [ ] Close git clients
- [ ] Stop any running Python processes
- [ ] Ensure 10 GB free disk space
- [ ] Ensure network access to F:\study (if on network)

---

## 📋 Post-Restore Checklist

After running restore:
- [ ] Verify venvs created: `Get-ChildItem F:\study -Recurse -Directory -Name "venv"`
- [ ] Verify Node projects: `Get-ChildItem F:\study -Recurse -Filter "package.json"`
- [ ] Test Python venv: `F:\study\Dev_Toolchain\programming\python\venv\Scripts\python.exe --version`
- [ ] Test npm: `npm --version`
- [ ] Open IDEs and verify project structure
- [ ] Run `npm install` in a few projects to verify package-lock.json
- [ ] Check RESTORE_REPORT.json for errors

---

## 🔧 Advanced Options

```powershell
# Skip everything, just validate backup contents
.\restore-dev-environments.ps1 -BackupPath "..." -ValidateOnly

# Restore without recreating Python venvs
.\restore-dev-environments.ps1 -BackupPath "..." -SkipVenvRecreate

# Restore without npm install (just copy package.json)
.\restore-dev-environments.ps1 -BackupPath "..." -SkipNodeModules

# Backup to custom location
.\backup-dev-environments.ps1 -BackupPath "D:\my-backups"

# Backup without compression
.\backup-dev-environments.ps1 -Compress:$false
```

---

## 📞 Where to Find Files

| What | Location |
|------|----------|
| Backup script | `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-dev-environments.ps1` |
| Restore script | `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-dev-environments.ps1` |
| Documentation | `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\DEV-ENVIRONMENTS-README.md` |
| Integration guide | `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\INTEGRATION-GUIDE.md` |
| Backup data | `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\dev-backup-*` |

---

## 📊 Typical Performance

| Operation | Time | Size |
|-----------|------|------|
| Full backup | 2-3 min | 500 MB - 1 GB |
| Backup + compress | 3-4 min | 300-500 MB |
| Full restore | 5-10 min | Depends on npm |
| Validate only | 30 sec | None |

---

## 🎓 Examples

### Example 1: Daily Backup Schedule
```powershell
# Add to Windows Task Scheduler
$action = New-ScheduledTaskAction -Execute "pwsh.exe" -Argument '-ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-dev-environments.ps1"'
$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
Register-ScheduledTask -TaskName "DailyDevBackup" -Action $action -Trigger $trigger
```

### Example 2: Check Last Backup Status
```powershell
$lastBackup = Get-ChildItem -Path "." -Filter "dev-backup-*" -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
$manifest = Get-Content "$($lastBackup.FullName)\MANIFEST.json" | ConvertFrom-Json
$manifest | Format-Table BackupDate, PythonVenvs, NodeProjects, GitRepos, ToolConfigs
```

### Example 3: Restore to Different Path
```powershell
# Extract backup to temp location first
Expand-Archive "dev-backup-20231215-143022.zip" -DestinationPath "D:\restore-test"

# Then restore
.\restore-dev-environments.ps1 -BackupPath "D:\restore-test\dev-backup-20231215-143022"
```

---

**Quick Version:** 1.0  
**Last Updated:** 2026-03-23
