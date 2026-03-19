<#
.SYNOPSIS
    Migration Script for Claude Code - Upgrade from older versions
.DESCRIPTION
    Handles migration between Claude Code versions including:
    - Configuration format upgrades
    - Database schema migrations
    - MCP server configuration updates
    - Settings consolidation
    - Legacy file cleanup
    - Profile compatibility fixes
.PARAMETER FromVersion
    Source version to migrate from (auto-detected if not specified)
.PARAMETER ToVersion
    Target version to migrate to (latest if not specified)
.PARAMETER BackupFirst
    Create a backup before migration (default: true)
.PARAMETER DryRun
    Show what would be migrated without making changes
.EXAMPLE
    .\migrate-claudecode.ps1
    .\migrate-claudecode.ps1 -FromVersion "1.0" -DryRun
.NOTES
    Version: 1.0
    Requires: PowerShell 5.0+
#>

param(
    [string]$FromVersion,
    [string]$ToVersion = "2.0",
    [switch]$BackupFirst = $true,
    [switch]$DryRun,
    [switch]$Force,
    [string]$BackupPath = "F:\backup\claudecode"
)

$ErrorActionPreference = "Continue"
$script:MigrationLog = @()
$script:Changes = @()

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor $Color
}

function Write-Migration {
    param([string]$Action, [string]$Details, [string]$Status = "OK")
    $color = switch ($Status) {
        "OK" { "Green" }
        "SKIP" { "DarkGray" }
        "WARN" { "Yellow" }
        "FAIL" { "Red" }
        default { "White" }
    }

    Write-Host "  [$Status] " -NoNewline -ForegroundColor $color
    Write-Host "$Action" -NoNewline
    if ($Details) {
        Write-Host " - $Details" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }

    $script:MigrationLog += @{
        Timestamp = Get-Date
        Action = $Action
        Details = $Details
        Status = $Status
    }

    if ($Status -ne "SKIP") {
        $script:Changes += "$Action`: $Details"
    }
}

function Get-ClaudeVersion {
    param([string]$Path = "$env:USERPROFILE\.claude")

    # Try to detect version from various sources
    $version = "1.0"  # Default/legacy

    # Check manifest
    $manifestPath = Join-Path $Path "manifest.json"
    if (Test-Path $manifestPath) {
        try {
            $manifest = Get-Content $manifestPath -Raw | ConvertFrom-Json
            if ($manifest.version) {
                return $manifest.version
            }
        } catch {}
    }

    # Check settings.json for version indicators
    $settingsPath = Join-Path $Path "settings.json"
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            if ($settings.version) {
                return $settings.version
            }
            # Check for v2.0 features
            if ($settings.mcpServers -or $settings.experimental) {
                return "1.5"
            }
        } catch {}
    }

    # Check for CLI version
    try {
        $cliVersion = & claude --version 2>$null
        if ($cliVersion -match "(\d+\.\d+\.\d+)") {
            $v = [version]$Matches[1]
            if ($v -ge [version]"1.0.0") {
                return "1.5"
            }
        }
    } catch {}

    return $version
}

function Backup-BeforeMigration {
    param([string]$Source, [string]$Destination)

    $timestamp = Get-Date -Format "yyyy_MM_dd_HH_mm_ss"
    $backupDir = Join-Path $Destination "pre_migration_$timestamp"

    Write-Status "Creating pre-migration backup..."

    try {
        New-Item -ItemType Directory -Path $backupDir -Force | Out-Null

        # Copy .claude directory
        $claudeDir = "$env:USERPROFILE\.claude"
        if (Test-Path $claudeDir) {
            $destClaudeDir = Join-Path $backupDir ".claude"
            Copy-Item -Path $claudeDir -Destination $destClaudeDir -Recurse -Force
        }

        # Copy .claude.json
        $claudeJson = "$env:USERPROFILE\.claude.json"
        if (Test-Path $claudeJson) {
            Copy-Item -Path $claudeJson -Destination $backupDir -Force
        }

        Write-Migration "Pre-migration backup" $backupDir "OK"
        return $backupDir
    } catch {
        Write-Migration "Pre-migration backup" $_.Exception.Message "FAIL"
        return $null
    }
}

# Banner
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║          Claude Code Migration Tool v1.0                     ║" -ForegroundColor Cyan
Write-Host "║          Upgrade from older versions                         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

if ($DryRun) {
    Write-Status "DRY RUN MODE - No changes will be made" "Yellow"
    Write-Host ""
}

# Detect current version
$claudeDir = "$env:USERPROFILE\.claude"
$claudeJson = "$env:USERPROFILE\.claude.json"

