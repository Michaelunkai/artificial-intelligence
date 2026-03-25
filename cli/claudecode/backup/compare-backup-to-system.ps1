#Requires -Version 5.0
<#
.SYNOPSIS
Compares backup files to current system files and reports differences.

.DESCRIPTION
Analyzes a backup directory against current system files and identifies:
- Files added since backup
- Files modified since backup
- Files deleted since backup
- File size changes
- Timestamp changes

.PARAMETER BackupPath
Path to the backup directory to compare against.

.PARAMETER CurrentPath
Path to the current system directory. Defaults to the backup parent directory.

.PARAMETER OutputFormat
Report format: 'Console', 'CSV', or 'JSON'. Default is 'Console'.

.PARAMETER OutputFile
Path to save report file (for CSV/JSON output).

.PARAMETER Sync
If specified, copies new/modified files back to backup directory.

.PARAMETER ExcludePatterns
Array of patterns to exclude (wildcards supported).

.EXAMPLE
.\compare-backup-to-system.ps1 -BackupPath "D:\Backup\MyProject" -OutputFormat Console

.EXAMPLE
.\compare-backup-to-system.ps1 -BackupPath "D:\Backup\MyProject" -OutputFormat JSON -OutputFile "report.json"

.EXAMPLE
.\compare-backup-to-system.ps1 -BackupPath "D:\Backup\MyProject" -Sync
#>

param(
    [Parameter(Mandatory=$true, HelpMessage="Path to backup directory")]
    [ValidateScript({Test-Path $_ -PathType Container})]
    [string]$BackupPath,

    [Parameter(HelpMessage="Path to current system directory (defaults to backup parent)")]
    [string]$CurrentPath,

    [ValidateSet('Console', 'CSV', 'JSON')]
    [string]$OutputFormat = 'Console',

    [string]$OutputFile,

    [switch]$Sync,

    [string[]]$ExcludePatterns = @('*.tmp', 'thumbs.db', '.DS_Store')
)

# ============================================================================
# FUNCTIONS
# ============================================================================

function Test-ExcludePattern {
    param([string]$Path, [string[]]$Patterns)
    
    foreach ($pattern in $Patterns) {
        if ($Path -like $pattern) { return $true }
    }
    return $false
}

function Get-FileHash {
    param([string]$FilePath)
    
    try {
        $hash = (Get-FileHash -Path $FilePath -Algorithm SHA256 -ErrorAction Stop).Hash
        return $hash
    }
    catch {
        return $null
    }
}

