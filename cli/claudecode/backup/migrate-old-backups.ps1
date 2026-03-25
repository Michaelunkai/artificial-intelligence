#Requires -Version 5.0
<#
.SYNOPSIS
Backup Migration Utility for Claude Code backups
Migrates old unorganized backups to new structured format with versioning

.DESCRIPTION
1. Detects old backups in F:\backup\claudecode\
2. Migrates to new organized structure with semantic versioning
3. Reindexes and validates backups
4. Creates comprehensive migration report
5. Optionally deletes/compresses old backups

.PARAMETER SourcePath
Path to old backups (default: F:\backup\claudecode\)

.PARAMETER DestinationPath
Path to new organized backups (default: F:\study\AI_ML\...\backup\data\)

.PARAMETER ValidateOnly
Scan and report without migrating

.PARAMETER DeleteAfterMigration
Delete old backups after successful migration

.PARAMETER CompressArchive
Compress old backups to archive before deletion

.PARAMETER ReportPath
Output path for migration report (default: .\migrate-report-TIMESTAMP.json)
#>

param(
    [string]$SourcePath = "F:\backup\claudecode",
    [string]$DestinationPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\data",
    [switch]$ValidateOnly,
    [switch]$DeleteAfterMigration,
    [switch]$CompressArchive,
    [string]$ReportPath
)

# ============================================================================
# CONFIG
# ============================================================================

$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"

$scriptName = Split-Path $MyInvocation.MyCommand.Path -Leaf
$scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm-ss"

if (-not $ReportPath) {
    $ReportPath = Join-Path $scriptDir "migrate-report_$timestamp.json"
}

# Logging arrays
$migrationLog = @()
$errors = @()
$warnings = @()
$stats = @{
    TotalBackupsFound = 0
    BackupsMigrated = 0
    BackupsFailed = 0
    TotalSizeProcessed = 0
    TotalSizeNew = 0
    StartTime = Get-Date
    EndTime = $null
    Duration = $null
}

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Progress-Message {
    param(
        [string]$Message,
        [ValidateSet("Info", "Success", "Warning", "Error")]
        [string]$Level = "Info"
    )
    
    $timestamp = Get-Date -Format "HH:mm:ss"
    $symbol = @{
        Info = "[INFO]"
        Success = "[OK]"
        Warning = "[WARN]"
        Error = "[ERR]"
    }[$Level]
    
    Write-Host "$symbol [$timestamp] $Message"
}

function Validate-BackupPath {
    param([string]$Path)
    
    # Check if path exists and is a directory
    if (-not (Test-Path -Path $Path -PathType Container)) {
        return @{ Valid = $false; Error = "Path does not exist or is not a directory" }
    }
    
    # Check if path is readable
    try {
        $null = Get-ChildItem -Path $Path -ErrorAction Stop | Select-Object -First 1
    }
    catch {
        return @{ Valid = $false; Error = "Path is not readable: $_" }
    }
    
    return @{ Valid = $true }
}

