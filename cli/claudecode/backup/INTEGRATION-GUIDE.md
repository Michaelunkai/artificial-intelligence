# Dev Environment Backup Integration Guide

**Purpose:** Integrate dev environment backups with the existing Claude Code backup system and broader system maintenance workflows.

---

## 📦 System Architecture

The dev environment backup system operates **INDEPENDENTLY** from the Claude Code backup but can be triggered as part of a broader orchestration:

```
System Backup Flow
├── backup-claudecode.ps1 (Claude Code config + environment)
├── backup-dev-environments.ps1 (Python venvs, Node projects, etc.)
│   ├── Python venvs backup
│   ├── Node projects backup
│   ├── Git metadata backup
│   └── Tool configs backup
├── backup-databases.ps1 (Databases and data stores)
├── backup-browser-data.ps1 (Browser profiles and extensions)
└── backup-orchestrator.ps1 (Master coordinator)
```

---

## 🔗 Integration Points

### 1. **Master Backup Orchestrator**

Add dev environment backup to your main backup script:

```powershell
# File: backup-orchestrator.ps1 (or your master backup)

function Invoke-DevEnvironmentBackup {
    param([string]$LogFile)
    
    Write-Status "Starting dev environment backup..." Info
    
    $backupScript = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-dev-environments.ps1"
    $result = & $backupScript -BackupPath "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Write-Status "✓ Dev environment backup completed" Success
        Add-Content -Path $LogFile -Value "✓ Dev environment backup completed"
    }
    else {
        Write-Status "✗ Dev environment backup failed" Error
        Add-Content -Path $LogFile -Value "✗ Dev environment backup failed: $result"
    }
}

# In your main orchestration:
Invoke-DevEnvironmentBackup -LogFile "backup-run-$(Get-Date -Format 'yyyyMMdd').log"
```

### 2. **Scheduled Task Integration**

Add a Windows Task Scheduler entry for daily backups:

```powershell
# Create scheduled task for dev environment backup
$taskName = "DailyDevEnvironmentBackup"
$taskDescription = "Daily backup of Python venvs, Node projects, and tool configs"
$taskPath = "\Claude-Code\"

$action = New-ScheduledTaskAction `
    -Execute "pwsh.exe" `
    -Argument '-ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-dev-environments.ps1"'

$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM

$settings = New-ScheduledTaskSettingsSet `
    -AllowStartIfOnBatteries `
    -DontStopIfGoingOnBatteries `
    -StartWhenAvailable

Register-ScheduledTask `
    -TaskName $taskName `
    -TaskPath $taskPath `
    -Action $action `
    -Trigger $trigger `
    -Settings $settings `
    -Description $taskDescription `
    -Force
```

### 3. **Restore Chain**

Execute restore operations in proper sequence:

```powershell
# Restore in reverse order of backup
function Restore-AllSystems {
    param([string]$BackupDate = "20231215-143022")
    
    $baseBackupPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
    
    # 1. Restore dev environments first
    Write-Host "Step 1: Restoring development environments..."
    & "$baseBackupPath\restore-dev-environments.ps1" `
        -BackupPath "$baseBackupPath\dev-backup-$BackupDate"
    
    # 2. Restore browser data
    Write-Host "Step 2: Restoring browser data..."
    & "$baseBackupPath\restore-browser-data.ps1" `
        -BackupPath "$baseBackupPath\browser-backup-$BackupDate"
    
    # 3. Restore Claude Code
    Write-Host "Step 3: Restoring Claude Code..."
    & "$baseBackupPath\restore-claudecode.ps1" `
        -BackupPath "$baseBackupPath\claudecode-backup-$BackupDate"
    
    # 4. Restore databases
    Write-Host "Step 4: Restoring databases..."
    & "$baseBackupPath\restore-databases.ps1" `
        -BackupPath "$baseBackupPath\databases-backup-$BackupDate"
    
    Write-Host "All restore operations completed!"
}

# Execute:
Restore-AllSystems -BackupDate "20231215-143022"
```

---

## 🔄 Workflow Patterns

### Pattern 1: Daily Backup with Weekly Verification

```powershell
# Script: Daily backup with weekly integrity check

$backupScript = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-dev-environments.ps1"
$restoreScript = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-dev-environments.ps1"

# Run daily backup
& $backupScript

# Every Monday, validate the latest backup
if ((Get-Date).DayOfWeek -eq "Monday") {
    $latestBackup = Get-ChildItem -Path "..." -Filter "dev-backup-*" -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    & $restoreScript -BackupPath $latestBackup.FullName -ValidateOnly
}
```

### Pattern 2: Before Major Updates

```powershell
# Script: Backup before system updates or dependency changes

Write-Host "Backing up development environments before update..."
$timestamp = Get-Date -Format "yyyyMMdd-HHmmss-PRE-UPDATE"

& $backupScript -BackupPath "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"

# Proceed with updates...
npm update
pip install --upgrade -r requirements.txt

# If needed, restore:
if ($updateFailed) {
    Write-Host "Update failed, restoring from pre-update backup..."
    & $restoreScript -BackupPath "..."
}
```

### Pattern 3: Multi-System Sync

```powershell
# Script: Backup on one machine, restore on another

# On primary machine (MACHINE-A):
.\backup-dev-environments.ps1

# On secondary machine (MACHINE-B):
# Copy backup from network share
Copy-Item \\MACHINE-A\backup-share\dev-backup-* -Destination "F:\backups" -Recurse

# Restore on secondary
.\restore-dev-environments.ps1 -BackupPath "F:\backups\dev-backup-20231215-143022"
```

---

## 📊 Monitoring & Logging

### Log File Structure

