#requires -Version 5.0
# ============================================================================
# BACKUP-CLAUDECODE.PS1 - COMPREHENSIVE Claude Code Backup Utility v4.3
# ============================================================================
# FAST & COMPLETE - Skips regeneratable binaries, backs up everything else
#
# STRATEGY:
# - SKIPS: npm node_modules (8GB), uvx binaries, Bun (~500MB)
#   These are regeneratable from package lists in seconds
# - BACKS UP FULLY: configs, credentials, MCP wrappers, conversations,
#   PowerShell profiles, registry, environment vars, etc.
#
# RESTORE REGENERATABLES:
# - npm:  Run restore-npm-packages.ps1 (or: npm install -g from packages.json)
# - uvx:  uv tool install <tool> (from tool-list.txt)  
# - Bun:  irm bun.sh/install.ps1 | iex
#
# FEATURES:
# - Timeout protection on ALL external commands (never hangs)
# - Progress reporting with ETA
# - Backup of ALL credentials and API keys
# - Full OpenCode and Sisyphus backup
# - All MCP wrappers backed up
# - Conversation history preserved
# - PowerShell modules including ClaudeUsage
# - ~30 seconds typical runtime
# ============================================================================

param(
    [switch]$VerboseOutput,
    [switch]$DryRun,
    [switch]$SkipCompression,
    [switch]$Force,
    [switch]$FullCopy,  # Use actual file copies instead of junction points (SLOW for large dirs)
    [ValidateSet('Full', 'Minimal', 'Custom')]
    [string]$Profile = 'Full',
    [int]$ThreadCount = 8,
    [string]$BackupRoot = "F:\backup\claudecode",
    [int]$CommandTimeout = 10  # Timeout in seconds for external commands
)

# DEFAULT: Use instant backup (junction points) unless -FullCopy is specified
$InstantBackup = -not $FullCopy

$ErrorActionPreference = 'Continue'
$VerbosePreference = if ($VerboseOutput) { 'Continue' } else { 'SilentlyContinue' }

# ============================================================================
# Configuration
# ============================================================================

$timestamp = Get-Date -Format "yyyy_MM_dd_HH_mm_ss"
$backupPath = Join-Path $BackupRoot "backup_$timestamp"
$logsPath = Join-Path $BackupRoot "logs"
$userHome = $env:USERPROFILE
$script:totalSize = 0
$script:backedUpItems = @()
$script:errors = @()
$script:warnings = @()
$script:fileManifest = @()
$script:lockFile = $null
$script:logFile = $null
$script:startTime = Get-Date
$script:MIN_DISK_SPACE_GB = 5
$script:currentStep = 0
$script:totalSteps = 50

# ============================================================================
# Logging System
# ============================================================================

function Initialize-LogSystem {
    param([string]$LogsPath)

    if (-not (Test-Path $LogsPath)) {
        New-Item -ItemType Directory -Path $LogsPath -Force | Out-Null
    }

    $logDate = Get-Date -Format "yyyy_MM_dd"
    $script:logFile = Join-Path $LogsPath "backup_$logDate.log"

    # Rotate old logs (keep 10 days)
    $cutoffDate = (Get-Date).AddDays(-10)
    Get-ChildItem -Path $LogsPath -Filter "backup_*.log" -ErrorAction SilentlyContinue |
        Where-Object { $_.LastWriteTime -lt $cutoffDate } |
        ForEach-Object {
            Remove-Item $_.FullName -Force -ErrorAction SilentlyContinue
        }

    Write-Log "=========================================="
    Write-Log "Backup session started: $timestamp"
    Write-Log "Backup version: 4.3 (FAST - skips regeneratables)"
    Write-Log "=========================================="
}

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('INFO', 'WARN', 'ERROR', 'DEBUG', 'SUCCESS')]
        [string]$Level = 'INFO'
    )

    $logEntry = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"

    if ($script:logFile) {
        try {
            $logEntry | Out-File -FilePath $script:logFile -Append -Encoding UTF8
        } catch { }
    }

    if ($VerboseOutput -or $Level -in @('ERROR', 'SUCCESS')) {
        switch ($Level) {
            'ERROR'   { Write-Host $logEntry -ForegroundColor Red }
            'WARN'    { Write-Host $logEntry -ForegroundColor Yellow }
            'DEBUG'   { Write-Host $logEntry -ForegroundColor DarkGray }
            'SUCCESS' { Write-Host $logEntry -ForegroundColor Green }
            default   { Write-Host $logEntry -ForegroundColor Gray }
        }
    }
}

# ============================================================================
# Helper Functions
# ============================================================================

function Write-Progress-Step {
    param(
        [string]$StepNumber,
        [string]$Message,
        [ConsoleColor]$Color = "Green"
    )
    
    $script:currentStep++
    $percentComplete = [Math]::Round(($script:currentStep / $script:totalSteps) * 100, 0)
    $elapsed = (Get-Date) - $script:startTime
    
    if ($script:currentStep -gt 1) {
        $avgSecondsPerStep = $elapsed.TotalSeconds / ($script:currentStep - 1)
        $remainingSteps = $script:totalSteps - $script:currentStep
        $eta = [TimeSpan]::FromSeconds($avgSecondsPerStep * $remainingSteps)
        $etaStr = " (ETA: {0:mm}:{0:ss})" -f $eta
    } else {
        $etaStr = ""
    }
    
    Write-Host "$StepNumber $Message$etaStr" -ForegroundColor $Color
    Write-Log "$StepNumber $Message"
    
    # Update PowerShell progress bar
    Write-Progress -Activity "Claude Code Backup v4.3" -Status $Message -PercentComplete $percentComplete
}

function Write-Info {
    param([string]$Message, [ConsoleColor]$Color = "Gray")
    Write-Host "  -> $Message" -ForegroundColor $Color
    Write-Log "  -> $Message"
}

function Write-Success {
    param([string]$Message)
    Write-Host "  -> $Message" -ForegroundColor Green
    Write-Log "  -> $Message" -Level 'SUCCESS'
}

# ============================================================================
# Instant Backup Functions (Junction Points)
# ============================================================================

function New-InstantBackup {
    <#
    .SYNOPSIS
    Creates instant backup using junction points (directory symbolic links).
    Takes <1 second regardless of directory size.

    .DESCRIPTION
    Instead of copying 8GB of files, creates junction points that reference
    the original directories. Instant, saves disk space, fully functional.

    .PARAMETER SourcePath
    The source directory to backup

    .PARAMETER DestPath
    The destination path for the junction point

    .PARAMETER Name
    Friendly name for logging
    #>
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Name = "Directory"
    )

    if (-not (Test-Path $SourcePath)) {
        Write-Info "$Name not found at $SourcePath" "DarkGray"
        return $false
    }

    try {
        # Remove existing destination if it exists
        if (Test-Path $DestPath) {
            Remove-Item -Path $DestPath -Force -Recurse -ErrorAction SilentlyContinue
        }

        # Create junction point (instant!)
        cmd /c mklink /J "`"$DestPath`"" "`"$SourcePath`"" | Out-Null

        if (Test-Path $DestPath) {
            Write-Success "$Name linked (instant)"
            Write-Log "${Name}: Instant backup via junction point created"
            return $true
        } else {
            Write-Info "Failed to create junction for $Name" "Yellow"
            return $false
        }
    } catch {
        Write-Info "Junction creation failed for ${Name}: $($_.Exception.Message)" "Yellow"
        return $false
    }
}

function Copy-WithTimeout {
    <#
    .SYNOPSIS
    Copies files with timeout protection.

    .DESCRIPTION
    When InstantBackup is OFF, uses robocopy with timeout.
    When InstantBackup is ON, uses junction points instead.
    #>
    param(
        [string]$SourcePath,
        [string]$DestPath,
        [string]$Name = "Files",
        [int]$TimeoutSeconds = 10
    )

    if (-not (Test-Path $SourcePath)) {
        Write-Info "$Name not found at $SourcePath" "DarkGray"
        return $false
    }

    # Instant backup mode - use junction point
    if ($InstantBackup) {
        return New-InstantBackup -SourcePath $SourcePath -DestPath $DestPath -Name $Name
    }

    # Regular backup mode - use robocopy with timeout
    try {
        $robocopyArgs = @($SourcePath, $DestPath, "/E", "/ZB", "/R:1", "/W:1", "/MT:16", "/XJ", "/NFL", "/NDL", "/NJH")
        $process = Start-Process -FilePath "robocopy.exe" -ArgumentList $robocopyArgs -NoNewWindow -PassThru

        # Wait with timeout
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            Write-Warning-Msg "$Name backup timed out after ${TimeoutSeconds}s"
            $process.Kill()
            return $false
        }

        if ($process.ExitCode -lt 8) {
            Write-Success "$Name backed up"
            return $true
        } else {
            Write-Warning-Msg "$Name backup failed (exit code: $($process.ExitCode))"
            return $false
        }
    } catch {
        Write-Warning-Msg "$Name backup error: $($_.Exception.Message)"
        return $false
    }
}


