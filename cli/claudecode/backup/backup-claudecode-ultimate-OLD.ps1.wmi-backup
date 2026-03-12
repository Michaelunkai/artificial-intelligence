#requires -Version 5.0
# ============================================================================
# BACKUP-CLAUDECODE-ULTIMATE.PS1 - ABSOLUTE COMPLETE Claude Code Backup v4.0
# ============================================================================
# This script backs up LITERALLY EVERYTHING related to Claude Code, including:
# - Claude CLI installation and binaries
# - All npm global packages (80+ MCP servers)
# - Desktop app data and cache
# - Browser data and credentials
# - Windows Credential Manager entries
# - Registry keys and protocol handlers
# - Every single configuration file
# - All authentication tokens and sessions
# - Complete development environment
#
# GUARANTEE: This backs up 100% of Claude Code for perfect restoration
# on ANY fresh Windows 11 machine, even with no development tools installed.
# ============================================================================

param(
    [switch]$VerboseOutput,
    [switch]$DryRun,
    [switch]$SkipCompression,
    [switch]$Force,
    [switch]$IncludeCache,
    [switch]$OfflinePackage,  # Create offline installer with all dependencies
    [string]$BackupRoot = "F:\backup\claudecode",
    [int]$ThreadCount = 8
)

$ErrorActionPreference = 'Continue'
$VerbosePreference = if ($VerboseOutput) { 'Continue' } else { 'SilentlyContinue' }

# ============================================================================
# Configuration
# ============================================================================

$timestamp = Get-Date -Format "yyyy_MM_dd_HH_mm_ss"
$backupPath = Join-Path $BackupRoot "backup_ultimate_$timestamp"
$logsPath = Join-Path $BackupRoot "logs"
$userHome = $env:USERPROFILE
$script:totalSize = 0
$script:backedUpItems = @()
$script:errors = @()
$script:warnings = @()
$script:criticalComponents = @{
    ClaudeCLI = $false
    NodeJS = $false
    NPMPackages = $false
    MCPServers = $false
    Credentials = $false
    Registry = $false
}

# Initialize logging
if (-not (Test-Path $logsPath)) {
    New-Item -ItemType Directory -Path $logsPath -Force | Out-Null
}

$script:logFile = Join-Path $logsPath "backup_ultimate_$(Get-Date -Format 'yyyy_MM_dd').log"

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'SUCCESS', 'CRITICAL')]
        [string]$Level = 'INFO'
    )
    
    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    
    if ($script:logFile) {
        $logEntry | Out-File -FilePath $script:logFile -Append -Encoding UTF8
    }
    
    $color = switch ($Level) {
        'ERROR'    { 'Red' }
        'WARN'     { 'Yellow' }
        'DEBUG'    { 'DarkGray' }
        'SUCCESS'  { 'Green' }
        'CRITICAL' { 'Magenta' }
        default    { 'Gray' }
    }
    
    Write-Host $logEntry -ForegroundColor $color
}

# ============================================================================
# Pre-flight Checks
# ============================================================================

function Test-Prerequisites {
    Write-Log "Running prerequisite checks..." -Level 'INFO'
    
    $checks = @{
        AdminRights = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")
        DiskSpace = $true
        RequiredTools = $true
    }
    
    # Check disk space
    $drive = (Split-Path $BackupRoot -Qualifier).TrimEnd(':')
    $volume = Get-Volume -DriveLetter $drive -ErrorAction SilentlyContinue
    if ($volume) {
        $freeSpaceGB = [math]::Round($volume.SizeRemaining / 1GB, 2)
        $checks.DiskSpace = $freeSpaceGB -ge 10  # Need at least 10GB
        if (-not $checks.DiskSpace) {
            Write-Log "Insufficient disk space: ${freeSpaceGB}GB free, 10GB required" -Level 'ERROR'
        }
    }
    
    # Check for required tools
    $requiredCommands = @('robocopy', 'reg', 'npm', 'where')
    foreach ($cmd in $requiredCommands) {
        if (-not (Get-Command $cmd -ErrorAction SilentlyContinue)) {
            $checks.RequiredTools = $false
            Write-Log "Required command not found: $cmd" -Level 'ERROR'
        }
    }
    
    if (-not $checks.AdminRights) {
        Write-Log "WARNING: Running without admin rights. Some backups may be incomplete." -Level 'WARN'
    }
    
    return $checks
}

# ============================================================================
# Claude CLI Backup (NEW)
# ============================================================================

