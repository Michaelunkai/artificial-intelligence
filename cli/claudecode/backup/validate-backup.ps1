<#
.SYNOPSIS
    Validate Backup Script - Standalone backup integrity verification
.DESCRIPTION
    Comprehensive validation of Claude Code backups including:
    - SHA-256 hash verification
    - File structure validation
    - JSON syntax verification
    - Database integrity checks
    - Completeness assessment
    - Age and freshness checks
.PARAMETER BackupPath
    Path to backup directory or specific backup folder
.PARAMETER All
    Validate all backups in the backup root directory
.PARAMETER Detailed
    Show detailed file-by-file validation results
.EXAMPLE
    .\validate-backup.ps1 -BackupPath "F:\backup\claudecode\backup_2025_01_15"
    .\validate-backup.ps1 -All
.NOTES
    Version: 1.0
    Requires: PowerShell 5.0+
#>

param(
    [Parameter(Position=0)]
    [string]$BackupPath = "F:\backup\claudecode",
    [switch]$All,
    [switch]$Detailed,
    [switch]$Quiet
)

$ErrorActionPreference = "Continue"
$script:Errors = @()
$script:Warnings = @()
$script:ValidationResults = @()

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    if (-not $Quiet) {
        $timestamp = Get-Date -Format "HH:mm:ss"
        Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
        Write-Host $Message -ForegroundColor $Color
    }
}

