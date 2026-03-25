#Requires -Version 5.0
<#
.SYNOPSIS
    Intelligent Incremental Backup System with Hash-Based Change Detection
    
.DESCRIPTION
    After initial full backup, performs fast incremental backups by:
    - Comparing current state to last backup using file hashes
    - Only backing up changed files
    - Detecting new and deleted files
    - Creating delta-based incremental backups (only changes stored)
    - Supports automatic daily incremental backups
    - Weekly full backups with compression of old incrementals
    - Retention policy (keep 4 weeks)
    - Space-efficient delta storage

.PARAMETER SourcePath
    Root directory to backup

.PARAMETER BackupRoot
    Root directory for all backups

.PARAMETER Force
    Force full backup even if recent full backup exists

.PARAMETER Incremental
    Force incremental backup (skip full backup check)

.PARAMETER Cleanup
    Run retention policy and compress old incrementals

.NOTES
    Backup structure:
    BackupRoot\
      full\
        full-YYYYMMDD-HHMMSS\
          [full backup files]
      incremental\
        inc-YYYYMMDD-HHMMSS\
          [changed/new files only]
          deletions.txt
      metadata\
        full-manifest.json     (hash of all files in last full backup)
        backup-log.json        (backup history and state)
#>

param(
    [Parameter(Mandatory=$false)]
    [string]$SourcePath = "C:\Users\micha",
    
    [Parameter(Mandatory=$false)]
    [string]$BackupRoot = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\data",
    
    [switch]$Force,
    [switch]$Incremental,
    [switch]$Cleanup
)

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'

# Configuration
$Config = @{
    SourcePath       = $SourcePath
    BackupRoot       = $BackupRoot
    FullBackupDir    = Join-Path $BackupRoot "full"
    IncrementalDir   = Join-Path $BackupRoot "incremental"
    MetadataDir      = Join-Path $BackupRoot "metadata"
    LogFile          = Join-Path $BackupRoot "metadata\backup-log.txt"
    ManifestFile     = Join-Path $BackupRoot "metadata\full-manifest.json"
    StateFile        = Join-Path $BackupRoot "metadata\backup-state.json"
    RetentionDays    = 28  # Keep 4 weeks
    FullBackupDayOfWeek = "Sunday"
}

# Exclusions
$Exclusions = @(
    '*.tmp', '*.temp', '~*', '$Recycle.Bin', 'System Volume Information',
    '.git', 'node_modules', '__pycache__', '.venv', 'venv',
    '*.log', 'thumbs.db'
)

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

function Initialize-BackupDirectories {
    Write-Log "Initializing backup directories..."
    @($Config.FullBackupDir, $Config.IncrementalDir, $Config.MetadataDir) | ForEach-Object {
        if (-not (Test-Path $_)) {
            New-Item -ItemType Directory -Path $_ -Force | Out-Null
            Write-Log "Created directory: $_"
        }
    }
}

function Should-Exclude {
    param([string]$FilePath)
    
    $name = Split-Path $FilePath -Leaf
    $dir = Split-Path $FilePath -Parent
    
    foreach ($pattern in $Exclusions) {
        if ($name -like $pattern -or $dir -like "*$(($pattern -replace '\*', ''))*") {
            return $true
        }
    }
    return $false
}

