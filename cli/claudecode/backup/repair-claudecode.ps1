<#
.SYNOPSIS
    Repair Script for Claude Code - Fix broken installations without full restore
.DESCRIPTION
    Diagnoses and repairs common Claude Code issues including:
    - Missing or corrupted configuration files
    - Broken MCP server connections
    - npm package issues
    - Path and environment variable problems
    - Database corruption
    - Permission issues
.PARAMETER DiagnoseOnly
    Only run diagnostics without making any changes
.PARAMETER FixAll
    Automatically fix all detected issues without prompting
.PARAMETER BackupPath
    Path to backup for reference/recovery (optional)
.EXAMPLE
    .\repair-claudecode.ps1 -DiagnoseOnly
    .\repair-claudecode.ps1 -FixAll
.NOTES
    Version: 1.0
    Requires: PowerShell 5.0+
#>

param(
    [switch]$DiagnoseOnly,
    [switch]$FixAll,
    [string]$BackupPath = "F:\backup\claudecode",
    [switch]$Verbose
)

$ErrorActionPreference = "Continue"
$script:Issues = @()
$script:Fixed = @()
$script:Failed = @()

function Write-Status {
    param([string]$Message, [string]$Color = "Cyan")
    $timestamp = Get-Date -Format "HH:mm:ss"
    Write-Host "[$timestamp] " -NoNewline -ForegroundColor DarkGray
    Write-Host $Message -ForegroundColor $Color
}

function Write-Issue {
    param([string]$Issue, [string]$Severity = "Warning")
    $color = switch ($Severity) {
        "Critical" { "Red" }
        "Warning" { "Yellow" }
        "Info" { "Cyan" }
        default { "White" }
    }
    Write-Host "  [!] " -NoNewline -ForegroundColor $color
    Write-Host $Issue -ForegroundColor $color
    $script:Issues += @{ Issue = $Issue; Severity = $Severity }
}

function Write-Fixed {
    param([string]$Message)
    Write-Host "  [+] " -NoNewline -ForegroundColor Green
    Write-Host $Message -ForegroundColor Green
    $script:Fixed += $Message
}

function Write-FixFailed {
    param([string]$Message)
    Write-Host "  [-] " -NoNewline -ForegroundColor Red
    Write-Host $Message -ForegroundColor Red
    $script:Failed += $Message
}

# Banner
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "          Claude Code Repair Tool v1.0                         " -ForegroundColor Cyan
Write-Host "          Fix broken installations without full restore        " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

if ($DiagnoseOnly) {
    Write-Status "Running in DIAGNOSE-ONLY mode (no changes will be made)" "Yellow"
    Write-Host ""
}

# ============================================================================
# PHASE 1: DIAGNOSTICS
# ============================================================================

Write-Status "Phase 1: Running Diagnostics..."
Write-Host ""

# 1. Check Node.js
Write-Status "Checking Node.js..."
$nodeOk = $false
try {
    $nodeVersion = & node --version 2>$null
    if ($nodeVersion) {
        $versionNum = [version]($nodeVersion -replace 'v', '')
        if ($versionNum -ge [version]"18.0.0") {
            Write-Status "  Node.js: $nodeVersion [OK]" "DarkGray"
            $nodeOk = $true
        } else {
            Write-Issue "Node.js version too old: $nodeVersion (need 18.0.0+)" "Warning"
        }
    } else {
        Write-Issue "Node.js not responding" "Critical"
    }
} catch {
    Write-Issue "Node.js not installed or not in PATH" "Critical"
}

# 2. Check npm
Write-Status "Checking npm..."
$npmOk = $false
try {
    $npmVersion = & npm --version 2>$null
    if ($npmVersion) {
        Write-Status "  npm: v$npmVersion [OK]" "DarkGray"
        $npmOk = $true
    } else {
        Write-Issue "npm not responding" "Critical"
    }
} catch {
    Write-Issue "npm not installed or not in PATH" "Critical"
}

# 3. Check Claude CLI
Write-Status "Checking Claude CLI..."
$claudeOk = $false
try {
    $claudeVersion = & claude --version 2>$null
    if ($claudeVersion) {
        Write-Status "  Claude CLI: $claudeVersion [OK]" "DarkGray"
        $claudeOk = $true
    } else {
        Write-Issue "Claude CLI not responding" "Warning"
    }
} catch {
    Write-Issue "Claude CLI not installed" "Warning"
}

