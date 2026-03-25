# Backup Scheduler - Automated Daily Backup Solution

## Overview

A comprehensive Windows PowerShell-based automated backup solution with Windows Task Scheduler integration, system monitoring, and advanced features like process pause/resume, cloud sync, and retention policies.

## Features

### Core Capabilities
- **Windows Task Scheduler Integration**: Fully automated daily backups at scheduled time
- **System Idle Detection**: Won't start backup until system is idle for specified duration
- **Process Management**: Auto-pause critical processes (SQL, Outlook, VSCode) during backup
- **Backup Types**: 
  - Full weekly backups (configurable day)
  - Incremental daily backups
- **Compression**: Optional ZIP compression for backup archives
- **Cloud Sync**: Integration points for OneDrive, Google Drive (implementation pending)
- **Retention Policy**: Automatic cleanup of old backups
- **Notifications**: Toast notifications or email alerts on completion/failure

### Advanced Features
- **Network Failure Retry**: Automatic retry logic with configurable delays
- **Activity Logging**: Comprehensive logging to date-stamped log files
- **Lock File Management**: Prevents duplicate concurrent backups
- **Stale Lock Detection**: Automatically clears locks older than 24 hours
- **State Tracking**: Tracks backup history and status
- **Error Handling**: Detailed error messages and alerts

## Installation

### Prerequisites
- Windows 10 or later (PowerShell 5.1+)
- Administrator privileges required
- Optional: `pssuspend.exe` (Sysinternals) for process pause feature

### Step 1: Run Installer

```powershell
# Open PowerShell as Administrator
Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope CurrentUser -Force
.\install-backup-functions.ps1
```

This will:
- Add backup commands to your PowerShell profile
- Create initial configuration file
- Display next steps

### Step 2: Close and Reopen PowerShell

PowerShell needs to reload the profile with the new functions.

### Step 3: Initial Configuration

```powershell
backup-configure
```

This shows you where the configuration file is located:
- Windows: `%APPDATA%\BackupScheduler\config.json`
- Typically: `C:\Users\YourUsername\AppData\Roaming\BackupScheduler\config.json`

Edit the JSON file with your preferences:

```json
{
  "scheduleTime": "02:00",
  "backupType": "Incremental",
  "fullBackupDay": "Sunday",
  "compressionEnabled": true,
  "cloudSyncEnabled": false,
  "cloudProvider": "OneDrive",
  "retentionPolicy": 10,
  "notificationMethod": "toast",
  "emailRecipient": "",
  "pauseProcesses": ["sql*", "outlook", "vscode"],
  "sourceDirectories": [
    "C:\\Users\\YourUsername\\Documents",
    "C:\\Users\\YourUsername\\Desktop"
  ],
  "excludePatterns": ["*.tmp", "*.cache", "Temp\\*", "node_modules\\*"],
  "retryOnNetworkFailure": true,
  "maxRetries": 3,
  "retryDelaySeconds": 30,
  "checkIdleMinutes": 5,
  "idleThreshold": 15,
  "enabled": false
}
```

### Configuration Options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `scheduleTime` | string | `02:00` | Daily backup time (24-hour format HH:MM) |
| `backupType` | string | `Incremental` | Type: `Full` or `Incremental` |
| `fullBackupDay` | string | `Sunday` | Day of week for full backups |
| `compressionEnabled` | bool | `true` | ZIP compress backups |
| `cloudSyncEnabled` | bool | `false` | Sync backups to cloud storage |
| `cloudProvider` | string | `OneDrive` | Cloud provider name |
| `retentionPolicy` | int | `10` | Keep this many backup copies |
| `notificationMethod` | string | `toast` | `toast` or `email` |
| `emailRecipient` | string | `` | Email address for notifications |
| `pauseProcesses` | array | Various | Process names to pause during backup |
| `sourceDirectories` | array | Documents, Desktop | Directories to backup |
| `excludePatterns` | array | Various | Files/folders to exclude |
| `retryOnNetworkFailure` | bool | `true` | Retry on network errors |
| `maxRetries` | int | `3` | Number of retry attempts |
| `retryDelaySeconds` | int | `30` | Delay between retries |
| `checkIdleMinutes` | int | `5` | How often to check if system is idle |
| `idleThreshold` | int | `15` | Minutes of inactivity required to start |
| `enabled` | bool | `false` | Whether scheduler is active |

