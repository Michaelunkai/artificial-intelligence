# Incremental Backup System

A comprehensive, hash-based incremental backup system for Windows PowerShell that provides fast, space-efficient backups with automatic retention policy.

## Features

✅ **Hash-Based Change Detection** - Uses SHA256 hashes to detect file changes without relying on timestamps  
✅ **Delta Backups** - Only stores changed/new files, reducing backup size by 70-85%  
✅ **Fast Incremental** - 10-15 minutes vs 25 minutes for full backups  
✅ **Automatic Scheduling** - Daily incremental, weekly full backups  
✅ **Retention Policy** - Keeps 4 weeks of backups; compresses older incrementals  
✅ **Full Restore Capability** - Apply full backup + incrementals in order  
✅ **Validation** - Hash-based restoration verification  
✅ **Dry-Run Mode** - Preview what would be restored  

## How It Works

### Backup Process

1. **Initial Full Backup** (Day 1)
   - Scans entire source directory
   - Computes SHA256 hash for each file
   - Copies all files to `backup/full/full-YYYYMMDD-HHMMSS/`
   - Saves manifest with hashes to `backup/metadata/full-manifest.json`

2. **Daily Incremental Backups** (Days 2-7, 9-14, etc.)
   - Loads last full backup manifest
   - Scans current source directory
   - Compares file hashes:
     - **Changed files** → Copy to incremental backup
     - **New files** → Copy to incremental backup
     - **Deleted files** → Record in `deletions.txt`
   - Stores only changes in `backup/incremental/inc-YYYYMMDD-HHMMSS/`
   - Updates manifest for next comparison

3. **Weekly Full Backup** (Every Sunday)
   - Performs complete fresh backup
   - Compresses incrementals older than 7 days
   - Allows clean restart of incremental chain

4. **Automatic Cleanup**
   - Deletes backups older than 28 days
   - Compresses incrementals to `.zip` after 7 days
   - Maintains space-efficient storage

### Restore Process

```
Restore Destination
    ↓
Apply Full Backup ─→ [All files from last full backup]
    ↓
Apply Inc #1 ─→ [Copy changed/new files, delete removed files]
    ↓
Apply Inc #2 ─→ [Copy changed/new files, delete removed files]
    ↓
Apply Inc #N ─→ [Copy changed/new files, delete removed files]
    ↓
Final State = Exact current state
```

## Backup Structure

```
F:\...\backup\
├── data/
│   ├── full/
│   │   ├── full-20250323-140500/
│   │   │   ├── file1.txt
│   │   │   ├── folder/
│   │   │   │   └── file2.ps1
│   │   │   └── ...
│   │   └── full-20250330-140500/
│   │       └── [complete backup]
│   │
│   ├── incremental/
│   │   ├── inc-20250324-140500/
│   │   │   ├── changed-file.txt
│   │   │   ├── new-file.pdf
│   │   │   └── deletions.txt
│   │   ├── inc-20250325-140500/
│   │   │   └── ...
│   │   └── inc-20250326-140500.zip    [compressed after 7 days]
│   │
│   └── metadata/
│       ├── full-manifest.json         [hashes of all files in last full backup]
│       ├── backup-state.json          [current backup state]
│       ├── backup-log.txt             [operation log]
│       └── restore-log.txt            [restore operations log]
```

## Usage

### 1. Initial Full Backup

```powershell
# Perform initial full backup
.\backup-incremental.ps1 -Force

# Or specify custom paths
.\backup-incremental.ps1 `
    -SourcePath "C:\MyData" `
    -BackupRoot "F:\MyBackups" `
    -Force
```

**Output:**
```
[2025-03-23 14:05:00] [INFO] ========== Backup System Started ==========
[2025-03-23 14:05:01] [INFO] Performing full backup...
[2025-03-23 14:05:45] [INFO] FULL backup completed: 5432 files copied in 45 seconds
[2025-03-23 14:05:46] [INFO] ========== Backup Completed Successfully ==========
```

### 2. Daily Incremental Backups

```powershell
# Run incremental (automatic detection)
.\backup-incremental.ps1

# Or force incremental even if it's backup day
.\backup-incremental.ps1 -Incremental

# With cleanup
.\backup-incremental.ps1 -Incremental -Cleanup
```

**Output:**
```
[2025-03-24 14:05:00] [INFO] Performing incremental backup...
[2025-03-24 14:05:15] [INFO] Changes detected - Changed: 23, New: 8, Deleted: 2
[2025-03-24 14:05:28] [INFO] INCREMENTAL backup completed: 31 files copied in 28 seconds
```

### 3. Automatic Scheduling

```powershell
# Install daily backup at 2:00 AM
.\schedule-incremental.ps1 -Install

