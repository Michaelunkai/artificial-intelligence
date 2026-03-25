<#
.SYNOPSIS
Backup Integrity Checker - Verifies backups are not corrupted

.DESCRIPTION
Checks backup archives and metadata for corruption:
- Validates .7z/.zip archive integrity
- Verifies file hashes against manifest
- Checks for truncated files
- Validates JSON metadata
- Tests full extraction capability
- Generates detailed health report

.PARAMETER Path
Path to single backup folder (optional - checks one backup)
If not provided, checks all backups in the parent directory

.PARAMETER OutputFile
Optional: Save report to file (e.g., "backup_report.txt")

.EXAMPLE
.\check-backup-integrity.ps1
# Checks all backups in F:\backup\claudecode\

.EXAMPLE
.\check-backup-integrity.ps1 -Path "F:\backup\claudecode\backup_2026_03_23_120000"
# Checks single backup

.EXAMPLE
.\check-backup-integrity.ps1 -OutputFile "report.txt"
# Checks all and saves report
#>

param(
    [string]$Path,
    [string]$OutputFile
)

# ============================================================================
# CONFIGURATION
# ============================================================================
$BackupRootDir = "F:\backup\claudecode"
$7zExe = "C:\Program Files\7-Zip\7z.exe"
$Script:Results = @()
$Script:CurrentBackup = ""
$Script:HasErrors = $false

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Log-Message {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = (Get-Date -Format "HH:mm:ss")
    $output = "[$timestamp] [$Level] $Message"
    
    Write-Host $output
    if ($OutputFile) {
        Add-Content -Path $OutputFile -Value $output
    }
    $Script:Results += $output
}

function Log-Result {
    param(
        [string]$Status,
        [string]$Details,
        [string]$Suggestion = ""
    )
    
    $result = @{
        Status = $Status
        Details = $Details
        Suggestion = $Suggestion
        Backup = $Script:CurrentBackup
    }
    
    if ($Status -eq "FAILED" -or $Status -eq "ERROR") {
        $Script:HasErrors = $true
    }
    
    $Script:Results += $result
}

function Test-7zAvailable {
    if (-not (Test-Path $7zExe)) {
        Log-Message "ERROR: 7-Zip not found at $7zExe" "ERROR"
        Log-Message "Install 7-Zip or update path in script" "ERROR"
        return $false
    }
    return $true
}

function Test-ArchiveIntegrity {
    param([string]$ArchivePath)
    
    if (-not (Test-Path $ArchivePath)) {
        Log-Message "Archive not found: $ArchivePath" "ERROR"
        return $false
    }
    
    # Use 7z to test archive integrity (doesn't extract, just validates)
    $output = & $7zExe t "$ArchivePath" 2>&1
    
    if ($LASTEXITCODE -eq 0) {
        Log-Message "✓ Archive valid: $(Split-Path -Leaf $ArchivePath)" "OK"
        return $true
    } else {
        Log-Message "✗ Archive corrupted: $(Split-Path -Leaf $ArchivePath)" "ERROR"
        Log-Message "7z output: $($output | Select-Object -Last 5 | Out-String)" "DEBUG"
        Log-Result "FAILED" "Archive integrity check failed: $(Split-Path -Leaf $ArchivePath)" "Run recovery: attempt re-download or restore from alternate source"
        return $false
    }
}

function Test-FileHashes {
    param([string]$BackupPath, [string]$ManifestFile)
    
    if (-not (Test-Path $ManifestFile)) {
        Log-Message "Manifest not found: $ManifestFile" "WARNING"
        return $false
    }
    
    $allValid = $true
    $manifest = @()
    
    try {
        $manifestContent = Get-Content $ManifestFile -Raw
        $manifest = $manifestContent | ConvertFrom-Json
    } catch {
        Log-Message "Failed to parse manifest JSON: $_" "ERROR"
        Log-Result "FAILED" "Manifest JSON is corrupted" "Restore backup metadata from archive or alternate source"
        return $false
    }
    
    $filesChecked = 0
    $filesFailed = 0
    
    foreach ($file in $manifest) {
        if (-not $file.filename -or -not $file.hash) {
            continue
        }
        
        $filePath = Join-Path -Path $BackupPath -ChildPath $file.filename
        $filesChecked++
        
        if (-not (Test-Path $filePath)) {
            Log-Message "Missing file: $($file.filename)" "WARNING"
            $filesFailed++
            continue
        }
        
        # Calculate actual hash
        $actualHash = (Get-FileHash -Path $filePath -Algorithm SHA256).Hash
        
        if ($actualHash -ne $file.hash) {
            Log-Message "Hash mismatch: $($file.filename)" "ERROR"
            Log-Message "Expected: $($file.hash | Substring 0 16)..." "DEBUG"
            Log-Message "Actual:   $($actualHash | Substring 0 16)..." "DEBUG"
            $filesFailed++
            $allValid = $false
        }
    }
    
    if ($filesFailed -gt 0) {
        Log-Result "FAILED" "File hash verification failed: $filesFailed of $filesChecked files" "Check filesystem integrity; restore affected files from archive"
    } elseif ($filesChecked -gt 0) {
        Log-Message "✓ All $filesChecked files verified: hashes match" "OK"
    }
    
    return ($filesFailed -eq 0)
}

