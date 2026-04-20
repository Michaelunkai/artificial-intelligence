param(
    [switch]$Verbose,
    [string]$BackupPath = "C:\Users\micha\.claude\mcp-backup-$(Get-Date -Format 'yyyyMMdd-HHmmss')"
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'

# Logging function
function Write-Log {
    param([string]$Message, [string]$Level = 'INFO')
    $logMsg = "[$timestamp] [$Level] $Message"
    Write-Host $logMsg
    Add-Content -Path "$BackupPath\backup.log" -Value $logMsg -ErrorAction SilentlyContinue
}

function Test-Path-Safe {
    param([string]$Path)
    return (Test-Path -Path $Path -ErrorAction SilentlyContinue)
}

# Create backup directory
if (-not (Test-Path -Path $BackupPath)) {
    New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "MCP Server Configuration Backup" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Log "Starting MCP backup to: $BackupPath"

# Counter variables
$backupCount = 0
$skipCount = 0
$errorCount = 0

# 1. Backup settings.json from .claude
Write-Host "`n[1/7] Backing up settings.json..." -ForegroundColor Yellow
if (Test-Path-Safe "C:\Users\micha\.claude\settings.json") {
    try {
        Copy-Item -Path "C:\Users\micha\.claude\settings.json" -Destination "$BackupPath\settings.json" -Force
        Write-Log "Backed up settings.json"
        $backupCount++
    } catch {
        Write-Log "Failed to backup settings.json: $_" "ERROR"
        $errorCount++
    }
} else {
    Write-Log "settings.json not found"
    $skipCount++
}

# 2. Backup MCP wrapper .cmd files
Write-Host "`n[2/7] Backing up MCP wrapper .cmd files..." -ForegroundColor Yellow
$cmdFiles = @()
try {
    $cmdFiles = Get-ChildItem -Path "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode" -Recurse -Include "*.cmd" -ErrorAction SilentlyContinue
    if ($cmdFiles.Count -gt 0) {
        New-Item -ItemType Directory -Path "$BackupPath\cmd-wrappers" -Force | Out-Null
        foreach ($file in $cmdFiles) {
            Copy-Item -Path $file.FullName -Destination "$BackupPath\cmd-wrappers\$($file.Name)" -Force
            Write-Log "Backed up: $($file.Name)"
            $backupCount++
        }
        Write-Host "Backed up $($cmdFiles.Count) .cmd files" -ForegroundColor Green
    } else {
        Write-Log "No .cmd files found"
        $skipCount++
    }
} catch {
    Write-Log "Error backing up .cmd files: $_" "ERROR"
    $errorCount++
}

# 3. Backup MCP server environment variables
Write-Host "`n[3/7] Backing up MCP environment configuration..." -ForegroundColor Yellow
try {
    $envVars = @{}
    $mcp_related = Get-ChildItem -Path Env: | Where-Object { $_.Name -like '*MCP*' -or $_.Name -like '*CLAUDE*' -or $_.Name -like '*NODE*' }
    
    if ($mcp_related.Count -gt 0) {
        $mcp_related | ForEach-Object {
            $envVars[$_.Name] = $_.Value
        }
        $envVars | ConvertTo-Json | Set-Content -Path "$BackupPath\env-variables.json"
        Write-Log "Backed up environment variables ($($mcp_related.Count) vars)"
        $backupCount++
    } else {
        Write-Log "No MCP-related environment variables found"
        $skipCount++
    }
} catch {
    Write-Log "Failed to backup environment variables: $_" "ERROR"
    $errorCount++
}

# 4. Backup MCP authentication credentials (from .claude subdirectories)
Write-Host "`n[4/7] Backing up MCP authentication and state..." -ForegroundColor Yellow
$credentialDirs = @("C:\Users\micha\.claude\session-env", "C:\Users\micha\.claude\plugins")
foreach ($dir in $credentialDirs) {
    if (Test-Path-Safe $dir) {
        try {
            $destDir = "$BackupPath\$(Split-Path -Leaf $dir)"
            Copy-Item -Path $dir -Destination $destDir -Recurse -Force
            Write-Log "Backed up: $(Split-Path -Leaf $dir)"
            $backupCount++
        } catch {
            Write-Log "Failed to backup $($dir): $_" "ERROR"
            $errorCount++
        }
    }
}

# 5. Backup custom MCP servers from F:\study\AI_ML\...\MCP\claudecode
Write-Host "`n[5/7] Backing up custom MCP server files..." -ForegroundColor Yellow
$customMcpPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode"
if (Test-Path-Safe $customMcpPath) {
    try {
        $subdirs = Get-ChildItem -Path $customMcpPath -Directory -ErrorAction SilentlyContinue
        $backed_subdirs = 0
        foreach ($subdir in $subdirs) {
            # Only backup meaningful directories
            if (@('wrappers', 'backup', 'Custom') -contains $subdir.Name -or $subdir.Name -like '*mcp*') {
                $destDir = "$BackupPath\custom-mcp\$($subdir.Name)"
                Copy-Item -Path $subdir.FullName -Destination $destDir -Recurse -Force -ErrorAction SilentlyContinue
                $backed_subdirs++
            }
        }
        Write-Log "Backed up $backed_subdirs custom MCP directories"
        $backupCount++
    } catch {
        Write-Log "Error backing up custom MCP servers: $_" "ERROR"
        $errorCount++
    }
}

# 6. Backup MCP dependencies (Node packages and Python packages)
Write-Host "`n[6/7] Backing up MCP dependencies..." -ForegroundColor Yellow
$depDirs = @(
    "C:\Users\micha\AppData\Roaming\npm",
    "C:\Users\micha\AppData\Local\Python*"
)

foreach ($depDir in $depDirs) {
    $resolvedPaths = Get-Item -Path $depDir -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName
    foreach ($path in $resolvedPaths) {
        if (Test-Path-Safe $path) {
            try {
                $destName = Split-Path -Leaf $path
                $destDir = "$BackupPath\dependencies\$destName"
                # Only backup package lists, not entire directory
                $packageList = Get-ChildItem -Path "$path\node_modules" -Directory -ErrorAction SilentlyContinue | Select-Object Name
                if ($packageList) {
                    New-Item -ItemType Directory -Path "$BackupPath\dependencies" -Force | Out-Null
                    $packageList | ConvertTo-Json | Set-Content -Path "$BackupPath\dependencies\npm-packages-list.json"
                    Write-Log "Backed up npm package list"
                }
                $backupCount++
            } catch {
                Write-Log "Could not enumerate dependencies in $path" "WARNING"
            }
        }
    }
}

# 7. Create MCP server inventory
Write-Host "`n[7/7] Creating MCP server inventory..." -ForegroundColor Yellow
try {
    $inventory = @{
        'BackupDateTime' = (Get-Date -Format 'o')
        'SettingsJsonPresent' = (Test-Path-Safe "C:\Users\micha\.claude\settings.json")
        'CmdWrapperCount' = $cmdFiles.Count
        'CustomMcpPath' = $customMcpPath
        'BackupItems' = @{
            'SettingsJson' = 'C:\Users\micha\.claude\settings.json'
            'CmdWrappers' = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\*.cmd'
            'SessionEnv' = 'C:\Users\micha\.claude\session-env'
            'Plugins' = 'C:\Users\micha\.claude\plugins'
            'CustomMCP' = $customMcpPath
        }
    }
    $inventory | ConvertTo-Json | Set-Content -Path "$BackupPath\backup-inventory.json"
    Write-Log "Created backup inventory"
    $backupCount++
} catch {
    Write-Log "Failed to create inventory: $_" "ERROR"
    $errorCount++
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Backup Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Backup Location: $BackupPath" -ForegroundColor White
Write-Host "Items Backed Up: $backupCount" -ForegroundColor Green
Write-Host "Items Skipped: $skipCount" -ForegroundColor Yellow
if ($errorCount -gt 0) {
    Write-Host "Errors: $errorCount" -ForegroundColor Red
}

# Create a summary report
$summary = @"
MCP Backup Report
==================
Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
Backup Path: $BackupPath

Statistics:
- Items Backed Up: $backupCount
- Items Skipped: $skipCount
- Errors: $errorCount

Contents:
- settings.json (main MCP settings)
- cmd-wrappers/ (MCP wrapper scripts)
- env-variables.json (environment configuration)
- session-env/ (session state)
- plugins/ (plugin data)
- custom-mcp/ (custom MCP server files)
- dependencies/ (package lists)
- backup-inventory.json (complete inventory)

To Restore:
powershell -ExecutionPolicy Bypass -File restore-mcp-config.ps1 -BackupPath "$BackupPath"
"@

$summary | Set-Content -Path "$BackupPath\README.txt"
Write-Host "`nBackup complete! Summary saved to: $BackupPath\README.txt" -ForegroundColor Green
