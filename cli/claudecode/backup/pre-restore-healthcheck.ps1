#Requires -Version 5.0
<#
.SYNOPSIS
    Pre-Restore Health Check for Claude Code Backup Restore
    
.DESCRIPTION
    Validates the NEW PC is ready for restore before running restore-claudecode-v3-complete.ps1
    Checks: disk space, admin privileges, network, Windows version, required software, no conflicts
    
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File pre-restore-healthcheck.ps1
#>

# ==================== CONFIG ====================
$MinDiskSpaceGB = 10
$RequiredSoftware = @{
    'Node.js' = @{
        'cmd' = 'node --version'
        'downloadUrl' = 'https://nodejs.org/en/download/'
        'installCmd' = 'winget install OpenJS.NodeJS -e'
    }
    'npm' = @{
        'cmd' = 'npm --version'
        'downloadUrl' = 'https://www.npmjs.com/package/npm'
        'installCmd' = 'npm install -g npm'
    }
    'Git' = @{
        'cmd' = 'git --version'
        'downloadUrl' = 'https://git-scm.com/download/win'
        'installCmd' = 'winget install Git.Git -e'
    }
    '7-Zip' = @{
        'cmd' = '7z'
        'downloadUrl' = 'https://www.7-zip.org/download.html'
        'installCmd' = 'winget install 7zip.7zip -e'
    }
}

# ==================== HELPERS ====================
function Write-Header {
    param([string]$Text)
    Write-Host "`n========== $Text ==========" -ForegroundColor Cyan
}

function Write-Pass {
    param([string]$Text)
    Write-Host "✅ $Text" -ForegroundColor Green
}

function Write-Fail {
    param([string]$Text)
    Write-Host "❌ $Text" -ForegroundColor Red
}

function Write-Warn {
    param([string]$Text)
    Write-Host "⚠️  $Text" -ForegroundColor Yellow
}

function Write-Info {
    param([string]$Text)
    Write-Host "ℹ️  $Text" -ForegroundColor Blue
}

function Show-Remediation {
    param([string]$Title, [string]$Description, [string]$DownloadUrl, [string]$InstallCmd, [string]$ExtraSteps)
    
    Write-Host "`n   📝 REMEDIATION: $Title" -ForegroundColor Magenta
    Write-Host "   ─────────────────────────────────────"
    if ($Description) { Write-Host "   Description: $Description" }
    if ($DownloadUrl) { Write-Host "   Download: $DownloadUrl" }
    if ($InstallCmd) { Write-Host "   Install: $InstallCmd" }
    if ($ExtraSteps) { Write-Host "   Steps: $ExtraSteps" }
}

# ==================== CHECK 1: DISK SPACE ====================
Write-Header "1. DISK SPACE CHECK"
try {
    $SystemDrive = $env:SystemDrive
    $DriveInfo = Get-Volume -DriveLetter $SystemDrive.Replace(':', '')
    $FreeGB = [math]::Round($DriveInfo.SizeRemaining / 1GB, 2)
    $TotalGB = [math]::Round($DriveInfo.Size / 1GB, 2)
    
    Write-Info "Drive: $SystemDrive | Total: $TotalGB GB | Free: $FreeGB GB"
    
    if ($FreeGB -gt $MinDiskSpaceGB) {
        Write-Pass "Disk space check passed ($FreeGB GB > $MinDiskSpaceGB GB)"
        $DiskCheck = $true
    } else {
        Write-Fail "Insufficient disk space ($FreeGB GB < $MinDiskSpaceGB GB required)"
        Show-Remediation -Title "Free Up Disk Space" `
            -Description "You need at least $MinDiskSpaceGB GB free space" `
            -ExtraSteps "1. Delete temporary files: cleanmgr.exe`n   2. Remove old backups or large files`n   3. Empty Recycle Bin (Shift+Delete)"
        $DiskCheck = $false
    }
} catch {
    Write-Fail "Error checking disk space: $_"
    $DiskCheck = $false
}

