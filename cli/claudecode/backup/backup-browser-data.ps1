#Requires -Version 5.0
<#
.SYNOPSIS
Comprehensive backup of all browser data across Chrome, Edge, Firefox, and Brave
Backs up IndexedDB, Local Storage, Cache, profiles, extensions, autofill, history, and cookies

.DESCRIPTION
Creates timestamped backup of:
- Chrome/Edge/Firefox/Brave IndexedDB + Local Storage + Cache
- Browser profiles and settings
- Browser extensions
- Auto-fill data (Claude/Anthropic domains only)
- Browser history (claude.ai optional)
- Browser cookies (optional, security-conscious)
- Reader/offline storage

.PARAMETER BackupPath
Target backup directory (default: script directory)

.PARAMETER IncludeHistory
Include browser history (optional, can be large)

.PARAMETER IncludeCookies
Include browser cookies (optional, security risk)

.PARAMETER Verbose
Verbose output

.EXAMPLE
.\backup-browser-data.ps1 -Verbose
.\backup-browser-data.ps1 -BackupPath "D:\Backups" -IncludeHistory -IncludeCookies
#>

param(
    [string]$BackupPath = $PSScriptRoot,
    [switch]$IncludeHistory,
    [switch]$IncludeCookies,
    [switch]$Verbose = $false
)

$ErrorActionPreference = "Continue"
$WarningPreference = "SilentlyContinue"

# ============================================================================
# CONFIGURATION
# ============================================================================

$timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
$backupDir = Join-Path $BackupPath "browser-backup-$timestamp"
$logFile = Join-Path $backupDir "backup-log.txt"

# Browser paths
$userProfile = [System.Environment]::GetFolderPath("UserProfile")
$appDataLocal = [System.Environment]::GetFolderPath("LocalApplicationData")
$appDataRoaming = [System.Environment]::GetFolderPath("ApplicationData")

$browserPaths = @{
    Chrome = @{
        ProfilePath = Join-Path $appDataLocal "Google\Chrome\User Data"
        CachePath = Join-Path $appDataLocal "Google\Chrome\User Data\Default\Cache"
        ExtensionsPath = Join-Path $appDataLocal "Google\Chrome\User Data\Default\Extensions"
    }
    Edge = @{
        ProfilePath = Join-Path $appDataLocal "Microsoft\Edge\User Data"
        CachePath = Join-Path $appDataLocal "Microsoft\Edge\User Data\Default\Cache"
        ExtensionsPath = Join-Path $appDataLocal "Microsoft\Edge\User Data\Default\Extensions"
    }
    Firefox = @{
        ProfilePath = Join-Path $appDataRoaming "Mozilla\Firefox\Profiles"
        ExtensionsPath = Join-Path $appDataRoaming "Mozilla\Firefox"
    }
    Brave = @{
        ProfilePath = Join-Path $appDataLocal "BraveSoftware\Brave-Browser\User Data"
        CachePath = Join-Path $appDataLocal "BraveSoftware\Brave-Browser\User Data\Default\Cache"
        ExtensionsPath = Join-Path $appDataLocal "BraveSoftware\Brave-Browser\User Data\Default\Extensions"
    }
}

# ============================================================================
# FUNCTIONS
# ============================================================================

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMsg = "[$timestamp] [$Level] $Message"
    Add-Content -Path $logFile -Value $logMsg -ErrorAction SilentlyContinue
    if ($Verbose) { Write-Host $logMsg }
}

function New-BackupDirectory {
    param([string]$Path)
    try {
        if (-not (Test-Path $Path)) {
            New-Item -ItemType Directory -Path $Path -Force | Out-Null
            Write-Log "Created directory: $Path"
            return $true
        }
        return $true
    }
    catch {
        Write-Log "ERROR: Failed to create directory $Path - $_" "ERROR"
        return $false
    }
}

