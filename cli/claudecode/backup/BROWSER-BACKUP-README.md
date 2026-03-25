# Browser Data Backup & Restore Suite

Comprehensive backup/restore solution for all major browsers: **Chrome, Edge, Firefox, and Brave**.

## Features

### Backup Coverage
✅ **IndexedDB** - Persistent application data  
✅ **Local Storage** - Web app settings and credentials  
✅ **Cache** - Browser cache (optimizes restore size)  
✅ **Extensions** - All installed browser extensions  
✅ **Settings** - Browser preferences and configuration  
✅ **Autofill Data** - Saved form data (Claude/Anthropic domains)  
✅ **Reader/Offline Storage** - Reader mode and offline content  
✅ **History** - Browse history (optional)  
✅ **Cookies** - Session cookies (optional, security risk)  

### Supported Browsers
- **Chrome** - Full profile backup
- **Microsoft Edge** - Full profile backup  
- **Firefox** - Profile-based backup
- **Brave** - Full profile backup

---

## Quick Start

### Backup

```powershell
# Basic backup (no history, no cookies)
.\backup-browser-data.ps1

# Backup with history
.\backup-browser-data.ps1 -IncludeHistory

# Backup with cookies (⚠️ security risk)
.\backup-browser-data.ps1 -IncludeCookies -IncludeHistory

# Custom backup location
.\backup-browser-data.ps1 -BackupPath "D:\Backups"

# Verbose output
.\backup-browser-data.ps1 -Verbose
```

### Restore

```powershell
# Interactive restore (asks before overwriting each browser)
.\restore-browser-data.ps1 -BackupPath ".\browser-backup-20240101-120000"

# Force overwrite all
.\restore-browser-data.ps1 -BackupPath ".\browser-backup-20240101-120000" -OverwriteExisting

# Verbose output
.\restore-browser-data.ps1 -BackupPath ".\browser-backup-20240101-120000" -Verbose
```

---

## What Gets Backed Up (Detailed)

### Chrome & Edge
```
Chrome/
├── IndexedDB/              # Application databases (claude.ai, anthropic.com)
├── Local Storage/          # Web app persistent storage
├── Cache/                  # Browser cache files
├── Extensions/             # All installed extensions
├── Settings/
│   └── Preferences        # Browser settings (theme, language, etc.)
├── Autofill/
│   └── Web Data           # Saved form data
├── Reader Data/           # Reader mode storage
├── History/               # Browse history (optional)
└── Cookies/               # Session cookies (optional)
```

### Firefox
```
Firefox/
├── {profile-name}/
│   ├── storage/           # IndexedDB and Local Storage
│   ├── cache2/            # Browser cache
│   ├── prefs.js           # User preferences
│   └── extensions/        # Extension data
└── Extensions/            # Global extension storage
```

### Brave
```
Brave/
├── IndexedDB/             # Application databases
├── Local Storage/         # Web app persistent storage
├── Cache/                 # Browser cache
├── Extensions/            # All installed extensions
├── Settings/              # Browser settings
└── ...                    # Same structure as Chrome
```

---

## Backup Structure

Each backup creates a timestamped directory:
```
browser-backup-20240315-143022/
├── Chrome/                # Chrome backup
├── Edge/                  # Edge backup
├── Firefox/               # Firefox backup
├── Brave/                 # Brave backup
├── BACKUP-MANIFEST.txt    # Backup metadata and info
├── backup-log.txt         # Detailed backup log
└── restore-browser-data.ps1  # Self-contained restore script
```

### BACKUP-MANIFEST.txt
Contains:
- Backup timestamp
- Backup ID (for reference)
- Backup location
- Included data types
- Security warnings
- Log file location

---

## Use Cases

### 1. **System Migration**
Backup before moving to a new computer:
```powershell
.\backup-browser-data.ps1 -IncludeHistory
# ... on new computer ...
.\restore-browser-data.ps1 -BackupPath "D:\old-backup\browser-backup-xxx" -OverwriteExisting
```

### 2. **Fresh Install Protection**
Before a clean OS reinstall:
```powershell
# Include everything
.\backup-browser-data.ps1 -IncludeHistory -IncludeCookies
```

### 3. **Browser Extension Recovery**
After accidental extension removal:
```powershell
# Backup current state (to avoid overwriting)
.\backup-browser-data.ps1 -BackupPath "D:\Backups\current"

# Restore only extensions from old backup
# (Manually copy Extensions/ folder only)
```

### 4. **Claude.ai Session Preservation**
Backup claude.ai data regularly:
```powershell
# Backs up IndexedDB with conversation data
.\backup-browser-data.ps1 -BackupPath "D:\Claude-Backups\backup-$(Get-Date -Format 'yyyyMMdd')"
```

---