function Get-BackupInfo {
    param(
        [string]$BackupPath,
        [string]$BackupName
    )
    
    try {
        $fullPath = Join-Path $BackupPath $BackupName
        $item = Get-Item -Path $fullPath -ErrorAction Stop
        
        # Parse timestamp from backup name
        # Expected format: backup_YYYY_MM_DD_HH_MM_SS
        $match = $BackupName -match 'backup_(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})'
        $timestamp = $null
        $version = $null
        
        if ($match) {
            $timestamp = [datetime]::ParseExact(
                "$($matches[1])-$($matches[2])-$($matches[3]) $($matches[4]):$($matches[5]):$($matches[6])",
                "yyyy-MM-dd HH:mm:ss",
                $null
            )
            # Generate semantic version: YY.MM.DD-HHMMSS
            $version = "{0}.{1}.{2}-{3}" -f $matches[1].Substring(2), $matches[2], $matches[3], $matches[4] + $matches[5] + $matches[6]
        }
        
        return @{
            Name = $BackupName
            FullPath = $fullPath
            CreatedTime = $item.CreationTime
            ModifiedTime = $item.LastWriteTime
            ParsedTimestamp = $timestamp
            SemanticVersion = $version
            IsDirectory = $item.PSIsContainer
            Size = if ($item.PSIsContainer) { 
                (Get-ChildItem -Path $fullPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum 
            } else { 
                $item.Length 
            }
            Valid = $true
        }
    }
    catch {
        $errors += "Failed to get backup info for $BackupName : $_"
        return @{
            Name = $BackupName
            Valid = $false
            Error = $_
        }
    }
}

function New-OrganizedPath {
    param(
        [hashtable]$BackupInfo,
        [string]$DestinationBase
    )
    
    if (-not $BackupInfo.SemanticVersion) {
        return $null
    }
    
    # New structure: /data/v<VERSION>/<DATE>/<BACKUP_NAME>/
    $versionFolder = "v$($BackupInfo.SemanticVersion.Split('-')[0])"
    $dateFolder = $BackupInfo.ParsedTimestamp.ToString("yyyy-MM-dd")
    
    return Join-Path $DestinationBase $versionFolder $dateFolder $BackupInfo.Name
}

function Test-BackupIntegrity {
    param(
        [string]$BackupPath
    )
    
    $issues = @()
    
    if (-not (Test-Path -Path $BackupPath)) {
        $issues += "Path does not exist"
        return @{ Valid = $false; Issues = $issues }
    }
    
    try {
        $items = @(Get-ChildItem -Path $BackupPath -ErrorAction Stop)
        
        if ($items.Count -eq 0) {
            $issues += "Backup is empty"
        }
        
        # Check for common backup file types
        $hasContent = $false
        foreach ($item in $items) {
            if ($item.Length -gt 0 -or $item.PSIsContainer) {
                $hasContent = $true
                break
            }
        }
        
        if (-not $hasContent) {
            $issues += "No backup content found"
        }
        
    }
    catch {
        $issues += "Integrity check failed: $_"
    }
    
    return @{ Valid = $issues.Count -eq 0; Issues = $issues }
}

function Copy-Backup {
    param(
        [string]$SourceBackup,
        [string]$DestinationBackup
    )
    
    try {
        # Create destination directory
        $destDir = Split-Path -Path $DestinationBackup -Parent
        if (-not (Test-Path -Path $destDir)) {
            $null = New-Item -ItemType Directory -Path $destDir -Force
        }
        
        # Copy with robocopy for better performance and reliability
        if (Get-Command robocopy -ErrorAction SilentlyContinue) {
            $result = & robocopy "$SourceBackup" "$DestinationBackup" /E /COPY:DAT /DCOPY:DAT /R:3 /W:10 /MT:4 | Out-String
            if ($LASTEXITCODE -le 1) {
                return @{ Success = $true }
            }
            else {
                return @{ Success = $false; Error = "Robocopy failed: exit code $LASTEXITCODE" }
            }
        }
        else {
            # Fallback to Copy-Item
            Copy-Item -Path "$SourceBackup\*" -Destination $DestinationBackup -Recurse -Force
            return @{ Success = $true }
        }
    }
    catch {
        return @{ Success = $false; Error = $_ }
    }
}

function Compress-BackupArchive {
    param(
        [string]$SourcePath,
        [string]$ArchivePath
    )
    
    try {
        # Create archive directory if needed
        $archiveDir = Split-Path -Path $ArchivePath -Parent
        if (-not (Test-Path -Path $archiveDir)) {
            $null = New-Item -ItemType Directory -Path $archiveDir -Force
        }
        
        # Use 7-Zip if available, otherwise PowerShell's Compress-Archive
        if (Get-Command 7z -ErrorAction SilentlyContinue) {
            & 7z a -tzip -mx=5 "$ArchivePath" "$SourcePath" | Out-Null
            if ($LASTEXITCODE -eq 0) {
                return @{ Success = $true }
            }
            else {
                return @{ Success = $false; Error = "7-Zip compression failed" }
            }
        }
        else {
            Compress-Archive -Path "$SourcePath" -DestinationPath $ArchivePath -CompressionLevel Optimal -Force
            return @{ Success = $true }
        }
    }
    catch {
        return @{ Success = $false; Error = $_ }
    }
}

function Create-BackupIndex {
    param(
        [hashtable[]]$Backups,
        [string]$IndexPath
    )
    
    try {
        $indexDir = Split-Path -Path $IndexPath -Parent
        if (-not (Test-Path -Path $indexDir)) {
            $null = New-Item -ItemType Directory -Path $indexDir -Force
        }
        
        # Create comprehensive index
        $index = @{
            CreatedAt = Get-Date -Format "o"
            TotalBackups = $Backups.Count
            Backups = @()
        }
        
        foreach ($backup in $Backups | Where-Object { $_.Valid }) {
            $index.Backups += @{
                Name = $backup.Name
                Version = $backup.SemanticVersion
                Timestamp = $backup.ParsedTimestamp.ToString("o")
                Size = $backup.Size
                Path = $backup.FullPath
            }
        }
        
        # Sort by timestamp
        $index.Backups = $index.Backups | Sort-Object { [datetime]$_.Timestamp }
        
        # Save as JSON
        $index | ConvertTo-Json -Depth 10 | Set-Content -Path $IndexPath -Force
        
        return @{ Success = $true; Path = $IndexPath }
    }
    catch {
        return @{ Success = $false; Error = $_ }
    }
}

# ============================================================================
# MAIN LOGIC
# ============================================================================

function Main {
    Write-Progress-Message "Starting Backup Migration Utility" "Info"
    Write-Progress-Message "Source: $SourcePath" "Info"
    Write-Progress-Message "Destination: $DestinationPath" "Info"
    Write-Progress-Message "Report: $ReportPath" "Info"
    Write-Host ""
    
    # ========================================================================
    # PHASE 1: VALIDATE SOURCE
    # ========================================================================
    Write-Progress-Message "PHASE 1: Validating source path..." "Info"
    $validation = Validate-BackupPath -Path $SourcePath
    if (-not $validation.Valid) {
        Write-Progress-Message "Source validation failed: $($validation.Error)" "Error"
        $errors += "Source validation failed: $($validation.Error)"
        $stats.EndTime = Get-Date
        $stats.Duration = ($stats.EndTime - $stats.StartTime).TotalSeconds
        Export-Report
        exit 1
    }
    Write-Progress-Message "Source path is valid" "Success"
    Write-Host ""
    
    # ========================================================================
    # PHASE 2: DISCOVER BACKUPS
    # ========================================================================
    Write-Progress-Message "PHASE 2: Discovering old backups..." "Info"
    
    try {
        $backupDirs = @(Get-ChildItem -Path $SourcePath -Directory -ErrorAction Stop | 
                       Where-Object { $_.Name -match '^backup_\d{4}_' })
    }
    catch {
        Write-Progress-Message "Failed to enumerate backups: $_" "Error"
        $errors += "Failed to enumerate backups: $_"
        $stats.EndTime = Get-Date
        $stats.Duration = ($stats.EndTime - $stats.StartTime).TotalSeconds
        Export-Report
        exit 1
    }
    
    $stats.TotalBackupsFound = $backupDirs.Count
    Write-Progress-Message "Found $($stats.TotalBackupsFound) backups to process" "Success"
    Write-Host ""
    
    if ($stats.TotalBackupsFound -eq 0) {
        Write-Progress-Message "No backups found matching pattern 'backup_YYYY_MM_DD_HH_MM_SS'" "Warning"
        $stats.EndTime = Get-Date
        $stats.Duration = ($stats.EndTime - $stats.StartTime).TotalSeconds
        Export-Report
        exit 0
    }
    
    # ========================================================================
    # PHASE 3: INDEX AND VALIDATE
    # ========================================================================
    Write-Progress-Message "PHASE 3: Indexing and validating backups..." "Info"
    
    $backupInfos = @()
    $backupCount = 0
    
    foreach ($backup in $backupDirs) {
        $backupCount++
        $percentComplete = [math]::Round(($backupCount / $stats.TotalBackupsFound) * 100)
        
        $info = Get-BackupInfo -BackupPath $SourcePath -BackupName $backup.Name
        
        if ($info.Valid) {
            $integrity = Test-BackupIntegrity -BackupPath $info.FullPath
            $info.IntegrityValid = $integrity.Valid
            $info.IntegrityIssues = $integrity.Issues
            
            if ($integrity.Valid) {
                Write-Progress-Message "[$percentComplete%] OK $($backup.Name) (v$($info.SemanticVersion), $([math]::Round($info.Size/1MB, 2))MB)" "Success"
            }
            else {
                Write-Progress-Message "[$percentComplete%] WARN $($backup.Name) - Integrity issues: $($integrity.Issues -join ', ')" "Warning"
            }
            
            $stats.TotalSizeProcessed += $info.Size
            $backupInfos += $info
        }
        else {
            Write-Progress-Message "[$percentComplete%] FAIL $($backup.Name) - $($info.Error)" "Error"
            $stats.BackupsFailed++
        }
    }
    
    Write-Host ""
    Write-Progress-Message "Indexed $($backupInfos.Where({$_.Valid}).Count) valid backups" "Success"
    Write-Progress-Message "Total size: $([math]::Round($stats.TotalSizeProcessed/1GB, 2))GB" "Info"
    Write-Host ""
    
    # ========================================================================
    # PHASE 4: VALIDATE-ONLY MODE (EXIT HERE IF REQUESTED)
    # ========================================================================
    if ($ValidateOnly) {
        Write-Progress-Message "VALIDATE-ONLY mode: Skipping migration" "Info"
        $stats.EndTime = Get-Date
        $stats.Duration = ($stats.EndTime - $stats.StartTime).TotalSeconds
        Export-Report
        Write-Progress-Message "Validation complete. Report saved to: $ReportPath" "Success"
        exit 0
    }
    
    # ========================================================================
    # PHASE 5: MIGRATE BACKUPS
    # ========================================================================
    Write-Progress-Message "PHASE 5: Migrating backups to new structure..." "Info"
    
    $migratedBackups = @()
    $backupCount = 0
    
    foreach ($backup in $backupInfos.Where({$_.Valid -and $_.IntegrityValid})) {
        $backupCount++
        $percentComplete = [math]::Round(($backupCount / $backupInfos.Where({$_.IntegrityValid}).Count) * 100)
        
        $newPath = New-OrganizedPath -BackupInfo $backup -DestinationBase $DestinationPath
        
        if (-not $newPath) {
            Write-Progress-Message "[$percentComplete%] FAIL $($backup.Name) - Failed to generate destination path" "Error"
            $stats.BackupsFailed++
            continue
        }
        
        Write-Progress-Message "[$percentComplete%] Migrating $($backup.Name) -> $([System.IO.Path]::GetFileName($newPath))..." "Info"
        
        $copyResult = Copy-Backup -SourceBackup $backup.FullPath -DestinationBackup $newPath
        
        if ($copyResult.Success) {
            # Verify destination
            if (Test-Path -Path $newPath) {
                $migratedBackups += @{
                    SourceName = $backup.Name
                    SourcePath = $backup.FullPath
                    DestinationPath = $newPath
                    Version = $backup.SemanticVersion
                    Size = $backup.Size
                    Status = "Migrated"
                }
                
                $stats.BackupsMigrated++
                $stats.TotalSizeNew += $backup.Size
                Write-Progress-Message "[$percentComplete%] OK Migration successful" "Success"
            }
            else {
                Write-Progress-Message "[$percentComplete%] FAIL Destination verification failed" "Error"
                $stats.BackupsFailed++
            }
        }
        else {
            Write-Progress-Message "[$percentComplete%] FAIL Copy failed: $($copyResult.Error)" "Error"
            $stats.BackupsFailed++
        }
    }
    
    Write-Host ""
    Write-Progress-Message "Migration phase complete: $($stats.BackupsMigrated) migrated, $($stats.BackupsFailed) failed" "Info"
    Write-Host ""
    
    # ========================================================================
    # PHASE 6: CREATE INDEX
    # ========================================================================
    Write-Progress-Message "PHASE 6: Creating backup index..." "Info"
    
    $indexPath = Join-Path $DestinationPath "index.json"
    $indexResult = Create-BackupIndex -Backups $backupInfos -IndexPath $indexPath
    
    if ($indexResult.Success) {
        Write-Progress-Message "Index created: $($indexResult.Path)" "Success"
    }
    else {
        Write-Progress-Message "Index creation failed: $($indexResult.Error)" "Warning"
    }
    
    Write-Host ""
    
    # ========================================================================
    # PHASE 7: COMPRESS ARCHIVE (OPTIONAL)
    # ========================================================================
    if ($CompressArchive) {
        Write-Progress-Message "PHASE 7: Compressing old backups to archive..." "Info"
        
        $archivePath = Join-Path $SourcePath "archive_$timestamp.zip"
        Write-Progress-Message "Creating archive: $archivePath" "Info"
        
        $compressResult = Compress-BackupArchive -SourcePath $SourcePath -ArchivePath $archivePath
        
        if ($compressResult.Success) {
            Write-Progress-Message "Archive created successfully" "Success"
            $stats | Add-Member -NotePropertyName ArchivePath -NotePropertyValue $archivePath -Force
        }
        else {
            Write-Progress-Message "Archive creation failed: $($compressResult.Error)" "Warning"
        }
        
        Write-Host ""
    }
    
    # ========================================================================
    # PHASE 8: DELETE OLD BACKUPS (OPTIONAL)
    # ========================================================================
    if ($DeleteAfterMigration -and $stats.BackupsMigrated -gt 0) {
        Write-Progress-Message "PHASE 8: Deleting old backups..." "Info"
        
        $deleteCount = 0
        $deleteFailures = 0
        
        foreach ($backup in $migratedBackups) {
            try {
                Remove-Item -Path $backup.SourcePath -Recurse -Force -ErrorAction Stop
                Write-Progress-Message "Deleted: $($backup.SourceName)" "Success"
                $deleteCount++
            }
            catch {
                Write-Progress-Message "Failed to delete $($backup.SourceName): $_" "Warning"
                $deleteFailures++
            }
        }
        
        Write-Progress-Message "Deletion complete: $deleteCount deleted, $deleteFailures failed" "Info"
        Write-Host ""
    }
    
    # ========================================================================
    # FINALIZE
    # ========================================================================
    $stats.EndTime = Get-Date
    $stats.Duration = ($stats.EndTime - $stats.StartTime).TotalSeconds
    
    Write-Progress-Message "Migration utility completed successfully" "Success"
    Write-Progress-Message "Total duration: $([math]::Round($stats.Duration, 2))s" "Info"
}

# ============================================================================
# EXPORT REPORT
# ============================================================================

function Export-Report {
    $report = @{
        Timestamp = Get-Date -Format "o"
        Statistics = $stats
        MigratedBackups = @($migrationLog)
        Errors = @($errors)
        Warnings = @($warnings)
        Configuration = @{
            SourcePath = $SourcePath
            DestinationPath = $DestinationPath
            ValidateOnly = $ValidateOnly
            DeleteAfterMigration = $DeleteAfterMigration
            CompressArchive = $CompressArchive
        }
    }
    
    try {
        $report | ConvertTo-Json -Depth 10 | Set-Content -Path $ReportPath -Force
        Write-Progress-Message "Report exported to: $ReportPath" "Success"
    }
    catch {
        Write-Progress-Message "Failed to export report: $_" "Error"
    }
}

# ============================================================================
# EXECUTION
# ============================================================================

try {
    Main
    Export-Report
}
catch {
    Write-Progress-Message "Fatal error: $_" "Error"
    $errors += "Fatal error: $_"
    Export-Report
    exit 1
}
