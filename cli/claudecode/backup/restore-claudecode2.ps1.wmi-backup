#requires -Version 5.0
# ============================================================================
# RESTORE-CLAUDECODE.PS1 - COMPREHENSIVE Claude Code Restore Script v3.0
# ============================================================================
# Enterprise-grade restore for 100% complete restoration on ANY Windows machine
# including BRAND NEW Windows 11 installations.
#
# V3.0 MAJOR FEATURES:
# - Automatic Node.js download and installation from nodejs.org
# - Automatic Python download and installation
# - Full npm global packages restoration from backup
# - uvx/uv tools complete restoration
# - pnpm/yarn/nvm restoration
# - MCP servers auto-setup with wrapper recreation
# - MCP connection verification with auto-fix
# - Complete PATH environment restoration
# - Registry key restoration for all dev tools
# - Post-restore verification suite
#
# Usage:
#   .\restore-claudecode.ps1                       # Uses most recent backup
#   .\restore-claudecode.ps1 -BackupPath "..."    # Use specific backup
#   .\restore-claudecode.ps1 -DryRun              # Test without changes
#   .\restore-claudecode.ps1 -Force               # Skip confirmations
#   .\restore-claudecode.ps1 -SelectiveRestore    # Choose components
#   .\restore-claudecode.ps1 -SkipNodeInstall     # Skip Node.js installation
#   .\restore-claudecode.ps1 -SkipPythonInstall   # Skip Python installation
# ============================================================================

param(
    [Parameter(Position=0)]
    [string]$BackupPath,
    [switch]$Force,
    [switch]$DryRun,
    [switch]$SelectiveRestore,
    [switch]$SkipNodeInstall,
    [switch]$SkipPythonInstall,
    [switch]$SkipMcpSetup,
    [switch]$SkipVerification,
    [switch]$VerboseOutput,
    [int]$ThreadCount = 8,
    [string]$BackupRoot = "F:\backup\claudecode"
)

$ErrorActionPreference = 'Continue'
$VerbosePreference = if ($VerboseOutput) { 'Continue' } else { 'SilentlyContinue' }

# ============================================================================
# Configuration
# ============================================================================

$userHome = $env:USERPROFILE
$script:restoredCount = 0
$script:skippedCount = 0
$script:errorCount = 0
$script:totalSize = 0
$script:checkpoints = @()
$script:auditLog = @()
$script:startTime = Get-Date
$script:MIN_NODE_VERSION = [Version]"18.0.0"
$script:MIN_PYTHON_VERSION = [Version]"3.9.0"
$script:MIN_DISK_SPACE_GB = 5
$logsPath = Join-Path $BackupRoot "logs"

# Node.js download URLs
$script:NODE_DOWNLOAD_URL = "https://nodejs.org/dist/v22.12.0/node-v22.12.0-x64.msi"
$script:NODE_MSI_NAME = "node-v22.12.0-x64.msi"

# Python download URLs
$script:PYTHON_DOWNLOAD_URL = "https://www.python.org/ftp/python/3.12.8/python-3.12.8-amd64.exe"
$script:PYTHON_EXE_NAME = "python-3.12.8-amd64.exe"

# ============================================================================
# Audit Trail System
# ============================================================================

function Add-AuditEntry {
    param(
        [string]$Operation,
        [string]$Target,
        [string]$Status,
        [string]$Details = ""
    )

    $entry = @{
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss.fff")
        operation = $Operation
        target = $Target
        status = $Status
        details = $Details
        user = $env:USERNAME
        computer = $env:COMPUTERNAME
    }

    $script:auditLog += $entry

    if ($VerboseOutput) {
        Write-Host "  [AUDIT] $Operation on $Target : $Status" -ForegroundColor DarkGray
    }
}

function Save-AuditTrail {
    param([string]$DestPath)

    $auditFile = Join-Path $DestPath "restore_audit_$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss').json"

    try {
        @{
            restoreTimestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
            restoreVersion = "3.0"
            backupPath = $BackupPath
            entries = $script:auditLog
            summary = @{
                totalOperations = $script:auditLog.Count
                successful = ($script:auditLog | Where-Object { $_.status -eq "success" }).Count
                failed = ($script:auditLog | Where-Object { $_.status -eq "failed" }).Count
                duration = ((Get-Date) - $script:startTime).TotalSeconds
            }
        } | ConvertTo-Json -Depth 10 | Out-File -FilePath $auditFile -Encoding UTF8 -Force

        return $auditFile
    } catch {
        return $null
    }
}

# ============================================================================
# Logging System
# ============================================================================

$script:logFile = $null

function Initialize-RestoreLog {
    param([string]$LogsPath)

    if (-not (Test-Path $LogsPath)) {
        New-Item -ItemType Directory -Path $LogsPath -Force | Out-Null
    }

    $logDate = Get-Date -Format "yyyy_MM_dd"
    $script:logFile = Join-Path $LogsPath "restore_$logDate.log"

    Write-Log "=========================================="
    Write-Log "Restore session started - v3.0"
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

function Write-Step {
    param([string]$Step, [string]$Message)
    Write-Host "$Step $Message" -ForegroundColor Cyan
    Write-Log "$Step $Message"
}

function Write-OK {
    param([string]$Message)
    Write-Host "  [OK] $Message" -ForegroundColor Green
    Write-Log "  [OK] $Message" -Level 'SUCCESS'
}

function Write-Skip {
    param([string]$Message)
    Write-Host "  [--] $Message" -ForegroundColor DarkGray
    Write-Log "  [--] $Message"
}

function Write-Fail {
    param([string]$Message)
    Write-Host "  [!!] $Message" -ForegroundColor Red
    Write-Log "  [!!] $Message" -Level 'ERROR'
}

function Write-Warn {
    param([string]$Message)
    Write-Host "  [!] $Message" -ForegroundColor Yellow
    Write-Log "  [!] $Message" -Level 'WARN'
}

function Format-Size {
    param([long]$Size)
    if ($Size -gt 1GB) { return "{0:N2} GB" -f ($Size/1GB) }
    elseif ($Size -gt 1MB) { return "{0:N2} MB" -f ($Size/1MB) }
    elseif ($Size -gt 1KB) { return "{0:N0} KB" -f ($Size/1KB) }
    else { return "$Size B" }
}

function Refresh-EnvironmentPath {
    # Refresh PATH from registry for current session
    $machinePath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
    $userPath = [Environment]::GetEnvironmentVariable("PATH", "User")
    $env:PATH = "$machinePath;$userPath"
    Write-Log "Environment PATH refreshed"
}

# ============================================================================
# Automatic Retry with Exponential Backoff
# ============================================================================

function Invoke-WithRetry {
    param(
        [scriptblock]$ScriptBlock,
        [int]$MaxRetries = 5,
        [int]$BaseDelaySeconds = 2,
        [int]$MaxDelaySeconds = 120,
        [string]$OperationName = "Operation"
    )

    $retryCount = 0
    $lastError = $null

    while ($retryCount -lt $MaxRetries) {
        try {
            $result = & $ScriptBlock
            return $result
        } catch {
            $lastError = $_
            $retryCount++

            if ($retryCount -lt $MaxRetries) {
                $delay = [Math]::Min($BaseDelaySeconds * [Math]::Pow(2, $retryCount - 1), $MaxDelaySeconds)
                Write-Log "$OperationName failed (attempt $retryCount/$MaxRetries). Retrying in $delay seconds..." -Level 'WARN'
                Start-Sleep -Seconds $delay
            }
        }
    }

    Write-Log "$OperationName failed after $MaxRetries attempts: $($lastError.Exception.Message)" -Level 'ERROR'
    throw $lastError
}

# ============================================================================
# Automatic Claude Process Termination
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

    Write-Log "Found $($claudeProcesses.Count) Claude Code process(es). Terminating..."
    Add-AuditEntry -Operation "ProcessTermination" -Target "Claude processes" -Status "in_progress" -Details "$($claudeProcesses.Count) processes"

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
            Add-AuditEntry -Operation "ProcessTermination" -Target "Claude processes" -Status "success"
            return $true
        }
        Start-Sleep -Milliseconds 500
    }

    $stillRunning = $claudeProcesses | Where-Object { -not $_.HasExited }
    foreach ($proc in $stillRunning) {
        try {
            Stop-Process -Id $proc.Id -Force -ErrorAction Stop
            Write-Log "Force terminated: $($proc.Name) (PID: $($proc.Id))" -Level 'WARN'
        } catch {
            Write-Log "Failed to terminate process $($proc.Id): $($_.Exception.Message)" -Level 'ERROR'
        }
    }

    Add-AuditEntry -Operation "ProcessTermination" -Target "Claude processes" -Status "completed_with_force"
    return $true
}

# ============================================================================
# FRESH WINDOWS 11: Node.js Auto-Download and Installation
# ============================================================================

function Test-NodeInstallation {
    Write-Log "Checking Node.js installation..."

    $result = @{
        installed = $false
        version = $null
        path = $null
        meetsMinimum = $false
        npmVersion = $null
    }

    try {
        $nodePath = (Get-Command node -ErrorAction Stop).Source
        $nodeVersionStr = (& node --version 2>&1).ToString().TrimStart('v')
        $nodeVersion = [Version]$nodeVersionStr

        $result.installed = $true
        $result.version = $nodeVersionStr
        $result.path = $nodePath
        $result.meetsMinimum = $nodeVersion -ge $script:MIN_NODE_VERSION

        Write-Log "Node.js found: v$nodeVersionStr at $nodePath"
    } catch {
        Write-Log "Node.js not found in PATH" -Level 'DEBUG'
    }

    try {
        $npmVersionStr = (& npm --version 2>&1).ToString().Trim()
        $result.npmVersion = $npmVersionStr
        Write-Log "npm found: v$npmVersionStr"
    } catch {
        Write-Log "npm not found" -Level 'DEBUG'
    }

    return $result
}