# ==================== CHECK 2: ADMIN PRIVILEGES ====================
Write-Header "2. ADMINISTRATOR PRIVILEGES CHECK"
$IsAdmin = [Security.Principal.WindowsIdentity]::GetCurrent().Groups -contains 'S-1-5-32-544'
if ($IsAdmin) {
    Write-Pass "Running with Administrator privileges"
    $AdminCheck = $true
} else {
    Write-Fail "NOT running as Administrator"
    Show-Remediation -Title "Enable Administrator Privileges" `
        -Description "This script requires Administrator access" `
        -ExtraSteps "1. Close this PowerShell window`n   2. Right-click PowerShell → 'Run as administrator'`n   3. Run: powershell -ExecutionPolicy Bypass -File pre-restore-healthcheck.ps1"
    $AdminCheck = $false
}

# ==================== CHECK 3: NETWORK CONNECTIVITY ====================
Write-Header "3. NETWORK CONNECTIVITY CHECK"
$NetworkTests = @(
    @{ Host = 'google.com'; Name = 'Google' },
    @{ Host = 'github.com'; Name = 'GitHub' },
    @{ Host = 'nodejs.org'; Name = 'Node.js' }
)

$NetworkCheck = $true
foreach ($Test in $NetworkTests) {
    try {
        $Result = Test-NetConnection -ComputerName $Test.Host -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
        if ($Result.PingSucceeded) {
            Write-Pass "$($Test.Name) is reachable"
        } else {
            Write-Fail "$($Test.Name) is NOT reachable"
            $NetworkCheck = $false
        }
    } catch {
        Write-Warn "Could not test $($Test.Name): $_"
    }
}

if (-not $NetworkCheck) {
    Show-Remediation -Title "Fix Network Connectivity" `
        -Description "One or more required services are not reachable" `
        -ExtraSteps "1. Check your internet connection: ping 8.8.8.8`n   2. Check firewall settings`n   3. Try disabling VPN/proxy temporarily`n   4. Restart network adapter: ipconfig /renew"
}

# ==================== CHECK 4: WINDOWS VERSION ====================
Write-Header "4. WINDOWS VERSION COMPATIBILITY CHECK"
$WinVersion = [System.Environment]::OSVersion
$WinMajor = $WinVersion.Version.Major
$WinMinor = $WinVersion.Version.Minor
$WinBuild = $WinVersion.Version.Build

Write-Info "Windows Version: $WinMajor.$WinMinor Build $WinBuild"

# Require Windows 10 (build 1909+) or Windows 11
$VersionCheck = $false
if ($WinMajor -eq 10 -and $WinBuild -ge 1909) {
    Write-Pass "Windows 10 (Build 1909+) detected - Compatible"
    $VersionCheck = $true
} elseif ($WinMajor -ge 11) {
    Write-Pass "Windows 11 detected - Compatible"
    $VersionCheck = $true
} else {
    Write-Fail "Windows version too old (requires Windows 10 build 1909+ or Windows 11)"
    Show-Remediation -Title "Update Windows" `
        -Description "Your Windows version is not compatible with the restore environment" `
        -ExtraSteps "1. Open Windows Update: Settings → System → About → Check for updates`n   2. Install all available updates`n   3. Restart your computer`n   4. Re-run this health check"
    $VersionCheck = $false
}

# ==================== CHECK 5: REQUIRED SOFTWARE ====================
Write-Header "5. REQUIRED SOFTWARE CHECK"
$SoftwareCheck = $true
$MissingSoftware = @()

foreach ($Software in $RequiredSoftware.GetEnumerator()) {
    $Name = $Software.Key
    $Config = $Software.Value
    
    try {
        $Output = & cmd /c "$($Config.cmd) 2>&1"
        if ($LASTEXITCODE -eq 0 -and $Output) {
            Write-Pass "$Name is installed: $($Output.Split([Environment]::NewLine)[0])"
        } else {
            Write-Fail "$Name is NOT installed"
            $SoftwareCheck = $false
            $MissingSoftware += @{ Name = $Name; Config = $Config }
        }
    } catch {
        Write-Fail "$Name is NOT installed"
        $SoftwareCheck = $false
        $MissingSoftware += @{ Name = $Name; Config = $Config }
    }
}

if (-not $SoftwareCheck) {
    Write-Host "`n📋 INSTALLATION GUIDE:" -ForegroundColor Magenta
    foreach ($Item in $MissingSoftware) {
        Show-Remediation -Title $Item.Name `
            -DownloadUrl $Item.Config.downloadUrl `
            -InstallCmd $Item.Config.installCmd
    }
}