# 4. Check .claude directory
Write-Status "Checking .claude directory..."
$claudeDir = "$env:USERPROFILE\.claude"
if (Test-Path $claudeDir) {
    Write-Status "  .claude directory exists [OK]" "DarkGray"

    $keyFiles = @(
        @{ Name = "settings.json"; Required = $true },
        @{ Name = "settings.local.json"; Required = $false },
        @{ Name = "mcp-ondemand.ps1"; Required = $false }
    )

    foreach ($file in $keyFiles) {
        $filePath = Join-Path $claudeDir $file.Name
        if (Test-Path $filePath) {
            if ($file.Name -like "*.json") {
                try {
                    $content = Get-Content $filePath -Raw -ErrorAction Stop
                    $null = $content | ConvertFrom-Json
                    Write-Status "    $($file.Name): Valid [OK]" "DarkGray"
                } catch {
                    Write-Issue "$($file.Name) is corrupted or invalid JSON" "Warning"
                }
            } else {
                Write-Status "    $($file.Name): Exists [OK]" "DarkGray"
            }
        } elseif ($file.Required) {
            Write-Issue "Missing required file: $($file.Name)" "Warning"
        }
    }
} else {
    Write-Issue ".claude directory missing" "Critical"
}

# 5. Check .claude.json
Write-Status "Checking .claude.json..."
$claudeJson = "$env:USERPROFILE\.claude.json"
if (Test-Path $claudeJson) {
    try {
        $content = Get-Content $claudeJson -Raw -ErrorAction Stop
        $config = $content | ConvertFrom-Json
        Write-Status "  .claude.json: Valid [OK]" "DarkGray"

        if (-not $config.primaryApiKey -and -not $config.anthropicApiKey) {
            Write-Issue "No API key configured in .claude.json" "Info"
        }
    } catch {
        Write-Issue ".claude.json is corrupted" "Warning"
    }
} else {
    Write-Issue ".claude.json missing (may need to run 'claude' first)" "Info"
}

# 6. Check MCP servers
Write-Status "Checking MCP servers..."
try {
    $mcpList = & claude mcp list 2>&1
    if ($mcpList) {
        $failedMcps = @()
        foreach ($line in $mcpList) {
            if ($line -match "Failed to connect" -or $line -match "error") {
                $serverName = if ($line -match "^(\S+)") { $Matches[1] } else { "unknown" }
                $failedMcps += $serverName
            }
        }
        if ($failedMcps.Count -gt 0) {
            $failedList = $failedMcps -join ', '
            Write-Issue "Failed MCP servers: $failedList" "Warning"
        } else {
            Write-Status "  All MCP servers healthy [OK]" "DarkGray"
        }
    }
} catch {
    Write-Status "  Could not check MCP servers" "DarkGray"
}

# 7. Check databases
Write-Status "Checking databases..."
$dbFiles = Get-ChildItem -Path $claudeDir -Filter "*.db" -Recurse -ErrorAction SilentlyContinue
foreach ($db in $dbFiles) {
    try {
        $stream = [System.IO.File]::Open($db.FullName, 'Open', 'Read', 'None')
        $stream.Close()

        if ($db.Length -eq 0) {
            Write-Issue "Empty database: $($db.Name)" "Warning"
        } else {
            $sizeKB = [math]::Round($db.Length/1KB, 1)
            Write-Status "  $($db.Name): OK ($sizeKB KB)" "DarkGray"
        }
    } catch {
        Write-Issue "Database may be locked or corrupted: $($db.Name)" "Warning"
    }
}

# 8. Check PATH
Write-Status "Checking PATH..."
$pathIssues = @()
$npmGlobalPath = & npm root -g 2>$null
if ($npmGlobalPath) {
    $npmBinPath = Split-Path $npmGlobalPath -Parent
    $npmBinPath = Join-Path $npmBinPath "node_modules\.bin"

    if ($env:PATH -notlike "*$npmBinPath*") {
        $pathIssues += "npm global bin not in PATH"
    }
}

$nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
if ($nodePath) {
    $nodeDir = Split-Path $nodePath -Parent
    if ($env:PATH -notlike "*$nodeDir*") {
        $pathIssues += "Node.js directory not in PATH"
    }
}

if ($pathIssues.Count -gt 0) {
    foreach ($issue in $pathIssues) {
        Write-Issue $issue "Warning"
    }
} else {
    Write-Status "  PATH configuration OK [OK]" "DarkGray"
}

# 9. Check permissions
Write-Status "Checking permissions..."
$testFile = Join-Path $claudeDir "permission_test_$(Get-Random).tmp"
try {
    "test" | Out-File $testFile -ErrorAction Stop
    Remove-Item $testFile -Force
    Write-Status "  Write permissions OK [OK]" "DarkGray"
} catch {
    Write-Issue "Cannot write to .claude directory" "Critical"
}

