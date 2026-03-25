# Backup Scheduler - Technical Implementation Details

## Architecture Overview

The backup scheduler consists of several integrated components:

### Core Components

1. **backup-scheduler.ps1** - Main engine
   - Configuration management
   - State tracking
   - Backup execution logic
   - Windows Task Scheduler integration
   - Logging and notifications

2. **install-backup-functions.ps1** - Setup tool
   - Profile integration
   - Function installation
   - Initial configuration

3. **PowerShell Functions** - User interface
   - `backup-now` - Immediate execution
   - `backup-schedule` - View schedule
   - `backup-status` - Show status
   - `backup-cancel` - Stop backup
   - `backup-configure` - Configuration
   - `backup-enable` - Enable scheduling
   - `backup-disable` - Disable scheduling

## Technical Implementation

### Configuration System

**Config File Location**: `%APPDATA%\BackupScheduler\config.json`

**Key Features**:
- JSON-based configuration
- Default values initialization
- Dynamic reload support
- Type validation

```powershell
function Initialize-BackupConfig {
    # Loads existing config or creates default
    # Returns PSCustomObject for type-safe access
}
```

### State Management

**State File Location**: `%APPDATA%\BackupScheduler\state.json`

**Tracked State**:
```json
{
  "lastBackupTime": "2024-03-23 02:15:32",
  "lastFullBackupTime": "2024-03-17 02:00:00",
  "backupStatus": "success|running|failed|idle",
  "currentBackupSize": 1234567890,
  "totalBackupsCount": 45,
  "lastErrorMessage": "...",
  "isRunning": false
}
```

**Usage Pattern**:
```powershell
$State = Get-BackupState
# Modify state
$State.backupStatus = "success"
Set-BackupState $State
```

### System Idle Detection

**Implementation**: Windows API via P/Invoke

```csharp
[DllImport("kernel32.dll")]
private static extern bool GetLastInputInfo(ref LASTINPUTINFO plii);
```

**Algorithm**:
1. Get system tick count
2. Get last input info (keyboard/mouse)
3. Calculate idle time: `(current tick - last input) / 1000 / 60`
4. Compare against idle threshold
5. Return idle minutes

**Usage**:
```powershell
$IdleMinutes = Test-SystemIdle
if ($IdleMinutes -lt $Config.idleThreshold) {
    # Wait for system to become idle
}
```

### Process Management

**Suspension**: Uses Sysinternals `pssuspend.exe`

```powershell
function Suspend-BackupProcesses {
    # Finds processes matching patterns
    # Suspends each one
    # Returns list of PIDs for later resumption
    
    foreach ($Pattern in $ProcessPatterns) {
        $Processes = Get-Process -Name $Pattern
        foreach ($Process in $Processes) {
            pssuspend.exe $Process.Id
        }
    }
}
```

**Resume Logic**:
```powershell
function Resume-BackupProcesses {
    # Resumes all suspended processes
    foreach ($Pid in $ProcessIds) {
        pssuspend.exe -r $Pid
    }
}
```

### Backup Execution

**Two-Phase Approach**:

**Phase 1: Pre-Backup**
```
1. Check lock file (prevent concurrent backups)
2. Wait for system idle
3. Suspend critical processes
4. Create timestamp-based backup directory
```

**Phase 2: Backup & Post-Processing**
```
1. Copy source directories to backup location
2. Apply exclusion patterns
3. Calculate backup size
4. Compress if enabled
5. Sync to cloud if enabled
6. Apply retention policy
7. Resume suspended processes
```

### Copy Strategy

**Tool**: Robocopy (Windows native, optimized)

```powershell
robocopy `
    "$SourceDir" "$DestDir" `
    /E                       # Recursive with empty dirs
    /R:2                     # Retry count
    /W:5                     # Wait between retries
    /XD $ExcludePattern      # Exclude directories
```

**Advantages**:
- Built-in to Windows
- Efficient
- Handles network resilience
- Progress tracking

### Compression

**Method**: Built-in `Compress-Archive`

```powershell
Compress-Archive -Path $BackupDir `
    -DestinationPath $ZipPath `
    -CompressionLevel Optimal `
    -Force
