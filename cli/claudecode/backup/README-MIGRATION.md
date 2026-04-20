# Backup Migration Utility - Guide

## Overview
`migrate-old-backups.ps1` is a comprehensive backup migration tool that:
- 🔍 Detects old backups in `F:\backup\claudecode\`
- 📦 Migrates to new organized structure with semantic versioning
- ✅ Validates backup integrity
- 📊 Creates detailed migration reports
- 🗜️ Optionally compresses and archives old backups
- 🗑️ Optionally deletes old backups after migration

## New Directory Structure
```
F:\study\AI_ML\.../backup/data/
├── v26.03/
│   ├── 2026-03-21/
│   │   └── backup_2026_03_21_21_20_33/
│   └── 2026-03-23/
│       ├── backup_2026_03_23_15_14_51/
│       ├── backup_2026_03_23_15_25_37/
│       └── ...
├── v26.04/ (future versions)
├── index.json (master index of all backups)
└── migrate-report_YYYY-MM-DD_HH-MM-SS.json (migration report)
```

## Semantic Versioning
Backups are versioned as: `vYY.MM.DD-HHMMSS`
- **YY.MM.DD** = Year (2-digit), Month, Day
- **HHMMSS** = Hour, Minute, Second
- Example: `v26.03.23-151451` = March 23, 2026 @ 15:14:51

## Usage

### 1. **VALIDATE FIRST (No-op, Safe)**
```powershell
cd "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\"
powershell -ExecutionPolicy Bypass -File migrate-old-backups.ps1 -ValidateOnly
```
This scans all backups, validates integrity, and generates a report WITHOUT making any changes.

### 2. **MIGRATE BACKUPS (Safe - verifies before deleting)**
```powershell
powershell -ExecutionPolicy Bypass -File migrate-old-backups.ps1
```
- Migrates all valid backups to new structure
- Creates index.json with all backup metadata
- Leaves old backups untouched (in F:\backup\claudecode\)
- Generates JSON report

### 3. **MIGRATE + COMPRESS OLD BACKUPS**
```powershell
powershell -ExecutionPolicy Bypass -File migrate-old-backups.ps1 -CompressArchive
```
- Migrates all backups
- Compresses old backups to `archive_TIMESTAMP.zip`
- Leaves original files intact

### 4. **MIGRATE + DELETE OLD BACKUPS (Full Cleanup)**
```powershell
powershell -ExecutionPolicy Bypass -File migrate-old-backups.ps1 -DeleteAfterMigration
```
- Migrates all backups
- **Deletes** old backups from F:\backup\claudecode\
- Only deletes after successful migration verification
- ⚠️ Be sure validation passed first!

### 5. **MIGRATE + COMPRESS + DELETE (Maximum Cleanup)**
```powershell
powershell -ExecutionPolicy Bypass -File migrate-old-backups.ps1 -CompressArchive -DeleteAfterMigration
```
- Migrates all backups to new structure
- Creates archive of old backups
- Deletes originals after verification
- Saves archive space + organizes backups perfectly

## Parameters

| Parameter | Type | Default | Description |
|-----------|------|---------|-------------|
| `-SourcePath` | String | `F:\backup\claudecode` | Location of old backups |
| `-DestinationPath` | String | Current directory `/data` | New organized backup location |
| `-ValidateOnly` | Switch | Off | Scan without migrating |
| `-DeleteAfterMigration` | Switch | Off | Delete old backups after successful migration |
| `-CompressArchive` | Switch | Off | Compress old backups to .zip archive |
| `-ReportPath` | String | `./migrate-report_TIMESTAMP.json` | Where to save the report |

## Example Workflows

### Scenario A: "Let me preview what will happen"
```powershell
# Step 1: Validate only
.\migrate-old-backups.ps1 -ValidateOnly
# Review the report → migrate-report_*.json
```

### Scenario B: "Migrate to new structure, I'll delete old manually later"
```powershell
# Step 1: Migrate
.\migrate-old-backups.ps1