# 10. Check disk space
Write-Status "Checking disk space..."
$freeSpace = (Get-PSDrive -Name C).Free / 1GB
if ($freeSpace -lt 1) {
    $spaceGB = [math]::Round($freeSpace, 2)
    Write-Issue "Very low disk space: $spaceGB GB" "Critical"
} elseif ($freeSpace -lt 5) {
    $spaceGB = [math]::Round($freeSpace, 2)
    Write-Issue "Low disk space: $spaceGB GB" "Warning"
} else {
    $spaceGB = [math]::Round($freeSpace, 2)
    Write-Status "  Disk space: $spaceGB GB available [OK]" "DarkGray"
}

Write-Host ""

# ============================================================================
# PHASE 2: REPAIRS
# ============================================================================

if (-not $DiagnoseOnly -and $script:Issues.Count -gt 0) {
    Write-Status "Phase 2: Applying Repairs..."
    Write-Host ""

    foreach ($issue in $script:Issues) {
        $shouldFix = $FixAll
        if (-not $FixAll) {
            Write-Host "Fix: $($issue.Issue)? (Y/n) " -NoNewline -ForegroundColor Yellow
            $response = Read-Host
            $shouldFix = ($response -ne 'n' -and $response -ne 'N')
        }

        if ($shouldFix) {
            switch -Regex ($issue.Issue) {
                "Node.js not installed" {
                    Write-Status "Installing Node.js..."
                    $wingetAvailable = Get-Command winget -ErrorAction SilentlyContinue
                    if ($wingetAvailable) {
                        try {
                            & winget install OpenJS.NodeJS.LTS --accept-source-agreements --accept-package-agreements 2>&1 | Out-Null
                            if ($LASTEXITCODE -eq 0) {
                                Write-Fixed "Node.js installed via winget"
                            } else {
                                Write-FixFailed "Node.js installation failed"
                            }
                        } catch {
                            Write-FixFailed "Node.js installation error: $_"
                        }
                    } else {
                        Write-FixFailed "winget not available - please install Node.js manually from https://nodejs.org/"
                    }
                }

                "Node.js version too old" {
                    Write-Status "Upgrading Node.js..."
                    try {
                        & winget upgrade OpenJS.NodeJS.LTS --accept-source-agreements 2>&1 | Out-Null
                        Write-Fixed "Node.js upgrade initiated"
                    } catch {
                        Write-FixFailed "Node.js upgrade failed"
                    }
                }

                "Claude CLI not installed" {
                    Write-Status "Installing Claude CLI..."
                    try {
                        & npm install -g @anthropic-ai/claude-code 2>&1 | Out-Null
                        if ($LASTEXITCODE -eq 0) {
                            Write-Fixed "Claude CLI installed"
                        } else {
                            Write-FixFailed "Claude CLI installation failed"
                        }
                    } catch {
                        Write-FixFailed "Claude CLI installation error: $_"
                    }
                }

                "\.claude directory missing" {
                    Write-Status "Creating .claude directory..."
                    try {
                        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
                        Write-Fixed ".claude directory created"
                    } catch {
                        Write-FixFailed "Could not create .claude directory: $_"
                    }
                }

                "settings\.json.*corrupted|Missing required file: settings\.json" {
                    Write-Status "Repairing settings.json..."
                    $settingsPath = Join-Path $claudeDir "settings.json"

                    if ($BackupPath -and (Test-Path $BackupPath)) {
                        $latestBackup = Get-ChildItem -Path $BackupPath -Directory -Filter "backup_*" |
                            Sort-Object Name -Descending | Select-Object -First 1

                        if ($latestBackup) {
                            $backupSettings = Join-Path $latestBackup.FullName ".claude\settings.json"
                            if (Test-Path $backupSettings) {
                                try {
                                    Copy-Item $backupSettings $settingsPath -Force
                                    Write-Fixed "settings.json restored from backup"
                                    continue
                                } catch {
                                    Write-Status "  Backup restore failed, creating default..." "Yellow"
                                }
                            }
                        }
                    }

                    try {
                        $defaultSettings = @{
                            version = "1.0"
                            theme = "auto"
                        } | ConvertTo-Json -Depth 10
                        $defaultSettings | Out-File $settingsPath -Encoding utf8 -Force
                        Write-Fixed "Created default settings.json"
                    } catch {
                        Write-FixFailed "Could not create settings.json: $_"
                    }
                }

                "\.claude\.json.*corrupted" {
                    Write-Status "Repairing .claude.json..."

                    if ($BackupPath -and (Test-Path $BackupPath)) {
                        $latestBackup = Get-ChildItem -Path $BackupPath -Directory -Filter "backup_*" |
                            Sort-Object Name -Descending | Select-Object -First 1

                        if ($latestBackup) {
                            $backupJson = Join-Path $latestBackup.FullName ".claude.json"
                            if (Test-Path $backupJson) {
                                try {
                                    Copy-Item $backupJson $claudeJson -Force
                                    Write-Fixed ".claude.json restored from backup"
                                    continue
                                } catch {
                                    Write-Status "  Backup restore failed" "Yellow"
                                }
                            }
                        }
                    }

                    try {
                        $defaultConfig = @{} | ConvertTo-Json
                        $defaultConfig | Out-File $claudeJson -Encoding utf8 -Force
                        Write-Fixed "Created empty .claude.json (will need API key)"
                    } catch {
                        Write-FixFailed "Could not create .claude.json: $_"
                    }
                }

                "Failed MCP servers" {
                    Write-Status "Cleaning up failed MCP servers..."
                    $mcpList = & claude mcp list 2>&1
                    foreach ($line in $mcpList) {
                        if ($line -match "Failed to connect" -and $line -match "^(\S+)") {
                            $serverName = $Matches[1]
                            try {
                                & claude mcp remove $serverName -s user 2>&1 | Out-Null
                                Write-Fixed "Removed failed MCP: $serverName"
                            } catch {
                                Write-FixFailed "Could not remove MCP: $serverName"
                            }
                        }
                    }
                }

                "Empty database" {
                    Write-Status "Removing empty database files..."
                    $emptyDbs = Get-ChildItem -Path $claudeDir -Filter "*.db" -Recurse |
                        Where-Object { $_.Length -eq 0 }
                    foreach ($db in $emptyDbs) {
                        try {
                            Remove-Item $db.FullName -Force
                            Write-Fixed "Removed empty database: $($db.Name)"
                        } catch {
                            Write-FixFailed "Could not remove: $($db.Name)"
                        }
                    }
                }

                "npm global bin not in PATH" {
                    Write-Status "Adding npm global bin to PATH..."
                    $npmGlobalPath = & npm root -g 2>$null
                    if ($npmGlobalPath) {
                        $npmBinPath = Split-Path $npmGlobalPath -Parent
                        $currentPath = [Environment]::GetEnvironmentVariable("Path", "User")
                        if ($currentPath -notlike "*$npmBinPath*") {
                            try {
                                $newPath = "$currentPath;$npmBinPath"
                                [Environment]::SetEnvironmentVariable("Path", $newPath, "User")
                                $env:PATH = "$env:PATH;$npmBinPath"
                                Write-Fixed "Added npm bin to PATH"
                            } catch {
                                Write-FixFailed "Could not update PATH: $_"
                            }
                        }
                    }
                }

                default {
                    Write-Status "  No automatic fix available for: $($issue.Issue)" "DarkGray"
                }
            }
        }
    }
}

