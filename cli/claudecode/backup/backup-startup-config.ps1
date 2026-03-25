# Windows Startup Configuration Backup Script
# Backs up all Claude/OpenClaw/ClawdBot startup-related configuration
# Usage: powershell -ExecutionPolicy Bypass -File backup-startup-config.ps1

param(
    [string]$BackupPath = "C:\Users\micha\.openclaw\startup_backup",
    [switch]$Verbose = $false
)

# Initialize
$ErrorActionPreference = "Continue"
$BackupTimestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$BackupDir = Join-Path $BackupPath $BackupTimestamp
$BackupLog = Join-Path $BackupDir "backup.log"
$BackupManifest = Join-Path $BackupDir "manifest.json"

# Create backup directory
try {
    New-Item -ItemType Directory -Force -Path $BackupDir | Out-Null
} catch {
    Write-Host "ERROR: Cannot create backup directory: $_" -ForegroundColor Red
    exit 1
}

# Logging function
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content $BackupLog $logMessage
    if ($Verbose) { Write-Host $logMessage }
}

Write-Log "========== BACKUP STARTED ==========" "INFO"
Write-Log "Backup destination: $BackupDir" "INFO"

# Initialize manifest
$manifest = @{
    timestamp = $BackupTimestamp
    computer = $env:COMPUTERNAME
    user = $env:USERNAME
    sections = @{}
}

# =============================================================================
# 1. SCHEDULED TASKS
# =============================================================================
Write-Log "Backing up Scheduled Tasks..." "INFO"
$tasksBackupDir = Join-Path $BackupDir "scheduled_tasks"
New-Item -ItemType Directory -Force -Path $tasksBackupDir | Out-Null

$keywords = @("Claude", "OpenClaw", "ClawdBot", "moltbot", "openclaw", "claude")
$backedupTasks = @()

try {
    Get-ScheduledTask | ForEach-Object {
        $taskName = $_.TaskName
        $taskPath = $_.TaskPath
        $taskFullPath = "$taskPath$taskName"
        
        # Check if task matches keywords
        $matches = $false
        foreach ($keyword in $keywords) {
            if ($taskFullPath -like "*$keyword*") {
                $matches = $true
                break
            }
        }
        
        if ($matches) {
            try {
                $taskXml = Export-ScheduledTask -TaskName $taskName -TaskPath $taskPath
                $fileName = ($taskFullPath -replace '\\', '_' -replace '/', '_' -replace ':', '') + ".xml"
                $filePath = Join-Path $tasksBackupDir $fileName
                $taskXml | Out-File -FilePath $filePath -Encoding UTF8
                $backedupTasks += @{
                    name = $taskFullPath
                    file = $fileName
                }
                Write-Log "  ✓ Task: $taskFullPath" "SUCCESS"
            } catch {
                Write-Log "  ✗ Task: $taskFullPath - Error: $_" "WARNING"
            }
        }
    }
} catch {
    Write-Log "Error enumerating scheduled tasks: $_" "ERROR"
}

$manifest.sections.scheduled_tasks = @{
    count = $backedupTasks.Count
    tasks = $backedupTasks
}

Write-Log "Total tasks backed up: $($backedupTasks.Count)" "INFO"

# =============================================================================
# 2. STARTUP FOLDER SHORTCUTS
# =============================================================================
Write-Log "Backing up Startup Folder Shortcuts..." "INFO"
$startupBackupDir = Join-Path $BackupDir "startup_folder"
$startupFolders = @(
    "C:\Users\micha\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup",
    "C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
)

$backedupShortcuts = @()

foreach ($startupFolder in $startupFolders) {
    if (Test-Path $startupFolder) {
        try {
            $shortcuts = Get-ChildItem -Path $startupFolder -Filter "*.lnk" -ErrorAction SilentlyContinue
            
            foreach ($shortcut in $shortcuts) {
                # Copy shortcut and extract target
                $fileName = $shortcut.Name
                $filePath = Join-Path $startupBackupDir $fileName
                
                New-Item -ItemType Directory -Force -Path $startupBackupDir | Out-Null
                Copy-Item -Path $shortcut.FullName -Destination $filePath -Force
                
                # Get shortcut target info
                $shell = New-Object -ComObject WScript.Shell
                $shortcutObj = $shell.CreateShortCut($shortcut.FullName)
                
                $backedupShortcuts += @{
                    name = $fileName
                    target = $shortcutObj.TargetPath
                    arguments = $shortcutObj.Arguments
                    workingDirectory = $shortcutObj.WorkingDirectory
                }
                
                Write-Log "  ✓ Shortcut: $fileName -> $($shortcutObj.TargetPath)" "SUCCESS"
            }
        } catch {
            Write-Log "  Error processing folder $startupFolder`: $_" "WARNING"
        }
    }
}

$manifest.sections.startup_shortcuts = @{
    count = $backedupShortcuts.Count
    shortcuts = $backedupShortcuts
}

Write-Log "Total shortcuts backed up: $($backedupShortcuts.Count)" "INFO"

# =============================================================================
# 3. REGISTRY STARTUP ENTRIES
# =============================================================================
Write-Log "Backing up Registry Startup Entries..." "INFO"
$registryBackupDir = Join-Path $BackupDir "registry"
New-Item -ItemType Directory -Force -Path $registryBackupDir | Out-Null

$registryBackup = @()
$regPaths = @(
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
    "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
)

foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        try {
            $entries = Get-ItemProperty -Path $regPath
            
            foreach ($property in $entries.PSObject.Properties) {
                if ($property.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider")) {
                    $value = $property.Value
                    
                    # Check if it matches our keywords
                    $matches = $false
                    foreach ($keyword in $keywords) {
                        if ($value -like "*$keyword*" -or $property.Name -like "*$keyword*") {
                            $matches = $true
                            break
                        }
                    }
                    
                    if ($matches) {
                        $registryBackup += @{
                            path = $regPath
                            name = $property.Name
                            value = $value
                        }
                        Write-Log "  ✓ Registry: $($property.Name) = $value" "SUCCESS"
                    }
                }
            }
        } catch {
            Write-Log "  Error reading registry path $regPath`: $_" "WARNING"
        }
    }
}

# Export registry hives as .reg files
foreach ($regPath in $regPaths) {
    if (Test-Path $regPath) {
        try {
            $regName = ($regPath -replace ":", "" -replace "\\", "_")
            $regFile = Join-Path $registryBackupDir "$regName.reg"
            reg export $regPath $regFile /y 2>$null | Out-Null
            Write-Log "  ✓ Registry export: $regName.reg" "SUCCESS"
        } catch {
            Write-Log "  Error exporting registry: $_" "WARNING"
        }
    }
}

$manifest.sections.registry = @{
    count = $registryBackup.Count
    entries = $registryBackup
}

Write-Log "Total registry entries backed up: $($registryBackup.Count)" "INFO"

# =============================================================================
# 4. WINDOWS SERVICES
# =============================================================================
Write-Log "Backing up Windows Services..." "INFO"
$servicesBackupDir = Join-Path $BackupDir "services"
New-Item -ItemType Directory -Force -Path $servicesBackupDir | Out-Null

$backedupServices = @()

try {
    Get-Service | ForEach-Object {
        $serviceName = $_.Name
        $serviceDisplayName = $_.DisplayName
        
        # Check if service matches keywords
        $matches = $false
        foreach ($keyword in $keywords) {
            if ($serviceName -like "*$keyword*" -or $serviceDisplayName -like "*$keyword*") {
                $matches = $true
                break
            }
        }
        
        if ($matches) {
            try {
                $serviceInfo = Get-WmiObject -Class Win32_Service -Filter "Name='$serviceName'"
                if ($serviceInfo) {
                    $backedupServices += @{
                        name = $serviceName
                        displayName = $serviceDisplayName
                        status = $_.Status
                        startType = $serviceInfo.StartMode
                        path = $serviceInfo.PathName
                        description = $serviceInfo.Description
                    }
                    Write-Log "  ✓ Service: $serviceDisplayName ($serviceName)" "SUCCESS"
                }
            } catch {
                Write-Log "  ✗ Service: $serviceName - Error: $_" "WARNING"
            }
        }
    }
} catch {
    Write-Log "Error enumerating services: $_" "ERROR"
}

$manifest.sections.services = @{
    count = $backedupServices.Count
    services = $backedupServices
}

Write-Log "Total services backed up: $($backedupServices.Count)" "INFO"

# =============================================================================
# 5. FIREWALL RULES
# =============================================================================
Write-Log "Backing up Firewall Rules..." "INFO"
$firewallBackupDir = Join-Path $BackupDir "firewall"
New-Item -ItemType Directory -Force -Path $firewallBackupDir | Out-Null

$backedupRules = @()

try {
    Get-NetFirewallRule | ForEach-Object {
        $ruleName = $_.DisplayName
        $rulePath = $_.Name
        
        # Check if rule matches keywords
        $matches = $false
        foreach ($keyword in $keywords) {
            if ($ruleName -like "*$keyword*" -or $rulePath -like "*$keyword*") {
                $matches = $true
                break
            }
        }
        
        if ($matches) {
            try {
                $ruleDetails = Get-NetFirewallRule -Name $_.Name | Get-NetFirewallPortFilter
                
                $backedupRules += @{
                    name = $ruleName
                    displayName = $ruleName
                    enabled = $_.Enabled
                    direction = $_.Direction
                    action = $_.Action
                    profile = $_.Profile
                }
                Write-Log "  ✓ Firewall rule: $ruleName" "SUCCESS"
            } catch {
                Write-Log "  ✗ Firewall rule: $ruleName - Error: $_" "WARNING"
            }
        }
    }
} catch {
    Write-Log "Error enumerating firewall rules: $_" "ERROR"
}

$manifest.sections.firewall_rules = @{
    count = $backedupRules.Count
    rules = $backedupRules
}

Write-Log "Total firewall rules backed up: $($backedupRules.Count)" "INFO"

# =============================================================================
# 6. SAVE MANIFEST
# =============================================================================
$manifest | ConvertTo-Json -Depth 5 | Out-File -FilePath $BackupManifest -Encoding UTF8

Write-Log "Manifest saved to: $BackupManifest" "SUCCESS"
Write-Log "========== BACKUP COMPLETED ==========" "SUCCESS"

# Summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "BACKUP SUMMARY" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "Location: $BackupDir" -ForegroundColor Cyan
Write-Host "Scheduled Tasks: $($backedupTasks.Count)" -ForegroundColor Yellow
Write-Host "Startup Shortcuts: $($backedupShortcuts.Count)" -ForegroundColor Yellow
Write-Host "Registry Entries: $($registryBackup.Count)" -ForegroundColor Yellow
Write-Host "Windows Services: $($backedupServices.Count)" -ForegroundColor Yellow
Write-Host "Firewall Rules: $($backedupRules.Count)" -ForegroundColor Yellow
Write-Host "Log: $BackupLog" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Green

exit 0