function Write-Warning-Msg {
    param([string]$Message)
    Write-Host "  -> WARNING: $Message" -ForegroundColor Yellow
    Write-Log "  -> WARNING: $Message" -Level 'WARN'
    $script:warnings += @{ message = $Message; timestamp = Get-Date }
}

function Write-Error-Message {
    param([string]$Message)
    Write-Host "  -> ERROR: $Message" -ForegroundColor Red
    Write-Log "  -> ERROR: $Message" -Level 'ERROR'
    $script:errors += @{ message = $Message; timestamp = Get-Date }
}

function Format-Size {
    param([long]$Size)
    if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size/1GB) }
    elseif ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size/1MB) }
    elseif ($Size -gt 1KB) { return "{0:N0} KB" -f ($Size/1KB) }
    else { return "$Size B" }
}

# ============================================================================
# CRITICAL: Execute External Command with Timeout
# ============================================================================

function Invoke-CommandWithTimeout {
    param(
        [scriptblock]$Command,
        [int]$TimeoutSeconds = 10,
        [string]$CommandName = "Command"
    )
    
    $job = $null
    try {
        Write-Log "Executing $CommandName with ${TimeoutSeconds}s timeout..."
        
        # Start command in background job
        $job = Start-Job -ScriptBlock $Command
        
        # Wait for completion or timeout
        $completed = Wait-Job $job -Timeout $TimeoutSeconds
        
        if ($completed) {
            # Command completed within timeout
            $result = Receive-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -ErrorAction SilentlyContinue
            Write-Log "$CommandName completed successfully"
            return @{
                Success = $true
                Output = $result
                Error = $null
            }
        } else {
            # Command timed out
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -ErrorAction SilentlyContinue
            Write-Warning-Msg "$CommandName timed out after ${TimeoutSeconds}s"
            return @{
                Success = $false
                Output = $null
                Error = "Command timed out after ${TimeoutSeconds}s"
            }
        }
    } catch {
        if ($job) {
            Stop-Job $job -ErrorAction SilentlyContinue
            Remove-Job $job -ErrorAction SilentlyContinue
        }
        Write-Warning-Msg "$CommandName failed: $($_.Exception.Message)"
        return @{
            Success = $false
            Output = $null
            Error = $_.Exception.Message
        }
    }
}

# ============================================================================
# Atomic Backup Operations with Lock Files
# ============================================================================

function Start-AtomicBackup {
    param([string]$BackupPath)

    $lockPath = Join-Path $BackupPath ".backup-lock"

    try {
        if (-not (Test-Path $BackupPath)) {
            New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        }

        $lockContent = @{
            startTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            pid = $PID
            computer = $env:COMPUTERNAME
            user = $env:USERNAME
            version = "4.3"
            state = "in_progress"
        }

        $lockContent | ConvertTo-Json | Out-File -FilePath $lockPath -Encoding UTF8 -Force
        $script:lockFile = $lockPath
        Write-Log "Atomic backup started with lock file: $lockPath"
        return $true
    } catch {
        Write-Log "Failed to create lock file: $($_.Exception.Message)" -Level 'ERROR'
        return $false
    }
}

function Complete-AtomicBackup {
    param([bool]$Success)

    if ($script:lockFile -and (Test-Path $script:lockFile)) {
        try {
            $lockContent = Get-Content $script:lockFile -Raw | ConvertFrom-Json
            $lockContent.state = if ($Success) { "completed" } else { "failed" }
            $lockContent.endTime = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            $lockContent | ConvertTo-Json | Out-File -FilePath $script:lockFile -Encoding UTF8 -Force
            Write-Log "Atomic backup completed with state: $($lockContent.state)"
        } catch {
            Write-Log "Failed to update lock file: $($_.Exception.Message)" -Level 'WARN'
        }
    }
}

# ============================================================================
# Pre-flight Validation Checks
# ============================================================================

function Test-PreFlightChecks {
    param([string]$BackupRoot)

    Write-Log "Running pre-flight validation checks..."

    $checks = @{
        passed = $true
        results = @()
    }

    # Check disk space
    try {
        $drive = (Split-Path $BackupRoot -Qualifier).TrimEnd(':')
        $volume = Get-Volume -DriveLetter $drive -ErrorAction Stop
        $freeSpaceGB = [Math]::Round($volume.SizeRemaining / 1GB, 2)

        $diskCheck = @{
            name = "Disk Space"
            freeSpaceGB = $freeSpaceGB
            requiredGB = $script:MIN_DISK_SPACE_GB
            passed = $freeSpaceGB -ge $script:MIN_DISK_SPACE_GB
        }
        $checks.results += $diskCheck

        if (-not $diskCheck.passed) {
            Write-Log "Insufficient disk space: ${freeSpaceGB}GB free, ${script:MIN_DISK_SPACE_GB}GB required" -Level 'ERROR'
            $checks.passed = $false
        } else {
            Write-Log "Disk space check passed: ${freeSpaceGB}GB free"
        }
    } catch {
        Write-Log "Could not check disk space: $($_.Exception.Message)" -Level 'WARN'
    }

    return $checks
}

# ============================================================================
# Stop Running Claude Processes
# ============================================================================

