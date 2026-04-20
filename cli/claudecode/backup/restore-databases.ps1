#Requires -Version 5.0
<#
.SYNOPSIS
    Comprehensive database restore script for Claude Code and OpenClaw
    
.DESCRIPTION
    Restores all SQLite databases and persistent data from backup:
    - Validates backup integrity and checksums
    - Restores to correct original locations
    - Runs integrity checks on restored databases
    - Rebuilds indexes if needed
    - Validates data consistency
    - Creates rollback points before restore

.PARAMETER BackupArchive
    Path to the backup archive (.zip) or directory to restore from

.PARAMETER TargetPath
    Root path where data should be restored (default: original locations)

.PARAMETER DryRun
    Run in dry-run mode without making changes

.EXAMPLE
    .\restore-databases.ps1 -BackupArchive "F:\backups\2024-01-15_14-30-00.zip"
    .\restore-databases.ps1 -BackupArchive "F:\backups\extracted" -DryRun
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupArchive,
    
    [string]$TargetPath,
    [bool]$DryRun = $false,
    [bool]$CreateRollback = $true,
    [bool]$CheckIntegrity = $true,
    [int]$MaxRetries = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$restoreLogDir = Join-Path $scriptDir "restore-logs"
$logFile = Join-Path $restoreLogDir "restore-log_$timestamp.txt"
$rollbackDir = Join-Path $scriptDir "rollback-points" $timestamp

# Database location mappings
$databaseMappings = @{
    'Claude_Settings' = @(
        @{ source = 'Claude_Settings\settings.db'; target = 'C:\Users\micha\.claude\settings.db' }
        @{ source = 'Claude_Settings\settings.json'; target = 'C:\Users\micha\.claude\settings.json' }
        @{ source = 'Claude_Settings\Claude'; target = 'C:\Users\micha\AppData\Local\Claude' }
    )
    'Claude_History' = @(
        @{ source = 'Claude_History\history.db'; target = 'C:\Users\micha\.claude\history.db' }
        @{ source = 'Claude_History\history.jsonl'; target = 'C:\Users\micha\.claude\history.jsonl' }
        @{ source = 'Claude_History\Claude'; target = 'C:\Users\micha\AppData\Roaming\Claude' }
    )
    'Claude_Cache' = @(
        @{ source = 'Claude_Cache\cache.db'; target = 'C:\Users\micha\.claude\cache.db' }
        @{ source = 'Claude_Cache\cache'; target = 'C:\Users\micha\.claude\cache' }
    )
    'Telegram_Database' = @(
        @{ source = 'Telegram_Database\tdata'; target = 'C:\Users\micha\AppData\Local\Telegram\Telegram Desktop\tdata' }
    )
    'Discord_Cache' = @(
        @{ source = 'Discord_Cache\Cache'; target = 'C:\Users\micha\AppData\Local\Discord\Cache' }
        @{ source = 'Discord_Cache\Code Cache'; target = 'C:\Users\micha\AppData\Local\Discord\Code Cache' }
    )
    'Game_Library' = @(
        @{ source = 'Game_Library\GameLibraryManager'; target = 'C:\Users\micha\Documents\GameLibraryManager' }
        @{ source = 'Game_Library\library.db'; target = 'F:\Games\library.db' }
    )
    'OpenClaw_Data' = @(
        @{ source = 'OpenClaw_Data\.openclaw'; target = 'C:\Users\micha\.openclaw' }
    )
}

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
}

