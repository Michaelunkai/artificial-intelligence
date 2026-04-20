# Windows Startup Configuration Restore Script
# Restores all Claude/OpenClaw/ClawdBot startup-related configuration
# Usage: powershell -ExecutionPolicy Bypass -File restore-startup-config.ps1 -BackupPath <path-to-backup>

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,
    [switch]$Verbose = $false,
    [switch]$DryRun = $false
)

# Initialize
$ErrorActionPreference = "Continue"
$RestoreLog = Join-Path $BackupPath "restore.log"
$BackupManifest = Join-Path $BackupPath "manifest.json"

# Validate backup path
if (-not (Test-Path $BackupPath)) {
    Write-Host "ERROR: Backup path not found: $BackupPath" -ForegroundColor Red
    exit 1
}

if (-not (Test-Path $BackupManifest)) {
    Write-Host "ERROR: Manifest not found: $BackupManifest" -ForegroundColor Red
    exit 1
}

# Load manifest
try {
    $manifest = Get-Content -Path $BackupManifest | ConvertFrom-Json
    Write-Host "Loaded backup from: $($manifest.timestamp)" -ForegroundColor Cyan
} catch {
    Write-Host "ERROR: Cannot parse manifest: $_" -ForegroundColor Red
    exit 1
}

# Logging function
function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "SUCCESS", "WARNING", "ERROR")]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Add-Content $RestoreLog $logMessage
    if ($Verbose) { Write-Host $logMessage }
}

Write-Log "========== RESTORE STARTED ==========" "INFO"
Write-Log "Dry Run: $DryRun" "INFO"

# Require admin
$currentUser = [Security.Principal.WindowsIdentity]::GetCurrent()
$principal = New-Object Security.Principal.WindowsPrincipal($currentUser)
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Log "ERROR: This script requires administrator privileges" "ERROR"
    Write-Host "ERROR: This script requires administrator privileges" -ForegroundColor Red
    exit 1
}

# =============================================================================
# 1. RESTORE SCHEDULED TASKS
# =============================================================================
Write-Log "Restoring Scheduled Tasks..." "INFO"
Write-Host ""
Write-Host "--- RESTORING SCHEDULED TASKS ---" -ForegroundColor Cyan

$tasksBackupDir = Join-Path $BackupPath "scheduled_tasks"
$restoredTasks = 0

if (Test-Path $tasksBackupDir) {
    $taskFiles = Get-ChildItem -Path $tasksBackupDir -Filter "*.xml" -ErrorAction SilentlyContinue
    
    foreach ($taskFile in $taskFiles) {
        try {
            $taskXml = [xml](Get-Content -Path $taskFile.FullName)
            $taskName = $taskFile.BaseName -replace '_', '\'
            
            if ($DryRun) {
                Write-Log "  [DRY RUN] Would import task: $taskName" "INFO"
                Write-Host "  [DRY RUN] Would import task: $taskName" -ForegroundColor Yellow
            } else {
                # Check if task exists and remove it
                try {
                    $existingTask = Get-ScheduledTask -TaskName (Split-Path -Leaf $taskName) -ErrorAction SilentlyContinue
                    if ($existingTask) {
                        Unregister-ScheduledTask -TaskName (Split-Path -Leaf $taskName) -Confirm:$false -ErrorAction SilentlyContinue
                        Write-Log "  Removed existing task: $taskName" "INFO"
                    }
                } catch {}
                
                # Import new task
                Register-ScheduledTask -Xml $taskXml.OuterXml -TaskName $taskName -Force -ErrorAction Stop
                Write-Log "  ✓ Task imported: $taskName" "SUCCESS"
                Write-Host "  ✓ Task imported: $taskName" -ForegroundColor Green
                $restoredTasks++
            }
        } catch {
            Write-Log "  ✗ Failed to import task $($taskFile.Name): $_" "ERROR"
            Write-Host "  ✗ Failed to import task $($taskFile.Name): $_" -ForegroundColor Red
        }
    }
}

Write-Log "Total tasks restored: $restoredTasks" "INFO"

# =============================================================================
# 2. RESTORE STARTUP FOLDER SHORTCUTS
# =============================================================================
Write-Log "Restoring Startup Folder Shortcuts..." "INFO"
Write-Host ""
Write-Host "--- RESTORING STARTUP SHORTCUTS ---" -ForegroundColor Cyan

$startupBackupDir = Join-Path $BackupPath "startup_folder"
$startupFolder = "C:\Users\micha\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
$restoredShortcuts = 0