function Write-ValidationResult {
    param(
        [string]$Category,
        [string]$Item,
        [string]$Status,
        [string]$Details = ""
    )

    $color = switch ($Status) {
        "PASS" { "Green" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        "SKIP" { "DarkGray" }
        default { "White" }
    }

    if (-not $Quiet -or $Status -eq "FAIL") {
        Write-Host "  [$Status] " -NoNewline -ForegroundColor $color
        Write-Host "$Category - $Item" -NoNewline
        if ($Details -and $Detailed) {
            Write-Host " ($Details)" -ForegroundColor DarkGray
        } else {
            Write-Host ""
        }
    }

    $script:ValidationResults += @{
        Category = $Category
        Item = $Item
        Status = $Status
        Details = $Details
    }

    if ($Status -eq "FAIL") {
        $script:Errors += "$Category - $Item"
    }
    if ($Status -eq "WARN") {
        $script:Warnings += "$Category - $Item"
    }
}

function Validate-SingleBackup {
    param([string]$BackupDir)

    Write-Host ""
    $backupName = Split-Path $BackupDir -Leaf
    Write-Status "Validating: $backupName" "Cyan"
    Write-Host ""

    $localErrors = @()
    $localWarnings = @()

    # 1. Check backup exists
    if (-not (Test-Path $BackupDir)) {
        Write-ValidationResult "Structure" "Backup Directory" "FAIL" "Does not exist"
        return @{ Valid = $false; Errors = 1; Warnings = 0 }
    }
    Write-ValidationResult "Structure" "Backup Directory" "PASS"

    # 2. Check manifest.json
    $manifestPath = Join-Path $BackupDir "manifest.json"
    $manifest = $null
    if (Test-Path $manifestPath) {
        try {
            $manifestContent = Get-Content $manifestPath -Raw
            $manifest = $manifestContent | ConvertFrom-Json
            Write-ValidationResult "Structure" "manifest.json" "PASS" "Valid JSON"

            if ($manifest.timestamp) {
                $backupAge = (Get-Date) - [DateTime]::Parse($manifest.timestamp)
                if ($backupAge.TotalDays -gt 30) {
                    $days = [math]::Round($backupAge.TotalDays)
                    Write-ValidationResult "Freshness" "Backup Age" "WARN" "$days days old"
                } elseif ($backupAge.TotalDays -gt 7) {
                    $days = [math]::Round($backupAge.TotalDays)
                    Write-ValidationResult "Freshness" "Backup Age" "PASS" "$days days old"
                } else {
                    $hours = [math]::Round($backupAge.TotalHours)
                    Write-ValidationResult "Freshness" "Backup Age" "PASS" "Recent ($hours hours)"
                }
            }

            if ($manifest.version) {
                Write-ValidationResult "Metadata" "Backup Version" "PASS" $manifest.version
            }
        } catch {
            Write-ValidationResult "Structure" "manifest.json" "FAIL" "Invalid JSON"
        }
    } else {
        Write-ValidationResult "Structure" "manifest.json" "WARN" "Missing (older backup format)"
    }

    # 3. Check essential directories
    $essentialDirs = @(
        @{ Path = ".claude"; Required = $true },
        @{ Path = "npm_global"; Required = $false },
        @{ Path = "registry"; Required = $false }
    )

    foreach ($dir in $essentialDirs) {
        $dirPath = Join-Path $BackupDir $dir.Path
        if (Test-Path $dirPath) {
            $fileCount = (Get-ChildItem $dirPath -Recurse -File -ErrorAction SilentlyContinue).Count
            Write-ValidationResult "Structure" $dir.Path "PASS" "$fileCount files"
        } elseif ($dir.Required) {
            Write-ValidationResult "Structure" $dir.Path "FAIL" "Missing required directory"
        } else {
            Write-ValidationResult "Structure" $dir.Path "SKIP" "Optional, not present"
        }
    }

    # 4. Check .claude.json
    $claudeJsonPath = Join-Path $BackupDir ".claude.json"
    if (Test-Path $claudeJsonPath) {
        try {
            $claudeJson = Get-Content $claudeJsonPath -Raw | ConvertFrom-Json
            Write-ValidationResult "Configuration" ".claude.json" "PASS" "Valid JSON"
        } catch {
            Write-ValidationResult "Configuration" ".claude.json" "FAIL" "Invalid JSON"
        }
    } else {
        Write-ValidationResult "Configuration" ".claude.json" "WARN" "Missing"
    }

    # 5. Check settings.json in .claude
    $settingsPath = Join-Path $BackupDir ".claude\settings.json"
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            Write-ValidationResult "Configuration" "settings.json" "PASS" "Valid JSON"
        } catch {
            Write-ValidationResult "Configuration" "settings.json" "FAIL" "Invalid JSON"
        }
    } else {
        Write-ValidationResult "Configuration" "settings.json" "FAIL" "Missing"
    }

    # 6. Verify SHA-256 hashes if available
    $hashesPath = Join-Path $BackupDir "file_hashes.json"
    if (Test-Path $hashesPath) {
        try {
            $hashes = Get-Content $hashesPath -Raw | ConvertFrom-Json
            $hashCount = 0
            $hashFailed = 0
            $hashChecked = 0

            if ($hashes.PSObject.Properties) {
                foreach ($prop in $hashes.PSObject.Properties) {
                    $hashCount++
                    $filePath = Join-Path $BackupDir $prop.Name
                    if (Test-Path $filePath) {
                        $currentHash = (Get-FileHash $filePath -Algorithm SHA256).Hash
                        if ($currentHash -eq $prop.Value) {
                            $hashChecked++
                        } else {
                            $hashFailed++
                            if ($Detailed) {
                                Write-ValidationResult "Integrity" $prop.Name "FAIL" "Hash mismatch"
                            }
                        }
                    }
                }
            }

            if ($hashFailed -eq 0 -and $hashChecked -gt 0) {
                Write-ValidationResult "Integrity" "SHA-256 Hashes" "PASS" "$hashChecked/$hashCount verified"
            } elseif ($hashFailed -gt 0) {
                Write-ValidationResult "Integrity" "SHA-256 Hashes" "FAIL" "$hashFailed files corrupted"
            } else {
                Write-ValidationResult "Integrity" "SHA-256 Hashes" "WARN" "No files to verify"
            }
        } catch {
            Write-ValidationResult "Integrity" "SHA-256 Hashes" "FAIL" "Could not parse hash file"
        }
    } else {
        Write-ValidationResult "Integrity" "SHA-256 Hashes" "SKIP" "No hash file present"
    }

    # 7. Check databases
    $dbFiles = Get-ChildItem -Path $BackupDir -Filter "*.db" -Recurse -ErrorAction SilentlyContinue
    if ($dbFiles.Count -gt 0) {
        foreach ($db in $dbFiles) {
            if ($db.Length -eq 0) {
                Write-ValidationResult "Database" $db.Name "FAIL" "Empty file"
            } elseif ($db.Length -lt 1024) {
                Write-ValidationResult "Database" $db.Name "WARN" "Very small ($($db.Length) bytes)"
            } else {
                $sizeKB = [math]::Round($db.Length/1KB, 1)
                Write-ValidationResult "Database" $db.Name "PASS" "$sizeKB KB"
            }
        }
    }

    # 8. Check npm packages list
    $npmPackagesPath = Join-Path $BackupDir "npm_global_packages.json"
    if (Test-Path $npmPackagesPath) {
        try {
            $npmPackages = Get-Content $npmPackagesPath -Raw | ConvertFrom-Json
            $packageCount = 0
            if ($npmPackages.dependencies) {
                $packageCount = ($npmPackages.dependencies.PSObject.Properties).Count
            }
            Write-ValidationResult "npm" "Global Packages List" "PASS" "$packageCount packages"
        } catch {
            Write-ValidationResult "npm" "Global Packages List" "FAIL" "Invalid JSON"
        }
    } else {
        Write-ValidationResult "npm" "Global Packages List" "SKIP" "Not present"
    }

    # 9. Check MCP configuration
    $mcpFiles = @(
        "mcp-ondemand.ps1",
        ".claude\mcp.json",
        ".claude\mcpServers.json"
    )
    $mcpFound = $false
    foreach ($mcpFile in $mcpFiles) {
        $mcpPath = Join-Path $BackupDir $mcpFile
        if (Test-Path $mcpPath) {
            Write-ValidationResult "MCP" $mcpFile "PASS"
            $mcpFound = $true
        }
    }
    if (-not $mcpFound) {
        Write-ValidationResult "MCP" "MCP Configuration" "WARN" "No MCP config found"
    }

    # 10. Calculate backup size
    $totalSize = (Get-ChildItem $BackupDir -Recurse -File -ErrorAction SilentlyContinue |
        Measure-Object -Property Length -Sum).Sum
    $sizeGB = $totalSize / 1GB
    $sizeMB = $totalSize / 1MB

    if ($sizeMB -lt 1) {
        $sizeKB = [math]::Round($totalSize/1KB, 1)
        Write-ValidationResult "Size" "Total Backup Size" "WARN" "$sizeKB KB (very small)"
    } else {
        $sizeMBRound = [math]::Round($sizeMB, 2)
        Write-ValidationResult "Size" "Total Backup Size" "PASS" "$sizeMBRound MB"
    }

    # 11. Check for compressed archive
    $archivePatterns = @("*.7z", "*.zip", "compressed.*")
    $archives = @()
    foreach ($pattern in $archivePatterns) {
        $archives += Get-ChildItem -Path $BackupDir -Filter $pattern -ErrorAction SilentlyContinue
    }
    if ($archives.Count -gt 0) {
        foreach ($archive in $archives) {
            $archiveSizeMB = [math]::Round($archive.Length/1MB, 2)
            Write-ValidationResult "Compression" $archive.Name "PASS" "$archiveSizeMB MB"
        }
    }

    # Summary for this backup
    $localErrors = ($script:ValidationResults | Where-Object { $_.Status -eq "FAIL" }).Count
    $localWarnings = ($script:ValidationResults | Where-Object { $_.Status -eq "WARN" }).Count
    $localPassed = ($script:ValidationResults | Where-Object { $_.Status -eq "PASS" }).Count

    $timestampValue = "Unknown"
    if ($manifest -and $manifest.timestamp) {
        $timestampValue = $manifest.timestamp
    }

    return @{
        Valid = ($localErrors -eq 0)
        Path = $BackupDir
        Errors = $localErrors
        Warnings = $localWarnings
        Passed = $localPassed
        Size = $totalSize
        Timestamp = $timestampValue
    }
}

