param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,
    
    [switch]$SkipValidation,
    [switch]$TestOnly,
    [switch]$VerboseMode
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $logMsg
    if ($logPath) {
        Add-Content -Path $logPath -Value $logMsg -ErrorAction SilentlyContinue
    }
}

function Test-Path-Safe {
    param([string]$Path)
    return (Test-Path -Path $Path -ErrorAction SilentlyContinue)
}

# Validate backup path
if (-not (Test-Path-Safe $BackupPath)) {
    Write-Host "ERROR: Backup path not found: $BackupPath" -ForegroundColor Red
    exit 1
}

$logPath = "$BackupPath\restore-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MCP Server Configuration Restore" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Log "Starting MCP restore from: $BackupPath"

if ($TestOnly) {
    Write-Host "[DRY RUN MODE - No changes will be made]" -ForegroundColor Yellow
}

$restoreCount = 0
$skipCount = 0
$errorCount = 0
$availableServers = @()
$unavailableServers = @()

# 1. Restore settings.json
Write-Host "`n[1/6] Restoring settings.json..." -ForegroundColor Yellow
if (Test-Path-Safe "$BackupPath\settings.json") {
    try {
        if (-not $TestOnly) {
            Copy-Item -Path "$BackupPath\settings.json" -Destination "C:\Users\micha\.claude\settings.json" -Force
        }
        Write-Log "Restored settings.json"
        $restoreCount++
    } catch {
        Write-Log "Failed to restore settings.json: $_" "ERROR"
        $errorCount++
    }
} else {
    Write-Log "settings.json not found in backup"
    $skipCount++
}

# 2. Restore MCP wrapper .cmd files
Write-Host "`n[2/6] Restoring MCP wrapper .cmd files..." -ForegroundColor Yellow
if (Test-Path-Safe "$BackupPath\cmd-wrappers") {
    try {
        $cmdFiles = Get-ChildItem -Path "$BackupPath\cmd-wrappers" -Filter "*.cmd" -ErrorAction SilentlyContinue
        if ($cmdFiles.Count -gt 0) {
            if (-not $TestOnly) {
                foreach ($file in $cmdFiles) {
                    Copy-Item -Path $file.FullName -Destination "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\$($file.Name)" -Force
                    Write-Log "Restored: $($file.Name)"
                    $restoreCount++
                }
            } else {
                Write-Log "[DRY RUN] Would restore $($cmdFiles.Count) .cmd files"
            }
        } else {
            Write-Log "No .cmd files found in backup"
            $skipCount++
        }
    } catch {
        Write-Log "Error restoring .cmd files: $_" "ERROR"
        $errorCount++
    }
}

# 3. Restore environment variables configuration
Write-Host "`n[3/6] Restoring MCP environment configuration..." -ForegroundColor Yellow
if (Test-Path-Safe "$BackupPath\env-variables.json") {
    try {
        $envVars = Get-Content -Path "$BackupPath\env-variables.json" -Raw | ConvertFrom-Json
        if (-not $TestOnly) {
            foreach ($key in $envVars.PSObject.Properties.Name) {
                [Environment]::SetEnvironmentVariable($key, $envVars.$key, [System.EnvironmentVariableTarget]::User)
                Write-Log "Set environment: $key"
            }
        } else {
            Write-Log "[DRY RUN] Would set $($envVars.PSObject.Properties.Name.Count) environment variables"
        }
        $restoreCount++
    } catch {
        Write-Log "Failed to restore environment variables: $_" "ERROR"
        $errorCount++
    }
} else {
    Write-Log "env-variables.json not found in backup"
    $skipCount++
}

# 4. Restore authentication and state files
Write-Host "`n[4/6] Restoring MCP authentication and state..." -ForegroundColor Yellow
$restoreDirs = @('session-env', 'plugins')
foreach ($dir in $restoreDirs) {
    $srcDir = "$BackupPath\$dir"
    if (Test-Path-Safe $srcDir) {
        try {
            if (-not $TestOnly) {
                New-Item -ItemType Directory -Path "C:\Users\micha\.claude\$dir" -Force -ErrorAction SilentlyContinue | Out-Null
                Copy-Item -Path "$srcDir\*" -Destination "C:\Users\micha\.claude\$dir\" -Recurse -Force
                Write-Log "Restored: $dir"
            } else {
                Write-Log "[DRY RUN] Would restore $dir directory"
            }
            $restoreCount++
        } catch {
            Write-Log "Failed to restore $dir`: $_" "ERROR"
            $errorCount++
        }
    }
}