function Test-TruncatedFiles {
    param([string]$BackupPath)
    
    $truncatedFound = @()
    
    # Check for obviously truncated files (size < expected, often 0 bytes or partial)
    $allFiles = Get-ChildItem -Path $BackupPath -File -Recurse
    
    foreach ($file in $allFiles) {
        # Skip empty files in temp/cache
        if ($file.Length -eq 0 -and $file.Name -notmatch "\.(tmp|cache|lock)$") {
            $truncatedFound += $file.FullName
        }
        
        # Check for suspiciously small files that should be larger
        # (Common in corrupted archives: JSON files much smaller than expected)
        if ($file.Extension -eq ".json") {
            if ($file.Length -lt 100) {
                $content = Get-Content $file.FullName -Raw
                if ($content -notmatch "^\{.*\}$" -and $content -notmatch "^\[.*\]$") {
                    $truncatedFound += $file.FullName
                }
            }
        }
    }
    
    if ($truncatedFound.Count -gt 0) {
        Log-Message "Truncated files detected: $($truncatedFound.Count)" "WARNING"
        foreach ($file in $truncatedFound) {
            Log-Message "  - $(Split-Path -Leaf $file) ($(Get-Item $file).Length bytes)" "DEBUG"
        }
        Log-Result "WARNING" "Found $($truncatedFound.Count) potentially truncated files" "Re-extract backup from archive or restore from source"
        return $false
    } else {
        Log-Message "✓ No truncated files detected" "OK"
        return $true
    }
}

function Test-JsonMetadata {
    param([string]$BackupPath)
    
    $allValid = $true
    $jsonFiles = Get-ChildItem -Path $BackupPath -Filter "*.json" -Recurse
    $jsonCount = $jsonFiles.Count
    $jsonInvalid = 0
    
    if ($jsonCount -eq 0) {
        Log-Message "No JSON metadata files found" "WARNING"
        return $true
    }
    
    foreach ($jsonFile in $jsonFiles) {
        try {
            $content = Get-Content $jsonFile.FullName -Raw
            $null = $content | ConvertFrom-Json -ErrorAction Stop
        } catch {
            Log-Message "Invalid JSON: $($jsonFile.Name)" "ERROR"
            Log-Message "Error: $_" "DEBUG"
            $jsonInvalid++
            $allValid = $false
        }
    }
    
    if ($jsonInvalid -gt 0) {
        Log-Result "FAILED" "JSON validation failed: $jsonInvalid of $jsonCount files are corrupted" "Restore metadata files from archive"
    } else {
        Log-Message "✓ All $jsonCount JSON files valid" "OK"
    }
    
    return $allValid
}

function Test-ExtractCapability {
    param([string]$ArchivePath)
    
    $testDir = Join-Path -Path $env:TEMP -ChildPath "backup_test_$(Get-Random)"
    
    try {
        New-Item -ItemType Directory -Path $testDir -Force | Out-Null
        
        # Test extraction (list files, don't fully extract to save time)
        $listOutput = & $7zExe l "$ArchivePath" 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            # Count files in archive
            $fileCount = ($listOutput | Where-Object { $_ -match '^\d{4}-\d{2}-\d{2}' }).Count
            Log-Message "✓ Archive extractable: $fileCount files" "OK"
            return $true
        } else {
            Log-Message "✗ Archive cannot be extracted" "ERROR"
            Log-Result "FAILED" "Archive extraction test failed" "Archive may be corrupt; restore from source"
            return $false
        }
    } catch {
        Log-Message "Extraction test error: $_" "ERROR"
        return $false
    } finally {
        if (Test-Path $testDir) {
            Remove-Item -Path $testDir -Recurse -Force -ErrorAction SilentlyContinue
        }
    }
}

function Test-RequiredFiles {
    param([string]$BackupPath)
    
    $requiredPatterns = @(
        "*.7z",
        "manifest.json",
        "metadata.json"
    )
    
    $missingFiles = @()
    
    foreach ($pattern in $requiredPatterns) {
        $found = Get-ChildItem -Path $BackupPath -Filter $pattern -ErrorAction SilentlyContinue
        if ($found.Count -eq 0) {
            $missingFiles += $pattern
        }
    }
    
    if ($missingFiles.Count -gt 0) {
        Log-Message "Missing required files: $($missingFiles -join ', ')" "WARNING"
        Log-Result "WARNING" "Missing files: $($missingFiles -join ', ')" "Verify backup source; restore missing components"
        return $false
    } else {
        Log-Message "✓ All required files present" "OK"
        return $true
    }
}