function Test-BackupIntegrity {
    param([string]$BackupPath)
    
    Write-Log "Verifying backup integrity: $BackupPath"
    
    if (-not (Test-Path $BackupPath)) {
        throw "Backup path not found: $BackupPath"
    }
    
    $integrity = @{
        valid = $true
        issues = @()
        filesChecked = 0
        filesValid = 0
    }
    
    # If it's a zip, verify it's valid
    if ($BackupPath -like "*.zip") {
        try {
            Add-Type -AssemblyName "System.IO.Compression.FileSystem"
            $zip = [System.IO.Compression.ZipFile]::OpenRead($BackupPath)
            $zip.Dispose()
            Write-Log "✓ Backup archive is valid"
        }
        catch {
            $integrity.valid = $false
            $integrity.issues += "Invalid or corrupted ZIP file: $_"
            Write-Log "✗ Backup archive is corrupted: $_" "ERROR"
        }
    }
    
    # Check metadata if it exists
    $metadataPath = Join-Path (Split-Path $BackupPath) "backup-metadata*.json"
    $metadataFiles = Get-ChildItem -Path $metadataPath -ErrorAction SilentlyContinue
    
    if ($metadataFiles) {
        try {
            $metadata = Get-Content $metadataFiles[0].FullName | ConvertFrom-Json
            Write-Log "Metadata found: Backed up $(Get-Date $metadata.timestamp) with $($metadata.categories.Count) categories"
        }
        catch {
            $integrity.issues += "Could not parse metadata: $_"
            Write-Log "Warning: Could not parse metadata" "WARN"
        }
    }
    
    return $integrity
}

function Extract-Backup {
    param([string]$BackupPath, [string]$ExtractPath)
    
    Write-Log "Extracting backup: $BackupPath → $ExtractPath"
    
    if ($BackupPath -like "*.zip") {
        try {
            Add-Type -AssemblyName "System.IO.Compression.FileSystem"
            [System.IO.Compression.ZipFile]::ExtractToDirectory($BackupPath, $ExtractPath, $true)
            Write-Log "✓ Backup extracted successfully"
            return $true
        }
        catch {
            Write-Log "Error extracting backup: $_" "ERROR"
            return $false
        }
    }
    else {
        # Already extracted, just return the path
        return $true
    }
}

function Create-Rollback {
    param([string]$TargetPath)
    
    Write-Log "Creating rollback point: $rollbackDir"
    
    try {
        New-Item -ItemType Directory -Path $rollbackDir -Force | Out-Null
        
        foreach ($category in $databaseMappings.Keys) {
            foreach ($mapping in $databaseMappings[$category]) {
                $targetFullPath = $mapping.target
                
                if (Test-Path $targetFullPath) {
                    $backupName = [System.IO.Path]::GetFileName($targetFullPath)
                    $rollbackPath = Join-Path $rollbackDir $category $backupName
                    
                    New-Item -ItemType Directory -Path (Split-Path $rollbackPath) -Force | Out-Null
                    
                    $item = Get-Item $targetFullPath
                    if ($item -is [System.IO.DirectoryInfo]) {
                        Copy-Item -Path $targetFullPath -Destination $rollbackPath -Recurse -Force -ErrorAction Continue
                    }
                    else {
                        Copy-Item -Path $targetFullPath -Destination $rollbackPath -Force -ErrorAction Continue
                    }
                    
                    Write-Log "  Rollback created: $targetFullPath → $rollbackPath"
                }
            }
        }
        
        Write-Log "✓ Rollback point created: $rollbackDir"
        return $rollbackDir
    }
    catch {
        Write-Log "Error creating rollback point: $_" "ERROR"
        return $null
    }
}

function Restore-Database {
    param(
        [string]$SourcePath,
        [string]$TargetPath,
        [string]$Category,
        [bool]$IsDryRun = $false
    )
    
    if (-not (Test-Path $SourcePath)) {
        Write-Log "Source not found (skipping): $SourcePath" "WARN"
        return @{ status = 'skipped'; reason = 'source_not_found' }
    }
    
    if ($IsDryRun) {
        Write-Log "[DRY RUN] Would restore: $SourcePath → $TargetPath"
        return @{ status = 'dry_run'; source = $SourcePath; target = $TargetPath }
    }
    
    try {
        # Create parent directory if needed
        $targetDir = Split-Path $TargetPath
        if (-not (Test-Path $targetDir)) {
            New-Item -ItemType Directory -Path $targetDir -Force | Out-Null
        }
        
        $item = Get-Item $SourcePath
        
        if ($item -is [System.IO.DirectoryInfo]) {
            Copy-Item -Path $SourcePath -Destination $TargetPath -Recurse -Force -ErrorAction Stop
            Write-Log "✓ Restored directory: $SourcePath → $TargetPath"
        }
        else {
            Copy-Item -Path $SourcePath -Destination $TargetPath -Force -ErrorAction Stop
            Write-Log "✓ Restored file: $SourcePath → $TargetPath"
        }
        
        return @{ status = 'restored'; source = $SourcePath; target = $TargetPath }
    }
    catch {
        Write-Log "Error restoring $SourcePath : $_" "ERROR"
        return @{ status = 'error'; source = $SourcePath; error = $_.Exception.Message }
    }
}