# ============================================================================
# PHASE 3: SUMMARY
# ============================================================================

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "                        Repair Summary                         " -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

$issueColor = if ($script:Issues.Count -eq 0) { "Green" } else { "Yellow" }
Write-Host "Issues Found: $($script:Issues.Count)" -ForegroundColor $issueColor

if ($script:Issues.Count -gt 0) {
    $criticalCount = ($script:Issues | Where-Object { $_.Severity -eq "Critical" }).Count
    $warningCount = ($script:Issues | Where-Object { $_.Severity -eq "Warning" }).Count
    $infoCount = ($script:Issues | Where-Object { $_.Severity -eq "Info" }).Count

    if ($criticalCount -gt 0) { Write-Host "  - Critical: $criticalCount" -ForegroundColor Red }
    if ($warningCount -gt 0) { Write-Host "  - Warning: $warningCount" -ForegroundColor Yellow }
    if ($infoCount -gt 0) { Write-Host "  - Info: $infoCount" -ForegroundColor Cyan }
}

if (-not $DiagnoseOnly) {
    Write-Host ""
    Write-Host "Issues Fixed: $($script:Fixed.Count)" -ForegroundColor Green
    if ($script:Failed.Count -gt 0) {
        Write-Host "Fixes Failed: $($script:Failed.Count)" -ForegroundColor Red
    }
}

Write-Host ""

if ($script:Issues.Count -eq 0) {
    Write-Host "Claude Code installation appears healthy!" -ForegroundColor Green
} elseif ($DiagnoseOnly) {
    Write-Host "Run without -DiagnoseOnly to apply fixes" -ForegroundColor Cyan
} elseif ($script:Failed.Count -eq 0 -and $script:Fixed.Count -gt 0) {
    Write-Host "All detected issues have been fixed!" -ForegroundColor Green
    Write-Host "Please restart your terminal and run 'claude' to verify." -ForegroundColor Cyan
} else {
    Write-Host "Some issues could not be fixed automatically." -ForegroundColor Yellow
    Write-Host "Consider running a full restore with restore-claudecode.ps1" -ForegroundColor Cyan
}

Write-Host ""

$exitCode = if ($script:Failed.Count -gt 0) { 1 } else { 0 }
exit $exitCode