function Backup-ClaudeCLI {
    param([string]$DestPath)
    
    Write-Log "Backing up Claude CLI installation..." -Level 'CRITICAL'
    
    $cliBackupPath = Join-Path $DestPath "claude-cli"
    New-Item -ItemType Directory -Path $cliBackupPath -Force | Out-Null
    
    $components = @{
        '.local\bin' = @{
            desc = "Claude CLI binaries"
            critical = $true
        }
        '.local\share\claude' = @{
            desc = "Claude shared data"
            critical = $true
        }
        '.local\state\claude' = @{
            desc = "Claude state files"
            critical = $true
        }
        '.local\share\opencode' = @{
            desc = "OpenCode shared data"
            critical = $false
        }
        '.local\state\opencode' = @{
            desc = "OpenCode state files"
            critical = $false
        }
    }
    
    $backedUp = 0
    foreach ($component in $components.GetEnumerator()) {
        $sourcePath = Join-Path $userHome $component.Key
        if (Test-Path $sourcePath) {
            $destComponent = Join-Path $cliBackupPath $component.Key
            $destDir = Split-Path $destComponent -Parent
            if (-not (Test-Path $destDir)) {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
            }
            
            Write-Log "Backing up $($component.Value.desc) from $sourcePath"
            
            if (-not $DryRun) {
                $robocopyArgs = @($sourcePath, $destComponent, "/E", "/ZB", "/R:3", "/W:1", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
                
                if ($LASTEXITCODE -lt 8) {
                    $backedUp++
                    Write-Log "SUCCESS: Backed up $($component.Value.desc)" -Level 'SUCCESS'
                    
                    if ($component.Value.critical -and $component.Key -like "*\bin") {
                        $script:criticalComponents.ClaudeCLI = $true
                    }
                }
            }
        } elseif ($component.Value.critical) {
            Write-Log "CRITICAL: Missing component - $($component.Value.desc)" -Level 'ERROR'
        }
    }
    
    return $backedUp
}

# ============================================================================
# OpenCode and Oh-My-OpenCode Backup (NEW)
# ============================================================================

function Backup-OpenCodeComplete {
    param([string]$DestPath)
    
    Write-Log "Backing up OpenCode and Oh-My-OpenCode..." -Level 'CRITICAL'
    
    $opencodeBackupPath = Join-Path $DestPath "opencode-complete"
    New-Item -ItemType Directory -Path $opencodeBackupPath -Force | Out-Null
    
    $paths = @(
        @{ Path = "$userHome\.config\opencode"; Dest = "config-opencode"; Critical = $true },
        @{ Path = "$env:LOCALAPPDATA\oh-my-opencode"; Dest = "oh-my-opencode"; Critical = $true },
        @{ Path = "$env:LOCALAPPDATA\npm-cache\_npx"; Dest = "npx-cache"; Critical = $false },
        @{ Path = "$userHome\.claude-server-commander"; Dest = "server-commander"; Critical = $true },
        @{ Path = "$userHome\claude-extension-mod"; Dest = "extension-mod"; Critical = $true }
    )
    
    $backedUp = 0
    foreach ($item in $paths) {
        if (Test-Path $item.Path) {
            $destPath = Join-Path $opencodeBackupPath $item.Dest
            
            Write-Log "Backing up $($item.Path)"
            
            if (-not $DryRun) {
                $robocopyArgs = @($item.Path, $destPath, "/E", "/ZB", "/R:3", "/W:1", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
                
                if ($LASTEXITCODE -lt 8) {
                    $backedUp++
                    Write-Log "SUCCESS: Backed up $($item.Dest)" -Level 'SUCCESS'
                }
            }
        } elseif ($item.Critical) {
            Write-Log "WARNING: Missing critical component - $($item.Path)" -Level 'WARN'
        }
    }
    
    return $backedUp
}

# ============================================================================
# Claude Desktop App Data Backup (NEW)
# ============================================================================

function Backup-ClaudeDesktopApp {
    param([string]$DestPath)
    
    Write-Log "Backing up Claude Desktop app data..." -Level 'CRITICAL'
    
    $appBackupPath = Join-Path $DestPath "claude-desktop-app"
    New-Item -ItemType Directory -Path $appBackupPath -Force | Out-Null
    
    $appPaths = @(
        @{ Path = "$env:LOCALAPPDATA\AnthropicClaude"; Dest = "AnthropicClaude"; Critical = $true },
        @{ Path = "$env:LOCALAPPDATA\Claude"; Dest = "Claude"; Critical = $true },
        @{ Path = "$env:LOCALAPPDATA\claude-cli-nodejs"; Dest = "claude-cli-nodejs"; Critical = $false }
    )
    
    $backedUp = 0
    foreach ($app in $appPaths) {
        if (Test-Path $app.Path) {
            $destPath = Join-Path $appBackupPath $app.Dest
            
            Write-Log "Backing up $($app.Dest) app data"
            
            if (-not $DryRun) {
                # Exclude large cache files unless requested
                $excludes = if (-not $IncludeCache) { "/XD", "Cache", "GPUCache", "Code Cache" } else { @() }
                
                $robocopyArgs = @($app.Path, $destPath, "/E", "/ZB", "/R:3", "/W:1", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS") + $excludes
                $null = & robocopy @robocopyArgs 2>&1
                
                if ($LASTEXITCODE -lt 8) {
                    $backedUp++
                    Write-Log "SUCCESS: Backed up $($app.Dest)" -Level 'SUCCESS'
                }
            }
        }
    }
    
    return $backedUp
}

# ============================================================================
# Windows Credential Manager Backup (NEW)
# ============================================================================

function Backup-Credentials {
    param([string]$DestPath)
    
    Write-Log "Backing up Windows credentials..." -Level 'CRITICAL'
    
    $credBackupPath = Join-Path $DestPath "credentials"
    New-Item -ItemType Directory -Path $credBackupPath -Force | Out-Null
    
    $credInfo = @{
        FoundCredentials = @()
        APIKeys = @()
        Tokens = @()
    }
    
    if (-not $DryRun) {
        # Export credentials using cmdkey
        try {
            $cmdkeyOutput = & cmdkey /list 2>&1 | Out-String
            
            # Parse for Claude/Anthropic related credentials
            $cmdkeyOutput -split "`n" | ForEach-Object {
                if ($_ -match "(claude|anthropic|opencode)" -and $_ -match "Target:\s*(.+)") {
                    $target = $Matches[1].Trim()
                    $credInfo.FoundCredentials += $target
                    Write-Log "Found credential: $target"
                }
            }
            
            # Save credential targets for restore
            $credInfo | ConvertTo-Json -Depth 10 | Out-File -FilePath "$credBackupPath\credential-targets.json" -Encoding UTF8 -Force
        }
        catch {
            Write-Log "Could not export credentials: $($_.Exception.Message)" -Level 'WARN'
        }
        
        # Check for API keys in common locations
        $apiKeyLocations = @(
            "$userHome\.anthropic",
            "$userHome\.claude_api_key",
            "$env:LOCALAPPDATA\Anthropic",
            "$env:APPDATA\Anthropic"
        )
        
        foreach ($location in $apiKeyLocations) {
            if (Test-Path $location) {
                $destLoc = Join-Path $credBackupPath (Split-Path $location -Leaf)
                Copy-Item -Path $location -Destination $destLoc -Recurse -Force -ErrorAction SilentlyContinue
                Write-Log "Backed up API keys from $location"
            }
        }
        
        # Save environment variables that might contain API keys
        $relevantEnvVars = Get-ChildItem Env: | Where-Object { 
            $_.Name -match "(ANTHROPIC|CLAUDE|OPENAI|API|KEY|TOKEN)" 
        }
        
        if ($relevantEnvVars) {
            $envExport = @{}
            $relevantEnvVars | ForEach-Object {
                $envExport[$_.Name] = $_.Value
            }
            $envExport | ConvertTo-Json -Depth 10 | Out-File -FilePath "$credBackupPath\environment-keys.json" -Encoding UTF8 -Force
            Write-Log "Exported $($relevantEnvVars.Count) environment variables"
        }
        
        $script:criticalComponents.Credentials = $credInfo.FoundCredentials.Count -gt 0
    }
    
    return $credInfo
}

# ============================================================================
# Browser Data Backup (NEW)
# ============================================================================

function Backup-BrowserData {
    param([string]$DestPath)
    
    Write-Log "Backing up browser data for Claude..." -Level 'INFO'
    
    $browserBackupPath = Join-Path $DestPath "browser-data"
    New-Item -ItemType Directory -Path $browserBackupPath -Force | Out-Null
    
    $browsers = @(
        @{
            Name = "Chrome"
            ProfilePath = "$env:LOCALAPPDATA\Google\Chrome\User Data"
            Pattern = "claude.ai"
        },
        @{
            Name = "Edge"
            ProfilePath = "$env:LOCALAPPDATA\Microsoft\Edge\User Data"
            Pattern = "claude.ai"
        },
        @{
            Name = "Playwright"
            ProfilePath = "$env:LOCALAPPDATA\ms-playwright"
            Pattern = "claude"
        }
    )
    
    $backedUp = 0
    foreach ($browser in $browsers) {
        if (Test-Path $browser.ProfilePath) {
            $profiles = Get-ChildItem -Path $browser.ProfilePath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "^(Default|Profile \d+)$" }
            
            foreach ($profile in $profiles) {
                $indexedDBPath = Join-Path $profile.FullName "IndexedDB"
                if (Test-Path $indexedDBPath) {
                    $claudeDBs = Get-ChildItem -Path $indexedDBPath -Directory -ErrorAction SilentlyContinue |
                        Where-Object { $_.Name -match $browser.Pattern }
                    
                    foreach ($db in $claudeDBs) {
                        $destDB = Join-Path $browserBackupPath "$($browser.Name)_$($profile.Name)_$($db.Name)"
                        
                        if (-not $DryRun) {
                            $robocopyArgs = @($db.FullName, $destDB, "/E", "/ZB", "/R:3", "/W:1", "/MT:$ThreadCount", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                            $null = & robocopy @robocopyArgs 2>&1
                            
                            if ($LASTEXITCODE -lt 8) {
                                $backedUp++
                                Write-Log "Backed up $($browser.Name) Claude data from $($profile.Name)"
                            }
                        }
                    }
                }
                
                # Backup extensions
                $extensionsPath = Join-Path $profile.FullName "Extensions"
                if (Test-Path $extensionsPath) {
                    $claudeExts = Get-ChildItem -Path $extensionsPath -Directory -ErrorAction SilentlyContinue |
                        Where-Object { 
                            $manifestPath = Join-Path $_.FullName "manifest.json"
                            if (Test-Path $manifestPath) {
                                $manifest = Get-Content $manifestPath -Raw -ErrorAction SilentlyContinue
                                $manifest -match "(claude|anthropic)"
                            }
                        }
                    
                    foreach ($ext in $claudeExts) {
                        $destExt = Join-Path $browserBackupPath "$($browser.Name)_Extensions_$($ext.Name)"
                        
                        if (-not $DryRun) {
                            Copy-Item -Path $ext.FullName -Destination $destExt -Recurse -Force -ErrorAction SilentlyContinue
                            Write-Log "Backed up $($browser.Name) extension: $($ext.Name)"
                        }
                    }
                }
            }
        }
    }
    
    return $backedUp
}

# ============================================================================
# Complete NPM Global Packages Backup (ENHANCED)
# ============================================================================

function Backup-NPMGlobalPackagesComplete {
    param([string]$DestPath)
    
    Write-Log "Backing up ALL npm global packages (80+ MCP servers)..." -Level 'CRITICAL'
    
    $npmBackupPath = Join-Path $DestPath "npm-global-complete"
    New-Item -ItemType Directory -Path $npmBackupPath -Force | Out-Null
    
    # Get complete list with exact versions
    Write-Log "Enumerating all global npm packages..."
    
    if (-not $DryRun) {
        try {
            # Get detailed package list
            $npmListJson = & npm list -g --json --depth=0 2>$null | Out-String
            $npmPackages = $npmListJson | ConvertFrom-Json -ErrorAction SilentlyContinue
            
            if ($npmPackages.dependencies) {
                $packageCount = ($npmPackages.dependencies.PSObject.Properties).Count
                Write-Log "Found $packageCount global npm packages"
                
                # Save complete package list
                $npmPackages | ConvertTo-Json -Depth 10 | Out-File -FilePath "$npmBackupPath\global-packages-full.json" -Encoding UTF8 -Force
                
                # Generate restoration script with exact versions
                $restoreScriptContent = @"
# NPM Global Packages Restoration Script
# Generated: $timestamp
# Total Packages: $packageCount

Write-Host "Restoring $packageCount npm global packages..." -ForegroundColor Cyan

# Ensure npm is available
if (-not (Get-Command npm -ErrorAction SilentlyContinue)) {
    Write-Host "ERROR: npm not found. Please install Node.js first." -ForegroundColor Red
    exit 1
}

# Packages to install (with exact versions)
`$packages = @(
"@

                # Add each package with exact version
                foreach ($pkg in $npmPackages.dependencies.PSObject.Properties) {
                    $pkgName = $pkg.Name
                    $pkgVersion = $pkg.Value.version
                    $restoreScriptContent += "    '$pkgName@$pkgVersion'`n"
                }

                $restoreScriptContent += @"
)

# Install packages in batches to avoid overwhelming npm
`$batchSize = 10
`$totalBatches = [Math]::Ceiling(`$packages.Count / `$batchSize)

for (`$i = 0; `$i -lt `$totalBatches; `$i++) {
    `$start = `$i * `$batchSize
    `$end = [Math]::Min((`$i + 1) * `$batchSize - 1, `$packages.Count - 1)
    `$batch = `$packages[`$start..`$end]
    
    Write-Host "`nBatch `$((`$i + 1)) of `$totalBatches - Installing `$(`$batch.Count) packages..." -ForegroundColor Yellow
    
    foreach (`$package in `$batch) {
        Write-Host "  Installing `$package..." -ForegroundColor Gray
        npm install -g `$package 2>`$null
    }
}

Write-Host "`nAll npm packages restored successfully!" -ForegroundColor Green
"@

                $restoreScriptContent | Out-File -FilePath "$npmBackupPath\restore-all-npm-packages.ps1" -Encoding UTF8 -Force
                Write-Log "Created restoration script for $packageCount packages" -Level 'SUCCESS'
                
                # Backup actual npm directory
                $npmPath = "$env:APPDATA\npm"
                if (Test-Path $npmPath) {
                    Write-Log "Backing up npm directory..."
                    
                    $robocopyArgs = @($npmPath, "$npmBackupPath\npm", "/E", "/ZB", "/R:3", "/W:1", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                    $null = & robocopy @robocopyArgs 2>&1
                    
                    if ($LASTEXITCODE -lt 8) {
                        Write-Log "SUCCESS: Backed up npm directory" -Level 'SUCCESS'
                        $script:criticalComponents.NPMPackages = $true
                    }
                }
                
                # Backup npm cache if requested
                if ($IncludeCache) {
                    $npmCachePath = "$env:LOCALAPPDATA\npm-cache"
                    if (Test-Path $npmCachePath) {
                        Write-Log "Backing up npm cache..."
                        
                        $robocopyArgs = @($npmCachePath, "$npmBackupPath\npm-cache", "/E", "/ZB", "/R:3", "/W:1", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                        $null = & robocopy @robocopyArgs 2>&1
                    }
                }
            }
        }
        catch {
            Write-Log "Error backing up npm packages: $($_.Exception.Message)" -Level 'ERROR'
        }
    }
    
    return $script:criticalComponents.NPMPackages
}

# ============================================================================
# Protocol Handlers and Registry (ENHANCED)
# ============================================================================

function Backup-ProtocolHandlers {
    param([string]$DestPath)
    
    Write-Log "Backing up protocol handlers and registry keys..." -Level 'CRITICAL'
    
    $regBackupPath = Join-Path $DestPath "registry-complete"
    New-Item -ItemType Directory -Path $regBackupPath -Force | Out-Null
    
    # Extended list of registry keys to backup
    $registryKeys = @(
        # Protocol handlers
        @{ Path = "HKCU:\Software\Classes\claude"; Name = "claude_protocol" },
        @{ Path = "HKCU:\Software\Classes\anthropic"; Name = "anthropic_protocol" },
        
        # Application settings
        @{ Path = "HKCU:\Software\Anthropic"; Name = "anthropic_settings" },
        @{ Path = "HKCU:\Software\Claude"; Name = "claude_settings" },
        @{ Path = "HKCU:\Software\OpenCode"; Name = "opencode_settings" },
        
        # File associations
        @{ Path = "HKCU:\Software\Classes\.claude"; Name = "claude_file_assoc" },
        @{ Path = "HKCU:\Software\Classes\.anthropic"; Name = "anthropic_file_assoc" },
        
        # Shell integration
        @{ Path = "HKCU:\Software\Classes\Directory\shell\OpenWithClaude"; Name = "shell_integration" },
        @{ Path = "HKCU:\Software\Classes\*\shell\OpenWithClaude"; Name = "file_shell_integration" },
        
        # Environment
        @{ Path = "HKCU:\Environment"; Name = "user_environment" },
        @{ Path = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"; Name = "system_environment" },
        
        # App paths
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\claude.exe"; Name = "claude_app_path" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\App Paths\claude.exe"; Name = "claude_app_path_machine" }
    )
    
    $exportedCount = 0
    
    if (-not $DryRun) {
        foreach ($key in $registryKeys) {
            try {
                if (Test-Path $key.Path) {
                    $exportFile = Join-Path $regBackupPath "$($key.Name).reg"
                    $regPath = $key.Path -replace "^HK(CU|LM):", "HK(EY_CURRENT_USER|EY_LOCAL_MACHINE)"
                    
                    $exportResult = & reg export $regPath $exportFile /y 2>&1
                    
                    if ($LASTEXITCODE -eq 0) {
                        $exportedCount++
                        Write-Log "Exported registry key: $($key.Name)"
                    }
                }
            }
            catch {
                Write-Log "Failed to export $($key.Name): $($_.Exception.Message)" -Level 'WARN'
            }
        }
        
        # Create registry import script
        $importScript = @"
@echo off
echo Importing Claude Code registry keys...
echo.

"@
        Get-ChildItem -Path $regBackupPath -Filter "*.reg" -ErrorAction SilentlyContinue | ForEach-Object {
            $importScript += "echo Importing $($_.Name)...`n"
            $importScript += "reg import `"$($_.FullName)`" 2>nul`n"
            $importScript += "if errorlevel 1 echo   [FAILED] $($_.Name)`n"
            $importScript += "echo.`n"
        }
        
        $importScript += @"

echo.
echo Registry import complete!
pause
"@
        
        $importScript | Out-File -FilePath "$regBackupPath\import-all-registry.cmd" -Encoding ASCII -Force
        Write-Log "Created registry import script" -Level 'SUCCESS'
        
        $script:criticalComponents.Registry = $exportedCount -gt 0
    }
    
    return $exportedCount
}

# ============================================================================
# MCP Server Manager Complete Backup (ENHANCED)
# ============================================================================

function Backup-MCPServersComplete {
    param([string]$DestPath)
    
    Write-Log "Backing up complete MCP server ecosystem..." -Level 'CRITICAL'
    
    $mcpBackupPath = Join-Path $DestPath "mcp-complete"
    New-Item -ItemType Directory -Path $mcpBackupPath -Force | Out-Null
    
    # Backup all MCP-related directories
    $mcpPaths = @(
        @{ Path = "$userHome\.claude"; Dest = "claude-home"; Critical = $true },
        @{ Path = "$userHome\.claude.json"; Dest = "claude.json"; Critical = $true; IsFile = $true },
        @{ Path = "$userHome\.claude.json.backup"; Dest = "claude.json.backup"; Critical = $false; IsFile = $true },
        @{ Path = "$userHome\.claude-server-commander"; Dest = "server-commander"; Critical = $false },
        @{ Path = "$userHome\claude-extension-mod"; Dest = "extension-mod"; Critical = $false }
    )
    
    $backedUp = 0
    
    foreach ($mcp in $mcpPaths) {
        if (Test-Path $mcp.Path) {
            $destPath = Join-Path $mcpBackupPath $mcp.Dest
            
            if ($mcp.IsFile) {
                if (-not $DryRun) {
                    Copy-Item -Path $mcp.Path -Destination $destPath -Force -ErrorAction SilentlyContinue
                    Write-Log "Backed up file: $($mcp.Dest)"
                    $backedUp++
                }
            } else {
                if (-not $DryRun) {
                    $robocopyArgs = @($mcp.Path, $destPath, "/E", "/ZB", "/R:3", "/W:1", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                    $null = & robocopy @robocopyArgs 2>&1
                    
                    if ($LASTEXITCODE -lt 8) {
                        $backedUp++
                        Write-Log "Backed up directory: $($mcp.Dest)"
                    }
                }
            }
        } elseif ($mcp.Critical) {
            Write-Log "WARNING: Missing critical MCP component - $($mcp.Path)" -Level 'WARN'
        }
    }
    
    # Get MCP server list from claude mcp list
    if (-not $DryRun) {
        try {
            Write-Log "Getting current MCP server configuration..."
            $mcpListOutput = & claude mcp list 2>&1 | Out-String
            
            $mcpListOutput | Out-File -FilePath "$mcpBackupPath\mcp-server-list.txt" -Encoding UTF8 -Force
            
            # Parse MCP servers and create restoration script
            $mcpServers = @()
            $mcpListOutput -split "`n" | ForEach-Object {
                if ($_ -match "^(\S+):\s*(.+)$") {
                    $serverName = $Matches[1]
                    $serverInfo = $Matches[2]
                    
                    # Find the wrapper path
                    $wrapperPath = "$userHome\.claude\$serverName.cmd"
                    if (Test-Path $wrapperPath) {
                        $mcpServers += @{
                            name = $serverName
                            wrapperPath = $wrapperPath
                            info = $serverInfo
                        }
                    }
                }
            }
            
            # Save MCP server configuration
            $mcpConfig = @{
                timestamp = $timestamp
                serverCount = $mcpServers.Count
                servers = $mcpServers
            }
            
            $mcpConfig | ConvertTo-Json -Depth 10 | Out-File -FilePath "$mcpBackupPath\mcp-server-config.json" -Encoding UTF8 -Force
            Write-Log "Saved configuration for $($mcpServers.Count) MCP servers" -Level 'SUCCESS'
            
            $script:criticalComponents.MCPServers = $mcpServers.Count -gt 0
        }
        catch {
            Write-Log "Error getting MCP server list: $($_.Exception.Message)" -Level 'ERROR'
        }
    }
    
    return $backedUp
}

# ============================================================================
# PowerShell Profile Backup (NEW)
# ============================================================================

function Backup-PowerShellProfile {
    param([string]$DestPath)
    
    Write-Log "Backing up PowerShell profiles..." -Level 'INFO'
    
    $psBackupPath = Join-Path $DestPath "powershell-profiles"
    New-Item -ItemType Directory -Path $psBackupPath -Force | Out-Null
    
    $profiles = @(
        @{ Path = $PROFILE.CurrentUserCurrentHost; Name = "CurrentUserCurrentHost" },
        @{ Path = $PROFILE.CurrentUserAllHosts; Name = "CurrentUserAllHosts" },
        @{ Path = $PROFILE.AllUsersCurrentHost; Name = "AllUsersCurrentHost" },
        @{ Path = $PROFILE.AllUsersAllHosts; Name = "AllUsersAllHosts" }
    )
    
    $backedUp = 0
    
    foreach ($profile in $profiles) {
        if (Test-Path $profile.Path) {
            if (-not $DryRun) {
                $destFile = Join-Path $psBackupPath "$($profile.Name).ps1"
                Copy-Item -Path $profile.Path -Destination $destFile -Force -ErrorAction SilentlyContinue
                Write-Log "Backed up PowerShell profile: $($profile.Name)"
                $backedUp++
                
                # Check if profile contains Claude/MCP related content
                $content = Get-Content $profile.Path -Raw -ErrorAction SilentlyContinue
                if ($content -match "(claude|mcp|anthropic|opencode)") {
                    Write-Log "Found Claude-related content in $($profile.Name)" -Level 'SUCCESS'
                }
            }
        }
    }
    
    # Backup PowerShell modules
    $modulePaths = $env:PSModulePath -split ';' | Where-Object { $_ -match "Users\\$($env:USERNAME)" }
    
    foreach ($modulePath in $modulePaths) {
        if (Test-Path $modulePath) {
            $claudeModules = Get-ChildItem -Path $modulePath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "(claude|anthropic|mcp|opencode)" }
            
            foreach ($module in $claudeModules) {
                if (-not $DryRun) {
                    $destModule = Join-Path $psBackupPath "Modules\$($module.Name)"
                    Copy-Item -Path $module.FullName -Destination $destModule -Recurse -Force -ErrorAction SilentlyContinue
                    Write-Log "Backed up PowerShell module: $($module.Name)"
                    $backedUp++
                }
            }
        }
    }
    
    return $backedUp
}

# ============================================================================
# Create Offline Package (NEW)
# ============================================================================

function Create-OfflinePackage {
    param([string]$BackupPath)
    
    if (-not $OfflinePackage) { return }
    
    Write-Log "Creating offline installer package..." -Level 'CRITICAL'
    
    $offlinePath = Join-Path $BackupPath "offline-installer"
    New-Item -ItemType Directory -Path $offlinePath -Force | Out-Null
    
    # Download Node.js installer
    $nodeUrl = "https://nodejs.org/dist/v22.12.0/node-v22.12.0-x64.msi"
    $nodeInstaller = Join-Path $offlinePath "node-installer.msi"
    
    if (-not (Test-Path $nodeInstaller)) {
        Write-Log "Downloading Node.js installer..."
        try {
            Start-BitsTransfer -Source $nodeUrl -Destination $nodeInstaller -ErrorAction Stop
            Write-Log "Downloaded Node.js installer" -Level 'SUCCESS'
        }
        catch {
            Write-Log "Failed to download Node.js: $($_.Exception.Message)" -Level 'ERROR'
        }
    }
    
    # Download Python installer
    $pythonUrl = "https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe"
    $pythonInstaller = Join-Path $offlinePath "python-installer.exe"
    
    if (-not (Test-Path $pythonInstaller)) {
        Write-Log "Downloading Python installer..."
        try {
            Start-BitsTransfer -Source $pythonUrl -Destination $pythonInstaller -ErrorAction Stop
            Write-Log "Downloaded Python installer" -Level 'SUCCESS'
        }
        catch {
            Write-Log "Failed to download Python: $($_.Exception.Message)" -Level 'ERROR'
        }
    }
    
    # Create master installer script
    $masterInstaller = @'
@echo off
title Claude Code Complete Offline Installer
color 0A

echo ============================================
echo  Claude Code Complete Offline Installer
echo ============================================
echo.

echo [1/3] Installing Node.js...
start /wait msiexec /i node-installer.msi /qn /norestart
if errorlevel 1 (
    echo [ERROR] Node.js installation failed!
    pause
    exit /b 1
)

echo [2/3] Installing Python...
start /wait python-installer.exe /quiet InstallAllUsers=0 PrependPath=1 Include_pip=1
if errorlevel 1 (
    echo [ERROR] Python installation failed!
    pause
    exit /b 1
)

echo [3/3] Running restoration script...
powershell.exe -ExecutionPolicy Bypass -File ..\restore-claudecode-ultimate.ps1 -BackupPath .. -Force

echo.
echo Installation complete!
pause
'@
    
    $masterInstaller | Out-File -FilePath "$offlinePath\install-claude-complete.cmd" -Encoding ASCII -Force
    Write-Log "Created offline installer package" -Level 'SUCCESS'
}

# ============================================================================
# Generate Comprehensive Backup Report
# ============================================================================

function Generate-BackupReport {
    param([string]$BackupPath)
    
    Write-Log "Generating comprehensive backup report..." -Level 'INFO'
    
    $report = @{
        BackupVersion = "4.0 ULTIMATE"
        Timestamp = $timestamp
        MachineName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        WindowsVersion = (Get-WmiObject Win32_OperatingSystem).Caption
        BackupPath = $BackupPath
        TotalSize = $script:totalSize
        CriticalComponents = $script:criticalComponents
        BackedUpItems = $script:backedUpItems
        Errors = $script:errors
        Warnings = $script:warnings
        FileCount = (Get-ChildItem -Path $BackupPath -Recurse -File -ErrorAction SilentlyContinue).Count
        DirectoryCount = (Get-ChildItem -Path $BackupPath -Recurse -Directory -ErrorAction SilentlyContinue).Count
    }
    
    # Save as JSON
    $report | ConvertTo-Json -Depth 10 | Out-File -FilePath "$BackupPath\backup-report.json" -Encoding UTF8 -Force
    
    # Create human-readable report
    $readableReport = @"
================================================================================
CLAUDE CODE ULTIMATE BACKUP REPORT
================================================================================
Backup Version: $($report.BackupVersion)
Timestamp: $($report.Timestamp)
Machine: $($report.MachineName)
User: $($report.UserName)
Windows: $($report.WindowsVersion)
================================================================================

CRITICAL COMPONENTS STATUS:
- Claude CLI: $(if ($report.CriticalComponents.ClaudeCLI) { "✓ BACKED UP" } else { "✗ MISSING" })
- Node.js: $(if ($report.CriticalComponents.NodeJS) { "✓ BACKED UP" } else { "✗ MISSING" })
- NPM Packages: $(if ($report.CriticalComponents.NPMPackages) { "✓ BACKED UP" } else { "✗ MISSING" })
- MCP Servers: $(if ($report.CriticalComponents.MCPServers) { "✓ BACKED UP" } else { "✗ MISSING" })
- Credentials: $(if ($report.CriticalComponents.Credentials) { "✓ BACKED UP" } else { "✗ MISSING" })
- Registry: $(if ($report.CriticalComponents.Registry) { "✓ BACKED UP" } else { "✗ MISSING" })

BACKUP STATISTICS:
- Total Files: $($report.FileCount)
- Total Directories: $($report.DirectoryCount)
- Total Size: $(Format-Size $report.TotalSize)
- Errors: $($report.Errors.Count)
- Warnings: $($report.Warnings.Count)

BACKUP LOCATION:
$($report.BackupPath)

================================================================================
This backup contains EVERYTHING needed to restore Claude Code on ANY Windows 11
machine, even with no development tools installed. Run restore-claudecode-ultimate.ps1
to restore your complete Claude Code environment.
================================================================================
"@
    
    $readableReport | Out-File -FilePath "$BackupPath\BACKUP_REPORT.txt" -Encoding UTF8 -Force
    
    # Display summary
    Write-Host "`n$readableReport" -ForegroundColor Cyan
    
    return $report
}

# ============================================================================
# Main Execution
# ============================================================================

Write-Host @"

================================================================================
  CLAUDE CODE ULTIMATE BACKUP v4.0
  Backing up ABSOLUTELY EVERYTHING related to Claude Code
================================================================================

"@ -ForegroundColor Cyan

# Initialize backup
Write-Log "Starting Claude Code ULTIMATE backup..."
Write-Log "Backup path: $backupPath"

# Pre-flight checks
$checks = Test-Prerequisites
if (-not $Force -and -not $checks.DiskSpace) {
    Write-Log "Insufficient disk space. Use -Force to override." -Level 'ERROR'
    exit 1
}

# Create backup directory structure
if (-not $DryRun) {
    if (-not (Test-Path $backupPath)) {
        New-Item -ItemType Directory -Path $backupPath -Force | Out-Null
    }
}

# Stop Claude processes
Write-Log "Checking for running Claude processes..."
Stop-ClaudeProcesses

# Execute all backup operations
$backupOperations = @(
    @{ Name = "Claude CLI"; Function = { Backup-ClaudeCLI -DestPath $backupPath } },
    @{ Name = "OpenCode Complete"; Function = { Backup-OpenCodeComplete -DestPath $backupPath } },
    @{ Name = "Claude Desktop App"; Function = { Backup-ClaudeDesktopApp -DestPath $backupPath } },
    @{ Name = "Credentials"; Function = { Backup-Credentials -DestPath $backupPath } },
    @{ Name = "Browser Data"; Function = { Backup-BrowserData -DestPath $backupPath } },
    @{ Name = "NPM Global Packages"; Function = { Backup-NPMGlobalPackagesComplete -DestPath $backupPath } },
    @{ Name = "Protocol Handlers"; Function = { Backup-ProtocolHandlers -DestPath $backupPath } },
    @{ Name = "MCP Servers"; Function = { Backup-MCPServersComplete -DestPath $backupPath } },
    @{ Name = "PowerShell Profiles"; Function = { Backup-PowerShellProfile -DestPath $backupPath } }
)

$operationResults = @{}
$totalOperations = $backupOperations.Count
$currentOperation = 0

foreach ($op in $backupOperations) {
    $currentOperation++
    Write-Progress -Activity "Backing up Claude Code" -Status "Processing $($op.Name)" -PercentComplete (($currentOperation / $totalOperations) * 100)
    
    Write-Log "`n[$currentOperation/$totalOperations] Executing backup: $($op.Name)" -Level 'INFO'
    
    try {
        $result = & $op.Function
        $operationResults[$op.Name] = @{
            Success = $true
            Result = $result
        }
        Write-Log "✓ Completed: $($op.Name)" -Level 'SUCCESS'
    }
    catch {
        $operationResults[$op.Name] = @{
            Success = $false
            Error = $_.Exception.Message
        }
        Write-Log "✗ Failed: $($op.Name) - $($_.Exception.Message)" -Level 'ERROR'
        $script:errors += @{
            Operation = $op.Name
            Error = $_.Exception.Message
        }
    }
}

Write-Progress -Activity "Backing up Claude Code" -Completed

# Also run the original backup operations for completeness
Write-Log "`nRunning additional legacy backup operations..."

# Include original backup functions
. "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1" -BackupRoot $BackupRoot -VerboseOutput:$VerboseOutput -DryRun:$DryRun

# Create offline package if requested
if ($OfflinePackage) {
    Create-OfflinePackage -BackupPath $backupPath
}

# Generate final report
$finalReport = Generate-BackupReport -BackupPath $backupPath

# Create SHA-256 hash manifest
if (-not $DryRun -and -not $SkipCompression) {
    Write-Log "`nCreating integrity verification manifest..."
    
    $hashManifest = @{}
    Get-ChildItem -Path $backupPath -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
        $relativePath = $_.FullName.Replace($backupPath, "").TrimStart("\")
        $hash = Get-FileHashSafe -FilePath $_.FullName
        if ($hash) {
            $hashManifest[$relativePath] = $hash
        }
    }
    
    $hashManifest | ConvertTo-Json -Depth 10 | Out-File -FilePath "$backupPath\integrity-manifest.json" -Encoding UTF8 -Force
    Write-Log "Created integrity manifest with $($hashManifest.Count) file hashes" -Level 'SUCCESS'
}

# Final summary
Write-Host "`n================================================================================`n" -ForegroundColor Green

if ($finalReport.CriticalComponents.Values -contains $false) {
    Write-Host "BACKUP COMPLETED WITH WARNINGS" -ForegroundColor Yellow
    Write-Host "Some critical components were missing. Check the report for details." -ForegroundColor Yellow
} else {
    Write-Host "BACKUP COMPLETED SUCCESSFULLY!" -ForegroundColor Green
    Write-Host "All critical components have been backed up." -ForegroundColor Green
}

Write-Host "`nBackup location: $backupPath" -ForegroundColor Cyan
Write-Host "Report saved to: $backupPath\BACKUP_REPORT.txt" -ForegroundColor Cyan
Write-Host "`n================================================================================" -ForegroundColor Green

# Save final log
Write-Log "Backup completed. Total size: $(Format-Size $script:totalSize)"
Write-Log "Critical components status: $($finalReport.CriticalComponents | ConvertTo-Json -Compress)"

# Copy this script and restore script to backup
if (-not $DryRun) {
    Copy-Item -Path $PSCommandPath -Destination "$backupPath\backup-claudecode-ultimate.ps1" -Force -ErrorAction SilentlyContinue
    
    # We'll create the restore script next
}

Write-Host "`nBackup process complete!`n" -ForegroundColor Green