# Banner
if (-not $Quiet) {
    Write-Host ""
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host "          Claude Code Backup Validator v1.0                    " -ForegroundColor Cyan
    Write-Host "          Standalone backup integrity verification             " -ForegroundColor Cyan
    Write-Host "================================================================" -ForegroundColor Cyan
    Write-Host ""
}

# Determine what to validate
$backupsToValidate = @()

if ($All) {
    Write-Status "Scanning for all backups in: $BackupPath"
    $backupsToValidate = Get-ChildItem -Path $BackupPath -Directory -Filter "backup_*" -ErrorAction SilentlyContinue |
        Sort-Object Name -Descending
    Write-Status "Found $($backupsToValidate.Count) backups to validate"
} else {
    if (Test-Path (Join-Path $BackupPath ".claude")) {
        $backupsToValidate = @(Get-Item $BackupPath)
    } elseif (Test-Path $BackupPath) {
        $latestBackup = Get-ChildItem -Path $BackupPath -Directory -Filter "backup_*" -ErrorAction SilentlyContinue |
            Sort-Object Name -Descending | Select-Object -First 1
        if ($latestBackup) {
            $backupsToValidate = @($latestBackup)
            Write-Status "Validating latest backup: $($latestBackup.Name)"
        }
    }

    if ($backupsToValidate.Count -eq 0) {
        Write-Status "No backup found at: $BackupPath" "Red"
        exit 1
    }
}

