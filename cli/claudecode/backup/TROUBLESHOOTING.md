# Claude Code + OpenClaw Backup System — TROUBLESHOOTING GUIDE

**Version:** 21.0 LEAN BLITZ  
**Last Updated:** 2026-03-23

---

## Quick Diagnostic Checklist

When something goes wrong:

1. **Check BACKUP-METADATA.json**
   ```powershell
   $meta = Get-Content "F:\backup\claudecode\backup_xxx\BACKUP-METADATA.json" | ConvertFrom-Json
   Write-Host "Items: $($meta.Items)"
   Write-Host "Size: $($meta.SizeMB) MB"
   Write-Host "Errors: $($meta.Errors.Count)"
   if ($meta.Errors.Count -gt 0) { $meta.Errors | Select-Object -First 5 }
   ```

2. **Check backup size (should be 2.5-3.5 GB)**
   ```powershell
   $size = (Get-ChildItem "F:\backup\claudecode\backup_xxx" -Recurse -File | Measure-Object -Property Length -Sum).Sum
   Write-Host "Total: $([math]::Round($size / 1GB, 2)) GB"
   ```

3. **Check for critical files**
   ```powershell
   $backup = "F:\backup\claudecode\backup_xxx"
   Test-Path "$backup\core\claude-home\.claude.json"
   Test-Path "$backup\openclaw\workspace-moltbot2"
   ```

4. **Check available disk space**
   ```powershell
   Get-Volume -DriveLetter F | Select-Object @{N='Free(GB)';E={[math]::Round($_.SizeRemaining/1GB,2)}}
   ```

---

## Common Errors & Solutions

### Error: "TIMEOUT: /path/to/file"

**Message:** Some backup tasks report `[TIMEOUT]` in output.

**Root Causes:**
1. File is locked by running process
2. System is under heavy load
3. Antivirus is scanning
4. Network drive disconnected
5. Disk is very slow

**Solutions (in order of likelihood):**

#### 1. Close running processes
```powershell
# Stop Claude
Get-Process claude -ErrorAction SilentlyContinue | Stop-Process -Force

# Stop Node.js servers
Get-Process node -ErrorAction SilentlyContinue | Stop-Process -Force

# Stop anything using .claude or .openclaw
Get-Process | Where-Object { 
    $_.Modules | Where-Object { $_.FileName -match "\.claude|\.openclaw" } 
} | Stop-Process -Force
```

#### 2. Disable/pause antivirus
```powershell
# Temporarily disable Windows Defender
Set-MpPreference -DisableRealtimeMonitoring $true

# Run backup
powershell -File "backup-claudecode.ps1"

# Re-enable
Set-MpPreference -DisableRealtimeMonitoring $false
```

#### 3. Increase per-task timeout
Edit `backup-claudecode.ps1`:
```powershell
# Find lines like:
Add-Task "$HP\.claude" ... -T 120   # 120 = 2 minutes

# Change to:
Add-Task "$HP\.claude" ... -T 300   # 300 = 5 minutes
```

#### 4. Reduce parallel threads
```powershell
powershell -File "backup-claudecode.ps1" -MaxJobs 8
# Lower number = less I/O contention = more reliable
```

#### 5. Check disk health
```powershell
# Test disk
CHKDSK F: /F /R

# Check SMART status
Get-PhysicalDisk | Select-Object FriendlyName,HealthStatus,OperationalStatus

# Run disk stress test
# Download: https://www.seagate.com/support/downloads/seatools/
```

**What if timeouts persist?**

The timeout files are usually not critical (mostly logs, caches, temp):
```powershell
# Get list of timed-out files
$backup = "F:\backup\claudecode\backup_xxx"
$meta = Get-Content "$backup\BACKUP-METADATA.json" | ConvertFrom-Json
$meta.Errors | Where-Object { $_ -match "TIMEOUT" }

# These are likely: .openclaw\logs, .claude\file-history, etc.
# Safe to ignore if < 10 timeouts
```

---

### Error: "FAIL: /path/to/file - access denied"

**Message:** `[FAIL] /some/path - access denied`

**Root Causes:**
1. File requires elevated permissions
2. File is protected by Windows
3. Antivirus is blocking access
4. ACLs are restrictive