if (Test-Path $startupBackupDir) {
    $shortcuts = Get-ChildItem -Path $startupBackupDir -Filter "*.lnk" -ErrorAction SilentlyContinue
    
    foreach ($shortcut in $shortcuts) {
        try {
            $destPath = Join-Path $startupFolder $shortcut.Name
            
            if ($DryRun) {
                Write-Log "  [DRY RUN] Would restore shortcut: $($shortcut.Name)" "INFO"
                Write-Host "  [DRY RUN] Would restore shortcut: $($shortcut.Name)" -ForegroundColor Yellow
            } else {
                New-Item -ItemType Directory -Force -Path $startupFolder | Out-Null
                Copy-Item -Path $shortcut.FullName -Destination $destPath -Force
                Write-Log "  ✓ Shortcut restored: $($shortcut.Name)" "SUCCESS"
                Write-Host "  ✓ Shortcut restored: $($shortcut.Name)" -ForegroundColor Green
                $restoredShortcuts++
            }
        } catch {
            Write-Log "  ✗ Failed to restore shortcut $($shortcut.Name): $_" "ERROR"
            Write-Host "  ✗ Failed to restore shortcut $($shortcut.Name): $_" -ForegroundColor Red
        }
    }
}

Write-Log "Total shortcuts restored: $restoredShortcuts" "INFO"

# =============================================================================
# 3. RESTORE REGISTRY ENTRIES
# =============================================================================
Write-Log "Restoring Registry Entries..." "INFO"
Write-Host ""
Write-Host "--- RESTORING REGISTRY ENTRIES ---" -ForegroundColor Cyan

$registryBackupDir = Join-Path $BackupPath "registry"
$restoredRegistry = 0

if (Test-Path $registryBackupDir) {
    $regFiles = Get-ChildItem -Path $registryBackupDir -Filter "*.reg" -ErrorAction SilentlyContinue
    
    foreach ($regFile in $regFiles) {
        try {
            if ($DryRun) {
                Write-Log "  [DRY RUN] Would import registry from: $($regFile.Name)" "INFO"
                Write-Host "  [DRY RUN] Would import registry from: $($regFile.Name)" -ForegroundColor Yellow
            } else {
                reg import $regFile.FullName /reg:32 2>$null
                Write-Log "  ✓ Registry imported: $($regFile.Name)" "SUCCESS"
                Write-Host "  ✓ Registry imported: $($regFile.Name)" -ForegroundColor Green
                $restoredRegistry++
            }
        } catch {
            Write-Log "  ✗ Failed to import registry $($regFile.Name): $_" "ERROR"
            Write-Host "  ✗ Failed to import registry $($regFile.Name): $_" -ForegroundColor Red
        }
    }
}

Write-Log "Total registry files restored: $restoredRegistry" "INFO"

# =============================================================================
# 4. RESTORE WINDOWS SERVICES
# =============================================================================
Write-Log "Restoring Windows Services..." "INFO"
Write-Host ""
Write-Host "--- RESTORING WINDOWS SERVICES ---" -ForegroundColor Cyan

$servicesBackupDir = Join-Path $BackupPath "services"
$restoredServices = 0

if ($manifest.sections.services -and $manifest.sections.services.services.Count -gt 0) {
    foreach ($service in $manifest.sections.services.services) {
        try {
            $serviceName = $service.name
            $existingService = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
            
            if ($existingService) {
                if ($DryRun) {
                    Write-Log "  [DRY RUN] Would update service: $($service.displayName)" "INFO"
                    Write-Host "  [DRY RUN] Would update service: $($service.displayName)" -ForegroundColor Yellow
                } else {
                    # Set service startup type
                    $startTypeMap = @{
                        "Auto" = "Automatic"
                        "Manual" = "Manual"
                        "Disabled" = "Disabled"
                        "Automatic" = "Automatic"
                    }
                    
                    $startType = $startTypeMap[$service.startType]
                    if (-not $startType) { $startType = "Manual" }
                    
                    Set-Service -Name $serviceName -StartupType $startType -ErrorAction SilentlyContinue
                    
                    # Start service if it was running
                    if ($service.status -eq "Running" -and $startType -ne "Disabled") {
                        Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                    }
                    
                    Write-Log "  ✓ Service configured: $($service.displayName) (StartType: $startType)" "SUCCESS"
                    Write-Host "  ✓ Service configured: $($service.displayName) (StartType: $startType)" -ForegroundColor Green
                    $restoredServices++
                }
            } else {
                Write-Log "  ⚠ Service not found: $serviceName" "WARNING"
                Write-Host "  ⚠ Service not found: $serviceName" -ForegroundColor Yellow
            }
        } catch {
            Write-Log "  ✗ Failed to restore service $($service.displayName): $_" "ERROR"
            Write-Host "  ✗ Failed to restore service $($service.displayName): $_" -ForegroundColor Red
        }
    }
}

Write-Log "Total services configured: $restoredServices" "INFO"

# =============================================================================
# 5. RESTORE FIREWALL RULES
# =============================================================================
Write-Log "Restoring Firewall Rules..." "INFO"
Write-Host ""
Write-Host "--- RESTORING FIREWALL RULES ---" -ForegroundColor Cyan

$restoredRules = 0