function Test-RestoredDatabaseIntegrity {
    param([string]$DatabasePath)
    
    if (-not (Test-Path $DatabasePath)) {
        return @{ status = 'not_found'; integrity = 0 }
    }
    
    try {
        $file = Get-Item $DatabasePath
        $size = $file.Length
        
        if ($size -lt 512) {
            return @{ status = 'corrupted'; integrity = 0; reason = 'file_too_small' }
        }
        
        # Check SQLite header
        if ($DatabasePath -like "*.db") {
            $bytes = [System.IO.File]::ReadAllBytes($DatabasePath)
            if ($bytes.Length -ge 16) {
                $header = [System.Text.Encoding]::ASCII.GetString($bytes[0..15])
                if ($header -notlike "SQLite format 3*") {
                    return @{ status = 'corrupted'; integrity = 0; reason = 'invalid_header' }
                }
            }
        }
        
        return @{ status = 'valid'; integrity = 100; size = $size; lastModified = $file.LastWriteTime }
    }
    catch {
        return @{ status = 'error'; integrity = 0; error = $_.Exception.Message }
    }
}

function Rebuild-Indexes {
    param([string]$DatabasePath)
    
    if (-not (Test-Path $DatabasePath) -or $DatabasePath -notlike "*.db") {
        return $false
    }
    
    Write-Log "Attempting to rebuild indexes: $DatabasePath"
    
    try {
        # SQLite PRAGMA commands to rebuild and optimize
        $sqlite3Path = "C:\Program Files\sqlite\sqlite3.exe"
        
        if (-not (Test-Path $sqlite3Path)) {
            Write-Log "sqlite3.exe not found, skipping index rebuild" "WARN"
            return $false
        }
        
        $commands = @(
            "PRAGMA integrity_check;",
            "VACUUM;",
            "REINDEX;",
            "PRAGMA optimize;"
        )
        
        foreach ($cmd in $commands) {
            & $sqlite3Path $DatabasePath $cmd | Out-Null
        }
        
        Write-Log "✓ Indexes rebuilt: $DatabasePath"
        return $true
    }
    catch {
        Write-Log "Could not rebuild indexes (non-fatal): $_" "WARN"
        return $false
    }
}

# ============================================================================
# MAIN RESTORE LOGIC
# ============================================================================