function Compare-Directories {
    param(
        [string]$BackupDir,
        [string]$CurrentDir,
        [string[]]$Exclude
    )

    $results = @{
        Added = @()
        Modified = @()
        Deleted = @()
        SizeChanges = @()
        TimestampChanges = @()
        AllFiles = @()
    }

    # Get all files from backup
    $backupFiles = @{}
    Get-ChildItem -Path $BackupDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
        $relative = $_.FullName.Substring($BackupDir.Length + 1)
        if (-not (Test-ExcludePattern -Path $relative -Patterns $Exclude)) {
            $backupFiles[$relative] = @{
                FullPath = $_.FullName
                Size = $_.Length
                Modified = $_.LastWriteTime
                Hash = $null
            }
        }
    }

    # Get all files from current
    $currentFiles = @{}
    if (Test-Path -Path $CurrentDir) {
        Get-ChildItem -Path $CurrentDir -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
            $relative = $_.FullName.Substring($CurrentDir.Length + 1)
            if (-not (Test-ExcludePattern -Path $relative -Patterns $Exclude)) {
                $currentFiles[$relative] = @{
                    FullPath = $_.FullName
                    Size = $_.Length
                    Modified = $_.LastWriteTime
                    Hash = $null
                }
            }
        }
    }

    # Compare files
    Write-Host "Analyzing files..." -ForegroundColor Cyan
    $totalFiles = ($backupFiles.Keys | Measure-Object).Count + ($currentFiles.Keys | Measure-Object).Count
    $processed = 0

    # Check for added files (in current but not in backup)
    foreach ($file in $currentFiles.Keys) {
        $processed++
        if ($processed % 100 -eq 0) { Write-Host "Progress: $processed/$totalFiles" -ForegroundColor Gray }

        if (-not $backupFiles.ContainsKey($file)) {
            $results.Added += @{
                File = $file
                Path = $currentFiles[$file].FullPath
                Size = $currentFiles[$file].Size
                Modified = $currentFiles[$file].Modified
            }
        }
    }

    # Check for deleted files (in backup but not in current) and modifications
    foreach ($file in $backupFiles.Keys) {
        $processed++
        if ($processed % 100 -eq 0) { Write-Host "Progress: $processed/$totalFiles" -ForegroundColor Gray }

        if ($currentFiles.ContainsKey($file)) {
            # File exists in both - check for modifications
            $backupFile = $backupFiles[$file]
            $currentFile = $currentFiles[$file]

            $sizeChanged = $backupFile.Size -ne $currentFile.Size
            $timeChanged = $backupFile.Modified -ne $currentFile.Modified

            # Only compute hash if we need to determine modification
            if ($sizeChanged -or $timeChanged) {
                $backupFile.Hash = Get-FileHash -FilePath $backupFile.FullPath
                $currentFile.Hash = Get-FileHash -FilePath $currentFile.FullPath

                $hashChanged = $backupFile.Hash -ne $currentFile.Hash

                if ($hashChanged) {
                    $results.Modified += @{
                        File = $file
                        Path = $currentFile.FullPath
                        BackupSize = $backupFile.Size
                        CurrentSize = $currentFile.Size
                        BackupModified = $backupFile.Modified
                        CurrentModified = $currentFile.Modified
                        BackupHash = $backupFile.Hash
                        CurrentHash = $currentFile.Hash
                    }
                }
                elseif ($sizeChanged -or $timeChanged) {
                    # Size or timestamp changed but content is same
                    $results.TimestampChanges += @{
                        File = $file
                        Path = $currentFile.FullPath
                        BackupModified = $backupFile.Modified
                        CurrentModified = $currentFile.Modified
                        BackupSize = $backupFile.Size
                        CurrentSize = $currentFile.Size
                    }

                    if ($sizeChanged) {
                        $results.SizeChanges += @{
                            File = $file
                            BackupSize = $backupFile.Size
                            CurrentSize = $currentFile.Size
                            SizeDifference = $currentFile.Size - $backupFile.Size
                        }
                    }
                }
            }

            $results.AllFiles += @{
                File = $file
                Status = "Unchanged"
                Size = $currentFile.Size
                Modified = $currentFile.Modified
            }
        }
        else {
            # File only in backup - deleted
            $results.Deleted += @{
                File = $file
                Path = $backupFile.FullPath
                Size = $backupFile.Size
                Modified = $backupFile.Modified
            }
        }
    }

    return $results
}