if ($manifest.sections.firewall_rules -and $manifest.sections.firewall_rules.rules.Count -gt 0) {
    foreach ($rule in $manifest.sections.firewall_rules.rules) {
        try {
            $ruleName = $rule.name
            $existingRule = Get-NetFirewallRule -DisplayName $ruleName -ErrorAction SilentlyContinue
            
            if ($DryRun) {
                Write-Log "  [DRY RUN] Would restore firewall rule: $ruleName" "INFO"
                Write-Host "  [DRY RUN] Would restore firewall rule: $ruleName" -ForegroundColor Yellow
            } else {
                if ($existingRule) {
                    # Remove existing rule
                    Remove-NetFirewallRule -DisplayName $ruleName -Confirm:$false -ErrorAction SilentlyContinue
                }
                
                # Create new rule with the same properties
                $newRule = New-NetFirewallRule `
                    -DisplayName $ruleName `
                    -Direction $rule.direction `
                    -Action $rule.action `
                    -Enabled $rule.enabled `
                    -Profile $rule.profile `
                    -ErrorAction SilentlyContinue
                
                if ($newRule) {
                    Write-Log "  ✓ Firewall rule restored: $ruleName" "SUCCESS"
                    Write-Host "  ✓ Firewall rule restored: $ruleName" -ForegroundColor Green
                    $restoredRules++
                }
            }
        } catch {
            Write-Log "  ✗ Failed to restore firewall rule $($rule.name): $_" "ERROR"
            Write-Host "  ✗ Failed to restore firewall rule $($rule.name): $_" -ForegroundColor Red
        }
    }
}

Write-Log "Total firewall rules restored: $restoredRules" "INFO"

# =============================================================================
# 6. VALIDATION
# =============================================================================
Write-Log "Validating Restoration..." "INFO"
Write-Host ""
Write-Host "--- VALIDATION ---" -ForegroundColor Cyan

$validationResults = @{
    tasksOK = 0
    shortcutsOK = 0
    registryOK = 0
    servicesOK = 0
    rulesOK = 0
}

# Validate tasks
if ($manifest.sections.scheduled_tasks) {
    foreach ($task in $manifest.sections.scheduled_tasks.tasks) {
        $taskNameOnly = Split-Path -Leaf $task.name
        try {
            $restored = Get-ScheduledTask -TaskName $taskNameOnly -ErrorAction SilentlyContinue
            if ($restored) {
                $validationResults.tasksOK++
                Write-Log "  ✓ Validated task: $($task.name)" "SUCCESS"
                Write-Host "  ✓ Validated task: $($task.name)" -ForegroundColor Green
            }
        } catch {}
    }
}

# Validate shortcuts
if ($manifest.sections.startup_shortcuts) {
    foreach ($shortcut in $manifest.sections.startup_shortcuts.shortcuts) {
        $shortcutPath = Join-Path $startupFolder $shortcut.name
        if (Test-Path $shortcutPath) {
            $validationResults.shortcutsOK++
            Write-Log "  ✓ Validated shortcut: $($shortcut.name)" "SUCCESS"
            Write-Host "  ✓ Validated shortcut: $($shortcut.name)" -ForegroundColor Green
        }
    }
}

# Validate services
if ($manifest.sections.services) {
    foreach ($service in $manifest.sections.services.services) {
        try {
            $svc = Get-Service -Name $service.name -ErrorAction SilentlyContinue
            if ($svc) {
                $validationResults.servicesOK++
                Write-Log "  ✓ Validated service: $($service.displayName)" "SUCCESS"
                Write-Host "  ✓ Validated service: $($service.displayName)" -ForegroundColor Green
            }
        } catch {}
    }
}

# Validate firewall rules
if ($manifest.sections.firewall_rules) {
    foreach ($rule in $manifest.sections.firewall_rules.rules) {
        try {
            $fwRule = Get-NetFirewallRule -DisplayName $rule.name -ErrorAction SilentlyContinue
            if ($fwRule) {
                $validationResults.rulesOK++
                Write-Log "  ✓ Validated firewall rule: $($rule.name)" "SUCCESS"
                Write-Host "  ✓ Validated firewall rule: $($rule.name)" -ForegroundColor Green
            }
        } catch {}
    }
}

Write-Log "========== RESTORE COMPLETED ==========" "SUCCESS"

# Summary
Write-Host ""
Write-Host "======================================" -ForegroundColor Green
Write-Host "RESTORE SUMMARY" -ForegroundColor Green
Write-Host "======================================" -ForegroundColor Green
Write-Host "Dry Run: $DryRun" -ForegroundColor Yellow
Write-Host "Tasks Restored: $restoredTasks (Validated: $($validationResults.tasksOK))" -ForegroundColor Yellow
Write-Host "Shortcuts Restored: $restoredShortcuts (Validated: $($validationResults.shortcutsOK))" -ForegroundColor Yellow
Write-Host "Registry Entries Restored: $restoredRegistry" -ForegroundColor Yellow
Write-Host "Services Configured: $restoredServices (Validated: $($validationResults.servicesOK))" -ForegroundColor Yellow
Write-Host "Firewall Rules Restored: $restoredRules (Validated: $($validationResults.rulesOK))" -ForegroundColor Yellow
Write-Host "Log: $RestoreLog" -ForegroundColor Cyan
Write-Host "======================================" -ForegroundColor Green

if ($DryRun) {
    Write-Host ""
    Write-Host "⚠ DRY RUN MODE - No changes were made." -ForegroundColor Yellow
    Write-Host "Run without -DryRun flag to perform actual restore." -ForegroundColor Yellow
}

exit 0