**Solutions:**

#### 1. Run as Administrator
```powershell
# Right-click PowerShell → "Run as administrator"
Start-Process powershell -ArgumentList @(
    '-NoProfile'
    '-ExecutionPolicy Bypass'
    '-File "F:\study\AI_ML\...\backup-claudecode.ps1"'
) -Verb RunAs
```

#### 2. Fix file permissions
```powershell
# Grant yourself permission to the file
$file = "C:\path\to\restricted\file"
$acl = Get-Acl $file
$rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
    "$env:USERNAME",
    "ReadAndExecute",
    "Allow"
)
$acl.SetAccessRule($rule)
Set-Acl -Path $file -AclObject $acl
```

#### 3. Disable antivirus
```powershell
# Temporarily disable Windows Defender
Set-MpPreference -DisableRealtimeMonitoring $true
powershell -File "backup-claudecode.ps1"
Set-MpPreference -DisableRealtimeMonitoring $false
```

#### 4. Exclude the problematic file
Edit `backup-claudecode.ps1`:
```powershell
# In the exclusion lists, add the file/directory
$claudeExcludeDirs = @(
    'file-history',
    'cache',
    'my-problem-folder'     # ← Add here
)
```

**Are these failures critical?**

Check what failed:
```powershell
$meta = Get-Content "$backup\BACKUP-METADATA.json" | ConvertFrom-Json
$meta.Errors
```

Most are non-critical (permissions on log files, caches, etc.). If they're in core areas (`.claude.json`, OpenClaw workspace), then you need to fix them.

---

### Error: "PowerShell terminated unexpectedly"

**Message:** Backup stops without completion message.

**Root Causes:**
1. Out of memory
2. System ran out of disk space
3. PowerShell crashed
4. Process killed by system

**Solutions:**

#### 1. Check available disk space
```powershell
Get-Volume -DriveLetter F | Select-Object @{
    N='Available(GB)';
    E={[math]::Round($_.SizeRemaining/1GB,2)}
}

# Need at least 5 GB free for backup
# If < 5 GB, delete old backups or clean up
```

#### 2. Check available memory
```powershell
$memory = Get-WmiObject -Class Win32_ComputerSystem
$usedMem = $memory.TotalPhysicalMemory - $memory.FreePhysicalMemory
$usedMem = [math]::Round($usedMem / 1GB, 2)
$totalMem = [math]::Round($memory.TotalPhysicalMemory / 1GB, 2)

Write-Host "Memory used: $usedMem GB / $totalMem GB"

# If > 90% used, close applications and retry
```

#### 3. Reduce parallel threads (uses less memory)
```powershell
powershell -File "backup-claudecode.ps1" -MaxJobs 8
```

#### 4. Increase virtual memory
```powershell
# Windows will use disk if RAM is full (slow but works)
# Edit System Properties → Advanced → Virtual Memory
# Increase to 4-8 GB
```

#### 5. Check Event Viewer for crash details
```powershell
# Open Event Viewer
eventvwr.msc

# Look in: Windows Logs → System
# Find errors with timestamp matching backup time
```

---

### Error: "The system cannot find the path specified"

**Message:** `[FAIL] /path - The system cannot find the path specified`