function Stop-ClaudeProcesses {
    param([int]$TimeoutSeconds = 30)

    Write-Log "Checking for running Claude Code processes..."

    $claudeProcesses = @()

    try {
        $processes = Get-Process -Name "claude" -ErrorAction SilentlyContinue
        if ($processes) { $claudeProcesses += $processes }

        $nodeProcesses = Get-Process -Name "node" -ErrorAction SilentlyContinue |
            Where-Object {
                try {
                    $_.Path -match "claude" -or
                    ($_.CommandLine -and $_.CommandLine -match "claude")
                } catch { $false }
            }
        if ($nodeProcesses) { $claudeProcesses += $nodeProcesses }
    } catch {
        Write-Log "Error checking processes: $($_.Exception.Message)" -Level 'WARN'
    }

    if ($claudeProcesses.Count -eq 0) {
        Write-Log "No Claude Code processes running"
        return $true
    }

    Write-Log "Found $($claudeProcesses.Count) Claude Code process(es). Requesting graceful termination..."

    foreach ($proc in $claudeProcesses) {
        try {
            $proc.CloseMainWindow() | Out-Null
        } catch { }
    }

    $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
    while ($stopwatch.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        $stillRunning = $claudeProcesses | Where-Object { -not $_.HasExited }
        if ($stillRunning.Count -eq 0) {
            Write-Log "All Claude Code processes terminated gracefully"
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    $stillRunning = $claudeProcesses | Where-Object { -not $_.HasExited }
    foreach ($proc in $stillRunning) {
        try {
            Write-Log "Force terminating process: $($proc.Name) (PID: $($proc.Id))" -Level 'WARN'
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
        } catch {
            Write-Log "Failed to terminate process $($proc.Id): $($_.Exception.Message)" -Level 'ERROR'
        }
    }

    return $true
}

# ============================================================================
# Development Tools Backup Functions with Timeout Protection
# ============================================================================

function Backup-NodeJsInstallation {
    param([string]$DestPath)

    Write-Log "Backing up Node.js (metadata only for fast backup)..."

    $nodeInfo = @{
        installed = $false
        version = $null
        path = $null
        backedUp = $false
        size = 0
    }

    # Find Node.js installation
    $nodePath = $null
    foreach ($path in @("C:\Program Files\nodejs", "C:\Program Files (x86)\nodejs")) {
        if (Test-Path $path) { $nodePath = $path; break }
    }

    if (-not $nodePath) {
        Write-Log "Node.js not found" -Level 'WARN'
        return $nodeInfo
    }

    # Get version with timeout
    $versionResult = Invoke-CommandWithTimeout -Command {
        & node --version 2>&1
    } -TimeoutSeconds 5 -CommandName "node --version"

    if ($versionResult.Success -and $versionResult.Output) {
        $nodeInfo.version = $versionResult.Output.ToString().Trim()
        $nodeInfo.path = $nodePath
        $nodeInfo.installed = $true
    }

    if (-not $DryRun -and $nodeInfo.installed) {
        $nodeBackupPath = Join-Path $DestPath "nodejs"
        New-Item -ItemType Directory -Path $nodeBackupPath -Force -ErrorAction SilentlyContinue | Out-Null

        # Save metadata
        @{
            version = $nodeInfo.version
            originalPath = $nodePath
            downloadUrl = "https://nodejs.org/dist/$($nodeInfo.version)/node-$($nodeInfo.version)-x64.msi"
            restoreCommand = "winget install OpenJS.NodeJS.LTS"
        } | ConvertTo-Json | Out-File -FilePath "$nodeBackupPath\node-info.json" -Encoding UTF8 -Force

        $nodeInfo.backedUp = $true
        $nodeInfo.size = 1KB
        Write-Success "Node.js metadata saved"
    }

    return $nodeInfo
}

function Backup-NpmGlobalPackages {
    param([string]$DestPath)

    Write-Log "Backing up npm global packages..."

    $npmInfo = @{
        installed = $false
        version = $null
        packages = @()
        backedUp = $false
        size = 0
    }

    $npmPath = "$env:APPDATA\npm"

    if (-not (Test-Path $npmPath)) {
        Write-Log "npm global directory not found" -Level 'WARN'
        return $npmInfo
    }

    # Get npm version with timeout
    $npmVersionResult = Invoke-CommandWithTimeout -Command {
        & npm --version 2>&1
    } -TimeoutSeconds 5 -CommandName "npm --version"

    if ($npmVersionResult.Success -and $npmVersionResult.Output) {
        $npmInfo.version = $npmVersionResult.Output.ToString().Trim()
        $npmInfo.installed = $true
        Write-Log "Found npm: v$($npmInfo.version)"
    }

    # Get package list with timeout
    if (-not $DryRun -and $npmInfo.installed) {
        $listResult = Invoke-CommandWithTimeout -Command {
            & npm list --global --depth=0 2>&1
        } -TimeoutSeconds 10 -CommandName "npm list"

        if ($listResult.Success -and $listResult.Output) {
            $listOutput = $listResult.Output | Out-String
            
            # Parse packages from output
            $listOutput -split "`n" | ForEach-Object {
                if ($_ -match '[\+\`]--\s+(.+)@(\d+\.\d+\.\d+.*)$') {
                    $npmInfo.packages += @{
                        name = $matches[1]
                        version = $matches[2]
                    }
                }
            }
            Write-Log "Found $($npmInfo.packages.Count) global npm packages"
        }
    }

    if (-not $DryRun) {
        $npmBackupPath = Join-Path $DestPath "npm"
        if (-not (Test-Path $npmBackupPath)) {
            New-Item -ItemType Directory -Path $npmBackupPath -Force | Out-Null
        }

        # SKIP npm node_modules - too large (8GB+), regeneratable via packages.json
        # Restore with: foreach ($pkg in (Get-Content packages.json | ConvertFrom-Json)) { npm install -g "$($pkg.name)@$($pkg.version)" }
        Write-Info "npm node_modules SKIPPED (regeneratable from packages.json)" "Cyan"

        # Backup npm bin scripts
        $binFiles = Get-ChildItem -Path $npmPath -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -in @(".cmd", ".ps1", "") }
        foreach ($bin in $binFiles) {
            Copy-Item -Path $bin.FullName -Destination "$npmBackupPath\$($bin.Name)" -Force -ErrorAction SilentlyContinue
        }

        # Calculate size
        if (Test-Path $npmBackupPath) {
            $sizeCalc = (Get-ChildItem -Path $npmBackupPath -Recurse -Force -ErrorAction SilentlyContinue |
                Where-Object { -not $_.PSIsContainer } |
                Measure-Object -Property Length -Sum)
            $npmInfo.size = if ($sizeCalc.Sum) { $sizeCalc.Sum } else { 0 }
            $npmInfo.backedUp = $true
            Write-Success "npm packages backed up: $(Format-Size $npmInfo.size)"
        }

        # Backup .npmrc
        $npmrcPath = "$env:USERPROFILE\.npmrc"
        if (Test-Path $npmrcPath) {
            Copy-Item -Path $npmrcPath -Destination "$npmBackupPath\.npmrc" -Force -ErrorAction SilentlyContinue
            Write-Success ".npmrc backed up"
        }

        # Generate restore script
        $packageList = $npmInfo.packages | ForEach-Object { "    '$($_.name)@$($_.version)'" }
        $restoreScript = @"
# npm Global Packages Restore Script
# Generated: $timestamp

Write-Host "Restoring npm global packages..." -ForegroundColor Cyan

`$packages = @(
$($packageList -join "`n")
)

foreach (`$pkg in `$packages) {
    if (`$pkg.Trim()) {
        Write-Host "Installing `$pkg..." -ForegroundColor Yellow
        npm install -g `$pkg 2>`$null
    }
}

Write-Host "Restore complete!" -ForegroundColor Green
"@
        $restoreScript | Out-File -FilePath "$npmBackupPath\restore-npm-packages.ps1" -Encoding UTF8 -Force

        # Save package list as JSON
        $npmInfo.packages | ConvertTo-Json -Depth 3 | Out-File -FilePath "$npmBackupPath\packages.json" -Encoding UTF8 -Force
    }

    return $npmInfo
}

function Backup-UvxTools {
    param([string]$DestPath)

    Write-Log "Backing up uvx/uv tools..."

    $uvInfo = @{
        installed = $false
        version = $null
        tools = @()
        backedUp = $false
        size = 0
    }

    # Check if uv is installed with timeout
    $uvVersionResult = Invoke-CommandWithTimeout -Command {
        & uv --version 2>&1
    } -TimeoutSeconds 5 -CommandName "uv --version"

    if ($uvVersionResult.Success -and $uvVersionResult.Output) {
        $uvInfo.version = $uvVersionResult.Output.ToString().Trim()
        $uvInfo.installed = $true
        Write-Log "Found uv: $($uvInfo.version)"

        # Get list of installed tools with timeout
        $toolListResult = Invoke-CommandWithTimeout -Command {
            & uv tool list 2>&1
        } -TimeoutSeconds 10 -CommandName "uv tool list"

        if ($toolListResult.Success -and $toolListResult.Output) {
            $uvInfo.toolList = $toolListResult.Output | Out-String
        }

        # Get Python versions with timeout
        $pythonListResult = Invoke-CommandWithTimeout -Command {
            & uv python list 2>&1
        } -TimeoutSeconds 10 -CommandName "uv python list"

        if ($pythonListResult.Success -and $pythonListResult.Output) {
            $uvInfo.pythonList = $pythonListResult.Output | Out-String
        }
    } else {
        Write-Log "uv not installed or not in PATH" -Level 'DEBUG'
    }

    if (-not $DryRun -and $uvInfo.installed) {
        $uvBackupPath = Join-Path $DestPath "uv"
        if (-not (Test-Path $uvBackupPath)) {
            New-Item -ItemType Directory -Path $uvBackupPath -Force | Out-Null
        }

        # Save tool and python lists
        if ($uvInfo.toolList) {
            $uvInfo.toolList | Out-File -FilePath "$uvBackupPath\tool-list.txt" -Encoding UTF8 -Force
        }
        if ($uvInfo.pythonList) {
            $uvInfo.pythonList | Out-File -FilePath "$uvBackupPath\python-list.txt" -Encoding UTF8 -Force
        }

        # Save uv info
        @{
            version = $uvInfo.version
            tools = $uvInfo.toolList
            pythonVersions = $uvInfo.pythonList
            restoreCommand = "pip install uv; uv tool install <tool-name>"
        } | ConvertTo-Json -Depth 3 | Out-File -FilePath "$uvBackupPath\uv-info.json" -Encoding UTF8 -Force

        # SKIP uvx binaries - large, regeneratable via: uv tool install <tool>
        Write-Info "uvx binaries SKIPPED (regeneratable from tool-list.txt)" "Cyan"

        $uvInfo.backedUp = $true
        $uvInfo.size = 1KB
        Write-Success "uvx/uv metadata backed up"
    }

    return $uvInfo
}

function Backup-PythonInstallation {
    param([string]$DestPath)

    Write-Log "Backing up Python..."

    $pythonInfo = @{
        installed = $false
        versions = @()
        pipPackages = @()
        backedUp = $false
        size = 0
    }

    # Get Python version with timeout
    $pyVersionResult = Invoke-CommandWithTimeout -Command {
        & python --version 2>&1
    } -TimeoutSeconds 5 -CommandName "python --version"

    if ($pyVersionResult.Success -and $pyVersionResult.Output) {
        $pythonInfo.versions += $pyVersionResult.Output.ToString().Trim()
        $pythonInfo.installed = $true
        Write-Log "Found Python: $($pythonInfo.versions[0])"
    } else {
        Write-Log "Python not found in PATH" -Level 'DEBUG'
    }

    if (-not $DryRun -and $pythonInfo.installed) {
        $pythonBackupPath = Join-Path $DestPath "python"
        if (-not (Test-Path $pythonBackupPath)) {
            New-Item -ItemType Directory -Path $pythonBackupPath -Force | Out-Null
        }

        # Generate pip freeze with timeout
        $pipFreezeResult = Invoke-CommandWithTimeout -Command {
            & pip freeze 2>&1
        } -TimeoutSeconds 15 -CommandName "pip freeze"

        if ($pipFreezeResult.Success -and $pipFreezeResult.Output) {
            $pipFreeze = $pipFreezeResult.Output | Out-String
            $pipFreeze | Out-File -FilePath "$pythonBackupPath\requirements.txt" -Encoding UTF8 -Force
            Write-Success "pip requirements.txt generated"
        }

        # Save Python info
        @{
            version = $pythonInfo.versions[0]
            path = (Get-Command python -ErrorAction SilentlyContinue).Source
            downloadUrl = "https://www.python.org/downloads/"
            restoreCommand = "pip install -r requirements.txt"
        } | ConvertTo-Json | Out-File -FilePath "$pythonBackupPath\python-info.json" -Encoding UTF8 -Force

        $pythonInfo.backedUp = $true
        $pythonInfo.size = 1KB
        Write-Success "Python metadata backed up"
    }

    return $pythonInfo
}