function Format-ConsoleReport {
    param([hashtable]$Results)

    $output = @()
    $output += "`n" + ("=" * 80)
    $output += "BACKUP COMPARISON REPORT"
    $output += ("=" * 80)
    $output += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"

    # Summary
    $output += "SUMMARY"
    $output += "-" * 40
    $output += "Added files:           $($Results.Added.Count)"
    $output += "Modified files:        $($Results.Modified.Count)"
    $output += "Deleted files:         $($Results.Deleted.Count)"
    $output += "Files with size change: $($Results.SizeChanges.Count)"
    $output += "Files with timestamp change: $($Results.TimestampChanges.Count)"
    $output += "Unchanged files:       $($Results.AllFiles.Count)`n"

    # Added files
    if ($Results.Added.Count -gt 0) {
        $output += "ADDED FILES (in current system, not in backup)"
        $output += "-" * 40
        foreach ($file in $Results.Added | Sort-Object File) {
            $output += "  📄 $($file.File)"
            $output += "     Size: $("{0:N0}" -f $file.Size) bytes"
            $output += "     Modified: $($file.Modified.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        $output += ""
    }

    # Modified files
    if ($Results.Modified.Count -gt 0) {
        $output += "MODIFIED FILES (content changed)"
        $output += "-" * 40
        foreach ($file in $Results.Modified | Sort-Object File) {
            $output += "  ✏️  $($file.File)"
            $output += "     Backup Size: $("{0:N0}" -f $file.BackupSize) bytes → Current: $("{0:N0}" -f $file.CurrentSize) bytes"
            $output += "     Backup Time: $($file.BackupModified.ToString('yyyy-MM-dd HH:mm:ss'))"
            $output += "     Current Time: $($file.CurrentModified.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        $output += ""
    }

    # Deleted files
    if ($Results.Deleted.Count -gt 0) {
        $output += "DELETED FILES (in backup, not in current)"
        $output += "-" * 40
        foreach ($file in $Results.Deleted | Sort-Object File) {
            $output += "  🗑️  $($file.File)"
            $output += "     Size: $("{0:N0}" -f $file.Size) bytes"
            $output += "     Modified: $($file.Modified.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        $output += ""
    }

    # Size changes
    if ($Results.SizeChanges.Count -gt 0) {
        $output += "SIZE CHANGES (metadata only, content unchanged)"
        $output += "-" * 40
        foreach ($file in $Results.SizeChanges | Sort-Object File) {
            $diff = $file.SizeDifference
            $sign = if ($diff -gt 0) { "+" } else { "" }
            $output += "  📊 $($file.File)"
            $output += "     Backup: $("{0:N0}" -f $file.BackupSize) bytes → Current: $("{0:N0}" -f $file.CurrentSize) bytes ($sign$("{0:N0}" -f $diff) bytes)"
        }
        $output += ""
    }

    # Timestamp changes
    if ($Results.TimestampChanges.Count -gt 0) {
        $output += "TIMESTAMP CHANGES (metadata only, content unchanged)"
        $output += "-" * 40
        foreach ($file in $Results.TimestampChanges | Sort-Object File) {
            $output += "  🕐 $($file.File)"
            $output += "     Backup: $($file.BackupModified.ToString('yyyy-MM-dd HH:mm:ss')) → Current: $($file.CurrentModified.ToString('yyyy-MM-dd HH:mm:ss'))"
        }
        $output += ""
    }

    $output += ("=" * 80) + "`n"
    return $output -join "`n"
}

function Format-CSVReport {
    param([hashtable]$Results)

    $csv = @()
    $csv += "Category,File,Details,Size,Modified,BackupSize,CurrentSize,SizeDifference"

    foreach ($file in $Results.Added) {
        $csv += "Added,$($file.File),'Size: $("{0:N0}" -f $file.Size)',$("{0:N0}" -f $file.Size),$($file.Modified.ToString('yyyy-MM-dd HH:mm:ss')),,,"
    }

    foreach ($file in $Results.Modified) {
        $csv += "Modified,$($file.File),'Content changed',$("{0:N0}" -f $file.CurrentSize),$($file.CurrentModified.ToString('yyyy-MM-dd HH:mm:ss')),$("{0:N0}" -f $file.BackupSize),$("{0:N0}" -f $file.CurrentSize),$($file.CurrentSize - $file.BackupSize)"
    }

    foreach ($file in $Results.Deleted) {
        $csv += "Deleted,$($file.File),'Not in current',$("{0:N0}" -f $file.Size),$($file.Modified.ToString('yyyy-MM-dd HH:mm:ss')),,,"
    }

    foreach ($file in $Results.SizeChanges) {
        $csv += "SizeChange,$($file.File),'Metadata only',$("{0:N0}" -f $file.CurrentSize),,$("{0:N0}" -f $file.BackupSize),$("{0:N0}" -f $file.CurrentSize),$($file.SizeDifference)"
    }

    foreach ($file in $Results.TimestampChanges) {
        $csv += "TimestampChange,$($file.File),'Metadata only',$("{0:N0}" -f $file.CurrentSize),$($file.CurrentModified.ToString('yyyy-MM-dd HH:mm:ss')),,,"
    }

    return $csv -join "`n"
}

function Format-JSONReport {
    param([hashtable]$Results)

    $report = @{
        Generated = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
        Summary = @{
            Added = $Results.Added.Count
            Modified = $Results.Modified.Count
            Deleted = $Results.Deleted.Count
            SizeChanges = $Results.SizeChanges.Count
            TimestampChanges = $Results.TimestampChanges.Count
            Unchanged = $Results.AllFiles.Count
        }
        Details = @{
            Added = $Results.Added
            Modified = $Results.Modified
            Deleted = $Results.Deleted
            SizeChanges = $Results.SizeChanges
            TimestampChanges = $Results.TimestampChanges
        }
    }

    return $report | ConvertTo-Json -Depth 10
}

function Sync-FilesToBackup {
    param(
        [string]$BackupPath,
        [string]$CurrentPath,
        [hashtable]$Results
    )

    Write-Host "`nStarting sync operation..." -ForegroundColor Cyan
    $syncCount = 0

    # Sync added files
    foreach ($file in $Results.Added) {
        $backupTarget = Join-Path -Path $BackupPath -ChildPath $file.File
        $backupDir = Split-Path -Path $backupTarget
        
        if (-not (Test-Path -Path $backupDir)) {
            New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
        }

        try {
            Copy-Item -Path $file.Path -Destination $backupTarget -Force
            Write-Host "✓ Synced added: $($file.File)" -ForegroundColor Green
            $syncCount++
        }
        catch {
            Write-Host "✗ Failed to sync: $($file.File) - $_" -ForegroundColor Red
        }
    }

    # Sync modified files
    foreach ($file in $Results.Modified) {
        $backupTarget = Join-Path -Path $BackupPath -ChildPath $file.File
        
        try {
            Copy-Item -Path $file.Path -Destination $backupTarget -Force
            Write-Host "✓ Synced modified: $($file.File)" -ForegroundColor Green
            $syncCount++
        }
        catch {
            Write-Host "✗ Failed to sync: $($file.File) - $_" -ForegroundColor Red
        }
    }

    Write-Host "`nSync complete. $syncCount files updated in backup." -ForegroundColor Green
}

# ============================================================================
# MAIN
# ============================================================================

try {
    # Resolve paths
    $BackupPath = Resolve-Path -Path $BackupPath
    
    if (-not $CurrentPath) {
        $CurrentPath = Split-Path -Path $BackupPath
    }
    
    if (-not (Test-Path -Path $CurrentPath)) {
        throw "Current path does not exist: $CurrentPath"
    }

    Write-Host "Backup Comparison Tool" -ForegroundColor Cyan
    Write-Host "Backup Path:  $BackupPath"
    Write-Host "Current Path: $CurrentPath"
    Write-Host ""

    # Run comparison
    $results = Compare-Directories -BackupDir $BackupPath -CurrentDir $CurrentPath -Exclude $ExcludePatterns

    # Generate report
    switch ($OutputFormat) {
        'Console' {
            $report = Format-ConsoleReport -Results $results
            Write-Host $report
        }
        'CSV' {
            if (-not $OutputFile) {
                $OutputFile = "backup-comparison-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
            }
            $report = Format-CSVReport -Results $results
            $report | Out-File -FilePath $OutputFile -Encoding UTF8
            Write-Host "CSV report saved: $OutputFile" -ForegroundColor Green
        }
        'JSON' {
            if (-not $OutputFile) {
                $OutputFile = "backup-comparison-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"
            }
            $report = Format-JSONReport -Results $results
            $report | Out-File -FilePath $OutputFile -Encoding UTF8
            Write-Host "JSON report saved: $OutputFile" -ForegroundColor Green
        }
    }

    # Sync if requested
    if ($Sync) {
        $confirm = Read-Host "Sync $($results.Added.Count + $results.Modified.Count) files to backup? (y/N)"
        if ($confirm -eq 'y') {
            Sync-FilesToBackup -BackupPath $BackupPath -CurrentPath $CurrentPath -Results $results
        }
        else {
            Write-Host "Sync cancelled." -ForegroundColor Yellow
        }
    }
}
catch {
    Write-Host "Error: $_" -ForegroundColor Red
    exit 1
}