```powershell
# File: Log all backup/restore operations

$logDir = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\logs"
$logFile = Join-Path $logDir "backup-run-$(Get-Date -Format 'yyyyMMdd').log"

# Start logging
Start-Transcript -Path $logFile -Append

# Run backups
.\backup-dev-environments.ps1

# End logging
Stop-Transcript
```

### Status Dashboard

```powershell
# Script: Quick backup status check

$backupDir = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
$backups = Get-ChildItem -Path $backupDir -Filter "dev-backup-*" -Directory | Sort-Object LastWriteTime -Descending | Select-Object -First 5

Write-Host "Recent Dev Environment Backups:" -ForegroundColor Cyan
foreach ($backup in $backups) {
    $manifest = Get-Content (Join-Path $backup.FullName "MANIFEST.json") -Raw | ConvertFrom-Json
    
    $size = (Get-ChildItem -Path $backup.FullName -Recurse | Measure-Object -Property Length -Sum).Sum / 1GB
    
    Write-Host ""
    Write-Host "  $($backup.Name)"
    Write-Host "    Date: $($manifest.BackupDate)"
    Write-Host "    Size: $([math]::Round($size, 2)) GB"
    Write-Host "    Items: Python=$($manifest.PythonVenvs) Node=$($manifest.NodeProjects) Git=$($manifest.GitRepos) Configs=$($manifest.ToolConfigs)"
    
    # Check if compressed
    if (Test-Path "$($backup.FullName).zip") {
        $zipSize = (Get-Item "$($backup.FullName).zip").Length / 1GB
        Write-Host "    Compressed: $([math]::Round($zipSize, 2)) GB"
    }
}
```

---

## 🔐 Backup Strategy

### Retention Policy

```powershell
# Script: Implement backup retention (keep last 30 days, then one per week)

function Clean-OldBackups {
    param(
        [string]$BackupDir = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup",
        [int]$DaysToKeep = 30
    )
    
    $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
    
    Get-ChildItem -Path $BackupDir -Filter "dev-backup-*" -Directory | Where-Object {
        $_.LastWriteTime -lt $cutoffDate
    } | Remove-Item -Recurse -Force -Confirm:$false
    
    Write-Host "Cleaned backups older than $DaysToKeep days"
}

# Run cleanup
Clean-OldBackups
```

### Backup Compression & Storage

```powershell
# Script: Archive old backups to external storage

function Archive-OldBackups {
    param(
        [string]$ArchivePath = "E:\backup-archive",
        [int]$DaysOld = 60
    )
    
    $cutoffDate = (Get-Date).AddDays(-$DaysOld)
    
    Get-ChildItem -Path $BackupDir -Filter "dev-backup-*.zip" | Where-Object {
        $_.LastWriteTime -lt $cutoffDate
    } | ForEach-Object {
        Copy-Item -Path $_.FullName -Destination $ArchivePath -Force
        Write-Host "Archived: $($_.Name)"
    }
}
```

---

## ⚡ Performance Optimization

### Incremental Backups

For faster backups of large Node projects, consider incremental approach:

```powershell
# Backup only changed package-lock.json files
$lastBackupTime = (Get-Item "...\dev-backup-latest").LastWriteTime

Get-ChildItem -Path "F:\study" -Recurse -Filter "package-lock.json" | Where-Object {
    $_.LastWriteTime -gt $lastBackupTime
} | ForEach-Object {
    # Backup this project...
}
```

### Parallel Backup Processing

For faster backups with many Node projects:

```powershell
# Process multiple projects in parallel (max 4 at a time)
Get-ChildItem -Path "F:\study" -Recurse -Filter "package.json" | ForEach-Object -Parallel {
    # Backup project...
} -ThrottleLimit 4
```

---

## 🧪 Testing Restore

### Validation Checklist

Before relying on backups, verify:

```powershell
# 1. Run validation
.\restore-dev-environments.ps1 -BackupPath "..." -ValidateOnly

# 2. Check manifest
Get-Content "...\MANIFEST.json"

# 3. Spot-check backup contents
Get-ChildItem -Path "...\python-venvs" -Recurse | head -20
Get-ChildItem -Path "...\node-projects" -Recurse -Filter "package.json" | head -10

# 4. Test restore on non-critical system first
# 5. Verify restored projects are accessible
Test-Path "F:\study\...\restored-project"
```

---

## 📋 Checklist: Setup Integration

- [ ] Copy backup and restore scripts to `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\`
- [ ] Review and adapt scripts for your specific projects
- [ ] Test backup: `.\backup-dev-environments.ps1`
- [ ] Test validation: `.\restore-dev-environments.ps1 -BackupPath "..." -ValidateOnly`
- [ ] Set up Windows scheduled task for daily backup
- [ ] Create cleanup/archival scripts
- [ ] Document backup retention policy
- [ ] Test restore on non-production system
- [ ] Add to main backup orchestrator
- [ ] Set up backup monitoring/logging
- [ ] Train team on restore procedures

---

## 📞 Troubleshooting

### Backup fails with "permission denied"
- Close all IDEs, terminals, and npm processes
- Check file locks: `Get-ChildItem ... | Where-Object { (Get-FileHash).Hash } 2>&1`
- Run as Administrator if needed

### Restore takes too long
- Skip NodeModules: `.\restore-dev-environments.ps1 -SkipNodeModules`
- Run in parallel if you have multiple machines
- Use `-SkipVenvRecreate` for faster restore

### Backup size is too large
- `node_modules` are NOT included by default
- `package-lock.json` can be 5-50 MB per project
- Consider archiving to external storage after 30 days

### Manifest is missing
- Backup may be corrupted or incomplete
- Re-run backup: `.\backup-dev-environments.ps1`
- Use `-ValidateOnly` to verify before restore

---

**Version:** 1.0  
**Last Updated:** 2026-03-23  
**Status:** Production Ready
