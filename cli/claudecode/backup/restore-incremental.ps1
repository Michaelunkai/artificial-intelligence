#Requires -Version 5.0
<#
.SYNOPSIS
    Restore from Incremental Backup System
    
.DESCRIPTION
    Restores files from incremental backup by:
    - Applying the last full backup first
    - Then applying all incremental layers in order
    - Processing deletions to result in exact current state
    - Supports selective restore and validation
    
.PARAMETER RestorePath
    Where to restore files (defaults to source original)

.PARAMETER SpecificPoint
    Restore to specific backup point (timestamp YYYYMMDD-HHMMSS)

.PARAMETER DryRun
    Show what would be restored without actually doing it

.PARAMETER Validate
    Validate restored files against manifest hashes

.PARAMETER List
    List available backup points

.NOTES
    Restore process:
    1. Find last full backup before specified point
    2. Copy all files from full backup
    3. Apply incrementals in chronological order
    4. Remove files listed in deletions.txt
    5. Validate if requested
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$RestorePath = "C:\Users\micha",
    
    [Parameter(Mandatory=$false)]
    [string]$BackupRoot = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\data",
    
    [Parameter(Mandatory=$false)]
    [string]$SpecificPoint = $null,
    
    [switch]$DryRun,
    [switch]$Validate,
    [switch]$List,
    [switch]$Force
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$Config = @{
    BackupRoot       = $BackupRoot
    FullBackupDir    = Join-Path $BackupRoot "full"
    IncrementalDir   = Join-Path $BackupRoot "incremental"
    MetadataDir      = Join-Path $BackupRoot "metadata"
    LogFile          = Join-Path $BackupRoot "metadata\restore-log.txt"
    ManifestFile     = Join-Path $BackupRoot "metadata\full-manifest.json"
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $logMsg
    
    # Ensure log directory exists
    $logDir = Split-Path $Config.LogFile -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    
    Add-Content -Path $Config.LogFile -Value $logMsg -Force
}

function Get-BackupPoints {
    $points = @()
    
    # Get full backups
    Get-ChildItem -Path $Config.FullBackupDir -Directory -ErrorAction SilentlyContinue |
        ForEach-Object {
            if ($_.Name -match 'full-(\d{8})-(\d{6})') {
                $points += @{
                    Type = "Full"
                    Timestamp = $matches[1] + $matches[2]
                    Name = $_.Name
                    Path = $_.FullName
                }
            }
        }
    
    # Get incremental backups
    Get-ChildItem -Path $Config.IncrementalDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like 'inc-*' -and $_.Name -notlike '*.zip' } |
        ForEach-Object {
            if ($_.Name -match 'inc-(\d{8})-(\d{6})') {
                $points += @{
                    Type = "Incremental"
                    Timestamp = $matches[1] + $matches[2]
                    Name = $_.Name
                    Path = $_.FullName
                }
            }
        }
    
    return $points | Sort-Object Timestamp
}

function List-BackupPoints {
    Write-Host "`n========== Available Backup Points ==========" -ForegroundColor Cyan
    
    $points = Get-BackupPoints
    
    if ($points.Count -eq 0) {
        Write-Host "No backup points found." -ForegroundColor Yellow
        return
    }
    
    $points | ForEach-Object {
        $timestamp = $_.Timestamp
        $date = [datetime]::ParseExact($timestamp, "yyyyMMddHHmmss", $null)
        $type = $_.Type
        $size = (Get-ChildItem -Path $_.Path -Recurse -File | Measure-Object -Property Length -Sum).Sum / 1MB
        Write-Host "$($date.ToString('yyyy-MM-dd HH:mm:ss')) | $type | $([math]::Round($size, 2)) MB | $($_.Name)"
    }
    Write-Host "=========================================`n" -ForegroundColor Cyan
}