# ==================== CHECK 6: CONFLICTING INSTALLATIONS ====================
Write-Header "6. CONFLICTING INSTALLATIONS CHECK"
$ConflictCheck = $true
$Conflicts = @()

# Check for existing Claude/OpenClaw installations that might conflict
$ProgramFiles = @(
    'C:\Program Files\Claude'
    'C:\Program Files (x86)\Claude'
    'C:\Program Files\OpenClaw'
    'C:\Program Files (x86)\OpenClaw'
    $env:APPDATA + '\Claude'
    $env:APPDATA + '\OpenClaw'
)

foreach ($Path in $ProgramFiles) {
    if (Test-Path $Path) {
        Write-Warn "Found existing installation at: $Path"
        $ConflictCheck = $false
        $Conflicts += $Path
    }
}

# Check for running Claude/OpenClaw processes
$BlockingProcesses = @()
$ProcessNames = @('claude', 'openclaw', 'gateway', 'ClaudioCodeServer')
foreach ($ProcName in $ProcessNames) {
    $Procs = Get-Process -Name $ProcName -ErrorAction SilentlyContinue
    if ($Procs) {
        Write-Warn "Found running process: $ProcName"
        $ConflictCheck = $false
        $BlockingProcesses += $ProcName
    }
}

if ($ConflictCheck) {
    Write-Pass "No conflicting installations or processes detected"
} else {
    Show-Remediation -Title "Resolve Conflicting Installations" `
        -Description "Found existing Claude/OpenClaw installations or running processes" `
        -ExtraSteps "For each conflict:`n   1. Uninstall old Claude/OpenClaw: Settings → Apps → Apps & features`n   2. Kill running processes: Get-Process <process-name> | Stop-Process -Force`n   3. Delete remaining folders manually`n   4. Restart your computer`n   5. Re-run this health check"
}

# ==================== SUMMARY ====================
Write-Header "HEALTH CHECK SUMMARY"

$CheckResults = @(
    @{ Name = 'Disk Space'; Pass = $DiskCheck }
    @{ Name = 'Administrator Privileges'; Pass = $AdminCheck }
    @{ Name = 'Network Connectivity'; Pass = $NetworkCheck }
    @{ Name = 'Windows Version'; Pass = $VersionCheck }
    @{ Name = 'Required Software'; Pass = $SoftwareCheck }
    @{ Name = 'No Conflicts'; Pass = $ConflictCheck }
)

$PassedChecks = 0
foreach ($Check in $CheckResults) {
    $Status = if ($Check.Pass) { "✅ PASS" } else { "❌ FAIL" }
    Write-Host "$Status | $($Check.Name)" -ForegroundColor $(if ($Check.Pass) { "Green" } else { "Red" })
    if ($Check.Pass) { $PassedChecks++ }
}

Write-Info "Result: $PassedChecks/6 checks passed"

# ==================== FINAL DECISION ====================
Write-Header "READY TO RESTORE?"

if ($DiskCheck -and $AdminCheck -and $NetworkCheck -and $VersionCheck -and $SoftwareCheck -and $ConflictCheck) {
    Write-Pass "✨ All checks passed! Your system is ready for restore."
    Write-Info "Next step: Run the full restore script"
    Write-Info "Command: powershell -ExecutionPolicy Bypass -File restore-claudecode-v3-complete.ps1"
    
    $Confirm = Read-Host -Prompt "`n❓ Proceed with restore? (yes/no)"
    if ($Confirm -eq 'yes' -or $Confirm -eq 'y') {
        Write-Host "`n🚀 Starting restore script..." -ForegroundColor Cyan
        $RestorePath = Split-Path -Path $PSCommandPath
        $RestoreScript = Join-Path -Path $RestorePath -ChildPath 'restore-claudecode-v3-complete.ps1'
        
        if (Test-Path $RestoreScript) {
            & powershell -ExecutionPolicy Bypass -File $RestoreScript
        } else {
            Write-Fail "Restore script not found at: $RestoreScript"
            Write-Info "Make sure restore-claudecode-v3-complete.ps1 is in the same directory"
        }
    } else {
        Write-Host "❌ Restore cancelled by user." -ForegroundColor Yellow
        exit 1
    }
} else {
    Write-Fail "❌ System is NOT ready for restore. Please fix the failed checks above."
    Write-Info "Once you've completed the remediation steps, re-run this health check."
    exit 1
}