if (-not $FromVersion) {
    $FromVersion = Get-ClaudeVersion -Path $claudeDir
}

Write-Status "Detected Version: $FromVersion"
Write-Status "Target Version: $ToVersion"
Write-Host ""

# Check if migration needed
if ([version]$FromVersion -ge [version]$ToVersion) {
    Write-Status "Already at target version or newer. No migration needed." "Green"
    exit 0
}

# Pre-migration backup
if ($BackupFirst -and -not $DryRun) {
    $backupLocation = Backup-BeforeMigration -Source $claudeDir -Destination $BackupPath
    if (-not $backupLocation -and -not $Force) {
        Write-Status "Backup failed. Use -Force to continue anyway." "Red"
        exit 1
    }
}

Write-Status "Starting migration from v$FromVersion to v$ToVersion..."
Write-Host ""

# ============================================================================
# MIGRATION STEPS
# ============================================================================

# Migration 1.0 -> 1.5: Settings consolidation
if ([version]$FromVersion -lt [version]"1.5") {
    Write-Status "Applying v1.0 -> v1.5 migrations..."

    # 1.1 Consolidate scattered config files
    $oldConfigs = @(
        "config.json",
        "preferences.json",
        "user-settings.json"
    )

    foreach ($oldConfig in $oldConfigs) {
        $oldPath = Join-Path $claudeDir $oldConfig
        if (Test-Path $oldPath) {
            if (-not $DryRun) {
                try {
                    $oldData = Get-Content $oldPath -Raw | ConvertFrom-Json
                    # Merge into settings.json
                    $settingsPath = Join-Path $claudeDir "settings.json"
                    $settings = @{}
                    if (Test-Path $settingsPath) {
                        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                    }

                    # Merge properties
                    foreach ($prop in $oldData.PSObject.Properties) {
                        if (-not $settings.PSObject.Properties[$prop.Name]) {
                            $settings | Add-Member -NotePropertyName $prop.Name -NotePropertyValue $prop.Value -Force
                        }
                    }

                    $settings | ConvertTo-Json -Depth 10 | Out-File $settingsPath -Encoding utf8
                    Remove-Item $oldPath -Force

                    Write-Migration "Merge $oldConfig" "Into settings.json" "OK"
                } catch {
                    Write-Migration "Merge $oldConfig" $_.Exception.Message "WARN"
                }
            } else {
                Write-Migration "Merge $oldConfig" "Would merge into settings.json" "SKIP"
            }
        }
    }

    # 1.2 Update MCP server format
    $mcpJsonPath = Join-Path $claudeDir "mcp.json"
    if (Test-Path $mcpJsonPath) {
        if (-not $DryRun) {
            try {
                $mcpConfig = Get-Content $mcpJsonPath -Raw | ConvertFrom-Json

                # Check for old format (array instead of object)
                if ($mcpConfig -is [Array]) {
                    $newConfig = @{
                        mcpServers = @{}
                    }
                    foreach ($server in $mcpConfig) {
                        if ($server.name) {
                            $newConfig.mcpServers[$server.name] = @{
                                command = $server.command
                                args = $server.args
                            }
                        }
                    }
                    $newConfig | ConvertTo-Json -Depth 10 | Out-File $mcpJsonPath -Encoding utf8
                    Write-Migration "Update MCP format" "Converted array to object format" "OK"
                } else {
                    Write-Migration "Update MCP format" "Already in correct format" "SKIP"
                }
            } catch {
                Write-Migration "Update MCP format" $_.Exception.Message "WARN"
            }
        } else {
            Write-Migration "Update MCP format" "Would update MCP configuration format" "SKIP"
        }
    }

    # 1.3 Clean up deprecated files
    $deprecatedFiles = @(
        "cache.json",
        ".cache",
        "temp",
        "*.log.old",
        "*.bak"
    )

    foreach ($pattern in $deprecatedFiles) {
        $files = Get-ChildItem -Path $claudeDir -Filter $pattern -Recurse -ErrorAction SilentlyContinue
        foreach ($file in $files) {
            if (-not $DryRun) {
                try {
                    Remove-Item $file.FullName -Force -Recurse -ErrorAction Stop
                    Write-Migration "Remove deprecated" $file.Name "OK"
                } catch {
                    Write-Migration "Remove deprecated" "$($file.Name): $($_.Exception.Message)" "WARN"
                }
            } else {
                Write-Migration "Remove deprecated" "Would remove $($file.Name)" "SKIP"
            }
        }
    }
}

