# Claude Code + OpenClaw Backup System — USER GUIDE

**Version:** 21.0 LEAN BLITZ  
**Last Updated:** 2026-03-23  
**Quick Start:** Run `/backclau` in any Telegram bot to back up everything automatically.

---

## Table of Contents

1. [Overview](#overview)
2. [Quick Start](#quick-start)
3. [Manual Backup](#manual-backup)
4. [Automatic Backups](#automatic-backups)
5. [Scheduling Backups](#scheduling-backups)
6. [Restore from Backup](#restore-from-backup)
7. [Storage & Organization](#storage--organization)
8. [Troubleshooting](#troubleshooting)
9. [FAQ](#faq)

---

## Overview

The Claude Code + OpenClaw Backup System v21.0 is a **comprehensive backup solution** that protects:

- **Claude Code** settings, sessions, and configuration
- **OpenClaw** workspaces, credentials, and agent state
- **MCP (Model Context Protocol)** configurations
- **CLI state** and tool configurations
- **Browser profiles** with Claude conversations
- **Git** SSH keys and credentials
- **Python & Node.js** package information
- **Environment variables** and registry settings

### What Gets Backed Up?

✅ **Everything Important:**
- `.claude` directory (settings, hooks, commands, sessions, memory)
- `.openclaw` workspaces (workspace-main, workspace-moltbot2, etc.)
- All credentials and authentication tokens
- MCP desktop config
- CLI state and locks
- Browser IndexedDB (Claude conversations)
- Scheduled tasks
- Git configuration

❌ **Regeneratable Garbage Excluded (~850MB savings):**
- File history cache
- Image/paste caches
- Shell snapshots
- Browser caches (Code Cache, GPU Cache, etc.)
- Old CLI versions
- Logs
- Telemetry

**Result:** Full backup in **reasonable size** without waste.

---

## Quick Start

### One-Command Backup (Recommended)

**In ANY Telegram bot (main agent, moltbot, clawdbot, openclaw), send:**

```
/backclau
```

This is a slash command registered in your Telegram bots that runs the full backup automatically.

**What happens:**
1. Opens PowerShell
2. Runs the backup script
3. Creates timestamped backup folder: `F:\backup\claudecode\backup_YYYY_MM_DD_HH_MM_SS`
4. Shows real-time progress (task count, completion percentage)
5. Reports final summary (file count, size, duration)

**Time:** ~2-5 minutes depending on system load  
**Output folder:** `F:\backup\claudecode\backup_<timestamp>`

---

## Manual Backup

### From PowerShell

If you prefer to run it manually:

```powershell
# Basic backup
powershell -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1"

# With automatic cleanup of regeneratable garbage
powershell -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1" -Cleanup

# Custom backup location
powershell -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1" -BackupPath "D:\my-backup-$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss')"

# More parallel threads for faster backups (default: 32)
powershell -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1" -MaxJobs 64
```

### Script Parameters

| Parameter | Default | Description |
|-----------|---------|-------------|
| `-BackupPath` | `F:\backup\claudecode\backup_<timestamp>` | Where to save the backup |
| `-MaxJobs` | `32` | Parallel copy threads (higher = faster, uses more CPU) |
| `-Cleanup` | (off) | Delete regeneratable garbage from live system after backup |

---

## Automatic Backups

### Using Windows Task Scheduler

Create a scheduled task to back up automatically:

#### Option 1: Via PowerShell (Recommended)

```powershell
# Create a daily backup at 2 AM
$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1"'
$settings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -WakeToRun
Register-ScheduledTask -TaskName "ClaudeCode Daily Backup" -Trigger $trigger -Action $action -Settings $settings -Force
```

#### Option 2: Via Task Scheduler GUI

1. **Open Task Scheduler**
   - Press `Win+R`
   - Type `taskschd.msc`
   - Press Enter

2. **Create Basic Task**
   - Click "Create Basic Task..." (right panel)
   - Name: `ClaudeCode Daily Backup`
   - Description: `Automated backup of Claude Code and OpenClaw data`

3. **Set Trigger**
   - Click "Triggers" → "New..."
   - Choose "Daily"
   - Set time: 2:00 AM (after you typically sleep)
   - Click OK

4. **Set Action**
   - Click "Actions" → "New..."
   - Program: `powershell.exe`
   - Arguments: `-NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1"`
   - Click OK

5. **Set Conditions**
   - Click "Conditions" tab
   - Check: "Wake the computer to run this task"
   - Uncheck: "Start the task only if the computer is on AC power"
   - Click OK

6. **Save**
   - Click OK
   - Enter your password when prompted

### Verify Scheduled Task

```powershell
# List your backup tasks
schtasks /query /tn "ClaudeCode*"

# Test the task (run it now)
schtasks /run /tn "ClaudeCode Daily Backup"

# Delete the task if needed
schtasks /delete /tn "ClaudeCode Daily Backup" /f
```

---

## Scheduling Backups

### Recommended Schedule

For most users, a **weekly backup** is ideal:

```powershell
# Weekly backup (Sundays at 1 AM)
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Sunday -At 1:00AM
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument '-NoProfile -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1" -Cleanup'
$settings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable -WakeToRun
Register-ScheduledTask -TaskName "ClaudeCode Weekly Backup" -Trigger $trigger -Action $action -Settings $settings -Force
```

### Backup Frequency Guidelines

| Frequency | Use Case | Command |
|-----------|----------|---------|
| **Daily** | Heavy development, critical data | `New-ScheduledTaskTrigger -Daily` |
| **Every 3 days** | Normal usage | `New-ScheduledTaskTrigger -Daily -DaysOfWeek Mon,Wed,Fri` |
| **Weekly** | Light usage, archives already exist | `New-ScheduledTaskTrigger -Weekly` |
| **Monthly** | Long-term archive only | `New-ScheduledTaskTrigger -Monthly` |

### Best Practices

✅ **DO:**
- Schedule backups during **off-hours** (2-4 AM is ideal)
- Use `-Cleanup` flag to free disk space
- Keep at least **2-3 recent backups** (rotate old ones)
- Store one backup **off-site** (cloud, external drive, NAS)

❌ **DON'T:**
- Run backups while actively coding (file locks cause timeouts)
- Schedule during peak work hours
- Delete backups too aggressively—keep at least 1 monthly

---

## Restore from Backup

### What Restoration Does

Restoration **overwrites your current data** with backed-up versions. Always backup FIRST before restoring.

### Full System Restore

```powershell
# Restore everything from a backup
# Replace <backup-path> with your backup folder path

$backupPath = "F:\backup\claudecode\backup_2026_03_23_14_30_15"

# Copy everything back
robocopy "$backupPath\core" "$env:USERPROFILE\.claude" /E /R:3 /W:1 /MT:32
robocopy "$backupPath\openclaw" "$env:USERPROFILE\.openclaw" /E /R:3 /W:1 /MT:32
robocopy "$backupPath\appdata" "$env:APPDATA\Claude" /E /R:3 /W:1 /MT:32

Write-Host "Restore complete. Restart Claude/OpenClaw." -ForegroundColor Green
```

### Selective Restore (Single Component)

#### Restore Only `.claude` Settings

```powershell
$backupPath = "F:\backup\claudecode\backup_2026_03_23_14_30_15"
robocopy "$backupPath\core\claude-home" "$env:USERPROFILE\.claude" /E /R:3 /W:1 /MT:32
Write-Host "Claude settings restored." -ForegroundColor Green
```

#### Restore Only OpenClaw Workspace

```powershell
$backupPath = "F:\backup\claudecode\backup_2026_03_23_14_30_15"
$workspace = "workspace-moltbot2"  # or any workspace name
robocopy "$backupPath\openclaw\$workspace" "$env:USERPROFILE\.openclaw\$workspace" /E /R:3 /W:1 /MT:32
Write-Host "$workspace workspace restored." -ForegroundColor Green
```

#### Restore Only Credentials

```powershell
$backupPath = "F:\backup\claudecode\backup_2026_03_23_14_30_15"
robocopy "$backupPath\credentials" "$env:USERPROFILE\.openclaw\credentials" /E /R:3 /W:1 /MT:32
Write-Host "Credentials restored." -ForegroundColor Green
```

### Step-by-Step Restore Process

1. **Stop all Claude/OpenClaw processes**
   ```powershell
   # Stop Claude
   Get-Process claude -ErrorAction SilentlyContinue | Stop-Process -Force
   
   # Stop OpenClaw
   Get-Process openclaw -ErrorAction SilentlyContinue | Stop-Process -Force
   Get-Process gateway -ErrorAction SilentlyContinue | Stop-Process -Force
   
   # Wait for all to exit
   Start-Sleep -Seconds 3
   ```

2. **Backup current state (just in case)**
   ```powershell
   Copy-Item "$env:USERPROFILE\.claude" "$env:USERPROFILE\.claude.pre-restore" -Recurse -Force
   Copy-Item "$env:USERPROFILE\.openclaw" "$env:USERPROFILE\.openclaw.pre-restore" -Recurse -Force
   ```

3. **Restore from backup**
   ```powershell
   $backupPath = "F:\backup\claudecode\backup_2026_03_23_14_30_15"
   robocopy "$backupPath\core\claude-home" "$env:USERPROFILE\.claude" /E /PURGE /R:3 /W:1 /MT:32
   robocopy "$backupPath\openclaw" "$env:USERPROFILE\.openclaw" /E /PURGE /R:3 /W:1 /MT:32
   Write-Host "Restore complete." -ForegroundColor Green
   ```

4. **Restart applications**
   ```powershell
   # Restart Claude
   & "$env:APPDATA\npm\claude.cmd"
   
   # Restart OpenClaw gateway
   openclaw gateway restart
   ```

5. **Verify**
   - Check settings in Claude
   - Verify OpenClaw workspaces are present
   - Test CLI commands: `claude --version`, `openclaw --version`

---

## Storage & Organization

### Backup Locations

Default backup location: **`F:\backup\claudecode\`**

Each backup is timestamped:
```
F:\backup\claudecode\
├── backup_2026_03_20_02_00_15/    ← Weekly (Sunday 2 AM)
├── backup_2026_03_22_14_30_12/    ← Manual backup
├── backup_2026_03_23_02_00_08/    ← Weekly (today)
└── BACKUP-METADATA.json            ← Index of all backups
```

### Managing Backup Storage

#### How Much Space Do Backups Use?

A typical backup is **2-4 GB**:
- Claude settings: ~50 MB
- OpenClaw workspaces: ~800 MB
- Browser IndexedDB: ~500 MB
- Metadata & configs: ~200 MB
- Credentials & keys: ~50 MB

**Multiple backups:** 3 backups = 6-12 GB, 10 backups = 20-40 GB

#### Clean Up Old Backups

```powershell
# Keep only the 5 most recent backups (delete older ones)
$backupDir = "F:\backup\claudecode"
$backups = Get-ChildItem $backupDir -Directory -Filter "backup_*" | Sort-Object Name -Descending
$keep = 5

if ($backups.Count -gt $keep) {
    $backups | Select-Object -Skip $keep | Remove-Item -Recurse -Force
    Write-Host "Deleted $($backups.Count - $keep) old backups" -ForegroundColor Green
}
```

#### Archive Old Backups

```powershell
# Compress backups older than 1 month
$backupDir = "F:\backup\claudecode"
$cutoff = (Get-Date).AddMonths(-1)

Get-ChildItem $backupDir -Directory -Filter "backup_*" | Where-Object {
    $_.LastWriteTime -lt $cutoff
} | ForEach-Object {
    $zipPath = "$backupDir\$($_.Name).zip"
    Compress-Archive -Path $_.FullName -DestinationPath $zipPath -CompressionLevel Optimal
    Remove-Item $_.FullName -Recurse -Force
    Write-Host "Archived: $($_.Name) → $($_.Name).zip" -ForegroundColor Green
}
```

#### Monitor Backup Size

```powershell
# Check total backup storage usage
$backupDir = "F:\backup\claudecode"
$size = (Get-ChildItem $backupDir -Recurse -File -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
$sizeMB = [math]::Round($size / 1MB, 2)
$sizeGB = [math]::Round($size / 1GB, 2)

Write-Host "Total backup storage: $sizeGB GB ($sizeMB MB)" -ForegroundColor Cyan

# Per-backup breakdown
Get-ChildItem $backupDir -Directory -Filter "backup_*" | ForEach-Object {
    $sz = (Get-ChildItem $_.FullName -Recurse -File | Measure-Object -Property Length -Sum).Sum
    $szMB = [math]::Round($sz / 1MB, 2)
    Write-Host "  $($_.Name): $szMB MB" -ForegroundColor DarkGray
}
```

---

## Troubleshooting

### Backup Fails with "TIMEOUT"

**Problem:** A backup task times out and gets killed.

**Causes:**
- System is busy (antivirus scanning, heavy I/O)
- Network drive disconnected
- File is locked by another process
- Slow disk

**Solutions:**

1. **Increase timeout (per-task)**
   ```powershell
   # Modify the script to increase timeout from 120s to 300s
   # Edit backup-claudecode.ps1, find: Add-Task ... -T 120
   # Change 120 to 300
   ```

2. **Run with fewer parallel jobs (reduce CPU contention)**
   ```powershell
   powershell -File "backup-claudecode.ps1" -MaxJobs 16
   ```

3. **Close background applications**
   - Stop antivirus scan
   - Close Claude/OpenClaw
   - Close heavy apps (Docker, Node.js servers)

4. **Check disk health**
   ```powershell
   # Run SMART health check
   Get-PhysicalDisk | Select-Object FriendlyName,HealthStatus
   ```

### Backup Shows "FAIL" Errors

**Problem:** Some files report `[FAIL]` in the output.

**Causes:**
- File is locked by running process
- Insufficient permissions
- File path is too long (Windows limit: 260 chars)

**Solutions:**

1. **Check which files failed**
   - Look for `[FAIL]` messages in output
   - Most are harmless (logs, temp files)

2. **If critical files failed:**
   ```powershell
   # Retry just those files manually
   robocopy "$src" "$dst" /R:5 /W:2 /MT:16
   ```

3. **For permission errors:**
   ```powershell
   # Run as Administrator
   Start-Process powershell -ArgumentList @(
     '-NoProfile'
     '-ExecutionPolicy Bypass'
     '-File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1"'
   ) -Verb RunAs
   ```

### Backup Takes Too Long

**Problem:** Backup is running for >10 minutes.

**Solutions:**

1. **Increase parallel jobs**
   ```powershell
   powershell -File "backup-claudecode.ps1" -MaxJobs 64
   ```

2. **Exclude large directories**
   - Edit the script and add directories to exclusion lists
   - Useful for `node_modules`, `.git`, `__pycache__`

3. **Check disk speed**
   ```powershell
   # Test disk read/write speed
   Get-PhysicalDisk | Select-Object FriendlyName,MediaType,BusType,Size
   ```

### Restore Doesn't Work

**Problem:** Restored files don't appear or are incomplete.

**Solutions:**

1. **Verify backup exists**
   ```powershell
   Get-ChildItem "F:\backup\claudecode\backup_<your-date>" | Measure-Object
   ```

2. **Check permissions**
   ```powershell
   # Run restore as Administrator
   Start-Process powershell -ArgumentList @(
     '-NoProfile'
     '-ExecutionPolicy Bypass'
     '-Command "robocopy ... /E /R:3 /W:1"'
   ) -Verb RunAs
   ```

3. **Manually verify critical files**
   ```powershell
   $backupPath = "F:\backup\claudecode\backup_2026_03_23_14_30_15"
   Test-Path "$backupPath\core\claude-home\.claude.json"
   Test-Path "$backupPath\openclaw\workspace-moltbot2"
   ```

4. **Use `/PURGE` flag to force overwrite**
   ```powershell
   robocopy "$backupPath\core\claude-home" "$env:USERPROFILE\.claude" /E /PURGE /R:3 /W:1
   ```

### Can't Delete Old Backups

**Problem:** Permission denied when trying to delete backups.

**Solutions:**

1. **Check file locks**
   ```powershell
   Handle "F:\backup\claudecode\backup_xxxx"
   ```

2. **Take ownership**
   ```powershell
   $path = "F:\backup\claudecode\backup_xxxx"
   icacls $path /grant:r "$($env:USERNAME):(F)" /T /C
   Remove-Item $path -Recurse -Force
   ```

3. **Run as Administrator**
   ```powershell
   # Right-click PowerShell → Run as Administrator
   # Then try delete again
   ```

---

## FAQ

### Q: How often should I back up?

**A:** For typical usage:
- **Weekly** is sufficient for most people
- **Daily** if you're actively developing or configuring systems
- **Before major changes** (OS updates, system reinstalls, major reconfigurations)

### Q: Can I back up to cloud storage?

**A:** Yes, but there are tradeoffs:

**OneDrive/Google Drive:**
```powershell
# Back up to OneDrive sync folder
powershell -File "backup-claudecode.ps1" -BackupPath "$env:USERPROFILE\OneDrive\Backups\claudecode_$(Get-Date -Format 'yyyy_MM_dd')"
```

**Pros:** Automatically synced, accessible from any computer  
**Cons:** Slower (network I/O), privacy concerns with credentials, quota limits

**Better approach:** Back up locally FIRST, then copy to cloud:
```powershell
# Local backup
powershell -File "backup-claudecode.ps1"

# Then sync to cloud (after local is done)
robocopy "F:\backup\claudecode" "D:\cloud-sync\backups" /E /M
```

### Q: What if I accidentally delete a file during restoration?

**A:** Use the pre-restore backup:

```powershell
# You created a .pre-restore copy before restoring
Copy-Item "$env:USERPROFILE\.claude.pre-restore\<file>" "$env:USERPROFILE\.claude\<file>" -Force
```

If you didn't create a pre-restore copy, use an older backup:
```powershell
robocopy "F:\backup\claudecode\backup_2026_03_20_02_00_15" "$env:USERPROFILE\.claude" /S
```

### Q: Can I backup to an external USB drive?

**A:** Yes!

```powershell
# Backup to external drive (E:)
powershell -File "backup-claudecode.ps1" -BackupPath "E:\backups\claudecode_$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss')"
```

**Important:**
- Keep USB plugged in for the entire backup (don't eject early)
- USB 3.0+ is recommended (2.0 will be very slow)
- Test restore before relying on it!

### Q: How much space do I need?

**A:** Minimum **10 GB** for 3 backups. Recommended **20 GB+** for safety.

```powershell
# Check available space on your backup drive
Get-Volume -DriveLetter F | Select-Object SizeRemaining
```

### Q: Will backup include my API keys?

**A:** Yes, it backs up credentials. **Keep backups secure!**

```powershell
# Encrypt a backup folder
$acl = New-Object System.Security.AccessControl.DirectorySecurity
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "$env:USERNAME", 
    "FullControl",
    "ContainerInherit,ObjectInherit",
    "None",
    "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl -Path "F:\backup\claudecode" -AclObject $acl
```

### Q: Can I run multiple backups simultaneously?

**A:** **Not recommended**. Multiple backups of the same source will:
- Fight for the same files
- Cause timeouts and locks
- Waste resources

**Better:** Schedule backups at different times:
```powershell
# Sunday 1 AM (full backup with cleanup)
# Wednesday 1 AM (full backup)
# Every Friday manual (on-demand)
```

### Q: How do I verify a backup is complete?

**A:** Check the metadata file:

```powershell
$backupPath = "F:\backup\claudecode\backup_2026_03_23_14_30_15"
$meta = Get-Content "$backupPath\BACKUP-METADATA.json" | ConvertFrom-Json

Write-Host "Files: $($meta.Items)"
Write-Host "Size: $($meta.SizeMB) MB"
Write-Host "Errors: $($meta.Errors.Count)"
Write-Host "Duration: $($meta.Duration)s"

if ($meta.Errors.Count -eq 0) {
    Write-Host "✓ Backup is complete and healthy" -ForegroundColor Green
} else {
    Write-Host "⚠ Backup has errors (see details above)" -ForegroundColor Yellow
}
```

### Q: Can I compress old backups?

**A:** Yes! Use PowerShell's Compress-Archive:

```powershell
$backupPath = "F:\backup\claudecode\backup_2026_03_20_02_00_15"
Compress-Archive -Path $backupPath -DestinationPath "$backupPath.zip" -CompressionLevel Optimal

# This takes ~5-10 minutes and reduces size by ~60%
# Then delete the original to free space
Remove-Item $backupPath -Recurse -Force
```

### Q: What's the difference between backup and system restore?

| Feature | Backup (This System) | Windows System Restore |
|---------|------------------|----------------------|
| **What it backs up** | Claude, OpenClaw, configs | System files only |
| **User data** | ✅ Included | ❌ Not included |
| **Apps** | ✅ Settings, not binaries | ✅ Partial |
| **Credentials** | ✅ Yes | ❌ No |
| **Restore time** | 2-5 minutes | 15-30 minutes |
| **Granularity** | ✅ Restore just one file | ❌ All-or-nothing |
| **Portable** | ✅ Yes (copy to new PC) | ❌ Windows-specific |

**Use this backup system for:** Claude, OpenClaw, personal configs  
**Use Windows restore for:** Virus removal, system corruption

---

## Advanced Topics

### Incremental Backups

The script doesn't do true incremental backups, but you can:

```powershell
# Full backup
powershell -File "backup-claudecode.ps1"

# Then hourly snapshot only changed files (poor man's incremental)
robocopy "$env:USERPROFILE\.claude" "F:\backup\hourly\$((Get-Date).ToString('HH_mm_ss'))" /E /M /XO
```

### Backup to NAS

If you have a network drive:

```powershell
# Map network drive
net use Z: "\\192.168.1.100\backup" /user:admin password

# Backup to NAS
powershell -File "backup-claudecode.ps1" -BackupPath "Z:\claudecode_$(Get-Date -Format 'yyyy_MM_dd')"
```

### Backup Verification Script

```powershell
function Test-Backup {
    param([string]$BackupPath)
    
    $meta = Get-Content "$BackupPath\BACKUP-METADATA.json" | ConvertFrom-Json
    $files = @(Get-ChildItem $BackupPath -Recurse -File).Count
    
    Write-Host "Backup: $(Split-Path $BackupPath -Leaf)"
    Write-Host "  Files: $files (expected: $($meta.Items))"
    Write-Host "  Size: $([math]::Round((Get-ChildItem $BackupPath -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB, 2)) MB"
    Write-Host "  Errors: $($meta.Errors.Count)"
    Write-Host "  Duration: $($meta.Duration)s"
    Write-Host "  ✓ Valid" -ForegroundColor Green
}

Test-Backup "F:\backup\claudecode\backup_2026_03_23_14_30_15"
```

---

**For admin/technical details, see [ADMIN_GUIDE.md](ADMIN_GUIDE.md)**  
**For troubleshooting errors, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**