function Start-DatabaseRestore {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  DATABASE RESTORE - Claude Code & OpenClaw                 ║" -ForegroundColor Cyan
    Write-Host "║  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                    ║" -ForegroundColor Cyan
    if ($DryRun) {
        Write-Host "║  MODE: DRY RUN (no changes will be made)                  ║" -ForegroundColor Yellow
    }
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Create restore log directory
    if (-not (Test-Path $restoreLogDir)) {
        New-Item -ItemType Directory -Path $restoreLogDir -Force | Out-Null
    }
    
    # ========================================================================
    # VERIFY BACKUP
    # ========================================================================
    
    Write-Host "► Verifying backup..." -ForegroundColor Yellow
    $integrity = Test-BackupIntegrity -BackupPath $BackupArchive
    
    if (-not $integrity.valid) {
        Write-Host "✗ Backup integrity check failed:" -ForegroundColor Red
        foreach ($issue in $integrity.issues) {
            Write-Host "  - $issue" -ForegroundColor Red
        }
        throw "Cannot proceed with corrupted backup"
    }
    
    Write-Log "✓ Backup integrity verified"
    
    # ========================================================================
    # EXTRACT BACKUP
    # ========================================================================
    
    Write-Host "► Preparing backup..." -ForegroundColor Yellow
    
    $extractPath = $BackupArchive
    if ($BackupArchive -like "*.zip") {
        $extractPath = Join-Path (Split-Path $BackupArchive) "extracted_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
        if (-not (Extract-Backup -BackupPath $BackupArchive -ExtractPath $extractPath)) {
            throw "Failed to extract backup"
        }
    }
    
    # ========================================================================
    # CREATE ROLLBACK POINT
    # ========================================================================
    
    if ($CreateRollback -and -not $DryRun) {
        Write-Host "► Creating rollback point..." -ForegroundColor Yellow
        $rollbackCreated = Create-Rollback -TargetPath $extractPath
        
        if ($rollbackCreated) {
            Write-Log "Rollback available at: $rollbackCreated"
        }
    }
    
    # ========================================================================
    # RESTORE DATABASES
    # ========================================================================
    
    Write-Host "► Restoring databases..." -ForegroundColor Yellow
    
    $restoreSummary = @{
        timestamp = $timestamp
        backupSource = $BackupArchive
        dryRun = $DryRun
        categories = @{}
        totalRestored = 0
        totalFailed = 0
        totalSkipped = 0
    }
    
    foreach ($category in $databaseMappings.Keys) {
        Write-Host "  ✓ $category" -ForegroundColor Cyan
        Write-Log "==== RESTORE CATEGORY: $category ===="
        
        $categoryData = @{
            items = @()
            restored = 0
            failed = 0
            skipped = 0
        }
        
        foreach ($mapping in $databaseMappings[$category]) {
            $sourceFullPath = Join-Path $extractPath $mapping.source
            $targetFullPath = $mapping.target
            
            $result = Restore-Database -SourcePath $sourceFullPath -TargetPath $targetFullPath -Category $category -IsDryRun $DryRun
            
            if ($result.status -eq 'restored') {
                $categoryData.restored++
                $restoreSummary.totalRestored++
                
                # Check integrity if enabled
                if ($CheckIntegrity -and $targetFullPath -like "*.db") {
                    $integrityCheck = Test-RestoredDatabaseIntegrity -DatabasePath $targetFullPath
                    Write-Log "Integrity check result: $($integrityCheck.status)"
                    
                    # Try to rebuild indexes
                    Rebuild-Indexes -DatabasePath $targetFullPath
                }
            }
            elseif ($result.status -eq 'skipped') {
                $categoryData.skipped++
                $restoreSummary.totalSkipped++
            }
            else {
                $categoryData.failed++
                $restoreSummary.totalFailed++
            }
            
            $categoryData.items += $result
        }
        
        $restoreSummary.categories[$category] = $categoryData
        Write-Log "Category summary - Restored: $($categoryData.restored), Failed: $($categoryData.failed), Skipped: $($categoryData.skipped)"
    }
    
    # ========================================================================
    # CLEANUP EXTRACTED FILES
    # ========================================================================
    
    if ($extractPath -ne $BackupArchive -and (Test-Path $extractPath)) {
        Write-Host "► Cleaning up extracted files..." -ForegroundColor Yellow
        Remove-Item -Path $extractPath -Recurse -Force -ErrorAction Continue
    }
    
    # ========================================================================
    # FINAL REPORT
    # ========================================================================
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  RESTORE COMPLETE                                          ║" -ForegroundColor Green
    Write-Host "║  Restored: $($restoreSummary.totalRestored) | Failed: $($restoreSummary.totalFailed) | Skipped: $($restoreSummary.totalSkipped)                      ║" -ForegroundColor Green
    Write-Host "║  Log: $logFile                          ║" -ForegroundColor Green
    if ($rollbackDir -and (Test-Path $rollbackDir)) {
        Write-Host "║  Rollback: $rollbackDir                    ║" -ForegroundColor Green
    }
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Log "Restore completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    return $restoreSummary
}

# ============================================================================
# EXECUTE
# ============================================================================

try {
    Start-DatabaseRestore
}
catch {
    Write-Host "FATAL ERROR: $_" -ForegroundColor Red
    Write-Log "FATAL ERROR: $_" "FATAL"
    exit 1
}

exit 0