function Get-RestorePoints {
    param([string]$UntilPoint)
    
    $points = Get-BackupPoints
    $fullBackup = $null
    $incrementals = @()
    
    foreach ($point in $points) {
        if ($UntilPoint) {
            if ($point.Timestamp -gt $UntilPoint) {
                break
            }
        }
        
        if ($point.Type -eq "Full") {
            $fullBackup = $point
            $incrementals = @()
        }
        else {
            $incrementals += $point
        }
    }
    
    if (-not $fullBackup) {
        throw "No full backup found before specified point!"
    }
    
    return @{
        Full = $fullBackup
        Incrementals = $incrementals
    }
}

function Restore-From-Backup {
    param(
        [string]$RestorePath,
        [object]$RestorePoints,
        [bool]$DryRun = $false
    )
    
    Write-Log "========== Restore Started =========="
    Write-Log "Restore destination: $RestorePath"
    
    if ($DryRun) {
        Write-Log "DRY RUN MODE - No files will be modified"
    }
    
    $startTime = Get-Date
    $totalCopied = 0
    $totalDeleted = 0
    
    # Step 1: Restore from full backup
    Write-Log "Step 1: Restoring from full backup: $($RestorePoints.Full.Name)"
    
    $fullPath = $RestorePoints.Full.Path
    Get-ChildItem -Path $fullPath -Recurse -File -ErrorAction SilentlyContinue |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($fullPath.Length).TrimStart('\')
            $destPath = Join-Path $RestorePath $relativePath
            $destDir = Split-Path $destPath -Parent
            
            if (-not $DryRun) {
                if (-not (Test-Path $destDir)) {
                    New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                }
                
                try {
                    Copy-Item -Path $_.FullName -Destination $destPath -Force -ErrorAction Stop
                    $totalCopied++
                }
                catch {
                    Write-Log "Failed to restore $relativePath : $_" "WARN"
                }
            }
            else {
                Write-Host "  [DRY] Copy: $relativePath" -ForegroundColor Gray
                $totalCopied++
            }
        }
    
    Write-Log "Full backup restored: $totalCopied files"
    
    # Step 2: Apply incremental backups in order
    if ($RestorePoints.Incrementals.Count -gt 0) {
        Write-Log "Step 2: Applying $($RestorePoints.Incrementals.Count) incremental backups in order"
        
        foreach ($inc in $RestorePoints.Incrementals) {
            Write-Log "Applying incremental: $($inc.Name)"
            $incPath = $inc.Path
            
            # Copy changed/new files
            Get-ChildItem -Path $incPath -Recurse -File -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -ne "deletions.txt" } |
                ForEach-Object {
                    $relativePath = $_.FullName.Substring($incPath.Length).TrimStart('\')
                    $destPath = Join-Path $RestorePath $relativePath
                    $destDir = Split-Path $destPath -Parent
                    
                    if (-not $DryRun) {
                        if (-not (Test-Path $destDir)) {
                            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                        }
                        
                        try {
                            Copy-Item -Path $_.FullName -Destination $destPath -Force -ErrorAction Stop
                            $totalCopied++
                        }
                        catch {
                            Write-Log "Failed to apply change $relativePath : $_" "WARN"
                        }
                    }
                    else {
                        Write-Host "  [DRY] Update: $relativePath" -ForegroundColor Gray
                        $totalCopied++
                    }
                }
            
            # Process deletions
            $deletionsFile = Join-Path $incPath "deletions.txt"
            if (Test-Path $deletionsFile) {
                $deletions = Get-Content $deletionsFile -ErrorAction SilentlyContinue
                if ($deletions) {
                    foreach ($delFile in $deletions) {
                        $fullPath = Join-Path $RestorePath $delFile
                        if (Test-Path $fullPath) {
                            if (-not $DryRun) {
                                try {
                                    Remove-Item -Path $fullPath -Force -ErrorAction Stop
                                    $totalDeleted++
                                    Write-Log "Deleted: $delFile"
                                }
                                catch {
                                    Write-Log "Failed to delete $delFile : $_" "WARN"
                                }
                            }
                            else {
                                Write-Host "  [DRY] Delete: $delFile" -ForegroundColor Gray
                                $totalDeleted++
                            }
                        }
                    }
                }
            }
        }
    }
    
    $elapsed = (Get-Date) - $startTime
    Write-Log "========== Restore Completed =========="
    Write-Log "Total files processed: $($totalCopied + $totalDeleted)"
    Write-Log "Files copied/updated: $totalCopied"
    Write-Log "Files deleted: $totalDeleted"
    Write-Log "Time elapsed: $([math]::Round($elapsed.TotalSeconds)) seconds"
    
    return @{
        Success = $true
        TotalCopied = $totalCopied
        TotalDeleted = $totalDeleted
        ElapsedSeconds = $elapsed.TotalSeconds
    }
}