## Security Considerations

### ⚠️ Cookies Backup
- **Enabled by default in restore**: `-IncludeCookies` flag
- Contains **session tokens** that could be exploited
- **Never** share backups publicly
- **Never** commit backups to version control
- Keep backups in **encrypted storage**

### ⚠️ Autofill Data
- Contains **saved passwords** (at application level)
- May contain **payment information**
- Store backups securely

### ✅ Best Practices
1. **Store backups offline** - External drive or air-gapped storage
2. **Encrypt backups** - Use BitLocker or similar
3. **Version control** - Don't use git/GitHub for backups
4. **Access control** - Restrict backup file permissions
5. **Verify integrity** - Check BACKUP-MANIFEST.txt before restore

---

## Troubleshooting

### Browser is running during backup
**Problem**: Files in use, incomplete backup  
**Solution**: Close all browser windows before running backup

```powershell
# Kill all browser processes
Stop-Process -Name "chrome" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "msedge" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "firefox" -Force -ErrorAction SilentlyContinue
Stop-Process -Name "brave" -Force -ErrorAction SilentlyContinue

# Then run backup
.\backup-browser-data.ps1
```

### Restore fails with permission errors
**Problem**: File permissions or profile locked  
**Solution**:
1. Close all browser windows
2. Ensure no background browser processes running
3. Run restore with elevation if needed

```powershell
# Restart PowerShell as Administrator
Start-Process powershell -Verb RunAs
# Then run restore script
```

### Some data not restored
**Problem**: Individual files skipped due to locks  
**Solution**: This is normal and logged:
```powershell
# Check the restore log
Get-Content "restore-log.txt" | Select-String "WARN"
```

Safe to ignore warnings unless critical data is missing.

### "Profile not found" error
**Problem**: Browser not installed or in unexpected location  
**Solution**: Script handles this gracefully, skips missing browsers. Check log:

```powershell
Get-Content "backup-log.txt" | Select-String "Not found"
```

---

## Advanced Usage

### Custom Backup Locations

```powershell
# Network share
.\backup-browser-data.ps1 -BackupPath "\\fileserver\backups\users\john"

# External drive
.\backup-browser-data.ps1 -BackupPath "E:\Backups\Browser-Data"

# Cloud sync folder (after backup completes)
.\backup-browser-data.ps1 -BackupPath "D:\Backups" | % { 
    robocopy "D:\Backups\browser-backup-*" "C:\OneDrive" /E /XO
}
```

### Scheduled Backups

Create `schedule-browser-backup.ps1`:
```powershell
# Weekly backup at 2 AM
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 2am
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-File 'F:\study\...\backup-browser-data.ps1' -BackupPath 'D:\Backups'"
Register-ScheduledTask -TaskName "Browser-Data-Backup" -Trigger $trigger -Action $action
```

### Backup Verification

```powershell
# Check backup size
Get-ChildItem -Path "browser-backup-xxx" -Recurse | 
  Measure-Object -Property Length -Sum | 
  Select-Object @{N="Size (MB)"; E={[math]::Round($_.Sum / 1MB, 2)}}

# List all browsers in backup
Get-ChildItem -Path "browser-backup-xxx" -Directory | Select-Object Name
```

---

## What's NOT Backed Up

❌ **Installed browser software** - Only profile data  
❌ **Sync passwords** - Stored in encrypted cloud  
❌ **Master passwords** - Not stored in plaintext  
❌ **Security credentials** - Limited to autofill data  
❌ **Temp files** - Intentionally excluded for size  

---

## Logs

Each backup/restore creates logs in the backup directory:
- `backup-log.txt` - Detailed backup operation log
- `restore-log.txt` - Detailed restore operation log

View recent entries:
```powershell
Get-Content "backup-log.txt" -Tail 20
```

---

## Version History

**v1.0** (Initial Release)
- Chrome, Edge, Firefox, Brave support
- IndexedDB, Local Storage, Cache, Extensions
- Optional history and cookies
- Manifest and logging

---

## Support & Issues

**Common Issues**:
1. Close browsers before running scripts
2. Run as Administrator if permission errors occur
3. Check backup/restore logs for detailed errors
4. Verify backup directory has free space (min 2GB recommended)

**Log Analysis**:
```powershell
# Find all errors
Select-String "ERROR" "backup-log.txt"

# Find all warnings
Select-String "WARN" "backup-log.txt"

# Summary
@(
  (Select-String "ERROR" "backup-log.txt").Count,
  "errors and",
  (Select-String "WARN" "backup-log.txt").Count,
  "warnings"
) -join " "
```

---

## License & Notes

Scripts created for comprehensive browser data preservation. Use with caution—backups contain sensitive data.

**Remember**: Always verify backups before trusting them with critical data!