**Root Causes:**
1. Path contains invalid characters (? * " < > |)
2. Path is longer than 260 characters (Windows limit)
3. Network path is unavailable
4. Drive is disconnected

**Solutions:**

#### 1. Check path length
```powershell
# Find paths > 260 characters
Get-ChildItem -Path "C:\Users" -Recurse -ErrorAction SilentlyContinue | 
    Where-Object { $_.FullName.Length -gt 260 } |
    Select-Object FullName, @{N='Length';E={$_.FullName.Length}}
```

If you find long paths:
```powershell
# Create shorter symlink
New-Item -ItemType SymbolicLink -Path "C:\short-path" -Target "C:\very\long\path\to\something"

# Edit backup script to use the symlink instead
```

#### 2. Check network connectivity
```powershell
# If backing up to network drive
Test-Connection -ComputerName "192.168.1.100" -Count 1

# If unavailable, back up locally instead
powershell -File "backup-claudecode.ps1" -BackupPath "F:\local-backup"
```

#### 3. Map network drive explicitly
```powershell
New-PSDrive -Name Z -PSProvider FileSystem -Root "\\server\share" -Persist
powershell -File "backup-claudecode.ps1" -BackupPath "Z:\backup"
```

---

### Backup Completes But Files Are Missing

**Symptom:** Backup finishes, but you're missing some directories (`.claude`, OpenClaw, etc.)

**Root Causes:**
1. Directory was being modified during backup
2. Directory didn't exist at backup time
3. Permissions prevent copying
4. Task was skipped (directory not found check)

**Solutions:**

#### 1. Check if directory existed at backup time
```powershell
# Check BACKUP-METADATA.json
$meta = Get-Content "$backup\BACKUP-METADATA.json" | ConvertFrom-Json
Write-Host "Backup timestamp: $($meta.Timestamp)"

# Check if your target directory existed then
Test-Path "$env:USERPROFILE\.claude"
```

#### 2. Manually copy missing directory
```powershell
# If .claude is missing:
$backup = "F:\backup\claudecode\backup_xxx"
robocopy "$backup\core\claude-home" "$env:USERPROFILE\.claude" /E /R:3 /W:1 /MT:32
```

#### 3. Check file count
```powershell
# Expected item counts
$backup = "F:\backup\claudecode\backup_xxx"
$meta = Get-Content "$backup\BACKUP-METADATA.json" | ConvertFrom-Json

Write-Host "Items in backup: $($meta.Items)"  # Should be 13,000-15,000

# Count actual files
$actual = @(Get-ChildItem $backup -Recurse -File).Count
Write-Host "Actual files: $actual"

# If mismatch > 5%, something went wrong
```

---

### Restore Fails With "Source and Destination Are Different"

**Message:** During restore, RoboCopy reports "source and destination are different"

**Root Causes:**
1. Trying to merge different directory structures
2. Files changed since backup
3. RoboCopy cache conflicts

**Solutions:**

#### 1. Use `/PURGE` to force overwrite
```powershell
$backup = "F:\backup\claudecode\backup_xxx"
robocopy "$backup\core\claude-home" "$env:USERPROFILE\.claude" /E /PURGE /R:3 /W:1 /MT:32
# /PURGE = delete destination files not in source
```

#### 2. Delete destination first
```powershell
# Save current state first
Copy-Item "$env:USERPROFILE\.claude" "$env:USERPROFILE\.claude.before-restore" -Recurse -Force

# Delete everything
Remove-Item "$env:USERPROFILE\.claude" -Recurse -Force

# Restore clean
$backup = "F:\backup\claudecode\backup_xxx"
robocopy "$backup\core\claude-home" "$env:USERPROFILE\.claude" /E /R:3 /W:1 /MT:32
```

#### 3. Close all running processes first
```powershell
# Stop Claude and OpenClaw
Get-Process claude -ErrorAction SilentlyContinue | Stop-Process -Force
Get-Process gateway -ErrorAction SilentlyContinue | Stop-Process -Force

# Wait for file locks to release
Start-Sleep -Seconds 3

# Then restore
```

---

### Restore Succeeds But Settings Don't Take Effect

**Symptom:** Restored settings don't appear in Claude/OpenClaw after restart.

**Root Causes:**
1. Processes cached old settings in memory
2. Application state file has locks
3. Restored files are corrupt
4. Wrong files were restored

**Solutions:**

#### 1. Force complete restart of all services
```powershell
# Kill ALL claude/openclaw related processes
Get-Process | Where-Object {
    $_.ProcessName -match "claude|openclaw|gateway|node" `
        -or $_.Modules.FileName -match "\.claude|\.openclaw"
} | Stop-Process -Force

# Wait for processes to fully exit
Start-Sleep -Seconds 5

# Restart
openclaw gateway restart
```

#### 2. Clear application cache
```powershell
# Claude cache
Remove-Item "$env:USERPROFILE\.claude\cache" -Recurse -Force

# OpenClaw cache
Remove-Item "$env:USERPROFILE\.openclaw\logs" -Recurse -Force

# Restart
```

#### 3. Verify restored files are present
```powershell
# Check critical files exist
$requiredFiles = @(
    "$env:USERPROFILE\.claude\.claude.json",
    "$env:USERPROFILE\.openclaw\workspace-moltbot2\SOUL.md",
    "$env:APPDATA\Claude\claude_desktop_config.json"
)

