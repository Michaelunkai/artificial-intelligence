#Requires -Version 5.0
<#
.SYNOPSIS
Restore browser data from backup across Chrome, Edge, Firefox, and Brave

.DESCRIPTION
Restores:
- Browser profile structure
- IndexedDB data
- Local storage
- Extensions
- Settings and preferences
- Autofill data
- Reader/offline storage
- Optional: History
- Optional: Cookies

.PARAMETER BackupPath
Path to the backup directory created by backup-browser-data.ps1

.PARAMETER OverwriteExisting
If true, overwrites existing data. If false, asks for confirmation per browser

.PARAMETER Verbose
Verbose output

.EXAMPLE
.\restore-browser-data.ps1 -BackupPath ".\browser-backup-20240101-120000" -Verbose
.\restore-browser-data.ps1 -BackupPath "D:\Backups\browser-backup-20240101-120000" -OverwriteExisting
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,
    [switch]$OverwriteExisting,
    [switch]$Verbose = $false
)

$ErrorActionPreference = "Continue"
$WarningPreference = "SilentlyContinue"

# ============================================================================
# CONFIGURATION
# ============================================================================

$logFile = Join-Path $BackupPath "restore-log.txt"

# Verify backup exists
if (-not (Test-Path $BackupPath)) {
    Write-Host "ERROR: Backup path not found: $BackupPath"
    exit 1
}

# Browser paths
$userProfile = [System.Environment]::GetFolderPath("UserProfile")
$appDataLocal = [System.Environment]::GetFolderPath("LocalApplicationData")
$appDataRoaming = [System.Environment]::GetFolderPath("ApplicationData")