# Migration 1.5 -> 2.0: Modern features
if ([version]$FromVersion -lt [version]"2.0") {
    Write-Status "Applying v1.5 -> v2.0 migrations..."

    # 2.1 Add version marker
    $settingsPath = Join-Path $claudeDir "settings.json"
    if (Test-Path $settingsPath) {
        if (-not $DryRun) {
            try {
                $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
                $settings | Add-Member -NotePropertyName "version" -NotePropertyValue "2.0" -Force
                $settings | Add-Member -NotePropertyName "migratedAt" -NotePropertyValue (Get-Date -Format "o") -Force
                $settings | ConvertTo-Json -Depth 10 | Out-File $settingsPath -Encoding utf8
                Write-Migration "Add version marker" "v2.0" "OK"
            } catch {
                Write-Migration "Add version marker" $_.Exception.Message "WARN"
            }
        } else {
            Write-Migration "Add version marker" "Would add version 2.0 marker" "SKIP"
        }
    }

    # 2.2 Create manifest.json if not exists
    $manifestPath = Join-Path $claudeDir "manifest.json"
    if (-not (Test-Path $manifestPath)) {
        if (-not $DryRun) {
            try {
                $manifest = @{
                    version = "2.0"
                    migratedFrom = $FromVersion
                    migratedAt = Get-Date -Format "o"
                    hostname = $env:COMPUTERNAME
                    username = $env:USERNAME
                }
                $manifest | ConvertTo-Json -Depth 10 | Out-File $manifestPath -Encoding utf8
                Write-Migration "Create manifest.json" "v2.0" "OK"
            } catch {
                Write-Migration "Create manifest.json" $_.Exception.Message "WARN"
            }
        } else {
            Write-Migration "Create manifest.json" "Would create manifest.json" "SKIP"
        }
    }

    # 2.3 Update .claude.json format
    if (Test-Path $claudeJson) {
        if (-not $DryRun) {
            try {
                $config = Get-Content $claudeJson -Raw | ConvertFrom-Json

                # Ensure proper structure
                $updated = $false

                # Migrate old API key formats
                if ($config.apiKey -and -not $config.anthropicApiKey) {
                    $config | Add-Member -NotePropertyName "anthropicApiKey" -NotePropertyValue $config.apiKey -Force
                    $config.PSObject.Properties.Remove("apiKey")
                    $updated = $true
                }

                # Add configVersion
                if (-not $config.configVersion) {
                    $config | Add-Member -NotePropertyName "configVersion" -NotePropertyValue "2.0" -Force
                    $updated = $true
                }

                if ($updated) {
                    $config | ConvertTo-Json -Depth 10 | Out-File $claudeJson -Encoding utf8
                    Write-Migration "Update .claude.json" "Migrated to v2.0 format" "OK"
                } else {
                    Write-Migration "Update .claude.json" "Already in v2.0 format" "SKIP"
                }
            } catch {
                Write-Migration "Update .claude.json" $_.Exception.Message "WARN"
            }
        } else {
            Write-Migration "Update .claude.json" "Would update to v2.0 format" "SKIP"
        }
    }

    # 2.4 Fix PowerShell profile encoding (BOM issues)
    $profileScripts = Get-ChildItem -Path $claudeDir -Filter "*.ps1" -ErrorAction SilentlyContinue
    foreach ($script in $profileScripts) {
        if (-not $DryRun) {
            try {
                $content = Get-Content $script.FullName -Raw
                $bytes = [System.IO.File]::ReadAllBytes($script.FullName)

                # Check for BOM
                $hasBom = ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF)

                if (-not $hasBom) {
                    # Add UTF-8 BOM for PowerShell compatibility
                    $utf8WithBom = New-Object System.Text.UTF8Encoding($true)
                    [System.IO.File]::WriteAllText($script.FullName, $content, $utf8WithBom)
                    Write-Migration "Fix PS1 encoding" $script.Name "OK"
                } else {
                    Write-Migration "Fix PS1 encoding" "$($script.Name) already has BOM" "SKIP"
                }
            } catch {
                Write-Migration "Fix PS1 encoding" "$($script.Name): $($_.Exception.Message)" "WARN"
            }
        } else {
            Write-Migration "Fix PS1 encoding" "Would fix $($script.Name)" "SKIP"
        }
    }

    # 2.5 Optimize database files
    $dbFiles = Get-ChildItem -Path $claudeDir -Filter "*.db" -Recurse -ErrorAction SilentlyContinue
    foreach ($db in $dbFiles) {
        if (-not $DryRun) {
            # Check for empty/corrupt databases
            if ($db.Length -eq 0) {
                try {
                    Remove-Item $db.FullName -Force
                    Write-Migration "Remove empty DB" $db.Name "OK"
                } catch {
                    Write-Migration "Remove empty DB" $_.Exception.Message "WARN"
                }
            }
        } else {
            if ($db.Length -eq 0) {
                Write-Migration "Remove empty DB" "Would remove $($db.Name)" "SKIP"
            }
        }
    }

    # 2.6 Create logs directory structure
    $logsDir = Join-Path $claudeDir "logs"
    if (-not (Test-Path $logsDir)) {
        if (-not $DryRun) {
            try {
                New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
                Write-Migration "Create logs directory" $logsDir "OK"
            } catch {
                Write-Migration "Create logs directory" $_.Exception.Message "WARN"
            }
        } else {
            Write-Migration "Create logs directory" "Would create logs directory" "SKIP"
        }
    }
}