foreach ($file in $requiredFiles) {
    $exists = Test-Path $file
    Write-Host "$file: $exists" -ForegroundColor $(if($exists){'Green'}else{'Red'})
}
```

#### 4. Restore from older backup if current backup is corrupt
```powershell
# List available backups
Get-ChildItem "F:\backup\claudecode" -Directory -Filter "backup_*" | 
    Sort-Object Name -Descending | 
    Select-Object -First 5

# Restore from older backup
robocopy "F:\backup\claudecode\backup_2026_03_20_02_00_15" "$env:USERPROFILE\.claude" /E /PURGE /R:3 /W:1
```

---

## Incomplete/Corrupt Backups

### Backup Interrupted Midway

**Symptom:** Backup folder exists but BACKUP-METADATA.json is missing or incomplete.

**Recovery Steps:**

#### 1. Check what exists
```powershell
$backup = "F:\backup\claudecode\incomplete-backup"
Get-ChildItem $backup -Directory | Select-Object Name

# Check if metadata exists
Test-Path "$backup\BACKUP-METADATA.json"
```

#### 2. Verify core directories
```powershell
# Check if critical dirs are complete
$critical = @('core\claude-home', 'openclaw\workspace-moltbot2', 'credentials')

foreach ($dir in $critical) {
    $fullPath = "$backup\$dir"
    $fileCount = @(Get-ChildItem $fullPath -Recurse -File -ErrorAction SilentlyContinue).Count
    Write-Host "$dir: $fileCount files" -ForegroundColor $(if($fileCount -gt 100){'Green'}else{'Yellow'})
}
```

#### 3. If backup is mostly complete, use it
```powershell
# If core directories have files, restore from incomplete backup
$backup = "F:\backup\claudecode\incomplete-backup"
robocopy "$backup\core\claude-home" "$env:USERPROFILE\.claude" /E /R:3 /W:1
```

#### 4. If backup is corrupt, delete and re-run
```powershell
# Delete incomplete backup
Remove-Item "F:\backup\claudecode\incomplete-backup" -Recurse -Force

# Start fresh backup
powershell -File "backup-claudecode.ps1" -MaxJobs 8  # Reduced threads for stability
```

---

### Files Are Corrupted After Restore

**Symptom:** Restored files open with errors (corrupted JSON, unreadable files).

**Root Causes:**
1. File was partially copied (incomplete transfer)
2. Backup storage failure (bad sectors)
3. Antivirus corrupted file during backup/restore

**Verification:**

#### 1. Check JSON files
```powershell
# Validate JSON files
$jsonFiles = Get-ChildItem "F:\backup\claudecode\backup_xxx\credentials" -Filter "*.json" -Recurse

foreach ($file in $jsonFiles) {
    try {
        $content = Get-Content $file -Raw | ConvertFrom-Json
        Write-Host "✓ $($file.Name)" -ForegroundColor Green
    } catch {
        Write-Host "✗ $($file.Name) - CORRUPT" -ForegroundColor Red
    }
}
```

#### 2. Check file integrity with checksums
```powershell
# Generate checksums during backup
Get-ChildItem "F:\backup\claudecode\backup_xxx" -Recurse -File | 
    ForEach-Object {
        $hash = Get-FileHash $_.FullName -Algorithm SHA256
        "$($hash.Hash)  $($_.FullName)" 
    } | Out-File "F:\backup\claudecode\backup_xxx\CHECKSUMS.txt"

# Later, verify checksums
(Get-Content "F:\backup\claudecode\backup_xxx\CHECKSUMS.txt") | 
    ForEach-Object {
        $hash, $path = $_ -split '  ', 2
        $actual = (Get-FileHash $path -Algorithm SHA256).Hash
        if ($actual -ne $hash) {
            Write-Host "✗ CORRUPT: $path" -ForegroundColor Red
        }
    }
```

#### 3. If backup is corrupt
```powershell
# Check backup storage for bad sectors
CHKDSK F: /V /F /R