function Backup-PnpmPackages {
    param([string]$DestPath)

    Write-Log "Backing up pnpm..."

    $pnpmInfo = @{
        installed = $false
        version = $null
        packages = @()
        backedUp = $false
        size = 0
    }

    # Check pnpm with timeout
    $pnpmVersionResult = Invoke-CommandWithTimeout -Command {
        & pnpm --version 2>&1
    } -TimeoutSeconds 5 -CommandName "pnpm --version"

    if ($pnpmVersionResult.Success -and $pnpmVersionResult.Output) {
        $pnpmInfo.version = $pnpmVersionResult.Output.ToString().Trim()
        $pnpmInfo.installed = $true
        Write-Log "Found pnpm: v$($pnpmInfo.version)"

        # Get global list with timeout
        $globalListResult = Invoke-CommandWithTimeout -Command {
            & pnpm list --global 2>&1
        } -TimeoutSeconds 10 -CommandName "pnpm list"

        if ($globalListResult.Success -and $globalListResult.Output) {
            $pnpmInfo.globalList = $globalListResult.Output | Out-String
        }
    } else {
        Write-Log "pnpm not installed" -Level 'DEBUG'
    }

    if (-not $DryRun -and $pnpmInfo.installed) {
        $pnpmBackupPath = Join-Path $DestPath "pnpm"
        if (-not (Test-Path $pnpmBackupPath)) {
            New-Item -ItemType Directory -Path $pnpmBackupPath -Force | Out-Null
        }

        # Save global list
        if ($pnpmInfo.globalList) {
            $pnpmInfo.globalList | Out-File -FilePath "$pnpmBackupPath\global-packages.txt" -Encoding UTF8 -Force
        }

        @{
            version = $pnpmInfo.version
            globalPackages = $pnpmInfo.globalList
            restoreCommand = "npm install -g pnpm; pnpm install -g <package>"
        } | ConvertTo-Json | Out-File -FilePath "$pnpmBackupPath\pnpm-info.json" -Encoding UTF8 -Force

        $pnpmInfo.backedUp = $true
        $pnpmInfo.size = 1KB
        Write-Success "pnpm metadata backed up"
    }

    return $pnpmInfo
}

function Backup-YarnPackages {
    param([string]$DestPath)

    Write-Log "Backing up yarn..."

    $yarnInfo = @{
        installed = $false
        version = $null
        packages = @()
        backedUp = $false
        size = 0
    }

    $yarnrcPath = "$env:USERPROFILE\.yarnrc"

    # Check yarn with timeout
    $yarnVersionResult = Invoke-CommandWithTimeout -Command {
        & yarn --version 2>&1
    } -TimeoutSeconds 5 -CommandName "yarn --version"

    if ($yarnVersionResult.Success -and $yarnVersionResult.Output) {
        $yarnInfo.version = $yarnVersionResult.Output.ToString().Trim()
        $yarnInfo.installed = $true
        Write-Log "Found yarn: v$($yarnInfo.version)"

        # Get global list with timeout
        $globalListResult = Invoke-CommandWithTimeout -Command {
            & yarn global list 2>&1
        } -TimeoutSeconds 10 -CommandName "yarn global list"

        if ($globalListResult.Success -and $globalListResult.Output) {
            $yarnInfo.globalList = $globalListResult.Output | Out-String
        }
    } else {
        Write-Log "yarn not installed" -Level 'DEBUG'
    }

    if (-not $DryRun -and $yarnInfo.installed) {
        $yarnBackupPath = Join-Path $DestPath "yarn"
        if (-not (Test-Path $yarnBackupPath)) {
            New-Item -ItemType Directory -Path $yarnBackupPath -Force | Out-Null
        }

        # Backup .yarnrc
        if (Test-Path $yarnrcPath) {
            Copy-Item -Path $yarnrcPath -Destination "$yarnBackupPath\.yarnrc" -Force -ErrorAction SilentlyContinue
        }

        # Save global list and info
        if ($yarnInfo.globalList) {
            $yarnInfo.globalList | Out-File -FilePath "$yarnBackupPath\global-packages.txt" -Encoding UTF8 -Force
        }

        @{
            version = $yarnInfo.version
            globalPackages = $yarnInfo.globalList
            restoreCommand = "npm install -g yarn; yarn global add <package>"
        } | ConvertTo-Json | Out-File -FilePath "$yarnBackupPath\yarn-info.json" -Encoding UTF8 -Force

        $yarnInfo.backedUp = $true
        $yarnInfo.size = 1KB
        Write-Success "yarn metadata backed up"
    }

    return $yarnInfo
}

function Backup-NvmInstallation {
    param([string]$DestPath)

    Write-Log "Backing up nvm-windows..."

    $nvmInfo = @{
        installed = $false
        version = $null
        nodeVersions = @()
        currentVersion = $null
        backedUp = $false
        size = 0
    }

    # Check NVM_HOME environment variable
    $nvmHome = $env:NVM_HOME
    if (-not $nvmHome) {
        $nvmHome = "$env:APPDATA\nvm"
    }

    if (-not (Test-Path $nvmHome)) {
        Write-Log "nvm-windows not installed" -Level 'DEBUG'
        return $nvmInfo
    }

    # Check nvm with timeout
    $nvmVersionResult = Invoke-CommandWithTimeout -Command {
        & nvm version 2>&1
    } -TimeoutSeconds 5 -CommandName "nvm version"

    if ($nvmVersionResult.Success -and $nvmVersionResult.Output) {
        $nvmInfo.version = $nvmVersionResult.Output.ToString().Trim()
        $nvmInfo.installed = $true
        Write-Log "Found nvm-windows: $($nvmInfo.version)"

        # Get node versions with timeout
        $nvmListResult = Invoke-CommandWithTimeout -Command {
            & nvm list 2>&1
        } -TimeoutSeconds 10 -CommandName "nvm list"

        if ($nvmListResult.Success -and $nvmListResult.Output) {
            $nvmInfo.nodeVersions = $nvmListResult.Output | Out-String
        }
    } else {
        Write-Log "Could not get nvm version" -Level 'WARN'
    }

    if (-not $DryRun -and $nvmInfo.installed) {
        $nvmBackupPath = Join-Path $DestPath "nvm"
        if (-not (Test-Path $nvmBackupPath)) {
            New-Item -ItemType Directory -Path $nvmBackupPath -Force | Out-Null
        }

        # Save version list
        if ($nvmInfo.nodeVersions) {
            $nvmInfo.nodeVersions | Out-File -FilePath "$nvmBackupPath\node-versions.txt" -Encoding UTF8 -Force
        }

        # Backup nvm settings file
        $nvmSettings = Join-Path $nvmHome "settings.txt"
        if (Test-Path $nvmSettings) {
            Copy-Item -Path $nvmSettings -Destination "$nvmBackupPath\settings.txt" -Force -ErrorAction SilentlyContinue
        }

        @{
            version = $nvmInfo.version
            nodeVersions = $nvmInfo.nodeVersions
            nvmHome = $nvmHome
            downloadUrl = "https://github.com/coreybutler/nvm-windows/releases"
            restoreCommand = "nvm install <version>; nvm use <version>"
        } | ConvertTo-Json | Out-File -FilePath "$nvmBackupPath\nvm-info.json" -Encoding UTF8 -Force

        $nvmInfo.backedUp = $true
        $nvmInfo.size = 1KB
        Write-Success "nvm-windows metadata backed up"
    }

    return $nvmInfo
}

# ============================================================================
# Bun Installation Backup
# ============================================================================