function Validate-Restore {
    param([string]$RestorePath)
    
    Write-Log "Validating restored files..."
    
    if (-not (Test-Path $Config.ManifestFile)) {
        Write-Log "No manifest file found. Skipping validation." "WARN"
        return @{ Success = $false; Reason = "No manifest" }
    }
    
    try {
        $manifest = Get-Content $Config.ManifestFile -Raw | ConvertFrom-Json -AsHashtable
    }
    catch {
        Write-Log "Failed to load manifest: $_" "WARN"
        return @{ Success = $false; Reason = "Manifest load failed" }
    }
    
    $valid = 0
    $invalid = 0
    $missing = 0
    
    foreach ($file in $manifest.Keys) {
        $fullPath = Join-Path $RestorePath $file
        
        if (-not (Test-Path $fullPath)) {
            $missing++
            Write-Log "Missing file: $file" "WARN"
            continue
        }
        
        $currentHash = (Get-FileHash -Path $fullPath -Algorithm SHA256).Hash
        $expectedHash = $manifest[$file].Hash
        
        if ($currentHash -eq $expectedHash) {
            $valid++
        }
        else {
            $invalid++
            Write-Log "Hash mismatch: $file (expected: $expectedHash, got: $currentHash)" "WARN"
        }
    }
    
    $total = $valid + $invalid + $missing
    $percentage = if ($total -gt 0) { [math]::Round(($valid / $total) * 100, 2) } else { 0 }
    
    Write-Log "Validation complete: $valid/$total files valid ($percentage%) | $invalid invalid | $missing missing"
    
    return @{
        Success = ($invalid -eq 0 -and $missing -eq 0)
        Valid = $valid
        Invalid = $invalid
        Missing = $missing
        Percentage = $percentage
    }
}

# Main execution
try {
    Write-Log "========== Restore System Started =========="
    
    if ($List) {
        List-BackupPoints
        Write-Log "Backup points listed"
        exit 0
    }
    
    # Validate paths
    if (-not (Test-Path $Config.BackupRoot)) {
        throw "Backup root path not found: $($Config.BackupRoot)"
    }
    
    # Get restore points
    $restorePoints = Get-RestorePoints -UntilPoint $SpecificPoint
    
    if (-not $restorePoints.Full) {
        throw "No suitable backup found for restore!"
    }
    
    Write-Log "Restore plan:"
    Write-Log "  Full backup: $($restorePoints.Full.Name)"
    Write-Log "  Incremental backups to apply: $($restorePoints.Incrementals.Count)"
    
    if (-not $Force -and -not $DryRun) {
        Write-Host "`nWARNING: This will overwrite files in $RestorePath" -ForegroundColor Yellow
        $confirm = Read-Host "Continue? (yes/no)"
        if ($confirm -ne "yes") {
            Write-Log "Restore cancelled by user"
            exit 0
        }
    }
    
    # Perform restore
    $result = Restore-From-Backup -RestorePath $RestorePath -RestorePoints $restorePoints -DryRun $DryRun
    
    # Validate if requested
    if ($Validate -and -not $DryRun) {
        $valResult = Validate-Restore -RestorePath $RestorePath
        $result.Validation = $valResult
    }
    
    Write-Output $result | ConvertTo-Json
}
catch {
    Write-Log "FATAL ERROR: $_" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