# 5. Restore custom MCP servers
Write-Host "`n[5/6] Restoring custom MCP server files..." -ForegroundColor Yellow
if (Test-Path-Safe "$BackupPath\custom-mcp") {
    try {
        $customDirs = Get-ChildItem -Path "$BackupPath\custom-mcp" -Directory -ErrorAction SilentlyContinue
        if ($customDirs.Count -gt 0) {
            if (-not $TestOnly) {
                foreach ($dir in $customDirs) {
                    $destPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\$($dir.Name)"
                    Copy-Item -Path $dir.FullName -Destination $destPath -Recurse -Force
                    Write-Log "Restored custom MCP: $($dir.Name)"
                    $restoreCount++
                }
            } else {
                Write-Log "[DRY RUN] Would restore $($customDirs.Count) custom MCP directories"
            }
        } else {
            Write-Log "No custom MCP directories found in backup"
            $skipCount++
        }
    } catch {
        Write-Log "Error restoring custom MCP servers: $_" "ERROR"
        $errorCount++
    }
}

# 6. Validate restored MCP servers
Write-Host "`n[6/6] Validating MCP servers..." -ForegroundColor Yellow
if (-not $SkipValidation) {
    Write-Log "Starting MCP server validation..."
    
    # Check if settings.json exists and parse it
    if (Test-Path-Safe "C:\Users\micha\.claude\settings.json") {
        try {
            $settings = Get-Content "C:\Users\micha\.claude\settings.json" -Raw | ConvertFrom-Json
            $mcpServers = $settings.mcpServers
            
            if ($mcpServers) {
                Write-Log "Found $($mcpServers.PSObject.Properties.Name.Count) MCP servers in configuration"
                
                foreach ($serverName in $mcpServers.PSObject.Properties.Name) {
                    $server = $mcpServers.$serverName
                    $serverStatus = "UNCHECKED"
                    
                    # Attempt to validate server accessibility
                    if ($server.command) {
                        # For now, we check if the command file exists
                        if ($server.command -eq 'npx' -or $server.command -eq 'node') {
                            # NPM-based servers
                            try {
                                $test = npm list $server.args[1] 2>$null
                                $serverStatus = "AVAILABLE"
                                $availableServers += $serverName
                            } catch {
                                $serverStatus = "UNAVAILABLE"
                                $unavailableServers += $serverName
                            }
                        } else {
                            # Command-based servers - check if command exists
                            $test = Get-Command $server.command -ErrorAction SilentlyContinue
                            if ($test) {
                                $serverStatus = "AVAILABLE"
                                $availableServers += $serverName
                            } else {
                                $serverStatus = "UNAVAILABLE"
                                $unavailableServers += $serverName
                            }
                        }
                    }
                    
                    Write-Log "Server '$serverName': $serverStatus"
                }
            } else {
                Write-Log "No MCP servers found in settings.json"
            }
        } catch {
            Write-Log "Failed to parse settings.json: $_" "ERROR"
            $errorCount++
        }
    } else {
        Write-Log "settings.json not available for validation"
    }
}

# Summary and Reporting
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Restore Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Restore Source: $BackupPath" -ForegroundColor White
Write-Host "Items Restored: $restoreCount" -ForegroundColor Green
Write-Host "Items Skipped: $skipCount" -ForegroundColor Yellow
if ($errorCount -gt 0) {
    Write-Host "Errors: $errorCount" -ForegroundColor Red
}

if ($availableServers.Count -gt 0) {
    Write-Host "`nAvailable MCP Servers ($($availableServers.Count)):" -ForegroundColor Green
    $availableServers | ForEach-Object { Write-Host "  OK $_" -ForegroundColor Green }
}

if ($unavailableServers.Count -gt 0) {
    Write-Host "`nUnavailable/Unchecked MCP Servers ($($unavailableServers.Count)):" -ForegroundColor Yellow
    $unavailableServers | ForEach-Object { 
        Write-Host "  XX $_" -ForegroundColor Yellow
        Write-Host "     -> Check: npm list <package-name>" 
        Write-Host "     -> Or: Get-Command <command-name>"
    }
}

# Create restoration report
$reportPath = "$BackupPath\restore-report-$(Get-Date -Format 'yyyyMMdd-HHmmss').txt"
$report = @"
MCP Configuration Restoration Report
=====================================
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Source Backup: $BackupPath
Mode: $(if ($TestOnly) { "DRY RUN (No Changes)" } else { "FULL RESTORE" })

Statistics:
- Items Restored: $restoreCount
- Items Skipped: $skipCount
- Errors: $errorCount

Available MCP Servers: $($availableServers.Count)
$($availableServers | ForEach-Object { "  OK $_`n" })

Unavailable/Unchecked Servers: $($unavailableServers.Count)
$($unavailableServers | ForEach-Object { "  XX $_`n" })

Troubleshooting Unavailable Servers:

For NPM-based servers:
  npm install -g <package-name>
  npm list <package-name>

For Node.js servers:
  node <path-to-server>.js

For Python-based servers:
  python -m pip install <package-name>

For wrapper scripts:
  powershell -File <wrapper-script>.cmd

Log File: $logPath
"@

$report | Set-Content -Path $reportPath
Write-Host "`nFull report saved to: $reportPath" -ForegroundColor Green
Write-Log "Restore process completed"

# Exit with appropriate code
if ($errorCount -gt 0) {
    exit 1
} else {
    exit 0
}