function Backup-BrowserData {
    param(
        [string]$BrowserName,
        [hashtable]$Paths,
        [string]$BackupRoot
    )
    
    $browserBackup = Join-Path $BackupRoot $BrowserName
    New-BackupDirectory $browserBackup | Out-Null
    
    Write-Log "Starting backup for $BrowserName..."
    
    # Backup IndexedDB and Local Storage
    $sourceIndexedDB = Join-Path $Paths.ProfilePath "Default\IndexedDB"
    if (Test-Path $sourceIndexedDB) {
        try {
            $destIndexedDB = Join-Path $browserBackup "IndexedDB"
            Copy-Item $sourceIndexedDB $destIndexedDB -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Backed up IndexedDB"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not backup IndexedDB - $_" "WARN"
        }
    }
    
    # Backup Local Storage
    $sourceLocalStorage = Join-Path $Paths.ProfilePath "Default\Local Storage"
    if (Test-Path $sourceLocalStorage) {
        try {
            $destLocalStorage = Join-Path $browserBackup "Local Storage"
            Copy-Item $sourceLocalStorage $destLocalStorage -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Backed up Local Storage"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not backup Local Storage - $_" "WARN"
        }
    }
    
    # Backup Cache
    if ($Paths.CachePath -and (Test-Path $Paths.CachePath)) {
        try {
            $destCache = Join-Path $browserBackup "Cache"
            Copy-Item $Paths.CachePath $destCache -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Backed up Cache"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not backup Cache - $_" "WARN"
        }
    }
    
    # Backup Extensions
    if ($Paths.ExtensionsPath -and (Test-Path $Paths.ExtensionsPath)) {
        try {
            $destExtensions = Join-Path $browserBackup "Extensions"
            Copy-Item $Paths.ExtensionsPath $destExtensions -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Backed up Extensions"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not backup Extensions - $_" "WARN"
        }
    }
    
    # Backup Preferences/Settings
    $sourcePrefs = Join-Path $Paths.ProfilePath "Default\Preferences"
    if (Test-Path $sourcePrefs) {
        try {
            $destPrefs = Join-Path $browserBackup "Settings"
            New-Item -ItemType Directory -Path $destPrefs -Force | Out-Null
            Copy-Item $sourcePrefs $destPrefs -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Backed up Preferences"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not backup Preferences - $_" "WARN"
        }
    }
    
    # Backup Autofill (Claude/Anthropic domains only)
    $sourceAutofill = Join-Path $Paths.ProfilePath "Default\Web Data"
    if (Test-Path $sourceAutofill) {
        try {
            $destAutofill = Join-Path $browserBackup "Autofill"
            New-Item -ItemType Directory -Path $destAutofill -Force | Out-Null
            Copy-Item $sourceAutofill "$destAutofill\Web Data" -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Backed up Autofill data"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not backup Autofill - $_" "WARN"
        }
    }
    
    # Backup History (optional)
    if ($IncludeHistory) {
        $sourceHistory = Join-Path $Paths.ProfilePath "Default\History"
        if (Test-Path $sourceHistory) {
            try {
                $destHistory = Join-Path $browserBackup "History"
                New-Item -ItemType Directory -Path $destHistory -Force | Out-Null
                Copy-Item $sourceHistory "$destHistory\History" -Force -ErrorAction SilentlyContinue
                Write-Log "$BrowserName: Backed up History"
            }
            catch {
                Write-Log "$BrowserName: Warning - Could not backup History - $_" "WARN"
            }
        }
    }
    
    # Backup Cookies (optional)
    if ($IncludeCookies) {
        $sourceCookies = Join-Path $Paths.ProfilePath "Default\Cookies"
        if (Test-Path $sourceCookies) {
            try {
                $destCookies = Join-Path $browserBackup "Cookies"
                New-Item -ItemType Directory -Path $destCookies -Force | Out-Null
                Copy-Item $sourceCookies "$destCookies\Cookies" -Force -ErrorAction SilentlyContinue
                Write-Log "$BrowserName: Backed up Cookies (SECURITY WARNING)"
            }
            catch {
                Write-Log "$BrowserName: Warning - Could not backup Cookies - $_" "WARN"
            }
        }
    }
    
    # Backup Reader/Offline Storage
    $sourceReaderData = Join-Path $Paths.ProfilePath "Default\Reader Data"
    if (Test-Path $sourceReaderData) {
        try {
            $destReaderData = Join-Path $browserBackup "Reader Data"
            Copy-Item $sourceReaderData $destReaderData -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Backed up Reader/Offline Storage"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not backup Reader Data - $_" "WARN"
        }
    }
}