### Step 4: Enable Scheduled Backups

```powershell
backup-enable
```

This will:
- Register the backup task with Windows Task Scheduler
- Set it to run daily at your configured time
- Start in System account with elevated privileges

### Step 5: Test

```powershell
# Test backup now (optional, before scheduling)
backup-now

# View schedule status
backup-schedule

# Check detailed status
backup-status
```

## Usage

### Available Commands

#### `backup-now`
Start a backup immediately (doesn't wait for schedule).

```powershell
backup-now
```

#### `backup-schedule`
View the current schedule and Task Scheduler status.

```powershell
backup-schedule
```

Output includes:
- Schedule settings (time, type, compression, retention)
- Task Scheduler status (state, enabled, next run, last run)
- Backup history (last backup time, size, count)

#### `backup-status`
Show detailed current backup status.

```powershell
backup-status
```

Output includes:
- Current status (running/idle/failed)
- Last backup time and size
- Total backups created
- List of backup archives on disk with sizes
- Last error message (if any)

#### `backup-cancel`
Cancel the current running backup and release the lock.

```powershell
backup-cancel
```

#### `backup-configure`
Show configuration location and available options.

```powershell
backup-configure
```

#### `backup-enable`
Enable daily scheduled backups (registers Task Scheduler task).

```powershell
backup-enable
```

#### `backup-disable`
Disable scheduled backups (unregisters Task Scheduler task).

```powershell
backup-disable
```

#### `backup-help`
Quick help reference for all commands.

```powershell
backup-help
```

## How It Works

### Scheduled Backup Flow

1. **Task Trigger** - Windows Task Scheduler triggers at configured time
2. **Idle Check** - Waits up to 1 hour for system to be idle
3. **Process Pause** - Suspends critical processes (SQL, Outlook, etc.)
4. **Backup Execution** - Copies source directories to backup location
5. **Compression** - Compresses backup if enabled
6. **Cloud Sync** - Uploads to cloud if enabled
7. **Retention** - Deletes old backups beyond retention count
8. **Process Resume** - Resumes suspended processes
9. **Notification** - Sends completion/error notification
10. **Logging** - Records all activities to log file

### System Idle Detection

The scheduler monitors user input to determine if the system is "idle":
- Tracks keyboard and mouse activity
- Waits for specified idle duration (default: 15 minutes)
- Checks every 30 seconds if not idle
- Times out after 1 hour waiting

### Process Pause/Resume

Critical processes can be paused during backup to ensure data consistency:
- Uses Sysinternals `pssuspend.exe` to suspend processes
- Tracks suspended PIDs
- Resumes all suspended processes after backup
- Gracefully handles process termination or errors

### Backup Types

**Incremental Backups**:
- Copy only changed/new files since last backup
- Smaller and faster than full backups
- Daily by default

**Full Backups**:
- Complete copy of all source directories
- Runs on configured day (default: Sunday)
- Larger but self-contained

### Retention Policy

- Keeps the specified number of backup copies (default: 10)
- Deletes oldest backups when limit is exceeded
- Counts both compressed and uncompressed backups

### Logging

All activities are logged to:
- **Location**: `%APPDATA%\BackupScheduler\logs\`
- **Filename**: `backup_YYYY-MM-DD.log`
- **Format**: `[YYYY-MM-DD HH:MM:SS] [LEVEL] Message`

Levels: INFO, WARN, ERROR, SUCCESS

## Configuration Examples

### Example 1: Simple Daily Backup

```json
{
  "scheduleTime": "22:00",
  "backupType": "Incremental",
  "fullBackupDay": "Sunday",
  "compressionEnabled": true,
  "cloudSyncEnabled": false,
  "retentionPolicy": 7,
  "notificationMethod": "toast",
  "sourceDirectories": [
    "C:\\Users\\Till\\Documents",
    "C:\\Users\\Till\\Desktop"
  ],
  "enabled": false
}
```

### Example 2: Full + Cloud Sync

```json
{
  "scheduleTime": "03:00",
  "backupType": "Full",
  "fullBackupDay": "Sunday",
  "compressionEnabled": true,
  "cloudSyncEnabled": true,
  "cloudProvider": "OneDrive",
  "retentionPolicy": 4,
  "notificationMethod": "email",
  "emailRecipient": "you@example.com",
  "sourceDirectories": [
    "C:\\Users\\Till\\Documents",
    "D:\\Projects"
  ],
  "enabled": false
}
```

### Example 3: Aggressive Retention

```json
{
  "scheduleTime": "23:00",
  "retentionPolicy": 30,
  "retryOnNetworkFailure": true,
  "maxRetries": 5,
  "idleThreshold": 30,
  "enabled": false
}
```

## Troubleshooting

### Task Scheduler Shows "The task is ready to run at its next scheduled time"

Normal - means task is registered and waiting for its scheduled time.

### Backup runs but doesn't appear in Task Scheduler history

Check logs in `%APPDATA%\BackupScheduler\logs\` for details.

### "Backup already in progress" error

A stale lock file exists. Run:
```powershell
backup-cancel
```

### Processes aren't pausing

Ensure `pssuspend.exe` is in system PATH, or install Sysinternals Suite.

### Toast notifications not showing

Windows notifications may be disabled. Change to email notifications in config.

### Cloud sync not working

Cloud sync is a placeholder in the current version. Manual copy or third-party tools recommended.

## File Locations

| Item | Path |
|------|------|
| Backup Scheduler Script | `F:\study\AI_ML\...\cli\claudecode\backup\backup-scheduler.ps1` |
| Installer Script | `F:\study\AI_ML\...\cli\claudecode\backup\install-backup-functions.ps1` |
| Configuration File | `%APPDATA%\BackupScheduler\config.json` |
| State File | `%APPDATA%\BackupScheduler\state.json` |
| Backup Data | `%APPDATA%\BackupScheduler\data\` |
| Log Files | `%APPDATA%\BackupScheduler\logs\` |
| Lock File | `%APPDATA%\BackupScheduler\backup.lock` |

## Advanced Usage

### Manual Task Scheduler Management

```powershell
# View all tasks
Get-ScheduledTask -Path "\Microsoft\Windows\BackupScheduler\*"

# Manually trigger task
Start-ScheduledTask -TaskPath "\Microsoft\Windows\BackupScheduler" -TaskName "BackupScheduler"

# View task history
Get-ScheduledTask -TaskName "BackupScheduler" -TaskPath "\Microsoft\Windows\BackupScheduler" | 
    Get-ScheduledTaskInfo
```

### Log Analysis

```powershell
# View today's log
Get-Content "$env:APPDATA\BackupScheduler\logs\backup_$(Get-Date -Format 'yyyy-MM-dd').log"

# Search for errors
Select-String "ERROR" "$env:APPDATA\BackupScheduler\logs\*.log"
```

### State Inspection

```powershell
# View current state
Get-Content "$env:APPDATA\BackupScheduler\state.json" | ConvertFrom-Json | Format-Table
```

## Limitations

- Cloud sync placeholder (requires manual implementation)
- Email notifications placeholder (requires SMTP configuration)
- `pssuspend.exe` must be available for process pause feature
- Backup compression uses system ZIP utility (slower than 7-Zip)
- Incremental backups copy entire files, not file deltas

## Future Enhancements

- [ ] Cloud sync implementation (OneDrive, Google Drive, AWS S3)
- [ ] Email notification integration
- [ ] Block-level incremental backups (faster)
- [ ] Backup verification/integrity checking
- [ ] Web dashboard for status monitoring
- [ ] REST API for remote monitoring
- [ ] Multi-destination support
- [ ] Deduplication across backups
- [ ] Encryption support

## Support

For issues or questions:
1. Check logs in `%APPDATA%\BackupScheduler\logs\`
2. Review configuration in `%APPDATA%\BackupScheduler\config.json`
3. Run `backup-help` for quick reference
4. Review this README for troubleshooting

---

**Author**: Till Thelet  
**Version**: 1.0  
**License**: Proprietary