# If errors found, backup to different drive
powershell -File "backup-claudecode.ps1" -BackupPath "D:\backup"
```

#### 4. Restore from previous backup
```powershell
# Use older backup that's still good
robocopy "F:\backup\claudecode\backup_2026_03_20_02_00_15" "$env:USERPROFILE\.claude" /E /R:3 /W:1
```

---

## Backup Verification

### Full Backup Health Check

```powershell
function Test-BackupHealth {
    param([string]$BackupPath)
    
    Write-Host "Testing backup: $BackupPath" -ForegroundColor Cyan
    
    # 1. Check metadata
    $metaPath = "$BackupPath\BACKUP-METADATA.json"
    if (-not (Test-Path $metaPath)) {
        Write-Host "✗ BACKUP-METADATA.json missing" -ForegroundColor Red
        return $false
    }
    
    $meta = Get-Content $metaPath | ConvertFrom-Json
    Write-Host "✓ Metadata found"
    Write-Host "  Items: $($meta.Items)"
    Write-Host "  Size: $($meta.SizeMB) MB"
    Write-Host "  Errors: $($meta.Errors.Count)"
    
    # 2. Check critical directories
    $critical = @(
        'core\claude-home',
        'openclaw\workspace-moltbot2',
        'appdata\roaming-claude',
        'credentials'
    )
    
    $allGood = $true
    foreach ($dir in $critical) {
        $fullPath = "$BackupPath\$dir"
        if (Test-Path $fullPath) {
            $fileCount = @(Get-ChildItem $fullPath -Recurse -File).Count
            Write-Host "✓ $dir ($fileCount files)" -ForegroundColor Green
        } else {
            Write-Host "✗ $dir missing" -ForegroundColor Red
            $allGood = $false
        }
    }
    
    # 3. Check file count vs metadata
    $actualCount = @(Get-ChildItem $BackupPath -Recurse -File).Count
    $variance = [math]::Abs($actualCount - $meta.Items) / $meta.Items * 100
    
    if ($variance -lt 5) {
        Write-Host "✓ File count matches ($actualCount)" -ForegroundColor Green
    } else {
        Write-Host "⚠ File count mismatch: $actualCount actual vs $($meta.Items) expected ($variance%)" -ForegroundColor Yellow
    }
    
    # 4. Check size
    $actualSize = (Get-ChildItem $BackupPath -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
    $sizeVariance = [math]::Abs($actualSize - $meta.SizeMB) / $meta.SizeMB * 100
    
    if ($sizeVariance -lt 5) {
        Write-Host "✓ Size matches ($([math]::Round($actualSize, 2)) MB)" -ForegroundColor Green
    } else {
        Write-Host "⚠ Size mismatch: $([math]::Round($actualSize, 2)) MB actual vs $($meta.SizeMB) expected" -ForegroundColor Yellow
    }
    
    # 5. Validate JSON files
    $jsonFiles = @(Get-ChildItem $BackupPath -Include "*.json" -Recurse)
    $jsonGood = 0
    
    foreach ($file in $jsonFiles) {
        try {
            Get-Content $file -Raw | ConvertFrom-Json | Out-Null
            $jsonGood++
        } catch {
            Write-Host "✗ Corrupt JSON: $($file.Name)" -ForegroundColor Red
            $allGood = $false
        }
    }
    
    Write-Host "✓ JSON validation: $jsonGood/$($jsonFiles.Count) valid" -ForegroundColor Green
    
    # 6. Summary
    Write-Host ""
    if ($allGood -and $variance -lt 5 -and $sizeVariance -lt 5) {
        Write-Host "✓ Backup is HEALTHY" -ForegroundColor Green
        return $true
    } else {
        Write-Host "⚠ Backup has issues (see above)" -ForegroundColor Yellow
        return $false
    }
}

# Usage:
Test-BackupHealth "F:\backup\claudecode\backup_2026_03_23_14_30_15"
```

---

## Recovery from Failed Backups

### Scenario: Backup folder deleted by mistake

```powershell
# Check if it's in Recycle Bin
$recycleBin = @(Get-ChildItem -Path 'C:\$Recycle.Bin' -Force -Recurse | 
    Where-Object { $_.Name -match 'backup_' })[0]

if ($recycleBin) {
    # Restore from Recycle Bin
    Move-Item $recycleBin.FullName "F:\backup\claudecode\$($recycleBin.BaseName)"
    Write-Host "Restored from Recycle Bin"
} else {
    # Try file recovery tool
    # https://www.recuva.com/
    Write-Host "Use Recuva to recover deleted files"
}
```

### Scenario: Only one backup available and it's old

```powershell
# Your options:
# 1. Use old backup (may be missing recent changes)
# 2. Combine old backup + manual recovery

# Start with old backup
$oldBackup = "F:\backup\claudecode\backup_2026_03_15_02_00_10"
robocopy "$oldBackup\core\claude-home" "$env:USERPROFILE\.claude" /E /PURGE /R:3 /W:1

# Then manually check for any newer files not in backup
$claude = "$env:USERPROFILE\.claude"
Get-ChildItem $claude -Recurse -File | 
    Where-Object { $_.LastWriteTime -gt (Get-Date "2026-03-15") } |
    ForEach-Object { Write-Host "Newer file: $($_.Name) - $($_.LastWriteTime)" }
```

### Scenario: Backup storage failed (bad sectors)

```powershell
# Don't try to use corrupted backup
# Instead, try recovery:

# 1. Check disk
CHKDSK F: /V /F /R

# 2. If recovery finds files, copy them out
Get-ChildItem "F:\backup" -Recurse -ErrorAction Continue |
    Copy-Item -Destination "D:\backup-recovery" -Force

# 3. If files are corrupt, try file recovery tool
# https://www.easeus.com/datarecoverywizard/
```

---

## Prevention

### Backup Maintenance Schedule

**Weekly:**
- Run backup with `-Cleanup`
- Verify BACKUP-METADATA.json

**Monthly:**
- Run `Test-BackupHealth` (see above)
- Verify restore process (test on staging if possible)
- Delete backups older than 3 months

**Quarterly:**
- Audit backup storage (check free space)
- Test restore on different machine
- Review error logs

### Automated Health Monitoring

```powershell
# Create PowerShell Scheduled Task to monitor backups
$trigger = New-ScheduledTaskTrigger -Daily -At 3:00AM
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument @(
    '-NoProfile'
    '-File'
    '"C:\scripts\monitor-backups.ps1"'
)

Register-ScheduledTask -TaskName "Monitor Backups" `
    -Trigger $trigger `
    -Action $action `
    -Force
```

**monitor-backups.ps1:**
```powershell
# Check all recent backups
$backups = Get-ChildItem "F:\backup\claudecode" -Directory -Filter "backup_*" | Sort-Object Name -Descending | Select-Object -First 3

$issues = @()

foreach ($backup in $backups) {
    $meta = Get-Content "$($backup.FullName)\BACKUP-METADATA.json" | ConvertFrom-Json -ErrorAction SilentlyContinue
    
    # Check for warnings
    if ($meta.Errors.Count -gt 20) {
        $issues += "⚠ $($backup.Name): $($meta.Errors.Count) errors"
    }
    
    if ($meta.SizeMB -lt 1000) {
        $issues += "⚠ $($backup.Name): Too small ($($meta.SizeMB) MB)"
    }
    
    if ($meta.Duration -gt 600) {
        $issues += "⚠ $($backup.Name): Took too long ($($meta.Duration)s)"
    }
}

# Email if issues found
if ($issues.Count -gt 0) {
    $body = ($issues -join "`n") + "`n`nReview: F:\backup\claudecode"
    Send-MailMessage -To "admin@example.com" -Subject "Backup Issues Detected" -Body $body -SmtpServer "smtp.example.com"
}
```

---

## Getting Help

If you're still having issues:

1. **Check ADMIN_GUIDE.md** for internal architecture
2. **Review USER_GUIDE.md** for common workflows
3. **Post your BACKUP-METADATA.json** with issue report
4. **Enable verbose logging:**
   ```powershell
   $DebugPreference = "Continue"
   powershell -File "backup-claudecode.ps1" -Verbose
   ```

---

**Summary:** Most backup issues are related to file locks, permissions, or disk space. Start with the Quick Diagnostic Checklist, check BACKUP-METADATA.json errors, and follow the specific error solution above. If all else fails, test with a smaller backup scope (just `.claude`) to isolate the problem.