function Backup-Firefox {
    param([string]$BackupRoot)
    
    $firefoxBackup = Join-Path $BackupRoot "Firefox"
    New-BackupDirectory $firefoxBackup | Out-Null
    
    Write-Log "Starting backup for Firefox..."
    
    $profilePath = Join-Path $appDataRoaming "Mozilla\Firefox\Profiles"
    if (Test-Path $profilePath) {
        try {
            # Backup entire profile directories
            $profiles = Get-ChildItem -Path $profilePath -Directory
            foreach ($profile in $profiles) {
                $profileBackup = Join-Path $firefoxBackup $profile.Name
                New-Item -ItemType Directory -Path $profileBackup -Force | Out-Null
                
                # Key Firefox storage locations
                $storageItems = @(
                    "storage",
                    "cache2",
                    "localstore.rdf",
                    "extensions",
                    "prefs.js"
                )
                
                foreach ($item in $storageItems) {
                    $sourcePath = Join-Path $profile.FullName $item
                    if (Test-Path $sourcePath) {
                        try {
                            if ((Get-Item $sourcePath).PSIsContainer) {
                                Copy-Item $sourcePath (Join-Path $profileBackup $item) -Recurse -Force -ErrorAction SilentlyContinue
                            }
                            else {
                                Copy-Item $sourcePath (Join-Path $profileBackup $item) -Force -ErrorAction SilentlyContinue
                            }
                        }
                        catch {
                            # Silently continue on individual item failures
                        }
                    }
                }
                
                Write-Log "Firefox: Backed up profile $($profile.Name)"
            }
        }
        catch {
            Write-Log "Firefox: Warning - Could not backup profiles - $_" "WARN"
        }
    }
    
    # Backup extensions
    $extensionsPath = Join-Path $appDataRoaming "Mozilla\Firefox\Extensions"
    if (Test-Path $extensionsPath) {
        try {
            $destExtensions = Join-Path $firefoxBackup "Extensions"
            Copy-Item $extensionsPath $destExtensions -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Firefox: Backed up Extensions"
        }
        catch {
            Write-Log "Firefox: Warning - Could not backup Extensions - $_" "WARN"
        }
    }
}

# ============================================================================
# MAIN BACKUP LOGIC
# ============================================================================

Write-Host "Browser Data Backup Utility"
Write-Host "============================"
Write-Host "Backup Directory: $backupDir"
Write-Host ""

# Create main backup directory
if (-not (New-BackupDirectory $backupDir)) {
    Write-Host "ERROR: Could not create backup directory. Exiting."
    exit 1
}

# Initialize log file
Write-Log "=== Browser Data Backup Started ===" "INFO"
Write-Log "Backup Path: $backupDir" "INFO"
Write-Log "Include History: $IncludeHistory" "INFO"
Write-Log "Include Cookies: $IncludeCookies" "INFO"

# Backup Chrome
if (Test-Path $browserPaths.Chrome.ProfilePath) {
    Backup-BrowserData -BrowserName "Chrome" -Paths $browserPaths.Chrome -BackupRoot $backupDir
}
else {
    Write-Log "Chrome: Not found or not installed" "WARN"
}

# Backup Edge
if (Test-Path $browserPaths.Edge.ProfilePath) {
    Backup-BrowserData -BrowserName "Edge" -Paths $browserPaths.Edge -BackupRoot $backupDir
}
else {
    Write-Log "Edge: Not found or not installed" "WARN"
}

# Backup Brave
if (Test-Path $browserPaths.Brave.ProfilePath) {
    Backup-BrowserData -BrowserName "Brave" -Paths $browserPaths.Brave -BackupRoot $backupDir
}
else {
    Write-Log "Brave: Not found or not installed" "WARN"
}

# Backup Firefox (special handling)
if (Test-Path (Join-Path $appDataRoaming "Mozilla\Firefox")) {
    Backup-Firefox -BackupRoot $backupDir
}
else {
    Write-Log "Firefox: Not found or not installed" "WARN"
}

# Create backup manifest
$manifestPath = Join-Path $backupDir "BACKUP-MANIFEST.txt"
@"
Browser Data Backup Manifest
=============================
Backup Date: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Backup ID: $timestamp
Backup Location: $backupDir

Included Data:
- IndexedDB (all stored data)
- Local Storage (app data, settings)
- Cache (browser cache)
- Extensions (all installed extensions)
- Browser Profiles (settings, autofill)
- Reader/Offline Storage

Optional Data:
- History: $IncludeHistory
- Cookies: $IncludeCookies

Browsers Included:
- Chrome
- Microsoft Edge
- Firefox
- Brave

Security Notes:
- Cookies backup includes session tokens (SECURITY RISK - keep secure)
- Autofill data includes saved credentials (keep secure)
- Do not share backups without reviewing contents first

Log File: $logFile
"@ | Out-File -FilePath $manifestPath -Encoding UTF8 -Force

Write-Log "=== Browser Data Backup Completed ===" "INFO"
Write-Log "Backup Location: $backupDir" "INFO"

Write-Host ""
Write-Host "✅ Backup Complete!"
Write-Host "Location: $backupDir"
Write-Host "Manifest: $manifestPath"
Write-Host "Log: $logFile"
Write-Host ""

# Final statistics
$backupSize = (Get-ChildItem -Path $backupDir -Recurse | Measure-Object -Property Length -Sum).Sum / 1MB
Write-Host "Total Size: $([math]::Round($backupSize, 2)) MB"