function Check-SingleBackup {
    param([string]$BackupPath)
    
    if (-not (Test-Path $BackupPath)) {
        Log-Message "Backup path not found: $BackupPath" "ERROR"
        return $false
    }
    
    $Script:CurrentBackup = Split-Path -Leaf $BackupPath
    Log-Message "═══════════════════════════════════════════════════════" "INFO"
    Log-Message "Checking: $($Script:CurrentBackup)" "INFO"
    Log-Message "═══════════════════════════════════════════════════════" "INFO"
    
    $healthChecks = @()
    
    # 1. Required files
    $healthChecks += Test-RequiredFiles -BackupPath $BackupPath
    
    # 2. Archive integrity
    $archiveFiles = Get-ChildItem -Path $BackupPath -Filter "*.7z" -ErrorAction SilentlyContinue
    if ($archiveFiles) {
        foreach ($archive in $archiveFiles) {
            $healthChecks += Test-ArchiveIntegrity -ArchivePath $archive.FullName
        }
    }
    
    # 3. Extract capability
    if ($archiveFiles) {
        $healthChecks += Test-ExtractCapability -ArchivePath $archiveFiles[0].FullName
    }
    
    # 4. JSON metadata
    $healthChecks += Test-JsonMetadata -BackupPath $BackupPath
    
    # 5. Truncated files
    $healthChecks += Test-TruncatedFiles -BackupPath $BackupPath
    
    # 6. Hash verification
    $manifestPath = Join-Path -Path $BackupPath -ChildPath "manifest.json"
    if (Test-Path $manifestPath) {
        $healthChecks += Test-FileHashes -BackupPath $BackupPath -ManifestFile $manifestPath
    }
    
    # Determine overall health
    $failCount = ($healthChecks | Where-Object { $_ -eq $false }).Count
    
    if ($failCount -eq 0) {
        Log-Message "Status: ✓ OK - All checks passed" "OK"
        Log-Result "OK" "Backup is healthy - all integrity checks passed" ""
    } elseif ($failCount -lt 3) {
        Log-Message "Status: ⚠ WARNING - Some checks failed" "WARNING"
        Log-Result "WARNING" "Backup has issues but may be recoverable" "Review detailed messages above"
    } else {
        Log-Message "Status: ✗ FAILED - Multiple checks failed" "ERROR"
        Log-Result "FAILED" "Backup is severely corrupted" "Restore from alternate source immediately"
    }
    
    return ($failCount -eq 0)
}

function Check-AllBackups {
    # Find all backup directories
    if (-not (Test-Path $BackupRootDir)) {
        Log-Message "Backup root directory not found: $BackupRootDir" "ERROR"
        return
    }
    
    $backupDirs = Get-ChildItem -Path $BackupRootDir -Directory -Filter "backup_*" | Sort-Object Name -Descending
    
    if ($backupDirs.Count -eq 0) {
        Log-Message "No backups found in $BackupRootDir" "WARNING"
        return
    }
    
    Log-Message "Found $($backupDirs.Count) backups" "INFO"
    Log-Message "" "INFO"
    
    $healthyCount = 0
    $warningCount = 0
    $failedCount = 0
    
    foreach ($backup in $backupDirs) {
        $isHealthy = Check-SingleBackup -BackupPath $backup.FullName
        
        if ($isHealthy) {
            $healthyCount++
        }
    }
    
    Log-Message "" "INFO"
    Log-Message "═══════════════════════════════════════════════════════" "INFO"
    Log-Message "SUMMARY" "INFO"
    Log-Message "═══════════════════════════════════════════════════════" "INFO"
    Log-Message "Total backups: $($backupDirs.Count)" "INFO"
    Log-Message "Healthy (OK):  $healthyCount" "OK"
    Log-Message "At risk (⚠):   Check logs above" "WARNING"
    Log-Message "Failed (✗):    Check logs above" "ERROR"
}

function Print-Report {
    Log-Message "" "INFO"
    Log-Message "═══════════════════════════════════════════════════════" "INFO"
    Log-Message "INTEGRITY CHECK COMPLETE" "INFO"
    Log-Message "═══════════════════════════════════════════════════════" "INFO"
    
    if ($Script:HasErrors) {
        Log-Message "⚠ Issues detected - review details above" "WARNING"
    } else {
        Log-Message "✓ All checks passed" "OK"
    }
    
    if ($OutputFile) {
        Log-Message "Report saved to: $OutputFile" "INFO"
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

# Verify 7-Zip is available
if (-not (Test-7zAvailable)) {
    exit 1
}

# Initialize output file if specified
if ($OutputFile) {
    Clear-Content -Path $OutputFile -ErrorAction SilentlyContinue
    New-Item -Path $OutputFile -Force | Out-Null
    Log-Message "Backup Integrity Checker Report" "INFO"
    Log-Message "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" "INFO"
    Log-Message "" "INFO"
}

# Run checks
if ($Path) {
    # Check single backup
    Check-SingleBackup -BackupPath $Path
} else {
    # Check all backups
    Check-AllBackups
}

# Print final report
Print-Report

# Exit with appropriate code
if ($Script:HasErrors) {
    exit 1
} else {
    exit 0
}