```

**Trade-offs**:
- ✓ Built-in, no dependencies
- ✓ Compatible everywhere
- ✗ Slower than 7-Zip/WinRAR
- ✗ No incremental compression

### Retention Policy

**Algorithm**:
```
1. List all backup directories
2. Sort by LastWriteTime descending
3. If count > retention policy:
   a. Skip first N directories (keep these)
   b. Delete remaining (old ones)
```

**Implementation**:
```powershell
$BackupDirs = Get-ChildItem $BackupDataPath -Directory | 
    Sort-Object LastWriteTime -Descending

if ($BackupDirs.Count -gt $Config.retentionPolicy) {
    $ToDelete = $BackupDirs | Select-Object -Skip $Config.retentionPolicy
    foreach ($Dir in $ToDelete) {
        Remove-Item $Dir -Recurse -Force
    }
}
```

### Lock File Management

**Purpose**: Prevent concurrent backup executions

**Lock File Location**: `%APPDATA%\BackupScheduler\backup.lock`

**Stale Lock Detection**:
```powershell
if (Test-Path $LockFile) {
    $LockTime = (Get-Item $LockFile).LastWriteTime
    $Age = (Get-Date) - $LockTime
    
    if ($Age.TotalHours -gt 24) {
        # Lock is stale, remove it
        Remove-Item $LockFile -Force
    }
}
```

**Benefits**:
- Prevents data corruption
- Handles process crashes
- Auto-recovery after 24 hours

### Logging System

**Log File Pattern**: `backup_YYYY-MM-DD.log`

**Log Location**: `%APPDATA%\BackupScheduler\logs\`

**Log Format**:
```
[2024-03-23 02:15:32] [INFO] Message
[2024-03-23 02:15:45] [ERROR] Error message
[2024-03-23 02:16:00] [SUCCESS] Backup completed
```

**Log Levels**:
- `INFO` - General information
- `WARN` - Non-critical issues
- `ERROR` - Critical errors
- `SUCCESS` - Successful operations

**Log Implementation**:
```powershell
function Write-BackupLog {
    param(
        [string]$Message,
        [string]$Level = "INFO",
        [string]$LogFile
    )
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $LogMessage = "[$Timestamp] [$Level] $Message"
    
    Add-Content -Path $LogFile -Value $LogMessage
    
    # Color output
    switch ($Level) {
        "ERROR" { Write-Host $LogMessage -ForegroundColor Red }
        "SUCCESS" { Write-Host $LogMessage -ForegroundColor Green }
        # ...
    }
}
```

### Windows Task Scheduler Integration

**Task Configuration**:
```
Name: BackupScheduler
Path: \Microsoft\Windows\BackupScheduler\
Principal: NT AUTHORITY\SYSTEM
Trigger: Daily at configured time
Action: PowerShell.exe -File backup-scheduler.ps1 -RunBackup
Settings:
  - Allow start if on batteries
  - Don't stop if going on batteries
  - Start when available
  - Run only if network available
```

**Registration Process**:
```powershell
function Register-BackupTask {
    $Principal = New-ScheduledTaskPrincipal `
        -UserID "NT AUTHORITY\SYSTEM" `
        -LogonType ServiceAccount `
        -RunLevel Highest
    
    $Trigger = New-ScheduledTaskTrigger `
        -Daily -At ([datetime]"02:00")
    
    $Action = New-ScheduledTaskAction `
        -Execute "PowerShell.exe" `
        -Argument "-File backup-scheduler.ps1 -RunBackup"
    
    Register-ScheduledTask -TaskName "BackupScheduler" ...
}
```

### Notification System

**Toast Notifications**:
```powershell
[Windows.UI.Notifications.ToastNotificationManager, 
 Windows.UI.Notifications, 
 ContentType = WindowsRuntime] | Out-Null

$ToastXML = @"
<toast>
    <visual>
        <binding template="ToastText02">
            <text id="1">Backup $BackupStatus</text>
            <text id="2">Message...</text>
        </binding>
    </visual>
</toast>
"@

[Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier("Backup Scheduler").Show(...)
```

**Email Notifications**: Placeholder (requires SMTP configuration)

### Error Handling

**Three-Layer Approach**:

1. **Operation Level**:
   ```powershell
   try {
       $Processes = Get-Process -Name $Pattern
   }
   catch {
       Write-BackupLog "Failed to get process: $_" "ERROR"
   }
   ```

2. **Backup Level**:
   ```powershell
   try {
       Start-Backup -Config $Config
   }
   catch {
       $State.backupStatus = "failed"
       $State.lastErrorMessage = $_.Exception.Message
   }
   finally {
       # Always release resources
   }
   ```

3. **Recovery**:
   - Stale lock removal
   - Process resume on failure
   - State cleanup
   - Error notification

## Performance Considerations

### Optimization Techniques

1. **Robocopy for Copying**
   - Faster than Copy-Item
   - Built-in multi-threading
   - Handles network errors

2. **ZIP Compression**
   - Optional (can disable if CPU limited)
   - Run after backup complete
   - Parallel compression (system decides)

3. **Retention Cleanup**
   - Done in-process
   - No separate job
   - Efficient sorting

4. **State File Usage**
   - Tracks progress
   - Enables resumption
   - Minimal I/O overhead

### Scalability Limits

- **Maximum backup size**: Limited by disk space
- **Maximum retention count**: ~1000 (practical limit)
- **Maximum exclusion patterns**: ~100
- **Maximum source directories**: ~50

## Security Considerations

### Privilege Requirements

- **Task Scheduler registration**: Administrator
- **Process suspension**: Administrator
- **File access**: Current user + SYSTEM account
- **Configuration**: Current user only

### Data Protection

- Configuration stored in user AppData (access controlled by Windows)
- State file tracks sensitive info (file sizes, timestamps)
- Logs contain operation details (no sensitive data)
- No encryption (optional enhancement)

### Attack Surface

- Lock file could be manipulated (mitigated by 24h timeout)
- Config file could be tampered (mitigated by validation)
- Task could be disabled by admin (by design)

## Future Enhancement Opportunities

### Cloud Sync Implementation
```powershell
function Sync-BackupToCloud {
    param([string]$BackupPath, [string]$CloudProvider)
    
    switch ($CloudProvider) {
        "OneDrive" { # Use OneDrive API }
        "GoogleDrive" { # Use Google Drive API }
        "S3" { # Use AWS SDK }
    }
}
```

### Encryption
```powershell
# Before compression
Encrypt-Volume -Path $BackupDir -Algorithm AES256
```

### Block-Level Incremental
```powershell
# Only backup changed blocks, not entire files
function Backup-Incremental {
    # Compare file hashes/timestamps
    # Copy only changed files
}
```

### Integrity Verification
```powershell
function Verify-BackupIntegrity {
    # Check all files present
    # Verify checksums
    # Test extraction (for zips)
}
```

## Troubleshooting Guide

### Debug Logging

Enable verbose logging:
```powershell
$VerbosePreference = "Continue"
. backup-scheduler.ps1
```

### Common Issues

**1. Task doesn't run**
- Check: `backup-schedule` output
- View Task Scheduler: `taskschd.msc`
- Check logs: `$env:APPDATA\BackupScheduler\logs\`

**2. Backup locked**
- Run: `backup-cancel`
- Check: `Test-Path "$env:APPDATA\BackupScheduler\backup.lock"`

**3. Processes not suspending**
- Verify: `pssuspend.exe` in PATH
- Check: Administrator privileges
- Check logs for specific error

**4. Compression fails**
- Check: Disk space
- Check: File permissions
- Try: Disable compression

---

## Testing Checklist

- [ ] Installation completes without errors
- [ ] Functions load in new PowerShell session
- [ ] Config file created with defaults
- [ ] Manual backup runs (`backup-now`)
- [ ] Task registered in Task Scheduler
- [ ] Idle detection works
- [ ] Process pause/resume works
- [ ] Compression completes
- [ ] Retention policy removes old backups
- [ ] Notifications sent
- [ ] Logs created and formatted correctly
- [ ] State file updated after backup
- [ ] Stale locks removed
- [ ] Backup cancellation works

---

**Version**: 1.0  
**Last Updated**: 2024-03-23  
**Author**: Till Thelet
