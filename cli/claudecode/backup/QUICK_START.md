# Quick Start Guide - Startup Configuration Backup/Restore

## One-Liner Examples

### Backup (Takes ~2-3 minutes)
```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-startup-config.ps1"
```

**Output:** Backup saved to `C:\Users\micha\.openclaw\startup_backup\YYYY-MM-DD_HHMMSS`

---

### Dry Run Restore (Show what would happen)
```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-startup-config.ps1" -BackupPath "C:\Users\micha\.openclaw\startup_backup\2025-03-23_143022" -DryRun
```

**Note:** Replace the date/time with your backup's folder name

---

### Full Restore (Apply changes - REQUIRES ADMIN)
```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-startup-config.ps1" -BackupPath "C:\Users\micha\.openclaw\startup_backup\2025-03-23_143022"
```

---

## What Gets Backed Up?

| Item | Count | Details |
|------|-------|---------|
| **Scheduled Tasks** | ? | All tasks with Claude/OpenClaw/ClawdBot keywords (XML format) |
| **Startup Shortcuts** | ? | All .lnk files in Startup folders |
| **Registry Entries** | ? | Run/RunOnce keys from HKLM & HKCU |
| **Windows Services** | ? | Services matching app keywords |
| **Firewall Rules** | ? | Inbound/Outbound rules for the apps |

*(Actual counts shown after first backup)*

---

## File Locations

### Source Files
```
F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\
├── backup-startup-config.ps1          ← Run this to backup
├── restore-startup-config.ps1         ← Run this to restore
├── README.md                           ← Full documentation
└── QUICK_START.md                      ← This file
```

### Backup Storage
```
C:\Users\micha\.openclaw\startup_backup\
├── 2025-03-23_143022\                 ← Timestamped backup folder
│   ├── scheduled_tasks/                ← Task XML files
│   ├── startup_folder/                 ← Shortcut files
│   ├── registry/                       ← Registry .reg files
│   ├── manifest.json                   ← Complete inventory
│   └── backup.log                      ← Operation log
└── 2025-03-24_090000\                 ← Another backup
```

---

## Common Workflows

### 1. Quick Backup Before Major Change
```powershell
# Backup now
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-startup-config.ps1"

# See the backup location printed
# = Do your system changes =

# If something breaks, dry-run restore:
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-startup-config.ps1" -BackupPath "C:\Users\micha\.openclaw\startup_backup\YYYY-MM-DD_HHMMSS" -DryRun
```

### 2. Regular Automated Backups
Open Task Scheduler and create daily task:
- **Trigger:** 2:00 AM daily
- **Action:** `powershell.exe -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-startup-config.ps1"`
- **Run with highest privileges**

### 3. Disaster Recovery
```powershell
# List available backups
Get-ChildItem "C:\Users\micha\.openclaw\startup_backup" -Directory | Sort-Object LastWriteTime -Descending

# Dry-run (always do this first!)
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-startup-config.ps1" -BackupPath "C:\Users\micha\.openclaw\startup_backup\<BACKUP_DATE>" -DryRun

# If dry-run looks good, do full restore (requires admin):
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-startup-config.ps1" -BackupPath "C:\Users\micha\.openclaw\startup_backup\<BACKUP_DATE>"
```

---

## Troubleshooting

### "Access Denied" error
- **Problem:** Not running as Administrator
- **Solution:** Right-click PowerShell → "Run as administrator" → Retry

### "Cannot find path" error
- **Problem:** Backup folder doesn't exist
- **Solution:** Check path in command matches output from backup script

### Restore shows warnings but says "Complete"
- **Problem:** Some items couldn't be restored (e.g., service not installed)
- **Solution:** Check `restore.log` in backup folder for details - it's usually safe

### Want to keep only last 7 backups?
```powershell
$backupRoot = "C:\Users\micha\.openclaw\startup_backup"
$maxKeep = 7
Get-ChildItem $backupRoot -Directory | Sort-Object LastWriteTime -Descending | Select-Object -Skip $maxKeep | Remove-Item -Recurse -Force
```

---

## Pro Tips

✅ **Always dry-run first** - Use `-DryRun` to see exactly what will happen  
✅ **Check the logs** - Read `backup.log` and `restore.log` for details  
✅ **Keep multiple backups** - Don't delete old backups immediately  
✅ **Document your changes** - Add notes about why you backed up  
✅ **Test on non-production first** - Test restore on a separate machine if possible  

---

## Need More?

See **README.md** for:
- Complete feature documentation
- Manifest JSON format
- Advanced usage examples
- System requirements
- Full troubleshooting guide