$browserPaths = @{
    Chrome = @{
        ProfilePath = Join-Path $appDataLocal "Google\Chrome\User Data"
        ExtensionsPath = Join-Path $appDataLocal "Google\Chrome\User Data\Default\Extensions"
    }
    Edge = @{
        ProfilePath = Join-Path $appDataLocal "Microsoft\Edge\User Data"
        ExtensionsPath = Join-Path $appDataLocal "Microsoft\Edge\User Data\Default\Extensions"
    }
    Firefox = @{
        ProfilePath = Join-Path $appDataRoaming "Mozilla\Firefox\Profiles"
        ExtensionsPath = Join-Path $appDataRoaming "Mozilla\Firefox\Extensions"
    }
    Brave = @{
        ProfilePath = Join-Path $appDataLocal "BraveSoftware\Brave-Browser\User Data"
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

function New-BrowserDirectory {
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

function Confirm-Overwrite {
    param([string]$BrowserName)
    
    if ($OverwriteExisting) {
        return $true
    }
    
    $response = Read-Host "Overwrite existing $BrowserName data? (y/N)"
    return $response -eq 'y' -or $response -eq 'Y'
}

function Restore-BrowserData {
    param(
        [string]$BrowserName,
        [hashtable]$Paths,
        [string]$BackupRoot
    )
    
    $browserBackup = Join-Path $BackupRoot $BrowserName
    if (-not (Test-Path $browserBackup)) {
        Write-Log "$BrowserName: No backup found"
        return
    }
    
    if (-not (Confirm-Overwrite $BrowserName)) {
        Write-Log "$BrowserName: Restore skipped by user"
        return
    }
    
    Write-Log "Starting restore for $BrowserName..."
    
    # Ensure profile path exists
    New-BrowserDirectory $Paths.ProfilePath | Out-Null
    
    # Restore IndexedDB
    $sourceIndexedDB = Join-Path $browserBackup "IndexedDB"
    if (Test-Path $sourceIndexedDB) {
        try {
            $destIndexedDB = Join-Path $Paths.ProfilePath "Default\IndexedDB"
            New-BrowserDirectory (Split-Path $destIndexedDB) | Out-Null
            
            # Remove old data if exists
            if (Test-Path $destIndexedDB) {
                Remove-Item $destIndexedDB -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            Copy-Item $sourceIndexedDB $destIndexedDB -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored IndexedDB"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore IndexedDB - $_" "WARN"
        }
    }
    
    # Restore Local Storage
    $sourceLocalStorage = Join-Path $browserBackup "Local Storage"
    if (Test-Path $sourceLocalStorage) {
        try {
            $destLocalStorage = Join-Path $Paths.ProfilePath "Default\Local Storage"
            New-BrowserDirectory (Split-Path $destLocalStorage) | Out-Null
            
            if (Test-Path $destLocalStorage) {
                Remove-Item $destLocalStorage -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            Copy-Item $sourceLocalStorage $destLocalStorage -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored Local Storage"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore Local Storage - $_" "WARN"
        }
    }
    
    # Restore Cache
    $sourceCache = Join-Path $browserBackup "Cache"
    if (Test-Path $sourceCache) {
        try {
            $destCache = Join-Path $Paths.ProfilePath "Default\Cache"
            New-BrowserDirectory (Split-Path $destCache) | Out-Null
            
            if (Test-Path $destCache) {
                Remove-Item $destCache -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            Copy-Item $sourceCache $destCache -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored Cache"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore Cache - $_" "WARN"
        }
    }
    
    # Restore Extensions
    $sourceExtensions = Join-Path $browserBackup "Extensions"
    if (Test-Path $sourceExtensions) {
        try {
            $destExtensions = Join-Path $Paths.ProfilePath "Default\Extensions"
            New-BrowserDirectory (Split-Path $destExtensions) | Out-Null
            
            if (Test-Path $destExtensions) {
                Remove-Item $destExtensions -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            Copy-Item $sourceExtensions $destExtensions -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored Extensions"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore Extensions - $_" "WARN"
        }
    }
    
    # Restore Preferences/Settings
    $sourcePrefs = Join-Path $browserBackup "Settings\Preferences"
    if (Test-Path $sourcePrefs) {
        try {
            $destPrefs = Join-Path $Paths.ProfilePath "Default\Preferences"
            New-BrowserDirectory (Split-Path $destPrefs) | Out-Null
            
            Copy-Item $sourcePrefs $destPrefs -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored Preferences"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore Preferences - $_" "WARN"
        }
    }
    
    # Restore Autofill
    $sourceAutofill = Join-Path $browserBackup "Autofill\Web Data"
    if (Test-Path $sourceAutofill) {
        try {
            $destAutofill = Join-Path $Paths.ProfilePath "Default\Web Data"
            New-BrowserDirectory (Split-Path $destAutofill) | Out-Null
            
            Copy-Item $sourceAutofill $destAutofill -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored Autofill data"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore Autofill - $_" "WARN"
        }
    }
    
    # Restore History (if exists)
    $sourceHistory = Join-Path $browserBackup "History\History"
    if (Test-Path $sourceHistory) {
        try {
            $destHistory = Join-Path $Paths.ProfilePath "Default\History"
            New-BrowserDirectory (Split-Path $destHistory) | Out-Null
            
            Copy-Item $sourceHistory $destHistory -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored History"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore History - $_" "WARN"
        }
    }
    
    # Restore Cookies (if exists)
    $sourceCookies = Join-Path $browserBackup "Cookies\Cookies"
    if (Test-Path $sourceCookies) {
        try {
            $destCookies = Join-Path $Paths.ProfilePath "Default\Cookies"
            New-BrowserDirectory (Split-Path $destCookies) | Out-Null
            
            Copy-Item $sourceCookies $destCookies -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored Cookies"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore Cookies - $_" "WARN"
        }
    }
    
    # Restore Reader/Offline Storage
    $sourceReaderData = Join-Path $browserBackup "Reader Data"
    if (Test-Path $sourceReaderData) {
        try {
            $destReaderData = Join-Path $Paths.ProfilePath "Default\Reader Data"
            New-BrowserDirectory (Split-Path $destReaderData) | Out-Null
            
            if (Test-Path $destReaderData) {
                Remove-Item $destReaderData -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            Copy-Item $sourceReaderData $destReaderData -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "$BrowserName: Restored Reader/Offline Storage"
        }
        catch {
            Write-Log "$BrowserName: Warning - Could not restore Reader Data - $_" "WARN"
        }
    }
}

function Restore-Firefox {
    param([string]$BackupRoot)
    
    $firefoxBackup = Join-Path $BackupRoot "Firefox"
    if (-not (Test-Path $firefoxBackup)) {
        Write-Log "Firefox: No backup found"
        return
    }
    
    if (-not (Confirm-Overwrite "Firefox")) {
        Write-Log "Firefox: Restore skipped by user"
        return
    }
    
    Write-Log "Starting restore for Firefox..."
    
    $profilePath = Join-Path $appDataRoaming "Mozilla\Firefox\Profiles"
    New-BrowserDirectory $profilePath | Out-Null
    
    try {
        # Restore profile directories
        $backupProfiles = Get-ChildItem -Path $firefoxBackup -Directory
        foreach ($profile in $backupProfiles) {
            $destProfile = Join-Path $profilePath $profile.Name
            
            # Create profile if it doesn't exist
            if (-not (Test-Path $destProfile)) {
                New-BrowserDirectory $destProfile | Out-Null
            }
            
            # Restore storage items
            $storageItems = @("storage", "cache2", "extensions")
            foreach ($item in $storageItems) {
                $sourcePath = Join-Path $profile.FullName $item
                $destPath = Join-Path $destProfile $item
                
                if (Test-Path $sourcePath) {
                    if (Test-Path $destPath) {
                        Remove-Item $destPath -Recurse -Force -ErrorAction SilentlyContinue
                    }
                    Copy-Item $sourcePath $destPath -Recurse -Force -ErrorAction SilentlyContinue
                }
            }
            
            # Restore prefs.js
            $sourcePrefs = Join-Path $profile.FullName "prefs.js"
            if (Test-Path $sourcePrefs) {
                Copy-Item $sourcePrefs (Join-Path $destProfile "prefs.js") -Force -ErrorAction SilentlyContinue
            }
            
            Write-Log "Firefox: Restored profile $($profile.Name)"
        }
    }
    catch {
        Write-Log "Firefox: Warning - Could not restore profiles - $_" "WARN"
    }
    
    # Restore extensions
    $sourceExtensions = Join-Path $firefoxBackup "Extensions"
    if (Test-Path $sourceExtensions) {
        try {
            $destExtensions = Join-Path $appDataRoaming "Mozilla\Firefox\Extensions"
            New-BrowserDirectory (Split-Path $destExtensions) | Out-Null
            
            if (Test-Path $destExtensions) {
                Remove-Item $destExtensions -Recurse -Force -ErrorAction SilentlyContinue
            }
            
            Copy-Item $sourceExtensions $destExtensions -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Firefox: Restored Extensions"
        }
        catch {
            Write-Log "Firefox: Warning - Could not restore Extensions - $_" "WARN"
        }
    }
}

# ============================================================================
# MAIN RESTORE LOGIC
# ============================================================================

Write-Host "Browser Data Restore Utility"
Write-Host "============================="
Write-Host "Backup Source: $BackupPath"
Write-Host ""

# Initialize log file
Write-Log "=== Browser Data Restore Started ===" "INFO"
Write-Log "Backup Source: $BackupPath" "INFO"
Write-Log "Overwrite Existing: $OverwriteExisting" "INFO"

# Check if backup has manifest
$manifestPath = Join-Path $BackupPath "BACKUP-MANIFEST.txt"
if (Test-Path $manifestPath) {
    Write-Host "Backup manifest found:"
    Get-Content $manifestPath | Select-Object -First 5 | ForEach-Object { Write-Host "  $_" }
    Write-Host ""
}

# Restore Chrome
if (Test-Path (Join-Path $BackupPath "Chrome")) {
    Restore-BrowserData -BrowserName "Chrome" -Paths $browserPaths.Chrome -BackupRoot $BackupPath
}

# Restore Edge
if (Test-Path (Join-Path $BackupPath "Edge")) {
    Restore-BrowserData -BrowserName "Edge" -Paths $browserPaths.Edge -BackupRoot $BackupPath
}

# Restore Brave
if (Test-Path (Join-Path $BackupPath "Brave")) {
    Restore-BrowserData -BrowserName "Brave" -Paths $browserPaths.Brave -BackupRoot $BackupPath
}

# Restore Firefox
if (Test-Path (Join-Path $BackupPath "Firefox")) {
    Restore-Firefox -BackupRoot $BackupPath
}

Write-Log "=== Browser Data Restore Completed ===" "INFO"

Write-Host ""
Write-Host "✅ Restore Complete!"
Write-Host "Log: $logFile"
Write-Host ""
Write-Host "⚠️  IMPORTANT: Please close all browser windows and restart them for changes to take effect."
Write-Host ""

# Display summary
Get-Content $logFile | Select-Object -Last 10 | ForEach-Object { Write-Host $_ }