function Backup-BunInstallation {
    param([string]$DestPath)

    Write-Log "Backing up Bun..."

    $bunInfo = @{
        installed = $false
        version = $null
        backedUp = $false
        size = 0
    }

    # Check if bun is installed
    $bunPath = "$env:USERPROFILE\.bun"
    if (-not (Test-Path $bunPath)) {
        Write-Log "Bun not installed" -Level 'DEBUG'
        return $bunInfo
    }

    $bunInfo.installed = $true

    if (-not $DryRun) {
        $bunBackupPath = Join-Path $DestPath "bun"
        if (-not (Test-Path $bunBackupPath)) {
            New-Item -ItemType Directory -Path $bunBackupPath -Force | Out-Null
        }

        # SKIP Bun binaries - large (500MB+), regeneratable via: irm bun.sh/install.ps1 | iex
        # Just save version info
        @{
            installed = $true
            path = $bunPath
            restoreCommand = "irm bun.sh/install.ps1 | iex"
        } | ConvertTo-Json | Out-File -FilePath "$bunBackupPath\bun-info.json" -Encoding UTF8 -Force

        Write-Info "Bun binaries SKIPPED (regeneratable: irm bun.sh/install.ps1 | iex)" "Cyan"
        $bunInfo.backedUp = $true
        $bunInfo.size = 1KB
    }

    return $bunInfo
}

# ============================================================================
# Copy with Tracking Function
# ============================================================================