function Get-FileHash {
    param([string]$FilePath)
    
    if (-not (Test-Path $FilePath)) {
        return $null
    }
    
    try {
        $hash = (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash
        return $hash
    }
    catch {
        Write-Log "Failed to hash $FilePath : $_" "WARN"
        return $null
    }
}

function Get-CurrentManifest {
    param([string]$Path)
    
    Write-Log "Scanning source directory for manifest..."
    $manifest = @{}
    $count = 0
    
    Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | 
        Where-Object { -not (Should-Exclude $_.FullName) } |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($Path.Length).TrimStart('\')
            $hash = Get-FileHash $_.FullName
            if ($hash) {
                $manifest[$relativePath] = @{
                    Hash = $hash
                    Size = $_.Length
                    Modified = $_.LastWriteTime.ToString("O")
                }
                $count++
            }
        }
    
    Write-Log "Scanned $count files for manifest"
    return $manifest
}

function Get-LastFullBackup {
    $fullDirs = Get-ChildItem -Path $Config.FullBackupDir -Directory -ErrorAction SilentlyContinue | 
                Sort-Object Name -Descending
    
    if ($fullDirs) {
        return $fullDirs[0]
    }
    return $null
}

function Get-LastBackupManifest {
    if (Test-Path $Config.ManifestFile) {
        try {
            return Get-Content $Config.ManifestFile -Raw | ConvertFrom-Json -AsHashtable
        }
        catch {
            Write-Log "Failed to load last manifest: $_" "WARN"
            return $null
        }
    }
    return $null
}

function Perform-FullBackup {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $Config.FullBackupDir "full-$timestamp"
    
    Write-Log "Starting FULL backup to: $backupDir"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    $manifest = @{}
    $fileCount = 0
    $startTime = Get-Date
    
    Get-ChildItem -Path $Config.SourcePath -Recurse -File -ErrorAction SilentlyContinue | 
        Where-Object { -not (Should-Exclude $_.FullName) } |
        ForEach-Object {
            $relativePath = $_.FullName.Substring($Config.SourcePath.Length).TrimStart('\')
            $destPath = Join-Path $backupDir $relativePath
            $destDir = Split-Path $destPath -Parent
            
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            try {
                Copy-Item -Path $_.FullName -Destination $destPath -Force -ErrorAction Stop | Out-Null
                $hash = Get-FileHash $_.FullName
                if ($hash) {
                    $manifest[$relativePath] = @{
                        Hash = $hash
                        Size = $_.Length
                        Modified = $_.LastWriteTime.ToString("O")
                    }
                    $fileCount++
                }
            }
            catch {
                Write-Log "Failed to copy $($_.FullName): $_" "WARN"
            }
        }
    
    $elapsed = (Get-Date) - $startTime
    Write-Log "FULL backup completed: $fileCount files copied in $([math]::Round($elapsed.TotalSeconds)) seconds"
    
    # Save manifest
    $manifest | ConvertTo-Json -Depth 10 | Set-Content -Path $Config.ManifestFile -Force
    Write-Log "Manifest saved to: $($Config.ManifestFile)"
    
    # Update state
    $state = @{
        LastFullBackup = $timestamp
        LastFullBackupPath = $backupDir
        LastIncrementalBackup = $null
        FileCount = $fileCount
        TotalSize = (Get-ChildItem -Path $backupDir -Recurse -File | Measure-Object -Property Length -Sum).Sum
    }
    $state | ConvertTo-Json | Set-Content -Path $Config.StateFile -Force
    
    return @{ Success = $true; BackupDir = $backupDir; FileCount = $fileCount }
}

function Perform-IncrementalBackup {
    $lastManifest = Get-LastBackupManifest
    
    if (-not $lastManifest) {
        Write-Log "No previous full backup manifest found. Performing full backup instead."
        return Perform-FullBackup
    }
    
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $backupDir = Join-Path $Config.IncrementalDir "inc-$timestamp"
    
    Write-Log "Starting INCREMENTAL backup to: $backupDir"
    New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
    
    $currentManifest = Get-CurrentManifest $Config.SourcePath
    
    # Find changed, new, and deleted files
    $changed = @()
    $new = @()
    $deleted = @()
    
    # Check for changed and new files
    foreach ($file in $currentManifest.Keys) {
        if ($lastManifest.ContainsKey($file)) {
            if ($currentManifest[$file].Hash -ne $lastManifest[$file].Hash) {
                $changed += $file
            }
        }
        else {
            $new += $file
        }
    }
    
    # Check for deleted files
    foreach ($file in $lastManifest.Keys) {
        if (-not $currentManifest.ContainsKey($file)) {
            $deleted += $file
        }
    }
    
    Write-Log "Changes detected - Changed: $($changed.Count), New: $($new.Count), Deleted: $($deleted.Count)"
    
    $startTime = Get-Date
    $copiedCount = 0
    
    # Copy changed files
    foreach ($file in $changed) {
        $srcPath = Join-Path $Config.SourcePath $file
        $destPath = Join-Path $backupDir $file
        $destDir = Split-Path $destPath -Parent
        
        if (Test-Path $srcPath) {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            try {
                Copy-Item -Path $srcPath -Destination $destPath -Force -ErrorAction Stop
                $copiedCount++
            }
            catch {
                Write-Log "Failed to copy changed file $srcPath : $_" "WARN"
            }
        }
    }
    
    # Copy new files
    foreach ($file in $new) {
        $srcPath = Join-Path $Config.SourcePath $file
        $destPath = Join-Path $backupDir $file
        $destDir = Split-Path $destPath -Parent
        
        if (Test-Path $srcPath) {
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            try {
                Copy-Item -Path $srcPath -Destination $destPath -Force -ErrorAction Stop
                $copiedCount++
            }
            catch {
                Write-Log "Failed to copy new file $srcPath : $_" "WARN"
            }
        }
    }
    
    # Save deletion list
    if ($deleted.Count -gt 0) {
        $deleted | Out-File -FilePath (Join-Path $backupDir "deletions.txt") -Encoding UTF8 -Force
    }
    
    $elapsed = (Get-Date) - $startTime
    Write-Log "INCREMENTAL backup completed: $copiedCount files copied (changed+new) in $([math]::Round($elapsed.TotalSeconds)) seconds"
    
    # Update manifest with current state
    $currentManifest | ConvertTo-Json -Depth 10 | Set-Content -Path $Config.ManifestFile -Force
    
    # Update state
    $state = Get-Content -Path $Config.StateFile -Raw | ConvertFrom-Json
    $state.LastIncrementalBackup = $timestamp
    $state | ConvertTo-Json | Set-Content -Path $Config.StateFile -Force
    
    return @{ 
        Success = $true
        BackupDir = $backupDir
        Changed = $changed.Count
        New = $new.Count
        Deleted = $deleted.Count
        Copied = $copiedCount
    }
}

function Invoke-RetentionPolicy {
    Write-Log "Running retention policy (keeping backups from last 28 days)..."
    
    $cutoffDate = (Get-Date).AddDays(-$Config.RetentionDays)
    $deleted = 0
    $compressed = 0
    
    # Clean old incremental backups
    Get-ChildItem -Path $Config.IncrementalDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { [datetime]::ParseExact($_.Name.Substring(4,15), "yyyyMMdd-HHmmss", $null) -lt $cutoffDate } |
        ForEach-Object {
            Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Deleted old incremental backup: $($_.Name)"
            $deleted++
        }
    
    # Compress incrementals older than 7 days
    $compressDate = (Get-Date).AddDays(-7)
    Get-ChildItem -Path $Config.IncrementalDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { 
            -not ($_.Name -like "*.zip") -and
            ([datetime]::ParseExact($_.Name.Substring(4,15), "yyyyMMdd-HHmmss", $null) -lt $compressDate)
        } |
        ForEach-Object {
            $zipPath = "$($_.FullName).zip"
            if (-not (Test-Path $zipPath)) {
                try {
                    Add-Type -AssemblyName System.IO.Compression.FileSystem
                    [System.IO.Compression.ZipFile]::CreateFromDirectory($_.FullName, $zipPath, 'Optimal', $false)
                    Remove-Item -Path $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Compressed incremental backup: $($_.Name)"
                    $compressed++
                }
                catch {
                    Write-Log "Failed to compress $($_.Name): $_" "WARN"
                }
            }
        }
    
    Write-Log "Retention policy complete: $deleted deleted, $compressed compressed"
}

# Main execution
try {
    Write-Log "========== Backup System Started =========="
    Write-Log "Source: $($Config.SourcePath)"
    Write-Log "Backup Root: $($Config.BackupRoot)"
    
    Initialize-BackupDirectories
    
    # Determine backup type
    $lastFullBackup = Get-LastFullBackup
    $dayOfWeek = (Get-Date).DayOfWeek.ToString()
    
    if ($Force) {
        Write-Log "Force flag set. Performing full backup."
        $result = Perform-FullBackup
    }
    elseif ($Incremental) {
        Write-Log "Incremental flag set. Forcing incremental backup."
        $result = Perform-IncrementalBackup
    }
    elseif (-not $lastFullBackup -or $dayOfWeek -eq $Config.FullBackupDayOfWeek) {
        Write-Log "No previous full backup or weekly full backup day. Performing full backup."
        $result = Perform-FullBackup
    }
    else {
        Write-Log "Performing incremental backup."
        $result = Perform-IncrementalBackup
    }
    
    if ($Cleanup) {
        Invoke-RetentionPolicy
    }
    
    Write-Log "========== Backup Completed Successfully =========="
    Write-Output $result | ConvertTo-Json
}
catch {
    Write-Log "FATAL ERROR: $_" "ERROR"
    Write-Log $_.ScriptStackTrace "ERROR"
    exit 1
}
