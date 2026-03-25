#Requires -Version 5.0
<#
.SYNOPSIS
    Comprehensive database backup script for Claude Code and OpenClaw
    
.DESCRIPTION
    Backs up all SQLite databases, application data, and persistent stores:
    - Claude Desktop databases (.claude directory)
    - Settings and configuration databases
    - Telegram client database
    - Discord cache databases
    - Game library manager database (1,032 games)
    - Any other persistent data stores
    
    Includes integrity checks, compression, and metadata logging.

.EXAMPLE
    .\backup-databases.ps1
    .\backup-databases.ps1 -BackupPath "D:\CustomBackup"
    .\backup-databases.ps1 -Compress -Verbose
#>

param(
    [string]$BackupPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\archives",
    [bool]$Compress = $true,
    [bool]$CheckIntegrity = $true,
    [int]$RetentionDays = 30
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================================
# CONFIGURATION
# ============================================================================

$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"
$backupDir = Join-Path $BackupPath $timestamp
$logFile = Join-Path $backupDir "backup-log_$timestamp.txt"
$metadataFile = Join-Path $backupDir "backup-metadata_$timestamp.json"

# Database locations to backup
$databaseLocations = @{
    'Claude_Settings' = @{
        paths = @(
            'C:\Users\micha\.claude\settings.db',
            'C:\Users\micha\.claude\settings.json',
            'C:\Users\micha\AppData\Local\Claude'
        )
        description = "Claude Desktop settings and configuration"
    }
    'Claude_History' = @{
        paths = @(
            'C:\Users\micha\.claude\history.db',
            'C:\Users\micha\.claude\history.jsonl',
            'C:\Users\micha\AppData\Roaming\Claude'
        )
        description = "Claude conversation history"
    }
    'Claude_Cache' = @{
        paths = @(
            'C:\Users\micha\.claude\cache.db',
            'C:\Users\micha\.claude\cache'
        )
        description = "Claude cache database"
    }
    'Telegram_Database' = @{
        paths = @(
            'C:\Users\micha\AppData\Local\Telegram\Telegram Desktop\tdata'
        )
        description = "Telegram Desktop encrypted database"
    }
    'Discord_Cache' = @{
        paths = @(
            'C:\Users\micha\AppData\Local\Discord\Cache',
            'C:\Users\micha\AppData\Local\Discord\Code Cache'
        )
        description = "Discord cache and temporary data"
    }
    'Game_Library' = @{
        paths = @(
            'C:\Users\micha\Documents\GameLibraryManager',
            'C:\Users\micha\AppData\Local\GameLibraryManager',
            'F:\Games\library.db'
        )
        description = "Game library manager database (1,032 games)"
    }
    'OpenClaw_Data' = @{
        paths = @(
            'C:\Users\micha\.openclaw'
        )
        description = "OpenClaw configuration and database files"
    }
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

function Test-DatabaseIntegrity {
    param([string]$DbPath)
    
    if (-not (Test-Path $DbPath)) {
        Write-Log "Database file not found: $DbPath" "WARN"
        return @{ status = 'missing'; integrity = 0 }
    }
    
    # Check file accessibility
    try {
        $file = Get-Item $DbPath
        $canRead = Test-Path $DbPath -PathType Leaf
        $size = $file.Length
        
        # Simple integrity check: verify it's not empty and has valid headers
        $isValid = $true
        if ($size -lt 512) {
            $isValid = $false
            Write-Log "Warning: File may be corrupted (size < 512 bytes): $DbPath" "WARN"
        }
        
        # Check for SQLite magic header (first 16 bytes should be "SQLite format 3")
        if ($DbPath -like "*.db") {
            $bytes = [System.IO.File]::ReadAllBytes($DbPath)
            $header = [System.Text.Encoding]::ASCII.GetString($bytes[0..15])
            if ($header -notlike "SQLite format 3*") {
                $isValid = $false
                Write-Log "Warning: Invalid SQLite header: $DbPath" "WARN"
            }
        }
        
        return @{
            status = 'accessible'
            integrity = if ($isValid) { 100 } else { 0 }
            size = $size
            lastModified = $file.LastWriteTime
        }
    }
    catch {
        Write-Log "Error checking integrity of $DbPath : $_" "ERROR"
        return @{ status = 'error'; integrity = 0; error = $_.Exception.Message }
    }
}

function Backup-Directory {
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Category
    )
    
    if (-not (Test-Path $SourcePath)) {
        Write-Log "Source path not found (skipping): $SourcePath" "WARN"
        return $false
    }
    
    try {
        $item = Get-Item $SourcePath
        
        if ($item -is [System.IO.DirectoryInfo]) {
            Write-Log "Backing up directory: $SourcePath → $DestPath"
            Copy-Item -Path $SourcePath -Destination $DestPath -Recurse -Force -ErrorAction Continue
            Write-Log "✓ Directory backup complete: $SourcePath" "SUCCESS"
            return $true
        }
        else {
            Write-Log "Backing up file: $SourcePath → $DestPath"
            $destDir = Split-Path $DestPath
            if (-not (Test-Path $destDir)) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
            Copy-Item -Path $SourcePath -Destination $DestPath -Force
            Write-Log "✓ File backup complete: $SourcePath" "SUCCESS"
            return $true
        }
    }
    catch {
        Write-Log "Error backing up $SourcePath : $_" "ERROR"
        return $false
    }
}

function Compress-Backup {
    param([string]$BackupFolder)
    
    Write-Log "Compressing backup folder: $BackupFolder"
    
    try {
        $zipPath = "$BackupFolder.zip"
        Add-Type -AssemblyName "System.IO.Compression.FileSystem"
        [System.IO.Compression.ZipFile]::CreateFromDirectory($BackupFolder, $zipPath, [System.IO.Compression.CompressionLevel]::Optimal, $true)
        
        $originalSize = (Get-ChildItem $BackupFolder -Recurse | Measure-Object -Property Length -Sum).Sum
        $compressedSize = (Get-Item $zipPath).Length
        $ratio = [math]::Round(($compressedSize / $originalSize) * 100, 2)
        
        Write-Log "✓ Compression complete: $ratio% of original size" "SUCCESS"
        Write-Log "  Original: $(($originalSize / 1MB).ToString('F2')) MB"
        Write-Log "  Compressed: $(($compressedSize / 1MB).ToString('F2')) MB"
        
        return @{
            zipPath = $zipPath
            originalSize = $originalSize
            compressedSize = $compressedSize
            ratio = $ratio
        }
    }
    catch {
        Write-Log "Error compressing backup: $_" "ERROR"
        return $null
    }
}

function Cleanup-OldBackups {
    param([int]$DaysToKeep)
    
    Write-Log "Cleaning up backups older than $DaysToKeep days"
    
    try {
        $cutoffDate = (Get-Date).AddDays(-$DaysToKeep)
        $backupParent = Split-Path $BackupPath
        
        Get-ChildItem -Path $backupParent -Directory | Where-Object { $_.LastWriteTime -lt $cutoffDate } | ForEach-Object {
            Write-Log "Removing old backup: $($_.FullName)"
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction Continue
        }
        
        Write-Log "✓ Cleanup complete" "SUCCESS"
    }
    catch {
        Write-Log "Error during cleanup: $_" "WARN"
    }
}

# ============================================================================
# MAIN BACKUP LOGIC
# ============================================================================

function Start-DatabaseBackup {
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║  DATABASE BACKUP - Claude Code & OpenClaw                 ║" -ForegroundColor Cyan
    Write-Host "║  Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')                    ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # Create backup directory
    if (-not (Test-Path $backupDir)) {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        Write-Log "Created backup directory: $backupDir"
    }
    
    $backupSummary = @{
        timestamp = $timestamp
        backupPath = $backupDir
        categories = @{}
        totalFiles = 0
        totalSize = 0
        checksums = @{}
        warnings = @()
        errors = @()
    }
    
    # ========================================================================
    # BACKUP EACH CATEGORY
    # ========================================================================
    
    foreach ($category in $databaseLocations.Keys) {
        Write-Host ""
        Write-Host "► Backing up: $category" -ForegroundColor Yellow
        Write-Log "==== BACKUP CATEGORY: $category ===="
        Write-Log "Description: $($databaseLocations[$category].description)"
        
        $categoryData = @{
            description = $databaseLocations[$category].description
            items = @()
            success = 0
            failed = 0
            skipped = 0
        }
        
        foreach ($sourcePath in $databaseLocations[$category].paths) {
            if (Test-Path $sourcePath) {
                $destPath = Join-Path $backupDir $category $([System.IO.Path]::GetFileName($sourcePath))
                
                # Integrity check
                if ($CheckIntegrity) {
                    $integrity = Test-DatabaseIntegrity $sourcePath
                    Write-Log "Integrity check: $sourcePath - Status: $($integrity.status), Integrity: $($integrity.integrity)%"
                }
                
                # Backup
                if (Backup-Directory -SourcePath $sourcePath -DestPath $destPath -Category $category) {
                    $categoryData.success++
                    $categoryData.items += @{
                        source = $sourcePath
                        destination = $destPath
                        status = "backed_up"
                    }
                }
                else {
                    $categoryData.failed++
                    $categoryData.items += @{
                        source = $sourcePath
                        status = "failed"
                    }
                    $backupSummary.errors += "Failed to backup: $sourcePath"
                }
            }
            else {
                $categoryData.skipped++
                Write-Log "Source not found (skipped): $sourcePath" "WARN"
            }
        }
        
        $backupSummary.categories[$category] = $categoryData
        Write-Log "Category summary - Success: $($categoryData.success), Failed: $($categoryData.failed), Skipped: $($categoryData.skipped)"
    }
    
    # ========================================================================
    # COMPRESSION
    # ========================================================================
    
    if ($Compress) {
        Write-Host ""
        Write-Host "► Compressing backup..." -ForegroundColor Yellow
        $compressionResult = Compress-Backup -BackupFolder $backupDir
        
        if ($compressionResult) {
            $backupSummary.compression = $compressionResult
            
            # Remove uncompressed directory if compression successful
            Remove-Item -Path $backupDir -Recurse -Force -ErrorAction Continue
        }
    }
    
    # ========================================================================
    # SAVE METADATA
    # ========================================================================
    
    Write-Host ""
    Write-Host "► Saving metadata..." -ForegroundColor Yellow
    
    $metadataJson = $backupSummary | ConvertTo-Json -Depth 10
    Set-Content -Path $metadataFile -Value $metadataJson
    Write-Log "Metadata saved: $metadataFile"
    
    # ========================================================================
    # CLEANUP OLD BACKUPS
    # ========================================================================
    
    Write-Host ""
    Write-Host "► Cleaning up old backups..." -ForegroundColor Yellow
    Cleanup-OldBackups -DaysToKeep $RetentionDays
    
    # ========================================================================
    # FINAL REPORT
    # ========================================================================
    
    Write-Host ""
    Write-Host "╔════════════════════════════════════════════════════════════╗" -ForegroundColor Green
    Write-Host "║  BACKUP COMPLETE                                           ║" -ForegroundColor Green
    Write-Host "║  Location: $($backupDir)                                   ║" -ForegroundColor Green
    Write-Host "║  Log: $($logFile)                          ║" -ForegroundColor Green
    Write-Host "║  Categories backed up: $($backupSummary.categories.Count)                                  ║" -ForegroundColor Green
    Write-Host "╚════════════════════════════════════════════════════════════╝" -ForegroundColor Green
    
    Write-Log "Backup completed at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')"
    
    return $backupSummary
}

# ============================================================================
# EXECUTE
# ============================================================================

try {
    Start-DatabaseBackup
}
catch {
    Write-Host "FATAL ERROR: $_" -ForegroundColor Red
    Write-Log "FATAL ERROR: $_" "FATAL"
    exit 1
}

exit 0