# Validate each backup
$allResults = @()
foreach ($backup in $backupsToValidate) {
    $script:ValidationResults = @()
    $result = Validate-SingleBackup -BackupDir $backup.FullName
    $allResults += $result
}

# Overall Summary
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "                    Validation Summary                         " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$validCount = ($allResults | Where-Object { $_.Valid }).Count
$invalidCount = ($allResults | Where-Object { -not $_.Valid }).Count
$totalErrors = ($allResults | Measure-Object -Property Errors -Sum).Sum
$totalWarnings = ($allResults | Measure-Object -Property Warnings -Sum).Sum
$totalPassed = ($allResults | Measure-Object -Property Passed -Sum).Sum

Write-Host "Backups Validated: $($allResults.Count)" -ForegroundColor Cyan
Write-Host "  Valid: $validCount" -ForegroundColor Green
if ($invalidCount -gt 0) {
    Write-Host "  Invalid: $invalidCount" -ForegroundColor Red
}
Write-Host ""
$totalChecks = $totalPassed + $totalErrors + $totalWarnings
Write-Host "Total Checks: $totalChecks" -ForegroundColor White
Write-Host "  Passed: $totalPassed" -ForegroundColor Green
if ($totalWarnings -gt 0) {
    Write-Host "  Warnings: $totalWarnings" -ForegroundColor Yellow
}
if ($totalErrors -gt 0) {
    Write-Host "  Errors: $totalErrors" -ForegroundColor Red
}

Write-Host ""

# List valid backups
if ($validCount -gt 0 -and $All) {
    Write-Host "Valid Backups:" -ForegroundColor Green
    foreach ($result in ($allResults | Where-Object { $_.Valid })) {
        $name = Split-Path $result.Path -Leaf
        $sizeMB = [math]::Round($result.Size/1MB, 1)
        Write-Host "  [+] $name ($sizeMB MB)" -ForegroundColor Green
    }
    Write-Host ""
}

# List invalid backups
if ($invalidCount -gt 0) {
    Write-Host "Invalid Backups:" -ForegroundColor Red
    foreach ($result in ($allResults | Where-Object { -not $_.Valid })) {
        $name = Split-Path $result.Path -Leaf
        Write-Host "  [-] $name ($($result.Errors) errors)" -ForegroundColor Red
    }
    Write-Host ""
}

# Recommendation
if ($invalidCount -eq 0 -and $validCount -gt 0) {
    $sorted = $allResults | Sort-Object {
        if ($_.Timestamp -ne "Unknown") {
            [DateTime]::Parse($_.Timestamp)
        } else {
            [DateTime]::MinValue
        }
    } -Descending
    $newest = $sorted | Select-Object -First 1
    Write-Host "Recommended backup for restore:" -ForegroundColor Cyan
    $newestName = Split-Path $newest.Path -Leaf
    Write-Host "  $newestName" -ForegroundColor White
} elseif ($validCount -gt 0) {
    $validOnly = $allResults | Where-Object { $_.Valid }
    $sorted = $validOnly | Sort-Object {
        if ($_.Timestamp -ne "Unknown") {
            [DateTime]::Parse($_.Timestamp)
        } else {
            [DateTime]::MinValue
        }
    } -Descending
    $bestValid = $sorted | Select-Object -First 1
    Write-Host "Recommended valid backup:" -ForegroundColor Cyan
    $bestName = Split-Path $bestValid.Path -Leaf
    Write-Host "  $bestName" -ForegroundColor White
} else {
    Write-Host "No valid backups found. Consider creating a new backup." -ForegroundColor Red
}

Write-Host ""

$exitCode = if ($invalidCount -gt 0) { 1 } else { 0 }
exit $exitCode