# Step 2: Check everything looks good
# Review: F:\study\.../backup/data/

# Step 3: Manually delete F:\backup\claudecode\ when ready
Remove-Item F:\backup\claudecode\backup_* -Recurse -Force
```

### Scenario C: "Full cleanup - I'm confident"
```powershell
# Step 1: Validate first
.\migrate-old-backups.ps1 -ValidateOnly

# Step 2: Review report (make sure all is green)

# Step 3: Do full migration with cleanup
.\migrate-old-backups.ps1 -CompressArchive -DeleteAfterMigration

# Result: New organized backups + archive of old ones + old files deleted
```

## Understanding the Report

### migrate-report_YYYY-MM-DD_HH-MM-SS.json
```json
{
  "Timestamp": "2026-03-23T19:30:00",
  "Statistics": {
    "TotalBackupsFound": 16,
    "BackupsMigrated": 16,
    "BackupsFailed": 0,
    "TotalSizeProcessed": "5.2GB",
    "Duration": "45.2"
  },
  "Errors": [],
  "Warnings": [],
  "Configuration": { ... }
}
```

**Key fields:**
- `TotalBackupsFound` = Backups detected in old location
- `BackupsMigrated` = Successfully migrated count
- `BackupsFailed` = Failed migrations (investigate!)
- `TotalSizeProcessed` = Total size of old backups
- `Duration` = Total execution time in seconds

## Troubleshooting

### Issue: "Source path does not exist"
**Solution:** Verify F:\backup\claudecode\ exists
```powershell
Test-Path F:\backup\claudecode\
```

### Issue: "No backups found matching pattern"
**Solution:** Old backup files don't follow the naming convention `backup_YYYY_MM_DD_HH_MM_SS`
- Check what files are in F:\backup\claudecode\
- Rename them to match the pattern, or
- Manually migrate and rename as needed

### Issue: "Integrity check failed"
**Solution:** Some backups may be corrupted
- Review the report for which ones failed
- Try `-ValidateOnly` first to see details
- Manually inspect those backups before deleting

### Issue: "Robocopy failed"
**Solution:** Falls back to Copy-Item automatically
- Check disk space: `dir F:\ -h` for free space
- Check file permissions on source/destination
- Run as Administrator if needed: `powershell -RunAs Administrator`

### Issue: "Compression failed - 7-Zip not found"
**Solution:** Uses PowerShell's Compress-Archive automatically
- Works without 7-Zip, just slower
- Install 7-Zip for better compression: `choco install 7zip`

## Best Practices

1. **Always validate first:**
   ```powershell
   .\migrate-old-backups.ps1 -ValidateOnly
   ```

2. **Check the report before deleting:**
   ```powershell
   Get-Content migrate-report_*.json | ConvertFrom-Json | Format-List
   ```

3. **Keep archives during transition period:**
   ```powershell
   .\migrate-old-backups.ps1 -CompressArchive
   # Keep archive_*.zip for 1-2 weeks, then delete if satisfied
   ```

4. **Schedule regular migration validation:**
   Create a Task Scheduler job to run `-ValidateOnly` weekly

## Automation

### Create a PowerShell scheduled task
```powershell
$action = New-ScheduledTaskAction -Execute "powershell" `
  -Argument '-ExecutionPolicy Bypass -File "F:\...\migrate-old-backups.ps1" -ValidateOnly'

$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek Saturday -At 02:00AM

Register-ScheduledTask -Action $action -Trigger $trigger `
  -TaskName "Backup-Migration-Validation" -Description "Weekly backup migration check"
```

## Support

For issues:
1. Review the JSON report for specific errors
2. Check Windows Event Viewer for PowerShell execution logs
3. Verify disk space: `Get-Volume` 
4. Test individual backup: `Get-ChildItem <backup-path> -Recurse | Measure-Object -Sum -Property Length`

---

**Last Updated:** 2026-03-23  
**Version:** 1.0  
**Author:** Till Thelet's AI Assistant