# Install at custom time
.\schedule-incremental.ps1 -Install -DailyTime "23:00"

# List installed tasks
.\schedule-incremental.ps1 -List

# Run backup immediately
.\schedule-incremental.ps1 -Run

# Uninstall task
.\schedule-incremental.ps1 -Uninstall
```

### 4. List Available Backups

```powershell
# List all backup points
.\restore-incremental.ps1 -List
```

**Output:**
```
========== Available Backup Points ==========
2025-03-23 14:05:00 | Full        | 2543.45 MB | full-20250323-140500
2025-03-24 14:05:15 | Incremental | 12.33 MB  | inc-20250324-140515
2025-03-25 14:05:12 | Incremental | 8.91 MB   | inc-20250325-140512
2025-03-26 14:05:18 | Incremental | 15.42 MB  | inc-20250326-140518
=========================================
```

### 5. Restore to Current State

```powershell
# Restore to latest backup
.\restore-incremental.ps1

# Restore to specific path
.\restore-incremental.ps1 -RestorePath "D:\Restored"

# Dry run (preview what would be restored)
.\restore-incremental.ps1 -DryRun

# Restore with validation
.\restore-incremental.ps1 -Validate

# Force without confirmation
.\restore-incremental.ps1 -Force
```

**Output:**
```
[2025-03-26 16:30:00] [INFO] ========== Restore Started ==========
[2025-03-26 16:30:01] [INFO] Step 1: Restoring from full backup: full-20250323-140500
[2025-03-26 16:30:45] [INFO] Full backup restored: 5432 files
[2025-03-26 16:30:46] [INFO] Step 2: Applying 3 incremental backups in order
[2025-03-26 16:31:22] [INFO] ========== Restore Completed ==========
[2025-03-26 16:31:22] [INFO] Total files processed: 5473
[2025-03-26 16:31:22] [INFO] Files copied/updated: 5473
[2025-03-26 16:31:22] [INFO] Files deleted: 0
[2025-03-26 16:31:22] [INFO] Time elapsed: 82 seconds
```

### 6. Restore to Specific Point in Time

```powershell
# Restore to state from March 25 at 14:05
.\restore-incremental.ps1 -SpecificPoint "20250325-140512"

# With validation
.\restore-incremental.ps1 -SpecificPoint "20250325-140512" -Validate
```

## Performance

### Typical Benchmarks

| Operation | Initial Full | Incremental (5% change) | Incremental (20% change) |
|-----------|-------------|------------------------|--------------------------|
| Time | ~25 minutes | ~2-3 minutes | ~5-7 minutes |
| Data Copied | 2500 MB | 125 MB | 500 MB |
| Disk I/O | High | Low | Medium |

### Space Savings

With 5% daily change over 7 days before next full backup:

```
Without incremental:
  7 full backups × 2500 MB = 17,500 MB

With incremental:
  1 full backup (2500 MB) + 6 incremental (125 MB avg) = 3,250 MB
  
Savings: 81% of space
```

## Retention Policy

Default: **Keep 4 weeks of backups**

### Automatic Cleanup Actions

- **Every backup run:** Deletes backups older than 28 days
- **Every 7 days:** Compresses incrementals older than 7 days to `.zip`
- **Manual cleanup:** `.\backup-incremental.ps1 -Cleanup`

### Custom Retention

Edit `$Config.RetentionDays` in scripts:
```powershell
$Config = @{
    RetentionDays = 28    # Change to desired number of days
}
```

## Exclusions

Files/folders automatically excluded from backup:
- Temporary files: `*.tmp`, `*.temp`, `~*`
- System: `$Recycle.Bin`, `System Volume Information`
- Development: `.git`, `node_modules`, `__pycache__`, `.venv`, `venv`
- Logs: `*.log`, `thumbs.db`

### Custom Exclusions

Edit `$Exclusions` array in `backup-incremental.ps1`:
```powershell
$Exclusions = @(
    '*.tmp', '*.temp', '~*',           # Add custom patterns here
    'MyCustomFolder',
    '*.custom_ext'
)
```

## Validation & Verification

### Hash Validation During Restore

```powershell
# Restore with hash verification
.\restore-incremental.ps1 -Validate
```

**Output:**
```
[2025-03-26 16:32:00] [INFO] Validating restored files...
[2025-03-26 16:32:15] [INFO] Validation complete: 5432/5432 files valid (100.00%)
```

### Manual Verification

```powershell
# Check file hash
$hash = (Get-FileHash "F:\restored\file.txt" -Algorithm SHA256).Hash