function Install-NodeJS {
    param([string]$BackupPath)

    Write-Log "Installing Node.js for fresh Windows 11..."
    Add-AuditEntry -Operation "NodeInstall" -Target "Node.js" -Status "in_progress"

    # Method 1: Check if backup has Node.js installation to restore
    $nodeBackupPath = Join-Path $BackupPath "dev-tools\nodejs"
    if (Test-Path $nodeBackupPath) {
        Write-Log "Found Node.js backup, attempting to restore..."

        $nodeDestPath = "C:\Program Files\nodejs"

        if ($DryRun) {
            Write-Log "[DRY-RUN] Would restore Node.js from backup to $nodeDestPath"
            return $true
        }

        try {
            # This requires admin - use robocopy
            $robocopyArgs = @($nodeBackupPath, $nodeDestPath, "/E", "/ZB", "/COPY:DAT", "/DCOPY:DAT", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
            $null = & robocopy @robocopyArgs 2>&1

            if ($LASTEXITCODE -lt 8) {
                # Add to PATH
                $currentPath = [Environment]::GetEnvironmentVariable("PATH", "Machine")
                if ($currentPath -notlike "*$nodeDestPath*") {
                    [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$nodeDestPath", "Machine")
                }

                Refresh-EnvironmentPath

                Write-Log "Node.js restored from backup successfully"
                Add-AuditEntry -Operation "NodeInstall" -Target "Node.js" -Status "success" -Details "Restored from backup"
                return $true
            }
        } catch {
            Write-Log "Failed to restore Node.js from backup: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # Method 2: Try winget first (Windows 11 built-in)
    try {
        $winget = Get-Command winget -ErrorAction Stop
        Write-Log "Using winget to install Node.js LTS..."

        $result = & winget install OpenJS.NodeJS.LTS --accept-package-agreements --accept-source-agreements 2>&1 | Out-String

        if ($LASTEXITCODE -eq 0 -or $result -match "successfully installed" -or $result -match "already installed") {
            Refresh-EnvironmentPath
            Write-Log "Node.js installed via winget"
            Add-AuditEntry -Operation "NodeInstall" -Target "Node.js" -Status "success" -Details "via winget"
            return $true
        }
    } catch {
        Write-Log "winget not available, trying alternative methods..." -Level 'DEBUG'
    }

    # Method 3: Try chocolatey
    try {
        $choco = Get-Command choco -ErrorAction Stop
        Write-Log "Using Chocolatey to install Node.js..."

        $result = & choco install nodejs-lts -y 2>&1 | Out-String

        if ($LASTEXITCODE -eq 0) {
            Refresh-EnvironmentPath
            Add-AuditEntry -Operation "NodeInstall" -Target "Node.js" -Status "success" -Details "via chocolatey"
            return $true
        }
    } catch {
        Write-Log "Chocolatey not available" -Level 'DEBUG'
    }

    # Method 4: Direct download and install
    Write-Log "Attempting direct download from nodejs.org..."

    $tempDir = Join-Path $env:TEMP "node_installer"
    $msiPath = Join-Path $tempDir $script:NODE_MSI_NAME

    try {
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        Write-Log "Downloading Node.js from $($script:NODE_DOWNLOAD_URL)..."

        # Use BITS for reliable download
        $bitsJob = Start-BitsTransfer -Source $script:NODE_DOWNLOAD_URL -Destination $msiPath -ErrorAction Stop

        if (Test-Path $msiPath) {
            Write-Log "Node.js downloaded, installing MSI..."

            # Silent install
            $installArgs = "/i `"$msiPath`" /qn /norestart"
            $process = Start-Process -FilePath "msiexec.exe" -ArgumentList $installArgs -Wait -PassThru

            if ($process.ExitCode -eq 0) {
                Refresh-EnvironmentPath
                Write-Log "Node.js installed from direct download"
                Add-AuditEntry -Operation "NodeInstall" -Target "Node.js" -Status "success" -Details "Direct download"

                # Cleanup
                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                return $true
            }
        }
    } catch {
        Write-Log "Direct download failed: $($_.Exception.Message)" -Level 'WARN'
    }

    Write-Log "All Node.js installation methods failed. Please install manually from https://nodejs.org/" -Level 'ERROR'
    Add-AuditEntry -Operation "NodeInstall" -Target "Node.js" -Status "failed" -Details "All methods exhausted"

    return $false
}

# ============================================================================
# FRESH WINDOWS 11: Python Auto-Download and Installation
# ============================================================================

function Test-PythonInstallation {
    Write-Log "Checking Python installation..."

    $result = @{
        installed = $false
        version = $null
        path = $null
        meetsMinimum = $false
        pipVersion = $null
    }

    try {
        $pythonPath = (Get-Command python -ErrorAction Stop).Source
        $pythonVersionStr = (& python --version 2>&1).ToString() -replace "Python ", ""
        $pythonVersion = [Version]$pythonVersionStr

        $result.installed = $true
        $result.version = $pythonVersionStr
        $result.path = $pythonPath
        $result.meetsMinimum = $pythonVersion -ge $script:MIN_PYTHON_VERSION

        Write-Log "Python found: v$pythonVersionStr at $pythonPath"
    } catch {
        Write-Log "Python not found in PATH" -Level 'DEBUG'
    }

    try {
        $pipVersionStr = (& pip --version 2>&1).ToString()
        if ($pipVersionStr -match "pip (\d+\.\d+(\.\d+)?)") {
            $result.pipVersion = $Matches[1]
        }
        Write-Log "pip found: v$($result.pipVersion)"
    } catch {
        Write-Log "pip not found" -Level 'DEBUG'
    }

    return $result
}

function Install-Python {
    param([string]$BackupPath)

    Write-Log "Installing Python for fresh Windows 11..."
    Add-AuditEntry -Operation "PythonInstall" -Target "Python" -Status "in_progress"

    # Method 1: Check if backup has Python installation
    $pythonBackupPath = Join-Path $BackupPath "dev-tools\python"
    if (Test-Path $pythonBackupPath) {
        Write-Log "Found Python backup, attempting to restore..."

        # Find Python version directories
        $pythonDirs = Get-ChildItem -Path $pythonBackupPath -Directory -ErrorAction SilentlyContinue

        foreach ($pyDir in $pythonDirs) {
            $destPath = "$env:LOCALAPPDATA\Programs\Python\$($pyDir.Name)"

            if ($DryRun) {
                Write-Log "[DRY-RUN] Would restore Python from $($pyDir.FullName) to $destPath"
                continue
            }

            try {
                $robocopyArgs = @($pyDir.FullName, $destPath, "/E", "/ZB", "/COPY:DAT", "/DCOPY:DAT", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1

                if ($LASTEXITCODE -lt 8) {
                    # Add to PATH
                    $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
                    $pythonScripts = Join-Path $destPath "Scripts"
                    if ($currentPath -notlike "*$destPath*") {
                        [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$destPath;$pythonScripts", "User")
                    }

                    Refresh-EnvironmentPath
                    Write-Log "Python restored from backup: $($pyDir.Name)"
                    Add-AuditEntry -Operation "PythonInstall" -Target "Python" -Status "success" -Details "Restored from backup"
                    return $true
                }
            } catch {
                Write-Log "Failed to restore Python: $($_.Exception.Message)" -Level 'WARN'
            }
        }
    }

    # Method 2: Try winget
    try {
        $winget = Get-Command winget -ErrorAction Stop
        Write-Log "Using winget to install Python..."

        $result = & winget install Python.Python.3.12 --accept-package-agreements --accept-source-agreements 2>&1 | Out-String

        if ($LASTEXITCODE -eq 0 -or $result -match "successfully installed" -or $result -match "already installed") {
            Refresh-EnvironmentPath
            Write-Log "Python installed via winget"
            Add-AuditEntry -Operation "PythonInstall" -Target "Python" -Status "success" -Details "via winget"
            return $true
        }
    } catch {
        Write-Log "winget not available for Python" -Level 'DEBUG'
    }

    # Method 3: Try chocolatey
    try {
        $choco = Get-Command choco -ErrorAction Stop
        Write-Log "Using Chocolatey to install Python..."

        $result = & choco install python3 -y 2>&1 | Out-String

        if ($LASTEXITCODE -eq 0) {
            Refresh-EnvironmentPath
            Add-AuditEntry -Operation "PythonInstall" -Target "Python" -Status "success" -Details "via chocolatey"
            return $true
        }
    } catch {
        Write-Log "Chocolatey not available for Python" -Level 'DEBUG'
    }

    # Method 4: Direct download
    Write-Log "Attempting direct download from python.org..."

    $tempDir = Join-Path $env:TEMP "python_installer"
    $exePath = Join-Path $tempDir $script:PYTHON_EXE_NAME

    try {
        if (-not (Test-Path $tempDir)) {
            New-Item -ItemType Directory -Path $tempDir -Force | Out-Null
        }

        Write-Log "Downloading Python from $($script:PYTHON_DOWNLOAD_URL)..."

        $bitsJob = Start-BitsTransfer -Source $script:PYTHON_DOWNLOAD_URL -Destination $exePath -ErrorAction Stop

        if (Test-Path $exePath) {
            Write-Log "Python downloaded, installing..."

            # Silent install with PATH
            $installArgs = "/quiet InstallAllUsers=0 PrependPath=1 Include_pip=1"
            $process = Start-Process -FilePath $exePath -ArgumentList $installArgs -Wait -PassThru

            if ($process.ExitCode -eq 0) {
                Refresh-EnvironmentPath
                Write-Log "Python installed from direct download"
                Add-AuditEntry -Operation "PythonInstall" -Target "Python" -Status "success" -Details "Direct download"

                Remove-Item -Path $tempDir -Recurse -Force -ErrorAction SilentlyContinue
                return $true
            }
        }
    } catch {
        Write-Log "Direct Python download failed: $($_.Exception.Message)" -Level 'WARN'
    }

    Write-Log "All Python installation methods failed. Please install manually from https://python.org/" -Level 'ERROR'
    Add-AuditEntry -Operation "PythonInstall" -Target "Python" -Status "failed"

    return $false
}

# ============================================================================
# npm Global Packages Restoration
# ============================================================================

function Restore-NpmGlobalPackages {
    param([string]$BackupPath)

    Write-Log "Restoring npm global packages..."
    Add-AuditEntry -Operation "NpmRestore" -Target "npm packages" -Status "in_progress"

    $npmBackupPath = Join-Path $BackupPath "dev-tools\npm"
    $npmDestPath = "$env:APPDATA\npm"

    if (-not (Test-Path $npmBackupPath)) {
        Write-Log "No npm backup found at $npmBackupPath" -Level 'WARN'
        return @{ success = $false; message = "No npm backup found" }
    }

    $results = @{
        success = $true
        restored = 0
        errors = @()
    }

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would restore npm packages from $npmBackupPath"
        return $results
    }

    # Option 1: Copy entire npm directory (fastest, full restoration)
    try {
        Write-Log "Restoring full npm directory..."

        $robocopyArgs = @($npmBackupPath, $npmDestPath, "/E", "/ZB", "/COPY:DAT", "/DCOPY:DAT", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
        $null = & robocopy @robocopyArgs 2>&1

        if ($LASTEXITCODE -lt 8) {
            # Count restored packages
            $nodeModulesPath = Join-Path $npmDestPath "node_modules"
            if (Test-Path $nodeModulesPath) {
                $packages = Get-ChildItem -Path $nodeModulesPath -Directory -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -notmatch "^\..*" }
                $results.restored = $packages.Count
            }

            Write-Log "npm packages restored: $($results.restored) packages"
            Add-AuditEntry -Operation "NpmRestore" -Target "npm packages" -Status "success" -Details "$($results.restored) packages"

            # Ensure npm is in PATH
            $currentPath = [Environment]::GetEnvironmentVariable("PATH", "User")
            if ($currentPath -notlike "*$npmDestPath*") {
                [Environment]::SetEnvironmentVariable("PATH", "$currentPath;$npmDestPath", "User")
                $env:PATH = "$env:PATH;$npmDestPath"
            }

            return $results
        }
    } catch {
        Write-Log "Failed to restore npm directory: $($_.Exception.Message)" -Level 'WARN'
    }

    # Option 2: Use restore script if exists
    $restoreScript = Join-Path $npmBackupPath "restore-npm-packages.ps1"
    if (Test-Path $restoreScript) {
        Write-Log "Running npm packages restore script..."
        try {
            & $restoreScript
            $results.success = $true
        } catch {
            $results.errors += $_.Exception.Message
        }
    }

    return $results
}

# ============================================================================
# uvx/uv Tools Restoration
# ============================================================================

function Restore-UvxTools {
    param([string]$BackupPath)

    Write-Log "Restoring uvx/uv tools..."
    Add-AuditEntry -Operation "UvxRestore" -Target "uvx tools" -Status "in_progress"

    $uvBackupPath = Join-Path $BackupPath "dev-tools\uv"

    if (-not (Test-Path $uvBackupPath)) {
        Write-Log "No uvx backup found" -Level 'DEBUG'
        return @{ success = $true; message = "No uvx backup to restore" }
    }

    $results = @{
        success = $true
        restored = @()
    }

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would restore uvx tools from $uvBackupPath"
        return $results
    }

    # Restore each uv directory
    $uvDirs = Get-ChildItem -Path $uvBackupPath -Directory -ErrorAction SilentlyContinue

    foreach ($uvDir in $uvDirs) {
        $destPath = switch ($uvDir.Name) {
            "uv" { "$env:LOCALAPPDATA\uv" }
            "bin" { "$env:USERPROFILE\.local\bin" }
            "Programs" { "$env:LOCALAPPDATA\Programs\uv" }
            default { "$env:LOCALAPPDATA\$($uvDir.Name)" }
        }

        try {
            $robocopyArgs = @($uvDir.FullName, $destPath, "/E", "/ZB", "/COPY:DAT", "/DCOPY:DAT", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
            $null = & robocopy @robocopyArgs 2>&1

            if ($LASTEXITCODE -lt 8) {
                $results.restored += $uvDir.Name
                Write-Log "Restored uvx: $($uvDir.Name)"
            }
        } catch {
            Write-Log "Failed to restore uvx $($uvDir.Name): $($_.Exception.Message)" -Level 'WARN'
        }
    }

    Add-AuditEntry -Operation "UvxRestore" -Target "uvx tools" -Status "success" -Details "$($results.restored.Count) restored"
    return $results
}

# ============================================================================
# pnpm/yarn/nvm Restoration
# ============================================================================

function Restore-PackageManagers {
    param([string]$BackupPath)

    Write-Log "Restoring additional package managers..."

    $results = @{
        pnpm = @{ success = $false }
        yarn = @{ success = $false }
        nvm = @{ success = $false }
    }

    # pnpm
    $pnpmBackupPath = Join-Path $BackupPath "dev-tools\pnpm"
    if (Test-Path $pnpmBackupPath) {
        $pnpmDestPath = "$env:LOCALAPPDATA\pnpm"
        try {
            if (-not $DryRun) {
                $robocopyArgs = @($pnpmBackupPath, $pnpmDestPath, "/E", "/ZB", "/COPY:DAT", "/DCOPY:DAT", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
            }
            $results.pnpm.success = $true
            Write-Log "pnpm restored"
        } catch {
            Write-Log "Failed to restore pnpm: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # yarn
    $yarnBackupPath = Join-Path $BackupPath "dev-tools\yarn"
    if (Test-Path $yarnBackupPath) {
        $yarnDestPath = "$env:LOCALAPPDATA\Yarn"
        try {
            if (-not $DryRun) {
                $robocopyArgs = @($yarnBackupPath, $yarnDestPath, "/E", "/ZB", "/COPY:DAT", "/DCOPY:DAT", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
            }
            $results.yarn.success = $true
            Write-Log "yarn restored"
        } catch {
            Write-Log "Failed to restore yarn: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # nvm
    $nvmBackupPath = Join-Path $BackupPath "dev-tools\nvm"
    if (Test-Path $nvmBackupPath) {
        $nvmDestPath = if ($env:NVM_HOME) { $env:NVM_HOME } else { "$env:APPDATA\nvm" }
        try {
            if (-not $DryRun) {
                $robocopyArgs = @($nvmBackupPath, $nvmDestPath, "/E", "/ZB", "/COPY:DAT", "/DCOPY:DAT", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
            }
            $results.nvm.success = $true
            Write-Log "nvm restored"
        } catch {
            Write-Log "Failed to restore nvm: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    return $results
}

# ============================================================================
# MCP Servers Auto-Setup with Wrapper Recreation
# ============================================================================

function Restore-McpServers {
    param([string]$BackupPath)

    Write-Log "Setting up MCP servers..."
    Add-AuditEntry -Operation "McpSetup" -Target "MCP servers" -Status "in_progress"

    $claudeDir = "$env:USERPROFILE\.claude"
    $results = @{
        wrappersRestored = 0
        serversConnected = 0
        serversFailed = 0
        errors = @()
    }

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would setup MCP servers"
        return $results
    }

    # Step 1: Ensure .claude directory exists
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    # Step 2: Restore MCP wrapper .cmd files
    $wrapperSources = @(
        (Join-Path $BackupPath "home\.claude"),
        (Join-Path $BackupPath "MCP\claudecode\wrappers"),
        (Join-Path $BackupPath "dev-tools\npm\node_modules")
    )

    $wrapperFiles = @()
    foreach ($source in $wrapperSources) {
        if (Test-Path $source) {
            $cmdFiles = Get-ChildItem -Path $source -Filter "*.cmd" -Recurse -ErrorAction SilentlyContinue
            $wrapperFiles += $cmdFiles
        }
    }

    foreach ($wrapper in $wrapperFiles) {
        try {
            $destPath = Join-Path $claudeDir $wrapper.Name
            Copy-Item -Path $wrapper.FullName -Destination $destPath -Force -ErrorAction Stop
            $results.wrappersRestored++
            Write-Log "Restored wrapper: $($wrapper.Name)"
        } catch {
            Write-Log "Failed to restore wrapper $($wrapper.Name): $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # Step 3: Restore mcp-ondemand.ps1
    $mcpOndemandSources = @(
        (Join-Path $BackupPath "home\.claude\mcp-ondemand.ps1"),
        (Join-Path $BackupPath "MCP\claudecode\mcp-ondemand.ps1")
    )

    foreach ($source in $mcpOndemandSources) {
        if (Test-Path $source) {
            try {
                Copy-Item -Path $source -Destination $claudeDir -Force
                Write-Log "Restored mcp-ondemand.ps1"
                break
            } catch {
                Write-Log "Failed to restore mcp-ondemand.ps1: $($_.Exception.Message)" -Level 'WARN'
            }
        }
    }

    # Step 4: Parse mcp-ondemand.ps1 to get server definitions
    $mcpOndemandPath = Join-Path $claudeDir "mcp-ondemand.ps1"
    $serverDefinitions = @{}

    if (Test-Path $mcpOndemandPath) {
        try {
            $content = Get-Content -Path $mcpOndemandPath -Raw

            # Extract server definitions from the $s hashtable
            if ($content -match '\$s=@\{([^}]+(?:\{[^}]*\}[^}]*)*)\}') {
                $serverBlock = $Matches[1]

                # Parse each server entry
                $serverBlock -split ';' | ForEach-Object {
                    if ($_ -match '"([^"]+)"=@\{w="([^"]+)"') {
                        $serverName = $Matches[1]
                        $wrapperName = $Matches[2]
                        $serverDefinitions[$serverName] = @{
                            wrapper = $wrapperName
                            wrapperPath = Join-Path $claudeDir $wrapperName
                        }
                    }
                }
            }

            Write-Log "Parsed $($serverDefinitions.Count) MCP server definitions"
        } catch {
            Write-Log "Failed to parse mcp-ondemand.ps1: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # Step 5: Verify and fix wrapper paths
    foreach ($serverName in $serverDefinitions.Keys) {
        $server = $serverDefinitions[$serverName]
        $wrapperPath = $server.wrapperPath

        if (Test-Path $wrapperPath) {
            # Read wrapper content and verify Node.js path
            $wrapperContent = Get-Content -Path $wrapperPath -Raw

            # Check if Node.js path is valid
            if ($wrapperContent -match '"([^"]+node\.exe)"') {
                $nodePath = $Matches[1]
                if (-not (Test-Path $nodePath)) {
                    # Try to find Node.js and fix the wrapper
                    $actualNodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
                    if ($actualNodePath) {
                        $newContent = $wrapperContent -replace [regex]::Escape($nodePath), $actualNodePath
                        $newContent | Out-File -FilePath $wrapperPath -Encoding ASCII -Force
                        Write-Log "Fixed Node.js path in $($server.wrapper)"
                    }
                }
            }
        } else {
            Write-Log "Wrapper missing: $($server.wrapper)" -Level 'WARN'
        }
    }

    # Step 6: Connect MCP servers
    # First, source the mcp-ondemand.ps1 to get functions
    if (Test-Path $mcpOndemandPath) {
        try {
            # Try to add key servers
            $keyServers = @("github", "filesystem", "puppeteer", "sequential-thinking", "context7")

            foreach ($serverName in $keyServers) {
                if ($serverDefinitions.ContainsKey($serverName)) {
                    $wrapperPath = $serverDefinitions[$serverName].wrapperPath
                    if (Test-Path $wrapperPath) {
                        try {
                            $addResult = & claude mcp add -s user $serverName $wrapperPath 2>&1
                            if ($LASTEXITCODE -eq 0 -or $addResult -notmatch "error|fail") {
                                $results.serversConnected++
                                Write-Log "Connected MCP: $serverName"
                            }
                        } catch {
                            $results.serversFailed++
                            Write-Log "Failed to connect $serverName" -Level 'WARN'
                        }
                    }
                }
            }
        } catch {
            Write-Log "Error connecting MCP servers: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    Add-AuditEntry -Operation "McpSetup" -Target "MCP servers" -Status "success" -Details "Wrappers: $($results.wrappersRestored), Connected: $($results.serversConnected)"

    return $results
}

# ============================================================================
# MCP Health Check and Auto-Fix
# ============================================================================

function Test-McpServerHealth {
    param([switch]$AutoFix)

    Write-Log "Checking MCP server health..."

    $results = @{
        checked = 0
        healthy = 0
        unhealthy = 0
        fixed = 0
        servers = @()
    }

    # Get current MCP list
    try {
        $mcpList = & claude mcp list 2>&1 | Out-String

        if ($mcpList -match "No MCP") {
            Write-Log "No MCP servers configured"
            return $results
        }

        # Parse each line
        $mcpList -split "`n" | ForEach-Object {
            if ($_ -match "^(\S+):\s*(.+)$") {
                $serverName = $Matches[1]
                $serverInfo = $Matches[2]

                $results.checked++

                $serverResult = @{
                    name = $serverName
                    info = $serverInfo
                    status = "unknown"
                }

                if ($serverInfo -match "Connected") {
                    $serverResult.status = "healthy"
                    $results.healthy++
                } elseif ($serverInfo -match "Failed|Error|Disconnected") {
                    $serverResult.status = "unhealthy"
                    $results.unhealthy++

                    if ($AutoFix) {
                        # Try to fix by re-adding
                        $wrapperPath = "$env:USERPROFILE\.claude\$serverName.cmd"
                        if (Test-Path $wrapperPath) {
                            try {
                                $null = & claude mcp remove $serverName -s user 2>&1
                                $null = & claude mcp add -s user $serverName $wrapperPath 2>&1
                                $results.fixed++
                                Write-Log "Auto-fixed MCP: $serverName"
                            } catch {
                                Write-Log "Failed to auto-fix $serverName" -Level 'WARN'
                            }
                        }
                    }
                }

                $results.servers += $serverResult
            }
        }
    } catch {
        Write-Log "Error checking MCP health: $($_.Exception.Message)" -Level 'WARN'
    }

    Add-AuditEntry -Operation "McpHealthCheck" -Target "MCP servers" -Status $(if ($results.unhealthy -eq 0) { "success" } else { "partial" }) -Details "$($results.healthy)/$($results.checked) healthy"

    return $results
}

# ============================================================================
# Registry Key Restoration
# ============================================================================

function Restore-RegistryKeys {
    param([string]$BackupPath)

    Write-Log "Restoring registry keys..."

    $regBackupPath = Join-Path $BackupPath "registry"
    if (-not (Test-Path $regBackupPath)) {
        Write-Log "No registry backup found"
        return @{ success = $true; message = "No registry backup to restore" }
    }

    $results = @{
        success = $true
        restored = @()
        failed = @()
    }

    $regFiles = Get-ChildItem -Path $regBackupPath -Filter "*.reg" -ErrorAction SilentlyContinue

    foreach ($regFile in $regFiles) {
        if ($DryRun) {
            Write-Log "[DRY-RUN] Would import: $($regFile.Name)"
            continue
        }

        try {
            $regResult = & reg import $regFile.FullName 2>&1
            $results.restored += $regFile.Name
            Write-Log "Imported registry: $($regFile.Name)"
            Add-AuditEntry -Operation "RegistryRestore" -Target $regFile.Name -Status "success"
        } catch {
            $results.failed += @{ file = $regFile.Name; error = $_.Exception.Message }
            Write-Log "Failed to import $($regFile.Name): $($_.Exception.Message)" -Level 'WARN'
            Add-AuditEntry -Operation "RegistryRestore" -Target $regFile.Name -Status "failed" -Details $_.Exception.Message
        }
    }

    return $results
}

# ============================================================================
# Environment Variable Restoration
# ============================================================================

function Restore-EnvironmentVariables {
    param([string]$BackupPath)

    Write-Log "Restoring environment variables..."

    $envFile = Join-Path $BackupPath "environment_variables.json"
    if (-not (Test-Path $envFile)) {
        Write-Log "No environment variables backup found"
        return @{ success = $true; message = "No environment backup to restore" }
    }

    $results = @{
        success = $true
        restored = @()
        skipped = @()
    }

    try {
        $envBackup = Get-Content $envFile -Raw | ConvertFrom-Json

        # Restore dev tools related variables
        if ($envBackup.devTools) {
            $envBackup.devTools.PSObject.Properties | ForEach-Object {
                $varName = $_.Name
                $varData = $_.Value

                # Skip PATH - handled separately
                if ($varName -eq "PATH") {
                    return
                }

                if ($DryRun) {
                    Write-Log "[DRY-RUN] Would set: $varName"
                    return
                }

                try {
                    $scope = if ($varData.scope -eq "Machine") { "Machine" } else { "User" }
                    [Environment]::SetEnvironmentVariable($varName, $varData.value, $scope)
                    $results.restored += $varName
                    Write-Log "Restored env var: $varName"
                    Add-AuditEntry -Operation "EnvVarRestore" -Target $varName -Status "success"
                } catch {
                    Write-Log "Failed to set $varName : $($_.Exception.Message)" -Level 'WARN'
                    Add-AuditEntry -Operation "EnvVarRestore" -Target $varName -Status "failed"
                }
            }
        }

        # Handle PATH - merge backed up paths with current
        if ($envBackup.paths) {
            $backedUpUserPath = $envBackup.paths.user
            $currentUserPath = [Environment]::GetEnvironmentVariable("PATH", "User")

            # Critical paths that must be in PATH
            $criticalPaths = @(
                "$env:APPDATA\npm",
                "C:\Program Files\nodejs",
                "$env:LOCALAPPDATA\Programs\Python\Python312",
                "$env:LOCALAPPDATA\Programs\Python\Python312\Scripts",
                "$env:LOCALAPPDATA\pnpm",
                "$env:USERPROFILE\.local\bin"
            )

            $pathParts = @()
            if ($currentUserPath) {
                $pathParts = ($currentUserPath -split ";") | Where-Object { $_ -ne "" }
            }

            foreach ($criticalPath in $criticalPaths) {
                if ($criticalPath -and (Test-Path $criticalPath) -and $pathParts -notcontains $criticalPath) {
                    $pathParts += $criticalPath
                }
            }

            # Add backed up paths that exist
            if ($backedUpUserPath) {
                $backedUpParts = ($backedUpUserPath -split ";") | Where-Object { $_ -ne "" }
                foreach ($part in $backedUpParts) {
                    if ($part -and (Test-Path $part) -and $pathParts -notcontains $part) {
                        $pathParts += $part
                    }
                }
            }

            $newPath = ($pathParts | Select-Object -Unique) -join ";"

            if (-not $DryRun) {
                [Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
                $env:PATH = [Environment]::GetEnvironmentVariable("PATH", "Machine") + ";" + $newPath
                Write-Log "Updated user PATH with critical and backed up paths"
                Add-AuditEntry -Operation "PathUpdate" -Target "User PATH" -Status "success"
            }

            $results.restored += "PATH"
        }

    } catch {
        $results.success = $false
        Write-Log "Error restoring environment variables: $($_.Exception.Message)" -Level 'ERROR'
    }

    return $results
}

# ============================================================================
# Restore ALL MCP Wrappers
# ============================================================================

function Restore-AllMcpWrappers {
    param([string]$BackupPath)

    Write-Log "Restoring ALL MCP wrapper scripts (94 wrappers)..."
    
    $mcpWrapperBackupPath = Join-Path $BackupPath "mcp-wrappers"
    $claudeDir = "$env:USERPROFILE\.claude"
    
    $results = @{
        wrapperCount = 0
        totalWrappers = 0
        success = $false
    }

    if (-not (Test-Path $mcpWrapperBackupPath)) {
        Write-Log "No MCP wrapper backup found"
        return $results
    }

    # Ensure .claude directory exists
    if (-not (Test-Path $claudeDir)) {
        New-Item -ItemType Directory -Path $claudeDir -Force | Out-Null
    }

    # Get all .cmd files from backup
    $backupWrappers = Get-ChildItem -Path $mcpWrapperBackupPath -Filter "*.cmd" -File -ErrorAction SilentlyContinue
    $results.totalWrappers = $backupWrappers.Count

    Write-Log "Found $($results.totalWrappers) MCP wrapper scripts to restore"

    foreach ($wrapper in $backupWrappers) {
        try {
            $destPath = Join-Path $claudeDir $wrapper.Name
            if ($DryRun) {
                Write-Log "[DRY-RUN] Would restore wrapper: $($wrapper.Name)"
            } else {
                Copy-Item -Path $wrapper.FullName -Destination $destPath -Force
                $results.wrapperCount++
                Write-Log "Restored wrapper: $($wrapper.Name)"
            }
        } catch {
            Write-Log "Failed to restore wrapper $($wrapper.Name): $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # Also restore mcp-ondemand.ps1 dispatcher
    $mcpOnDemandBackup = Join-Path $mcpWrapperBackupPath "mcp-ondemand.ps1"
    if (Test-Path $mcpOnDemandBackup) {
        try {
            $destPath = Join-Path $claudeDir "mcp-ondemand.ps1"
            if (-not $DryRun) {
                Copy-Item -Path $mcpOnDemandBackup -Destination $destPath -Force
                Write-Log "Restored mcp-ondemand.ps1 dispatcher"
            }
        } catch {
            Write-Log "Failed to restore mcp-ondemand.ps1: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    $results.success = ($results.wrapperCount -gt 0)
    Write-Success "Restored $($results.wrapperCount) of $($results.totalWrappers) MCP wrapper scripts"
    
    Add-AuditEntry -Operation "McpWrapperRestore" -Target "MCP Wrappers" -Status $(if ($results.success) { "success" } else { "failed" })
    
    return $results
}

# ============================================================================
# Restore Browser Extension Data
# ============================================================================

function Restore-BrowserExtensionData {
    param([string]$BackupPath)

    Write-Log "Restoring browser extension data..."
    
    $browserBackupPath = Join-Path $BackupPath "browser-extensions"
    
    $results = @{
        chrome = $false
        edge = $false
        success = $false
    }

    if (-not (Test-Path $browserBackupPath)) {
        Write-Log "No browser extension backup found"
        return $results
    }

    # Restore Chrome extension data
    $chromeBackup = Join-Path $browserBackupPath "chrome\claude-extension"
    if (Test-Path $chromeBackup) {
        $chromeUserData = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Extensions\fcoeoabgfenejglbffodgkkbkcdhcgfn"
        try {
            if ($DryRun) {
                Write-Log "[DRY-RUN] Would restore Chrome extension data"
            } else {
                # Ensure parent directory exists
                $parentDir = Split-Path $chromeUserData -Parent
                if (-not (Test-Path $parentDir)) {
                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                }
                
                $robocopyArgs = @($chromeBackup, $chromeUserData, "/E", "/ZB", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
                
                if ($LASTEXITCODE -lt 8) {
                    Write-Log "Restored Chrome Claude extension"
                    $results.chrome = $true
                }
            }
        } catch {
            Write-Log "Failed to restore Chrome extension: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # Restore Chrome IndexedDB data
    $indexedDBBackup = Join-Path $browserBackupPath "chrome\indexeddb"
    if (Test-Path $indexedDBBackup) {
        $chromeIndexedDB = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\IndexedDB\https_claude.ai_0.indexeddb.leveldb"
        try {
            if (-not $DryRun) {
                # Ensure parent directory exists
                $parentDir = Split-Path $chromeIndexedDB -Parent
                if (-not (Test-Path $parentDir)) {
                    New-Item -ItemType Directory -Path $parentDir -Force | Out-Null
                }
                
                $robocopyArgs = @($indexedDBBackup, $chromeIndexedDB, "/E", "/ZB", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
                
                if ($LASTEXITCODE -lt 8) {
                    Write-Log "Restored Chrome IndexedDB for claude.ai"
                }
            }
        } catch {
            Write-Log "Failed to restore Chrome IndexedDB: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # Restore Edge extensions
    $edgeBackupPath = Join-Path $browserBackupPath "edge"
    if (Test-Path $edgeBackupPath) {
        $edgeUserData = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default\Extensions"
        $edgeExtensions = Get-ChildItem -Path $edgeBackupPath -Directory -ErrorAction SilentlyContinue
        
        foreach ($ext in $edgeExtensions) {
            try {
                if (-not $DryRun) {
                    $destPath = Join-Path $edgeUserData $ext.Name
                    $robocopyArgs = @($ext.FullName, $destPath, "/E", "/ZB", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                    $null = & robocopy @robocopyArgs 2>&1
                    
                    if ($LASTEXITCODE -lt 8) {
                        Write-Log "Restored Edge extension: $($ext.Name)"
                        $results.edge = $true
                    }
                }
            } catch {
                Write-Log "Failed to restore Edge extension $($ext.Name): $($_.Exception.Message)" -Level 'WARN'
            }
        }
    }

    $results.success = ($results.chrome -or $results.edge)
    Add-AuditEntry -Operation "BrowserExtRestore" -Target "Browser Extensions" -Status $(if ($results.success) { "success" } else { "failed" })
    
    return $results
}

# ============================================================================
# Restore PowerShell Modules
# ============================================================================

function Restore-PowerShellModules {
    param([string]$BackupPath)

    Write-Log "Restoring PowerShell modules (including ClaudeUsage)..."
    
    $psModulesBackupPath = Join-Path $BackupPath "powershell-modules"
    
    $results = @{
        claudeUsage = $false
        otherModules = @()
        success = $false
    }

    if (-not (Test-Path $psModulesBackupPath)) {
        Write-Log "No PowerShell modules backup found"
        return $results
    }

    # Determine target PowerShell module path (user scope)
    $psModulePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules"
    if (-not (Test-Path $psModulePath)) {
        New-Item -ItemType Directory -Path $psModulePath -Force | Out-Null
    }

    # Restore ClaudeUsage module specifically
    $claudeUsageBackup = Join-Path $psModulesBackupPath "ClaudeUsage"
    if (Test-Path $claudeUsageBackup) {
        try {
            $destPath = Join-Path $psModulePath "ClaudeUsage"
            if ($DryRun) {
                Write-Log "[DRY-RUN] Would restore ClaudeUsage module"
            } else {
                $robocopyArgs = @($claudeUsageBackup, $destPath, "/E", "/ZB", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
                
                if ($LASTEXITCODE -lt 8) {
                    Write-Success "Restored ClaudeUsage PowerShell module"
                    $results.claudeUsage = $true
                }
            }
        } catch {
            Write-Log "Failed to restore ClaudeUsage module: $($_.Exception.Message)" -Level 'WARN'
        }
    }

    # Restore other Claude-related modules
    $otherModules = Get-ChildItem -Path $psModulesBackupPath -Directory -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -ne "ClaudeUsage" }
    
    foreach ($module in $otherModules) {
        try {
            $destPath = Join-Path $psModulePath $module.Name
            if (-not $DryRun) {
                $robocopyArgs = @($module.FullName, $destPath, "/E", "/ZB", "/R:3", "/W:2", "/MT:$ThreadCount", "/XJ", "/NP", "/NFL", "/NDL", "/NJH", "/NJS")
                $null = & robocopy @robocopyArgs 2>&1
                
                if ($LASTEXITCODE -lt 8) {
                    Write-Log "Restored PowerShell module: $($module.Name)"
                    $results.otherModules += $module.Name
                }
            }
        } catch {
            Write-Log "Failed to restore module $($module.Name): $($_.Exception.Message)" -Level 'WARN'
        }
    }

    $results.success = ($results.claudeUsage -or ($results.otherModules.Count -gt 0))
    Add-AuditEntry -Operation "PSModuleRestore" -Target "PowerShell Modules" -Status $(if ($results.success) { "success" } else { "failed" })
    
    return $results
}

# ============================================================================
# Backup Integrity Validation
# ============================================================================

function Test-BackupIntegrity {
    param([string]$BackupPath)

    Write-Log "Validating backup integrity..."

    $validation = @{
        passed = $true
        results = @()
        hashMismatches = @()
    }

    # Check metadata exists (make it non-critical - just warn if missing)
    $metadataPath = Join-Path $BackupPath "metadata.json"
    if (-not (Test-Path $metadataPath)) {
        # Don't fail validation for missing metadata.json, just warn
        Write-Log "metadata.json not found - using default settings" -Level 'WARN'
        $validation.results += @{ check = "metadata.json"; passed = $false; error = "File not found (non-critical)" }
        # Create a minimal metadata object with defaults
        $validation.metadata = @{
            timestamp = "Unknown"
            version = "Unknown"
            machine = $env:COMPUTERNAME
            user = $env:USERNAME
        }
    } else {
        try {
            $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
            $validation.results += @{ check = "metadata.json"; passed = $true }
            $validation.metadata = $metadata
        } catch {
            # Don't fail validation for invalid metadata.json, just warn
            Write-Log "metadata.json is invalid - using default settings" -Level 'WARN'
            $validation.results += @{ check = "metadata.json"; passed = $false; error = "Invalid JSON (non-critical)" }
            $validation.metadata = @{
                timestamp = "Unknown"
                version = "Unknown"
                machine = $env:COMPUTERNAME
                user = $env:USERNAME
            }
        }
    }

    # Check critical directories exist
    $criticalPaths = @(
        "home\.claude",
        "npm\node_modules\@anthropic-ai\claude-code"
    )

    foreach ($path in $criticalPaths) {
        $fullPath = Join-Path $BackupPath $path
        $exists = Test-Path $fullPath
        $validation.results += @{ check = "critical_path:$path"; passed = $exists }
        if (-not $exists) {
            Write-Log "Critical path missing: $path" -Level 'WARN'
        }
    }

    # Check disk space
    try {
        $drive = (Split-Path $userHome -Qualifier).TrimEnd(':')
        $disk = Get-WmiObject Win32_LogicalDisk -Filter "DeviceID='${drive}:'" -ErrorAction Stop
        $freeSpaceGB = [math]::Round($disk.FreeSpace / 1GB, 2)

        $spaceOK = $freeSpaceGB -ge $script:MIN_DISK_SPACE_GB
        $validation.results += @{ check = "disk_space"; passed = $spaceOK; freeGB = $freeSpaceGB; requiredGB = $script:MIN_DISK_SPACE_GB }

        if (-not $spaceOK) {
            $validation.passed = $false
            Write-Log "Insufficient disk space: ${freeSpaceGB}GB free, ${script:MIN_DISK_SPACE_GB}GB required" -Level 'ERROR'
        }
    } catch {
        Write-Log "Could not check disk space: $($_.Exception.Message)" -Level 'WARN'
    }

    Add-AuditEntry -Operation "IntegrityCheck" -Target $BackupPath -Status $(if ($validation.passed) { "success" } else { "failed" })

    return $validation
}

# ============================================================================
# Checkpoint System
# ============================================================================

function Save-Checkpoint {
    param(
        [string]$Name,
        [string]$Status,
        [hashtable]$Data = @{}
    )

    $checkpoint = @{
        name = $Name
        timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
        status = $Status
        data = $Data
    }

    $script:checkpoints += $checkpoint
    Write-Log "Checkpoint saved: $Name ($Status)"
}

# ============================================================================
# Main Restore Function
# ============================================================================

function Restore-Item {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Name,
        [switch]$Critical
    )

    if (-not (Test-Path $Source)) {
        if ($Critical) {
            Write-Fail "Critical item missing: $Name"
            $script:errorCount++
            Add-AuditEntry -Operation "Restore" -Target $Name -Status "failed" -Details "Source not found"
        } else {
            Write-Skip "$Name (not in backup)"
        }
        $script:skippedCount++
        return
    }

    if ($DryRun) {
        $sizeCalc = Get-ChildItem -Path $Source -Recurse -Force -ErrorAction SilentlyContinue |
                    Where-Object {-not $_.PSIsContainer} |
                    Measure-Object -Property Length -Sum
        $size = if ($sizeCalc.Sum) { $sizeCalc.Sum } else { 0 }
        Write-Log "[DRY-RUN] Would restore: $Name ($(Format-Size $size))"
        return
    }

    try {
        $destParent = Split-Path $Destination -Parent
        if (-not (Test-Path $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }

        $sourceItem = Get-Item $Source -Force
        $isDir = $sourceItem.PSIsContainer

        if ($isDir) {
            # Remove existing destination first
            if (Test-Path $Destination) {
                Remove-Item -Path $Destination -Recurse -Force -ErrorAction SilentlyContinue
            }

            # Use robocopy with retry logic
            $robocopyResult = Invoke-WithRetry -OperationName "Robocopy $Name" -ScriptBlock {
                $result = & robocopy $Source $Destination /E /COPYALL /R:3 /W:2 /MT:$ThreadCount /NP /NFL /NDL /NJH /NJS 2>&1
                $exitCode = $LASTEXITCODE
                if ($exitCode -ge 8) {
                    throw "Robocopy failed with exit code $exitCode"
                }
                return @{ output = $result; exitCode = $exitCode }
            }

            $sizeCalc = Get-ChildItem -Path $Source -Recurse -Force -ErrorAction SilentlyContinue |
                        Where-Object {-not $_.PSIsContainer} |
                        Measure-Object -Property Length -Sum
            $size = if ($sizeCalc.Sum) { $sizeCalc.Sum } else { 0 }

        } else {
            if (Test-Path $Destination) {
                Remove-Item -Path $Destination -Force -ErrorAction SilentlyContinue
            }

            Invoke-WithRetry -OperationName "Copy $Name" -ScriptBlock {
                Copy-Item -Path $Source -Destination $Destination -Force -ErrorAction Stop
            }

            $size = $sourceItem.Length
        }

        $sizeStr = Format-Size $size
        Write-OK "$Name ($sizeStr)"
        $script:restoredCount++
        $script:totalSize += $size

        Add-AuditEntry -Operation "Restore" -Target $Name -Status "success" -Details "Size: $sizeStr"
        Save-Checkpoint -Name $Name -Status "restored" -Data @{ size = $size }

    } catch {
        Write-Fail "$Name - $($_.Exception.Message)"
        $script:errorCount++
        Add-AuditEntry -Operation "Restore" -Target $Name -Status "failed" -Details $_.Exception.Message
    }
}

# ============================================================================
# PowerShell Profile Restoration
# ============================================================================

function Restore-PowerShellProfile {
    param(
        [string]$Source,
        [string]$Destination,
        [string]$Name
    )

    if (-not (Test-Path $Source)) {
        Write-Skip $Name
        $script:skippedCount++
        return
    }

    if ($DryRun) {
        Write-Log "[DRY-RUN] Would restore: $Name"
        return
    }

    try {
        $destParent = Split-Path $Destination -Parent
        if (-not (Test-Path $destParent)) {
            New-Item -ItemType Directory -Path $destParent -Force | Out-Null
        }

        # Read and copy
        Copy-Item -Path $Source -Destination $Destination -Force

        $size = (Get-Item $Source).Length
        $sizeStr = Format-Size $size
        Write-OK "$Name ($sizeStr)"
        $script:restoredCount++
        $script:totalSize += $size

        Add-AuditEntry -Operation "ProfileRestore" -Target $Name -Status "success"

    } catch {
        Write-Fail "$Name - $($_.Exception.Message)"
        $script:errorCount++
        Add-AuditEntry -Operation "ProfileRestore" -Target $Name -Status "failed" -Details $_.Exception.Message
    }
}

# ============================================================================
# Post-restore Verification Suite
# ============================================================================

function Invoke-PostRestoreVerification {
    Write-Log "Running post-restore verification suite..."

    $results = @{
        passed = 0
        failed = 0
        tests = @()
    }

    # Test 1: Claude CLI
    $cliTest = @{ name = "Claude CLI"; passed = $false }
    try {
        $claudeVersion = & claude --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $cliTest.passed = $true
            $cliTest.version = $claudeVersion.Trim()
        }
    } catch { }
    $results.tests += $cliTest

    # Test 2: Node.js
    $nodeTest = @{ name = "Node.js"; passed = $false }
    try {
        $nodeVersion = & node --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $nodeTest.passed = $true
            $nodeTest.version = $nodeVersion.Trim()
        }
    } catch { }
    $results.tests += $nodeTest

    # Test 3: npm
    $npmTest = @{ name = "npm"; passed = $false }
    try {
        $npmVersion = & npm --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $npmTest.passed = $true
            $npmTest.version = $npmVersion.Trim()
        }
    } catch { }
    $results.tests += $npmTest

    # Test 4: Python
    $pythonTest = @{ name = "Python"; passed = $false }
    try {
        $pythonVersion = & python --version 2>&1 | Out-String
        if ($LASTEXITCODE -eq 0) {
            $pythonTest.passed = $true
            $pythonTest.version = $pythonVersion.Trim()
        }
    } catch { }
    $results.tests += $pythonTest

    # Test 5: .claude directory
    $claudeDirTest = @{ name = ".claude directory"; passed = (Test-Path "$userHome\.claude") }
    $results.tests += $claudeDirTest

    # Test 6: settings.json
    $settingsTest = @{ name = "settings.json"; passed = (Test-Path "$userHome\.claude\settings.json") }
    $results.tests += $settingsTest

    # Test 7: npm claude-code package
    $packageTest = @{ name = "claude-code package"; passed = (Test-Path "$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code") }
    $results.tests += $packageTest

    # Test 8: MCP wrapper files
    $wrapperTest = @{ name = "MCP wrappers"; passed = $false }
    $wrapperCount = (Get-ChildItem -Path "$userHome\.claude" -Filter "*.cmd" -ErrorAction SilentlyContinue).Count
    if ($wrapperCount -gt 0) {
        $wrapperTest.passed = $true
        $wrapperTest.count = $wrapperCount
    }
    $results.tests += $wrapperTest

    # Test 9: mcp-ondemand.ps1
    $mcpOndemandTest = @{ name = "mcp-ondemand.ps1"; passed = (Test-Path "$userHome\.claude\mcp-ondemand.ps1") }
    $results.tests += $mcpOndemandTest

    # Test 10: PowerShell profile
    $profileTest = @{ name = "PS5 Profile"; passed = (Test-Path "$userHome\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1") }
    $results.tests += $profileTest

    # Count results
    $results.passed = ($results.tests | Where-Object { $_.passed }).Count
    $results.failed = ($results.tests | Where-Object { -not $_.passed }).Count

    foreach ($test in $results.tests) {
        Add-AuditEntry -Operation "Verification" -Target $test.name -Status $(if ($test.passed) { "success" } else { "failed" })
    }

    return $results
}

# ============================================================================
# Available Backups
# ============================================================================

function Get-AvailableBackups {
    param([string]$BackupRoot)

    $backups = @()

    if (-not (Test-Path $BackupRoot)) {
        return $backups
    }

    $backupDirs = Get-ChildItem -Path $BackupRoot -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match "^backup_\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}$" } |
        Sort-Object Name -Descending

    foreach ($dir in $backupDirs) {
        $metadataPath = Join-Path $dir.FullName "metadata.json"
        $backup = @{
            path = $dir.FullName
            name = $dir.Name
            date = $null
            size = $null
            valid = $false
        }

        # Try to get info from metadata first
        if (Test-Path $metadataPath) {
            try {
                $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
                $backup.date = $metadata.backupDate
                $backup.size = Format-Size $metadata.totalSizeBytes
                $backup.computerName = $metadata.computerName
                $backup.claudeVersion = $metadata.claudeVersion
                $backup.valid = $true
            } catch { }
        }
        
        # If no metadata or date/size missing, calculate from directory
        if (-not $backup.date) {
            # Parse date from directory name
            if ($dir.Name -match "backup_(\d{4})_(\d{2})_(\d{2})_(\d{2})_(\d{2})_(\d{2})") {
                $backup.date = "$($Matches[1])-$($Matches[2])-$($Matches[3]) $($Matches[4]):$($Matches[5]):$($Matches[6])"
            } else {
                $backup.date = $dir.LastWriteTime.ToString("yyyy-MM-dd HH:mm:ss")
            }
        }
        
        if (-not $backup.size) {
            # Calculate actual directory size
            $sizeResult = Get-ChildItem -Path $dir.FullName -Recurse -Force -ErrorAction SilentlyContinue | 
                Where-Object { -not $_.PSIsContainer } | 
                Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue
            $sizeBytes = if ($sizeResult.Sum) { $sizeResult.Sum } else { 0 }
            $backup.size = Format-Size $sizeBytes
        }
        
        # Mark as valid if we have a path
        $backup.valid = $true

        $backups += $backup
    }

    return $backups
}

function Select-Backup {
    param([array]$Backups)

    Write-Host "`nAvailable Backups:" -ForegroundColor Cyan
    Write-Host ("-" * 60)

    for ($i = 0; $i -lt $Backups.Count; $i++) {
        $b = $Backups[$i]
        $marker = if ($i -eq 0) { " [LATEST]" } else { "" }
        Write-Host "[$($i + 1)] $($b.name)$marker" -ForegroundColor Yellow
        Write-Host "    Date: $($b.date)" -ForegroundColor Gray
        Write-Host "    Size: $($b.size)" -ForegroundColor Gray
        if ($b.claudeVersion) {
            Write-Host "    Version: $($b.claudeVersion)" -ForegroundColor Gray
        }
        Write-Host ""
    }

    $selection = Read-Host "Select backup number (1-$($Backups.Count)) or press Enter for latest"

    if ([string]::IsNullOrWhiteSpace($selection)) {
        return $Backups[0].path
    }

    $index = [int]$selection - 1
    if ($index -ge 0 -and $index -lt $Backups.Count) {
        return $Backups[$index].path
    }

    return $Backups[0].path
}

# ============================================================================
# Main Script
# ============================================================================

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  CLAUDE CODE COMPREHENSIVE RESTORE v3.0" -ForegroundColor Cyan
Write-Host "  FRESH WINDOWS 11 READY - FULL NODE/NPM/PYTHON/MCP SETUP" -ForegroundColor Yellow
Write-Host ("=" * 70) -ForegroundColor Cyan
if ($DryRun) { Write-Host "MODE: DRY RUN (no changes will be made)" -ForegroundColor Magenta }
Write-Host ""

# Initialize logging
Initialize-RestoreLog -LogsPath $logsPath

# Step 1: Find and validate backup
Write-Step "[1/23]" "Locating backup..."

if (-not $BackupPath) {
    if (-not (Test-Path $BackupRoot)) {
        Write-Fail "Backup root not found: $BackupRoot"
        exit 1
    }

    $availableBackups = Get-AvailableBackups -BackupRoot $BackupRoot

    if ($availableBackups.Count -eq 0) {
        Write-Fail "No backups found in $BackupRoot"
        exit 1
    }

    if ($SelectiveRestore -or $availableBackups.Count -gt 1) {
        $BackupPath = Select-Backup -Backups $availableBackups
    } else {
        $BackupPath = $availableBackups[0].path
    }
}

if (-not (Test-Path $BackupPath)) {
    Write-Fail "Backup not found: $BackupPath"
    exit 1
}

Write-OK "Using: $(Split-Path $BackupPath -Leaf)"
Add-AuditEntry -Operation "BackupSelection" -Target $BackupPath -Status "success"

# Read and display metadata
$metadataPath = Join-Path $BackupPath "metadata.json"
$metadata = $null
if (Test-Path $metadataPath) {
    try {
        $metadata = Get-Content $metadataPath -Raw | ConvertFrom-Json
        Write-Host "  Date: $($metadata.backupDate)" -ForegroundColor Gray
        Write-Host "  Size: $(Format-Size $metadata.totalSizeBytes)" -ForegroundColor Gray
        Write-Host "  Claude: $($metadata.claudeVersion)" -ForegroundColor Gray
    } catch { }
}

Write-Host ""

# Step 2: Pre-restore validation
Write-Step "[2/23]" "Validating backup integrity..."
$validation = Test-BackupIntegrity -BackupPath $BackupPath

if (-not $validation.passed -and -not $Force) {
    Write-Fail "Backup validation failed. Use -Force to override."
    foreach ($result in $validation.results) {
        if (-not $result.passed) {
            Write-Host "  - $($result.check): FAILED" -ForegroundColor Red
        }
    }
    exit 1
}

if ($validation.passed) {
    Write-OK "Backup integrity verified"
} else {
    Write-Warn "Backup has issues but continuing with -Force"
}

# Confirmation
if (-not $Force -and -not $DryRun) {
    Write-Host ""
    Write-Host "WARNING: This will restore Claude Code including Node.js, Python, npm, MCP!" -ForegroundColor Red
    $confirm = Read-Host "Continue with restore? (type 'YES' to confirm)"
    if ($confirm -ne 'YES') {
        Write-Host "Cancelled." -ForegroundColor Yellow
        exit 0
    }
}

Write-Host ""

# Step 3: Stop Claude processes
Write-Step "[3/23]" "Stopping Claude Code processes..."
if (-not $DryRun) {
    Stop-ClaudeProcesses -TimeoutSeconds 30
}
Write-OK "Processes handled"

# Step 4: Check and install Node.js (FRESH WINDOWS 11 SUPPORT)
Write-Step "[4/23]" "Checking/Installing Node.js..."
$nodeInfo = Test-NodeInstallation

if (-not $nodeInfo.installed -and -not $SkipNodeInstall) {
    Write-Warn "Node.js not found - Installing for fresh Windows 11..."
    if (-not $DryRun) {
        if (Install-NodeJS -BackupPath $BackupPath) {
            Write-OK "Node.js installed successfully"
            $nodeInfo = Test-NodeInstallation
        } else {
            Write-Warn "Node.js installation failed - some features may not work"
        }
    }
} elseif ($nodeInfo.installed) {
    if ($nodeInfo.meetsMinimum) {
        Write-OK "Node.js v$($nodeInfo.version) (meets minimum)"
    } else {
        Write-Warn "Node.js v$($nodeInfo.version) is below recommended v$($script:MIN_NODE_VERSION)"
    }
}

Save-Checkpoint -Name "NodeJS" -Status "completed"
Write-Host ""

# Step 5: Check and install Python (FRESH WINDOWS 11 SUPPORT)
Write-Step "[5/23]" "Checking/Installing Python..."
$pythonInfo = Test-PythonInstallation

if (-not $pythonInfo.installed -and -not $SkipPythonInstall) {
    Write-Warn "Python not found - Installing for fresh Windows 11..."
    if (-not $DryRun) {
        if (Install-Python -BackupPath $BackupPath) {
            Write-OK "Python installed successfully"
            $pythonInfo = Test-PythonInstallation
        } else {
            Write-Warn "Python installation failed - some MCP servers may not work"
        }
    }
} elseif ($pythonInfo.installed) {
    Write-OK "Python v$($pythonInfo.version)"
}

Save-Checkpoint -Name "Python" -Status "completed"
Write-Host ""

# Step 6: Restore npm global packages
Write-Step "[6/23]" "Restoring npm global packages..."
$npmResults = Restore-NpmGlobalPackages -BackupPath $BackupPath
if ($npmResults.success) {
    Write-OK "npm packages restored: $($npmResults.restored) packages"
}
Save-Checkpoint -Name "NpmPackages" -Status "completed"
Write-Host ""

# Step 7: Restore uvx/uv tools
Write-Step "[7/23]" "Restoring uvx/uv tools..."
$uvxResults = Restore-UvxTools -BackupPath $BackupPath
if ($uvxResults.restored.Count -gt 0) {
    Write-OK "uvx tools restored: $($uvxResults.restored.Count) components"
}
Save-Checkpoint -Name "UvxTools" -Status "completed"
Write-Host ""

# Step 8: Restore other package managers
Write-Step "[8/23]" "Restoring pnpm/yarn/nvm..."
$pmResults = Restore-PackageManagers -BackupPath $BackupPath
$pmRestored = @()
if ($pmResults.pnpm.success) { $pmRestored += "pnpm" }
if ($pmResults.yarn.success) { $pmRestored += "yarn" }
if ($pmResults.nvm.success) { $pmRestored += "nvm" }
if ($pmRestored.Count -gt 0) {
    Write-OK "Restored: $($pmRestored -join ', ')"
}
Save-Checkpoint -Name "PackageManagers" -Status "completed"
Write-Host ""

# Step 9: Restore core Claude Code files
Write-Step "[9/23]" "Restoring Claude Code configuration..."
Write-Host ""

$restorePaths = @(
    @{Src="$BackupPath\home\.claude"; Dst="$userHome\.claude"; Name=".claude directory"; Critical=$true},
    @{Src="$BackupPath\home\.claude.json"; Dst="$userHome\.claude.json"; Name=".claude.json"},
    @{Src="$BackupPath\home\.claude.json.backup"; Dst="$userHome\.claude.json.backup"; Name=".claude.json.backup"},
    @{Src="$BackupPath\home\.claude-server-commander"; Dst="$userHome\.claude-server-commander"; Name=".claude-server-commander"},
    @{Src="$BackupPath\home\CLAUDE.md"; Dst="$userHome\CLAUDE.md"; Name="CLAUDE.md"},
    @{Src="$BackupPath\home\claude.md"; Dst="$userHome\claude.md"; Name="claude.md"}
)

foreach ($item in $restorePaths) {
    $params = @{
        Source = $item.Src
        Destination = $item.Dst
        Name = $item.Name
    }
    if ($item.Critical) { $params.Critical = $true }
    Restore-Item @params
}

Save-Checkpoint -Name "CoreConfig" -Status "completed"
Write-Host ""

# Step 10: Restore AppData directories
Write-Step "[10/23]" "Restoring AppData directories..."
Write-Host ""

$appDataPaths = @(
    @{Src="$BackupPath\AppData\Roaming\Claude"; Dst="$env:APPDATA\Claude"; Name="AppData\Roaming\Claude"},
    @{Src="$BackupPath\AppData\Local\AnthropicClaude"; Dst="$env:LOCALAPPDATA\AnthropicClaude"; Name="AnthropicClaude"},
    @{Src="$BackupPath\AppData\Local\claude-cli-nodejs"; Dst="$env:LOCALAPPDATA\claude-cli-nodejs"; Name="claude-cli-nodejs"},
    @{Src="$BackupPath\AppData\Roaming\Anthropic"; Dst="$env:APPDATA\Anthropic"; Name="AppData\Anthropic"}
)

foreach ($item in $appDataPaths) {
    Restore-Item -Source $item.Src -Destination $item.Dst -Name $item.Name
}

Save-Checkpoint -Name "AppData" -Status "completed"
Write-Host ""

# Step 11: Restore npm packages (claude-code)
Write-Step "[11/23]" "Restoring npm claude-code packages..."
Write-Host ""

$npmPaths = @(
    @{Src="$BackupPath\npm\node_modules\@anthropic-ai\claude-code"; Dst="$env:APPDATA\npm\node_modules\@anthropic-ai\claude-code"; Name="claude-code package"; Critical=$true},
    @{Src="$BackupPath\npm\claude"; Dst="$env:APPDATA\npm\claude"; Name="npm claude"},
    @{Src="$BackupPath\npm\claude.cmd"; Dst="$env:APPDATA\npm\claude.cmd"; Name="npm claude.cmd"},
    @{Src="$BackupPath\npm\claude.ps1"; Dst="$env:APPDATA\npm\claude.ps1"; Name="npm claude.ps1"}
)

foreach ($item in $npmPaths) {
    $params = @{
        Source = $item.Src
        Destination = $item.Dst
        Name = $item.Name
    }
    if ($item.Critical) { $params.Critical = $true }
    Restore-Item @params
}

Save-Checkpoint -Name "ClaudeCodePackage" -Status "completed"
Write-Host ""

# Step 12: Restore PowerShell profiles
Write-Step "[12/23]" "Restoring PowerShell profiles..."
Write-Host ""

# PS5
Restore-PowerShellProfile -Source "$BackupPath\PowerShell\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" `
                          -Destination "$userHome\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" `
                          -Name "PS5 Profile"

Restore-PowerShellProfile -Source "$BackupPath\PowerShell\WindowsPowerShell\dadada.ps1" `
                          -Destination "$userHome\Documents\WindowsPowerShell\dadada.ps1" `
                          -Name "PS5 dadada.ps1"

# PS7
Restore-PowerShellProfile -Source "$BackupPath\PowerShell\PowerShell\Microsoft.PowerShell_profile.ps1" `
                          -Destination "$userHome\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" `
                          -Name "PS7 Profile"

Restore-PowerShellProfile -Source "$BackupPath\PowerShell\PowerShell\Microsoft.VSCode_profile.ps1" `
                          -Destination "$userHome\Documents\PowerShell\Microsoft.VSCode_profile.ps1" `
                          -Name "PS7 VSCode Profile"

Save-Checkpoint -Name "Profiles" -Status "completed"
Write-Host ""

# Step 13: Restore OpenCode integration
Write-Step "[13/23]" "Restoring OpenCode integration..."

if (-not $DryRun) {
    $opencodeResults = Restore-OpenCodeIntegration -BackupPath $BackupPath
    if ($opencodeResults.configRestored -or $opencodeResults.sisyphusRestored) {
        Write-OK "OpenCode restored - Config: $($opencodeResults.configRestored), Sisyphus: $($opencodeResults.sisyphusRestored)"
    }
}
Save-Checkpoint -Name "OpenCode" -Status "completed"
Write-Host ""

# Step 14: Restore additional Claude data
Write-Step "[14/23]" "Restoring additional Claude data (conversations, history, learned.md)..."

if (-not $DryRun) {
    $additionalResults = Restore-AdditionalClaudeData -BackupPath $BackupPath
    if ($additionalResults.conversationsRestored -gt 0 -or $additionalResults.knowledgeFilesRestored -gt 0) {
        Write-OK "Additional data restored - Conversations: $($additionalResults.conversationsRestored), Knowledge: $($additionalResults.knowledgeFilesRestored)"
    }
}
Save-Checkpoint -Name "AdditionalData" -Status "completed"
Write-Host ""

# Step 15: Restore Claude extensions
Write-Step "[15/23]" "Restoring Claude extensions..."

if (-not $DryRun) {
    $extensionsResults = Restore-ClaudeExtensions -BackupPath $BackupPath
    if ($extensionsResults.extensionsRestored -gt 0) {
        Write-OK "Extensions restored: $($extensionsResults.extensionsRestored)"
    }
}
Save-Checkpoint -Name "Extensions" -Status "completed"
Write-Host ""

# Step 16: Restore registry and environment
Write-Step "[16/23]" "Restoring registry keys and environment variables..."

if (-not $DryRun) {
    $regResults = Restore-RegistryKeys -BackupPath $BackupPath
    if ($regResults.restored.Count -gt 0) {
        Write-OK "Registry keys restored: $($regResults.restored.Count)"
    }

    $envResults = Restore-EnvironmentVariables -BackupPath $BackupPath
    if ($envResults.restored.Count -gt 0) {
        Write-OK "Environment variables restored: $($envResults.restored.Count)"
    }
}
Save-Checkpoint -Name "RegistryEnv" -Status "completed"
Write-Host ""

# Step 17: Restore ALL MCP wrapper scripts
Write-Step "[17/23]" "Restoring ALL MCP wrapper scripts (94 wrappers)..."

if (-not $DryRun) {
    $mcpWrapperResults = Restore-AllMcpWrappers -BackupPath $BackupPath
    if ($mcpWrapperResults.success) {
        Write-OK "MCP wrappers restored: $($mcpWrapperResults.wrapperCount) of $($mcpWrapperResults.totalWrappers)"
    }
}
Save-Checkpoint -Name "McpWrappers" -Status "completed"
Write-Host ""

# Step 18: Restore browser extension data
Write-Step "[18/23]" "Restoring browser extension data..."

if (-not $DryRun) {
    $browserExtResults = Restore-BrowserExtensionData -BackupPath $BackupPath
    if ($browserExtResults.success) {
        Write-OK "Browser extensions restored - Chrome: $($browserExtResults.chrome), Edge: $($browserExtResults.edge)"
    }
}
Save-Checkpoint -Name "BrowserExtensions" -Status "completed"
Write-Host ""

# Step 19: Restore PowerShell modules
Write-Step "[19/23]" "Restoring PowerShell modules (including ClaudeUsage)..."

if (-not $DryRun) {
    $psModuleResults = Restore-PowerShellModules -BackupPath $BackupPath
    if ($psModuleResults.success) {
        Write-OK "PowerShell modules restored - ClaudeUsage: $($psModuleResults.claudeUsage), Others: $($psModuleResults.otherModules -join ', ')"
    }
}
Save-Checkpoint -Name "PSModules" -Status "completed"
Write-Host ""

# Step 20: Setup MCP servers
Write-Step "[20/23]" "Setting up MCP servers..."

if (-not $SkipMcpSetup -and -not $DryRun) {
    $mcpResults = Restore-McpServers -BackupPath $BackupPath
    Write-OK "MCP servers setup: $($mcpResults.serversConnected) connected"
}
Save-Checkpoint -Name "McpSetup" -Status "completed"
Write-Host ""

# Step 21: Verify MCP connections
Write-Step "[21/23]" "Verifying MCP connections..."

if (-not $SkipMcpSetup -and -not $DryRun) {
    $mcpHealth = Test-McpServerHealth -AutoFix
    if ($mcpHealth.unhealthy -gt 0) {
        Write-Warn "MCP: $($mcpHealth.healthy)/$($mcpHealth.checked) healthy, $($mcpHealth.fixed) auto-fixed"
    } else {
        Write-OK "MCP: $($mcpHealth.healthy)/$($mcpHealth.checked) servers healthy"
    }
}
Write-Host ""

# Step 22: Post-restore validation
Write-Step "[22/23]" "Running post-restore verification..."
Write-Host ""

$verificationResults = @{ tests = @(); passed = 0; failed = 0 }

if (-not $SkipVerification -and -not $DryRun) {
    $verificationResults = Invoke-PostRestoreVerification

    Write-Host "  Verification Results:" -ForegroundColor Cyan
    foreach ($test in $verificationResults.tests) {
        $status = if ($test.passed) { "[PASS]" } else { "[FAIL]" }
        $color = if ($test.passed) { "Green" } else { "Red" }
        Write-Host "    $status $($test.name)" -ForegroundColor $color
    }
} else {
    Write-Skip "Verification skipped"
}
Save-Checkpoint -Name "Verification" -Status "completed"
Write-Host ""

# Step 23: Finalize
Write-Step "[23/23]" "Finalizing restore..."

if (-not $DryRun) {
    # Save audit trail
    $auditFile = Save-AuditTrail -DestPath $BackupRoot
    if ($auditFile) {
        Write-OK "Audit trail saved"
    }
}

# ============================================================================
# Summary
# ============================================================================

$executionTime = ((Get-Date) - $script:startTime).TotalSeconds

Write-Host ""
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host "  RESTORE COMPLETE - v3.0 (FRESH WINDOWS 11 READY)" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan

if ($DryRun) {
    Write-Host "MODE: DRY RUN - No changes were made" -ForegroundColor Magenta
} else {
    Write-Host "Restored: $script:restoredCount items ($(Format-Size $script:totalSize))" -ForegroundColor Green
}

Write-Host "Skipped:  $script:skippedCount items" -ForegroundColor Gray

if ($script:errorCount -gt 0) {
    Write-Host "Errors:   $script:errorCount" -ForegroundColor Red
} else {
    Write-Host "Errors:   None" -ForegroundColor Green
}

Write-Host "Time:     $([math]::Round($executionTime, 2)) seconds" -ForegroundColor Gray

# Dev tools status
Write-Host ""
Write-Host "Dev Tools Status:" -ForegroundColor Yellow
Write-Host "  Node.js: $(if ($nodeInfo.installed) { "v$($nodeInfo.version)" } else { 'Not installed' })" -ForegroundColor $(if ($nodeInfo.installed) { 'Green' } else { 'Red' })
Write-Host "  Python:  $(if ($pythonInfo.installed) { "v$($pythonInfo.version)" } else { 'Not installed' })" -ForegroundColor $(if ($pythonInfo.installed) { 'Green' } else { 'Yellow' })
Write-Host "  npm:     $(if ($nodeInfo.npmVersion) { "v$($nodeInfo.npmVersion)" } else { 'Not available' })" -ForegroundColor $(if ($nodeInfo.npmVersion) { 'Green' } else { 'Yellow' })

if (-not $DryRun -and -not $SkipVerification) {
    Write-Host ""
    Write-Host "Verification: $($verificationResults.passed)/$($verificationResults.tests.Count) tests passed" -ForegroundColor $(if ($verificationResults.failed -eq 0) { "Green" } else { "Yellow" })
}

Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""
Write-Host "NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Restart your terminal for all PATH changes to take effect" -ForegroundColor White
Write-Host "  2. Run: . ~/.claude/mcp-ondemand.ps1; mcps" -ForegroundColor White
Write-Host "  3. Use mcp-on to enable desired MCP servers" -ForegroundColor White
Write-Host ""

Write-Log "Restore completed. Items: $script:restoredCount, Errors: $script:errorCount, Time: $executionTime seconds"

if ($script:errorCount -gt 0) {
    exit 1
} else {
    exit 0
}