# ============================================================================
# POST-MIGRATION VERIFICATION
# ============================================================================

Write-Host ""
Write-Status "Verifying migration..."

$verificationPassed = $true

# Check settings.json
$settingsPath = Join-Path $claudeDir "settings.json"
if (Test-Path $settingsPath) {
    try {
        $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
        if ($settings.version -eq "2.0" -or $DryRun) {
            Write-Migration "Verify settings.json" "Version 2.0" "OK"
        } else {
            Write-Migration "Verify settings.json" "Version mismatch" "WARN"
            $verificationPassed = $false
        }
    } catch {
        Write-Migration "Verify settings.json" "Parse error" "FAIL"
        $verificationPassed = $false
    }
} else {
    Write-Migration "Verify settings.json" "Missing" "FAIL"
    $verificationPassed = $false
}

# Check manifest
$manifestPath = Join-Path $claudeDir "manifest.json"
if (Test-Path $manifestPath) {
    Write-Migration "Verify manifest.json" "Present" "OK"
} elseif (-not $DryRun) {
    Write-Migration "Verify manifest.json" "Missing" "WARN"
}

# ============================================================================
# SUMMARY
# ============================================================================

Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║                    Migration Summary                         ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host ""

$okCount = ($script:MigrationLog | Where-Object { $_.Status -eq "OK" }).Count
$warnCount = ($script:MigrationLog | Where-Object { $_.Status -eq "WARN" }).Count
$failCount = ($script:MigrationLog | Where-Object { $_.Status -eq "FAIL" }).Count
$skipCount = ($script:MigrationLog | Where-Object { $_.Status -eq "SKIP" }).Count

Write-Host "Migration: v$FromVersion -> v$ToVersion" -ForegroundColor Cyan
Write-Host ""
Write-Host "Actions Completed: $okCount" -ForegroundColor Green
if ($warnCount -gt 0) { Write-Host "Warnings: $warnCount" -ForegroundColor Yellow }
if ($failCount -gt 0) { Write-Host "Failures: $failCount" -ForegroundColor Red }
if ($DryRun) { Write-Host "Would Skip: $skipCount (Dry Run)" -ForegroundColor DarkGray }

Write-Host ""

if ($DryRun) {
    Write-Host "This was a dry run. No changes were made." -ForegroundColor Yellow
    Write-Host "Run without -DryRun to apply migrations." -ForegroundColor Cyan
} elseif ($failCount -eq 0) {
    Write-Host "Migration completed successfully!" -ForegroundColor Green

    if ($backupLocation) {
        Write-Host ""
        Write-Host "Pre-migration backup saved to:" -ForegroundColor Cyan
        Write-Host "  $backupLocation" -ForegroundColor White
    }
} else {
    Write-Host "Migration completed with errors." -ForegroundColor Yellow
    Write-Host "Review the log above and consider restoring from backup." -ForegroundColor Yellow

    if ($backupLocation) {
        Write-Host ""
        Write-Host "To restore, run:" -ForegroundColor Cyan
        Write-Host "  .\restore-claudecode.ps1 -BackupPath `"$backupLocation`"" -ForegroundColor White
    }
}

Write-Host ""

# Save migration log
if (-not $DryRun) {
    $logPath = Join-Path $claudeDir "migration_$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss').log"
    try {
        $script:MigrationLog | ForEach-Object {
            "[$($_.Timestamp.ToString('yyyy-MM-dd HH:mm:ss'))] [$($_.Status)] $($_.Action) - $($_.Details)"
        } | Out-File $logPath -Encoding utf8
        Write-Status "Migration log saved: $logPath" "DarkGray"
    } catch {
        Write-Status "Could not save migration log" "Yellow"
    }
}

exit $(if ($failCount -gt 0) { 1 } else { 0 })