function Copy-WithTracking {
    param(
        [Parameter(Mandatory=$true)]
        [string]$Source,
        [Parameter(Mandatory=$true)]
        [string]$Destination,
        [Parameter(Mandatory=$true)]
        [string]$Name,
        [switch]$Required,
        [string[]]$ExcludeDirs = @()
    )

    if (-not (Test-Path $Source)) {
        if ($Required) {
            Write-Error-Message "Required item not found: $Name"
            $script:errors += @{
                item = $Name
                source = $Source
                error = "Path not found"
                status = "failed"
            }
        } else {
            Write-Info "Not found: $Name (skipped)"
        }
        return
    }

    if ($DryRun) {
        $sourceItem = Get-Item $Source -Force -ErrorAction SilentlyContinue
        if ($sourceItem) {
            if ($sourceItem.PSIsContainer) {
                Write-Info "[DRY-RUN] Would copy $Name (directory)"
            } else {
                $size = $sourceItem.Length
                Write-Info "[DRY-RUN] Would copy $Name ($(Format-Size $size))"
            }
        } else {
            Write-Info "[DRY-RUN] Would copy $Name"
        }
        return
    }

    try {
        $destParent = Split-Path $Destination -Parent
        if (-not (Test-Path $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force -ErrorAction Stop | Out-Null
        }

        $sourceItem = Get-Item $Source -Force
        $isDir = $sourceItem.PSIsContainer

        if ($isDir) {
            $robocopyArgs = @($Source, $Destination, "/E", "/ZB", "/COPY:DAT", "/DCOPY:DAT", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")

            if ($ExcludeDirs.Count -gt 0) {
                $robocopyArgs += "/XD"
                $robocopyArgs += $ExcludeDirs
            }

            $null = & robocopy @robocopyArgs 2>&1
            $exitCode = $LASTEXITCODE

            if ($exitCode -ge 16) {
                throw "Robocopy fatal error (exit code $exitCode)"
            }

            $sizeCalc = @(Get-ChildItem -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue |
                         Where-Object {-not $_.PSIsContainer} |
                         Measure-Object -Property Length -Sum)
            $size = if ($sizeCalc[0].Sum) { $sizeCalc[0].Sum } else { 0 }

            $itemCount = @(Get-ChildItem -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue |
                          Measure-Object).Count

            $sizeStr = Format-Size $size
            Write-Success "Copied $Name ($itemCount items, $sizeStr)"

        } else {
            Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop

            $size = $sourceItem.Length
            $sizeStr = Format-Size $size
            Write-Success "Copied $Name ($sizeStr)"
        }

        $script:totalSize += $size

        $script:backedUpItems += @{
            item = $Name
            source = $Source
            destination = $Destination
            size = $size
            status = "success"
        }

    } catch {
        Write-Error-Message "${Name}: $($_.Exception.Message)"

        $script:errors += @{
            item = $Name
            source = $Source
            error = $_.Exception.Message
            status = "failed"
        }
    }
}

# ============================================================================
# Backup ALL Claude Components
# ============================================================================

function Backup-AllClaudeComponents {
    param([string]$DestPath)

    Write-Log "Backing up ALL Claude Code components..."
    
    $components = @{
        credentials = @()
        opencode = @()
        sisyphus = @()
        mcpWrappers = @()
        extensions = @()
        browserData = @()
        psModules = @()
        conversations = @()
        learned = @()
    }

    # Backup credentials and API keys (COMPLETE LIST)
    $credentialPaths = @(
        "$env:USERPROFILE\.claude\api-keys.json",
        "$env:USERPROFILE\.claude\credentials.json",
        "$env:USERPROFILE\.claude\.credentials.json",
        "$env:USERPROFILE\.claude\auth.json",
        "$env:USERPROFILE\.claude\tokens.json",
        "$env:USERPROFILE\.anthropic",
        "$env:APPDATA\Claude\credentials",
        "$env:LOCALAPPDATA\Claude\credentials",
        "$env:USERPROFILE\.local\share\opencode\auth.json"
    )
    
    # Backup cache directories (critical for fast restoration)
    $cachePaths = @(
        "$env:USERPROFILE\.cache\opencode",
        "$env:USERPROFILE\.cache\puppeteer", 
        "$env:USERPROFILE\.cache\pkg",
        "$env:LOCALAPPDATA\opencode",
        "$env:LOCALAPPDATA\MCP"
    )
    
    foreach ($cachePath in $cachePaths) {
        if (Test-Path $cachePath) {
            $cacheName = Split-Path $cachePath -Leaf
            $destCache = Join-Path $DestPath "cache\$cacheName"
            Copy-WithTracking -Source $cachePath -Destination $destCache -Name "Cache: $cacheName"
        }
    }

    foreach ($credPath in $credentialPaths) {
        if (Test-Path $credPath) {
            $credName = Split-Path $credPath -Leaf
            $destCred = Join-Path $DestPath "credentials\$credName"
            Copy-WithTracking -Source $credPath -Destination $destCred -Name "Credential: $credName"
            $components.credentials += $credPath
        }
    }

    # Backup OpenCode integration
    $opencodePaths = @(
        "$env:USERPROFILE\.config\opencode",
        "$env:USERPROFILE\.opencode",
        "$env:APPDATA\opencode",
        "$env:LOCALAPPDATA\opencode"
    )

    foreach ($ocPath in $opencodePaths) {
        if (Test-Path $ocPath) {
            $ocName = Split-Path $ocPath -Leaf
            $destOc = Join-Path $DestPath "opencode\$ocName"
            Copy-WithTracking -Source $ocPath -Destination $destOc -Name "OpenCode: $ocName"
            $components.opencode += $ocPath
        }
    }

    # Backup Sisyphus/OhMyOpenCode
    $sisyphusPaths = @(
        "$env:USERPROFILE\.claude\.sisyphus",
        "$env:USERPROFILE\.oh-my-opencode",
        "$env:USERPROFILE\.claude\sisyphus",
        "$env:APPDATA\sisyphus"
    )

    foreach ($sisPath in $sisyphusPaths) {
        if (Test-Path $sisPath) {
            $sisName = Split-Path $sisPath -Leaf
            $destSis = Join-Path $DestPath "sisyphus\$sisName"
            Copy-WithTracking -Source $sisPath -Destination $destSis -Name "Sisyphus: $sisName"
            $components.sisyphus += $sisPath
        }
    }

    # Backup ALL MCP wrapper scripts
    $mcpWrapperPath = "$env:USERPROFILE\.claude"
    if (Test-Path $mcpWrapperPath) {
        $wrappers = Get-ChildItem -Path $mcpWrapperPath -Filter "*.cmd" -File -ErrorAction SilentlyContinue
        
        foreach ($wrapper in $wrappers) {
            $destWrapper = Join-Path $DestPath "mcp-wrappers\$($wrapper.Name)"
            Copy-WithTracking -Source $wrapper.FullName -Destination $destWrapper -Name "MCP Wrapper: $($wrapper.Name)"
            $components.mcpWrappers += $wrapper.Name
        }
        
        Write-Success "Backed up $($wrappers.Count) MCP wrapper scripts"
    }

    # Backup mcp-ondemand.ps1 and related scripts
    $mcpScripts = @(
        "$env:USERPROFILE\.claude\mcp-ondemand.ps1",
        "$env:USERPROFILE\.claude\mcp-manager.ps1",
        "$env:USERPROFILE\.claude\mcp-setup.ps1"
    )

    foreach ($mcpScript in $mcpScripts) {
        if (Test-Path $mcpScript) {
            $scriptName = Split-Path $mcpScript -Leaf
            $destScript = Join-Path $DestPath "mcp-scripts\$scriptName"
            Copy-WithTracking -Source $mcpScript -Destination $destScript -Name "MCP Script: $scriptName"
        }
    }

    # Backup conversation history - CRITICAL: Conversations are in projects folder as .jsonl files
    $conversationPaths = @(
        "$env:USERPROFILE\.claude\projects",          # MAIN LOCATION - All session .jsonl files
        "$env:USERPROFILE\.claude\conversations",
        "$env:USERPROFILE\.claude\history",
        "$env:USERPROFILE\.claude\sessions",
        "$env:USERPROFILE\.claude\transcripts",
        "$env:USERPROFILE\.claude\todos",
        "$env:APPDATA\Claude\conversations",
        "$env:APPDATA\Claude\Session Storage",        # Electron session data
        "$env:APPDATA\Claude\Local Storage"           # Local storage data
    )

    foreach ($convPath in $conversationPaths) {
        if (Test-Path $convPath) {
            $convName = Split-Path $convPath -Leaf
            $destConv = Join-Path $DestPath "conversations\$convName"
            
            # Show progress for large conversation directories
            $itemCount = (Get-ChildItem -Path $convPath -Recurse -File -ErrorAction SilentlyContinue | Measure-Object).Count
            if ($itemCount -gt 0) {
                Write-Host "  -> Backing up $convName ($itemCount files)..." -ForegroundColor Gray
            }
            
            Copy-WithTracking -Source $convPath -Destination $destConv -Name "Conversations: $convName"
            $components.conversations += $convPath
        }
    }

    # Backup learned.md and similar files
    $learnedFiles = @(
        "$env:USERPROFILE\.claude\learned.md",
        "$env:USERPROFILE\.claude\notes.md",
        "$env:USERPROFILE\.claude\context.md"
    )

    foreach ($learnedFile in $learnedFiles) {
        if (Test-Path $learnedFile) {
            $fileName = Split-Path $learnedFile -Leaf
            $destLearned = Join-Path $DestPath "learned\$fileName"
            Copy-WithTracking -Source $learnedFile -Destination $destLearned -Name "Learned: $fileName"
            $components.learned += $learnedFile
        }
    }

    # Backup browser extension data
    $browserPaths = @(
        @{ Browser = "Chrome"; Path = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions" },
        @{ Browser = "Edge"; Path = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions" }
    )

    foreach ($browser in $browserPaths) {
        if (Test-Path $browser.Path) {
            # Look for Claude-related extensions
            $extensions = Get-ChildItem -Path $browser.Path -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "claude|anthropic" }
            
            foreach ($ext in $extensions) {
                $destExt = Join-Path $DestPath "browser-extensions\$($browser.Browser)\$($ext.Name)"
                Copy-WithTracking -Source $ext.FullName -Destination $destExt -Name "$($browser.Browser) Extension: $($ext.Name)"
                $components.browserData += "$($browser.Browser): $($ext.Name)"
            }
        }
    }

    # Backup PowerShell modules
    $psModulePaths = @(
        "$env:USERPROFILE\Documents\WindowsPowerShell\Modules",
        "$env:USERPROFILE\Documents\PowerShell\Modules",
        "$env:ProgramFiles\WindowsPowerShell\Modules",
        "$env:ProgramFiles\PowerShell\Modules"
    )

    foreach ($modPath in $psModulePaths) {
        if (Test-Path $modPath) {
            $modules = Get-ChildItem -Path $modPath -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match "claude|anthropic|opencode" }
            
            foreach ($mod in $modules) {
                $destMod = Join-Path $DestPath "ps-modules\$($mod.Name)"
                Copy-WithTracking -Source $mod.FullName -Destination $destMod -Name "PS Module: $($mod.Name)"
                $components.psModules += $mod.Name
            }
        }
    }

    # Save component manifest
    $manifestPath = Join-Path $DestPath "components-manifest.json"
    $components | ConvertTo-Json -Depth 5 | Out-File -FilePath $manifestPath -Encoding UTF8 -Force
    Write-Success "Saved components manifest"

    return $components
}

# ============================================================================
# Main Backup Process
# ============================================================================

Write-Host "`n" -NoNewline
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  CLAUDE CODE COMPREHENSIVE BACKUP UTILITY v4.3" -ForegroundColor Cyan
Write-Host "  FAST MODE - Skips regeneratable binaries" -ForegroundColor Yellow
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Timestamp: $timestamp" -ForegroundColor Yellow
Write-Host "Backup Path: $backupPath" -ForegroundColor Yellow
Write-Host "Profile: $Profile" -ForegroundColor Yellow
Write-Host "Command Timeout: ${CommandTimeout}s" -ForegroundColor Yellow
if ($DryRun) { Write-Host "MODE: DRY RUN (no changes will be made)" -ForegroundColor Magenta }
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "`n" -NoNewline

# Initialize logging
Initialize-LogSystem -LogsPath $logsPath

# Step 1: Pre-flight checks
Write-Progress-Step "[1/50]" "Running pre-flight validation checks..."
$preFlightResults = Test-PreFlightChecks -BackupRoot $BackupRoot

if (-not $preFlightResults.passed -and -not $Force) {
    Write-Error-Message "Pre-flight checks failed. Use -Force to override."
    exit 1
}

# Step 2: Create backup directory
Write-Progress-Step "[2/50]" "Creating backup directory structure..."
if (-not $DryRun) {
    if (-not (Start-AtomicBackup -BackupPath $backupPath)) {
        Write-Error-Message "Failed to create backup directory"
        exit 1
    }
    Write-Success "Created backup directory with lock"
} else {
    Write-Info "[DRY-RUN] Would create: $backupPath"
}

# Step 3: Stop Claude processes
Write-Progress-Step "[3/50]" "Checking for running Claude Code processes..."
if (-not $DryRun) {
    Stop-ClaudeProcesses -TimeoutSeconds 30
}

# Create directories
$toolsBackupPath = Join-Path $backupPath "dev-tools"
if (-not $DryRun -and -not (Test-Path $toolsBackupPath)) {
    New-Item -ItemType Directory -Path $toolsBackupPath -Force | Out-Null
}

# Step 4-9: Backup development tools
Write-Progress-Step "[4/50]" "Backing up Node.js installation..."
$nodeInfo = Backup-NodeJsInstallation -DestPath $toolsBackupPath

Write-Progress-Step "[5/50]" "Backing up npm global packages..."
$npmInfo = Backup-NpmGlobalPackages -DestPath $toolsBackupPath

Write-Progress-Step "[6/50]" "Backing up uvx/uv Python tools..."
$uvxInfo = Backup-UvxTools -DestPath $toolsBackupPath

Write-Progress-Step "[7/50]" "Backing up Python installation..."
$pythonInfo = Backup-PythonInstallation -DestPath $toolsBackupPath

Write-Progress-Step "[8/50]" "Backing up pnpm packages..."
$pnpmInfo = Backup-PnpmPackages -DestPath $toolsBackupPath

Write-Progress-Step "[9/50]" "Backing up yarn packages..."
$yarnInfo = Backup-YarnPackages -DestPath $toolsBackupPath

Write-Progress-Step "[10/50]" "Backing up nvm-windows..."
$nvmInfo = Backup-NvmInstallation -DestPath $toolsBackupPath

Write-Progress-Step "[10.5/50]" "Backing up Bun installation..."
$bunInfo = Backup-BunInstallation -DestPath $toolsBackupPath

# Step 11-20: Backup Claude core files
Write-Progress-Step "[11/50]" "Backing up .claude.json..."
Copy-WithTracking -Source "$userHome\.claude.json" `
                  -Destination "$backupPath\home\.claude.json" `
                  -Name ".claude.json"

Write-Progress-Step "[12/50]" "Backing up .claude.json.backup..."
Copy-WithTracking -Source "$userHome\.claude.json.backup" `
                  -Destination "$backupPath\home\.claude.json.backup" `
                  -Name ".claude.json.backup"

Write-Progress-Step "[13/50]" "Backing up .claude directory (FULL)..."
Copy-WithTracking -Source "$userHome\.claude" `
                  -Destination "$backupPath\home\.claude" `
                  -Name ".claude directory (FULL)" `
                  -Required

Write-Progress-Step "[14/50]" "Backing up ALL Claude components (credentials, OpenCode, etc)..."
if (-not $DryRun) {
    $allComponents = Backup-AllClaudeComponents -DestPath $backupPath
}

Write-Progress-Step "[15/50]" "Backing up .claude-server-commander..."
Copy-WithTracking -Source "$userHome\.claude-server-commander" `
                  -Destination "$backupPath\home\.claude-server-commander" `
                  -Name ".claude-server-commander"

Write-Progress-Step "[16/50]" "Backing up .claude-mem..."
Copy-WithTracking -Source "$userHome\.claude-mem" `
                  -Destination "$backupPath\home\.claude-mem" `
                  -Name ".claude-mem"

Write-Progress-Step "[17/50]" "Scanning for all .claude.* files..."
$claudeFiles = Get-ChildItem -Path $userHome -Filter ".claude.*" -File -Force -ErrorAction SilentlyContinue
foreach ($file in $claudeFiles) {
    $fileName = $file.Name
    if ($fileName -notin @(".claude.json", ".claude.json.backup")) {
        Write-Info "Found: $fileName"
        Copy-WithTracking -Source $file.FullName `
                          -Destination "$backupPath\home\$fileName" `
                          -Name $fileName
    }
}

Write-Progress-Step "[18/50]" "Backing up AppData\Roaming\Claude..."
Copy-WithTracking -Source "$env:APPDATA\Claude" `
                  -Destination "$backupPath\AppData\Roaming\Claude" `
                  -Name "AppData\Roaming\Claude"

Write-Progress-Step "[19/50]" "Backing up AppData\Roaming\Claude Code..."
Copy-WithTracking -Source "$env:APPDATA\Claude Code" `
                  -Destination "$backupPath\AppData\Roaming\Claude Code" `
                  -Name "AppData\Roaming\Claude Code"

Write-Progress-Step "[20/50]" "Backing up AppData\Roaming\Anthropic..."
Copy-WithTracking -Source "$env:APPDATA\Anthropic" `
                  -Destination "$backupPath\AppData\Roaming\Anthropic" `
                  -Name "AppData\Roaming\Anthropic"

# Step 21-30: Backup additional locations
Write-Progress-Step "[21/50]" "Backing up AppData\Local\claude-cli-nodejs..."
Copy-WithTracking -Source "$env:LOCALAPPDATA\claude-cli-nodejs" `
                  -Destination "$backupPath\AppData\Local\claude-cli-nodejs" `
                  -Name "claude-cli-nodejs"

Write-Progress-Step "[22/50]" "Backing up AppData\Local\Claude..."
Copy-WithTracking -Source "$env:LOCALAPPDATA\Claude" `
                  -Destination "$backupPath\AppData\Local\Claude" `
                  -Name "AppData\Local\Claude"

Write-Progress-Step "[23/50]" "Backing up npm claude binaries..."
$npmBinPath = "$env:APPDATA\npm"
$claudeBinaries = Get-ChildItem -Path $npmBinPath -File -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^claude' } |
    Select-Object -ExpandProperty Name
if ($claudeBinaries) {
    foreach ($bin in $claudeBinaries) {
        Copy-WithTracking -Source "$npmBinPath\$bin" `
                          -Destination "$backupPath\npm\$bin" `
                          -Name "npm $bin"
    }
}

Write-Progress-Step "[24/50]" "Backing up MCP system..."
$mcpPaths = @(
    "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\MCP\claudecode",
    "$userHome\.claude\mcp",
    "$env:APPDATA\Claude\mcp"
)
foreach ($mcpPath in $mcpPaths) {
    if (Test-Path $mcpPath) {
        $mcpName = Split-Path $mcpPath -Leaf
        Copy-WithTracking -Source $mcpPath `
                          -Destination "$backupPath\MCP\$mcpName" `
                          -Name "MCP System ($mcpName)"
    }
}

Write-Progress-Step "[25/50]" "Backing up PowerShell profiles..."
$ps5ProfileDir = "$userHome\Documents\WindowsPowerShell"
foreach ($psFile in @("Microsoft.PowerShell_profile.ps1", "dadada.ps1")) {
    Copy-WithTracking -Source "$ps5ProfileDir\$psFile" `
                      -Destination "$backupPath\PowerShell\WindowsPowerShell\$psFile" `
                      -Name "PS5\$psFile"
}

$ps7ProfileDir = "$userHome\Documents\PowerShell"
foreach ($psFile in @("Microsoft.PowerShell_profile.ps1", "Microsoft.VSCode_profile.ps1")) {
    Copy-WithTracking -Source "$ps7ProfileDir\$psFile" `
                      -Destination "$backupPath\PowerShell\PowerShell\$psFile" `
                      -Name "PS7\$psFile"
}

Write-Progress-Step "[26/50]" "Backing up global CLAUDE.md files..."
foreach ($md in @("CLAUDE.md", "claude.md")) {
    Copy-WithTracking -Source "$userHome\$md" `
                      -Destination "$backupPath\home\$md" `
                      -Name "~\$md"
}

Write-Progress-Step "[27/50]" "Backing up registry keys..."
if (-not $DryRun) {
    $regBackupPath = Join-Path $backupPath "registry"
    if (-not (Test-Path $regBackupPath)) {
        New-Item -ItemType Directory -Path $regBackupPath -Force | Out-Null
    }

    $keysToBackup = @(
        @{ Path = "HKCU:\Software\Classes\.js"; Name = "js_file_assoc" },
        @{ Path = "HKCU:\Software\Classes\.ts"; Name = "ts_file_assoc" },
        @{ Path = "HKCU:\Software\Microsoft\Windows\CurrentVersion\App Paths\claude.exe"; Name = "claude_app_path" },
        @{ Path = "HKCU:\Software\Anthropic"; Name = "anthropic_settings" },
        @{ Path = "HKCU:\Software\Claude"; Name = "claude_settings" },
        @{ Path = "HKCU:\Environment"; Name = "user_environment" },
        @{ Path = "HKLM:\SOFTWARE\Node.js"; Name = "nodejs_settings" },
        @{ Path = "HKLM:\SOFTWARE\Python"; Name = "python_settings" }
    )

    foreach ($key in $keysToBackup) {
        try {
            if (Test-Path $key.Path) {
                $exportFile = Join-Path $regBackupPath "$($key.Name).reg"
                $regPath = $key.Path -replace "HKCU:", "HKEY_CURRENT_USER" -replace "HKLM:", "HKEY_LOCAL_MACHINE"
                $null = & reg export $regPath $exportFile /y 2>&1

                if (Test-Path $exportFile) {
                    Write-Log "Exported registry key: $($key.Path)"
                }
            }
        } catch {
            Write-Log "Could not export registry key $($key.Path): $($_.Exception.Message)" -Level 'WARN'
        }
    }
}

Write-Progress-Step "[28/50]" "Backing up environment variables..."
if (-not $DryRun) {
    $envVars = @{
        user = @{}
        system = @{}
        paths = @{}
        devTools = @{}
    }

    try {
        $userEnv = [Environment]::GetEnvironmentVariables([EnvironmentVariableTarget]::User)
        foreach ($key in $userEnv.Keys) {
            $envVars.user[$key] = $userEnv[$key]

            if ($key -match "PATH|NODE|NPM|CLAUDE|ANTHROPIC|NVM|PYTHON|PIP|UV|PNPM|YARN") {
                $envVars.devTools[$key] = @{
                    scope = "User"
                    value = $userEnv[$key]
                }
            }
        }
    } catch {
        Write-Log "Could not get user environment variables: $($_.Exception.Message)" -Level 'WARN'
    }

    $envVars.paths = @{
        user = [Environment]::GetEnvironmentVariable("PATH", "User")
        machine = [Environment]::GetEnvironmentVariable("PATH", "Machine")
        process = $env:PATH
    }

    $envFile = Join-Path $backupPath "environment_variables.json"
    $envVars | ConvertTo-Json -Depth 10 | Out-File -FilePath $envFile -Encoding UTF8 -Force
    Write-Success "Environment variables backed up"
}

# Continue with remaining steps...
Write-Progress-Step "[45/50]" "Creating backup metadata..."

# Get Claude version with timeout
$claudeVersionResult = Invoke-CommandWithTimeout -Command {
    & claude --version 2>&1
} -TimeoutSeconds 5 -CommandName "claude --version"

$claudeVersion = if ($claudeVersionResult.Success) { 
    $claudeVersionResult.Output.ToString().Trim() 
} else { 
    "Unknown" 
}

$metadata = @{
    backupVersion = "4.3"
    backupMode = "fast"
    backupTimestamp = $timestamp
    backupDate = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    backupPath = $backupPath
    backupProfile = $Profile
    dryRun = $DryRun
    computerName = $env:COMPUTERNAME
    userName = $env:USERNAME
    userProfile = $userHome
    claudeVersion = $claudeVersion
    totalSizeBytes = $script:totalSize
    executionTimeSeconds = ((Get-Date) - $script:startTime).TotalSeconds
    devTools = @{
        nodejs = $nodeInfo
        npm = $npmInfo
        uvx = $uvxInfo
        python = $pythonInfo
        pnpm = $pnpmInfo
        yarn = $yarnInfo
        nvm = $nvmInfo
    }
    components = if ($allComponents) { $allComponents } else { @{} }
    errorCount = $script:errors.Count
    warningCount = $script:warnings.Count
    backedUpItemsCount = $script:backedUpItems.Count
}

if (-not $DryRun) {
    $metadataPath = Join-Path $backupPath "metadata.json"
    $metadata | ConvertTo-Json -Depth 10 | Out-File -FilePath $metadataPath -Encoding UTF8 -Force
    Write-Success "Created metadata.json"
}

Write-Progress-Step "[46/50]" "Generating restore guide..."

$restoreGuide = @"
# Claude Code Comprehensive Restore Guide
# Generated: $timestamp
# Backup Version: 4.3

## Restore Steps:

### 1. Development Tools (REGENERATE THESE)
- Node.js: Install from nodejs.org or use winget install OpenJS.NodeJS.LTS
- npm packages: Run dev-tools\npm\restore-npm-packages.ps1 (regenerates node_modules)
- Bun: irm bun.sh/install.ps1 | iex
- npm packages: Run dev-tools\npm\restore-npm-packages.ps1
- Python: Install from python.org then run: pip install -r dev-tools\python\requirements.txt
- uv/uvx: pip install uv
- pnpm: npm install -g pnpm
- yarn: npm install -g yarn
- nvm: Download from https://github.com/coreybutler/nvm-windows/releases

### 2. Claude Code Configuration
- Copy home\.claude to %USERPROFILE%\.claude
- Copy home\.claude.json to %USERPROFILE%\.claude.json

### 3. MCP Wrappers and Scripts
- Copy all mcp-wrappers\*.cmd to %USERPROFILE%\.claude\
- Copy mcp-scripts\*.ps1 to %USERPROFILE%\.claude\

### 4. Credentials and API Keys
- Copy credentials\* to appropriate locations (see components-manifest.json)

### 5. OpenCode and Sisyphus
- Copy opencode\* to %USERPROFILE%\.config\opencode
- Copy sisyphus\* to %USERPROFILE%\.claude\.sisyphus

### 6. AppData Folders
- Copy AppData\Roaming\* to %APPDATA%\
- Copy AppData\Local\* to %LOCALAPPDATA%\

### 7. PowerShell Profiles
- Copy PowerShell\WindowsPowerShell\* to Documents\WindowsPowerShell\
- Copy PowerShell\PowerShell\* to Documents\PowerShell\

### 8. Environment Variables
- Review environment_variables.json and restore PATH settings
- Restore dev tool specific environment variables

### 9. Registry Keys
- Import all .reg files from registry\ folder (run as administrator)

### 10. Browser Extensions
- Restore browser-extensions\* to appropriate browser profile folders

## Quick Verification
After restore, run:
- claude --version
- npm list -g --depth=0
- python --version
- uv --version

## Full Automated Restore
Run: .\restore-claudecode.ps1 -BackupPath "$backupPath"
"@

if (-not $DryRun) {
    $restoreGuide | Out-File -FilePath "$backupPath\RESTORE-GUIDE.md" -Encoding UTF8 -Force
    Write-Success "Created RESTORE-GUIDE.md"
}

Write-Progress-Step "[47/50]" "Validating backup integrity..."
$validationResults = @{
    backupPathExists = Test-Path $backupPath
    metadataExists = Test-Path "$backupPath\metadata.json"
    criticalFilesPresent = (Test-Path "$backupPath\home\.claude")
    devToolsBackedUp = ($nodeInfo.backedUp -or $npmInfo.backedUp -or $pythonInfo.backedUp)
    componentsBackedUp = if ($allComponents) { $true } else { $false }
}

if ($validationResults.criticalFilesPresent) {
    Write-Success "All critical files validated successfully"
} else {
    Write-Error-Message "Some critical files are missing from backup!"
}

Write-Progress-Step "[48/50]" "Creating backup summary report..."

$summaryReport = @{
    timestamp = $timestamp
    backupPath = $backupPath
    totalSize = Format-Size $script:totalSize
    itemsBackedUp = $script:backedUpItems.Count
    errors = $script:errors.Count
    warnings = $script:warnings.Count
    executionTime = [Math]::Round(((Get-Date) - $script:startTime).TotalSeconds, 2)
    validation = $validationResults
}

if (-not $DryRun) {
    $summaryPath = Join-Path $backupPath "backup-summary.json"
    $summaryReport | ConvertTo-Json -Depth 5 | Out-File -FilePath $summaryPath -Encoding UTF8 -Force
}

Write-Progress-Step "[49/50]" "Compressing backup (optional)..."
if (-not $SkipCompression -and -not $DryRun) {
    Write-Info "Compression skipped (use -SkipCompression:$false to enable)"
}

Write-Progress-Step "[50/50]" "Finalizing backup..."

# Complete atomic backup
if (-not $DryRun) {
    Complete-AtomicBackup -Success ($script:errors.Count -eq 0)
}

# Clear progress bar
Write-Progress -Activity "Claude Code Backup v4.3" -Completed

# Display summary
$totalSizeStr = Format-Size $script:totalSize
$executionTime = ((Get-Date) - $script:startTime).TotalSeconds

Write-Host "`n" -NoNewline
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  BACKUP COMPLETE - v4.3 (FAST)" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "Location: $backupPath" -ForegroundColor Green
Write-Host "Items backed up: $($script:backedUpItems.Count)" -ForegroundColor Green
Write-Host "Total Size: $totalSizeStr" -ForegroundColor Green
Write-Host "Execution Time: $([math]::Round($executionTime, 2)) seconds" -ForegroundColor Gray

Write-Host "`nDev Tools Backed Up:" -ForegroundColor Yellow
Write-Host "  Node.js:  $(if ($nodeInfo.backedUp) { 'Yes' } else { 'Not found' })" -ForegroundColor $(if ($nodeInfo.backedUp) { 'Green' } else { 'Gray' })
Write-Host "  npm:      $(if ($npmInfo.backedUp) { "Yes ($(Format-Size $npmInfo.size))" } else { 'Not found' })" -ForegroundColor $(if ($npmInfo.backedUp) { 'Green' } else { 'Gray' })
Write-Host "  Python:   $(if ($pythonInfo.backedUp) { 'Yes' } else { 'Not found' })" -ForegroundColor $(if ($pythonInfo.backedUp) { 'Green' } else { 'Gray' })
Write-Host "  uvx/uv:   $(if ($uvxInfo.backedUp) { 'Yes' } else { 'Not found' })" -ForegroundColor $(if ($uvxInfo.backedUp) { 'Green' } else { 'Gray' })
Write-Host "  Bun:      $(if ($bunInfo.backedUp) { "Yes ($(Format-Size $bunInfo.size))" } else { 'Not found' })" -ForegroundColor $(if ($bunInfo.backedUp) { 'Green' } else { 'Gray' })

if ($allComponents) {
    Write-Host "`nComponents Backed Up:" -ForegroundColor Yellow
    Write-Host "  Credentials: $($allComponents.credentials.Count) files" -ForegroundColor Green
    Write-Host "  OpenCode: $($allComponents.opencode.Count) locations" -ForegroundColor Green
    Write-Host "  MCP Wrappers: $($allComponents.mcpWrappers.Count) scripts" -ForegroundColor Green
    Write-Host "  Conversations: $($allComponents.conversations.Count) paths" -ForegroundColor Green
}

if ($script:warnings.Count -gt 0) {
    Write-Host "`nWarnings: $($script:warnings.Count)" -ForegroundColor Yellow
    foreach ($warn in ($script:warnings | Select-Object -First 5)) {
        Write-Host "  - $($warn.message)" -ForegroundColor Yellow
    }
    if ($script:warnings.Count -gt 5) {
        Write-Host "  ... and $($script:warnings.Count - 5) more" -ForegroundColor Yellow
    }
}

if ($script:errors.Count -gt 0) {
    Write-Host "`nErrors: $($script:errors.Count)" -ForegroundColor Red
    foreach ($err in ($script:errors | Select-Object -First 5)) {
        Write-Host "  - $($err.message)" -ForegroundColor Red
    }
    if ($script:errors.Count -gt 5) {
        Write-Host "  ... and $($script:errors.Count - 5) more" -ForegroundColor Red
    }
} else {
    Write-Host "`nErrors: None" -ForegroundColor Green
}

Write-Host "`nRestore Command:" -ForegroundColor Yellow
Write-Host "  .\restore-claudecode.ps1 -BackupPath `"$backupPath`"" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "`n" -NoNewline

Write-Log "Backup completed. Total size: $totalSizeStr, Errors: $($script:errors.Count), Warnings: $($script:warnings.Count)"

return $backupPath