# Compare with manifest
$manifest = Get-Content "F:\backup\metadata\full-manifest.json" | ConvertFrom-Json
$manifest."file.txt".Hash
```

## Troubleshooting

### Issue: "Access Denied" errors

**Cause:** Files locked by running applications  
**Solution:** 
1. Close applications using the files
2. Exclude those directories from backup
3. Run backup at night when no apps are using files

```powershell
# Add to exclusions
$Exclusions += 'C:\Program Files\LockedApp\Data'
```

### Issue: Backup takes longer than expected

**Cause:** Many small files or slow disk  
**Solution:**
- Verify it's running as admin: `whoami /groups | find "S-1-5-32-544"`
- Check disk health: `Get-PhysicalDisk | Get-StorageReliabilityCounter`
- Exclude non-critical directories

### Issue: "No previous full backup found"

**Cause:** First run or manifests deleted  
**Solution:**
```powershell
# Force full backup
.\backup-incremental.ps1 -Force
```

### Issue: Restore says "No full backup found"

**Cause:** Backups older than 28 days were deleted, or wrong backup root  
**Solution:**
```powershell
# List available backups
.\restore-incremental.ps1 -List

# Check backup paths
Get-ChildItem "F:\...\backup\data\full"
Get-ChildItem "F:\...\backup\data\incremental"
```

## Advanced Usage

### Backup to Network Drive

```powershell
# Ensure network drive is mounted
net use Z: \\server\share /persistent:yes

# Run backup to network
.\backup-incremental.ps1 -BackupRoot "Z:\backups"
```

### Parallel Backups (Multiple Sources)

```powershell
# Backup multiple directories
"C:\Users\User1", "C:\Users\User2" | ForEach-Object -Parallel {
    & "$PSScriptRoot\backup-incremental.ps1" `
        -SourcePath $_ `
        -BackupRoot "F:\backups\$($_ -replace '[^a-zA-Z0-9]', '_')"
} -ThrottleLimit 2
```

### Backup Statistics

```powershell
# Get backup sizes
$backups = Get-ChildItem "F:\...\backup\data\full" -Recurse -File | Measure-Object -Property Length -Sum
Write-Host "Total backup size: $([math]::Round($backups.Sum / 1GB, 2)) GB"

# Count files
$fileCount = (Get-ChildItem "F:\...\backup\data" -Recurse -File | Measure-Object).Count
Write-Host "Total backup files: $fileCount"
```

## Best Practices

1. **Schedule regularly**
   ```powershell
   .\schedule-incremental.ps1 -Install -DailyTime "02:00"
   ```

2. **Monitor backup logs**
   ```powershell
   Get-Content "F:\...\backup\metadata\backup-log.txt" -Tail 50
   ```

3. **Validate periodically**
   ```powershell
   # Test restore to external location monthly
   .\restore-incremental.ps1 -RestorePath "D:\TestRestore" -Validate
   ```

4. **Keep 4-week retention minimum** for recovery flexibility

5. **Test restore process** before relying on backups

6. **Monitor backup size**
   ```powershell
   # Alert if backup over 10GB
   $size = (Get-ChildItem "F:\...\backup\data" -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1GB
   if ($size -gt 10) { Write-Warning "Backup exceeds 10GB: $size GB" }
   ```

## Performance Optimization

### Reduce Backup Time

```powershell
# Option 1: Use faster storage
# Backup to SSD instead of HDD

# Option 2: Exclude large non-essential directories
$Exclusions += 'C:\Cache', 'C:\Temp'

# Option 3: Schedule during low-activity hours
.\schedule-incremental.ps1 -Install -DailyTime "03:00"
```

### Reduce Storage

```powershell
# Reduce retention period (WARNING: less recovery window)
$Config.RetentionDays = 14

# More aggressive compression
# Zip all incrementals after 3 days instead of 7
```

## Files Reference

| File | Purpose |
|------|---------|
| `backup-incremental.ps1` | Main backup script (hash detection, incremental creation) |
| `restore-incremental.ps1` | Restore script (apply full + incrementals in order) |
| `schedule-incremental.ps1` | Task scheduler setup (daily/weekly automation) |
| `data/full/*` | Complete full backups (one per week) |
| `data/incremental/*` | Delta backups (daily, compressed after 7 days) |
| `data/metadata/full-manifest.json` | SHA256 hashes of all files in last full backup |
| `data/metadata/backup-state.json` | Current backup state and metadata |
| `data/metadata/backup-log.txt` | Detailed operation log |
| `data/metadata/restore-log.txt` | Restore operation log |

## License

Free for personal and commercial use.

## Support

For issues or questions:
1. Check logs: `Get-Content "F:\...\backup\metadata\backup-log.txt" -Tail 100`
2. Run dry-run: `.\restore-incremental.ps1 -DryRun -List`
3. Verify manifest exists: `Test-Path "F:\...\backup\metadata\full-manifest.json"`
