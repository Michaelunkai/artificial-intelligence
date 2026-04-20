# Backup Scheduler - Quick Start Guide

## 60-Second Setup

### 1. Install (Administrator PowerShell)
```powershell
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force
F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\install-backup-functions.ps1
```

### 2. Reopen PowerShell

### 3. Configure
```powershell
backup-configure
```
Edit `%APPDATA%\BackupScheduler\config.json` with your settings.

### 4. Enable
```powershell
backup-enable
```

### 5. Done!
Your backups will run daily at the scheduled time.

---

## Commands At a Glance

| Command | What It Does |
|---------|--------------|
| `backup-now` | Run backup immediately |
| `backup-schedule` | View schedule & Task Scheduler status |
| `backup-status` | Show backup status & history |
| `backup-cancel` | Stop current backup |
| `backup-enable` | Start daily scheduled backups |
| `backup-disable` | Stop scheduled backups |
| `backup-configure` | Show config location |
| `backup-help` | Quick help |

---

## Configuration Quickstart

Edit: `%APPDATA%\BackupScheduler\config.json`

**Essential Settings:**

```json
{
  "scheduleTime": "02:00",                    // When to run (24-hour)
  "compressionEnabled": true,                 // Zip backups?
  "retentionPolicy": 10,                      // Keep 10 backups
  "sourceDirectories": [                      // What to backup
    "C:\\Users\\YourName\\Documents",
    "C:\\Users\\YourName\\Desktop"
  ],
  "notificationMethod": "toast"               // Notify on completion
}
```

---

## Typical Workflow

```powershell
# First time
backup-configure                    # View where config is
# Edit config.json
backup-enable                       # Schedule daily backups
backup-now                          # Test it

# Daily usage
backup-schedule                     # Check next run time
backup-status                       # View backup history

# If needed
backup-cancel                       # Stop a backup
backup-disable                      # Turn off scheduling
```

---

## Files Created

| File | Purpose |
|------|---------|
| `backup-scheduler.ps1` | Main scheduler engine |
| `install-backup-functions.ps1` | Setup tool |
| `config.json` | Your settings |
| `logs/backup_YYYY-MM-DD.log` | Daily activity log |
| `data/` | Backup archives stored here |

---

## Troubleshooting

| Issue | Fix |
|-------|-----|
| "Functions not found" | Close & reopen PowerShell |
| "Backup already in progress" | `backup-cancel` |
| "Not running at scheduled time" | Check Task Scheduler status: `backup-schedule` |
| "Check logs for details" | See `%APPDATA%\BackupScheduler\logs\` |

---

## Next Steps

1. **Read full documentation**: `README.md` in same folder
2. **Monitor first backup**: `backup-status`
3. **Adjust config as needed**: Edit `config.json`
4. **Set email notifications** (optional): Update config.json
5. **Check logs** (optional): `%APPDATA%\BackupScheduler\logs\`

---

**Need help?** Review README.md or run `backup-help`
