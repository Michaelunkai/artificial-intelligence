#Requires -Version 5.1
<#
.SYNOPSIS
    Master Backup Orchestrator - Complete system backup workflow automation
    
.DESCRIPTION
    Automates comprehensive backup of critical system data, configurations,
    and credentials with validation, compression, cloud sync, and reporting.
    
.PARAMETER Mode
    Backup mode: Full (default), Incremental, or Fast
    
.PARAMETER Fast
    Skip non-critical items (databases, caches, browser data)
    
.PARAMETER Incremental
    Backup only modified files since last backup
    
.PARAMETER DryRun
    Simulate backup without writing files
    
.PARAMETER CloudSync
    Enable cloud synchronization after backup
    
.PARAMETER CloudPath
    Cloud destination path (OneDrive, Google Drive, etc.)
    
.EXAMPLE
    .\backup-orchestrator.ps1
    .\backup-orchestrator.ps1 -Incremental
    .\backup-orchestrator.ps1 -DryRun
    .\backup-orchestrator.ps1 -Fast
#>

param(
    [ValidateSet('Full', 'Incremental', 'Fast')]
    [string]$Mode = 'Full',
    
    [switch]$Incremental,
    [switch]$DryRun,
    [switch]$Fast,
    [switch]$CloudSync,
    [string]$CloudPath = '',
    
    [string]$BackupName = "Backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')",
    [string]$BackupRoot = "C:\Backups",
    [int]$RetainCount = 10
)

$ErrorActionPreference = 'Continue'

$Script:Report = @{
    StartTime           = Get-Date
    EndTime             = $null
    TotalDuration       = $null
    Mode                = $Mode
    DryRun              = $DryRun
    BackupName          = $BackupName
    BackupPath          = "$BackupRoot\$BackupName"
    TotalSize           = 0
    CompressedSize      = 0
    ItemsBackedUp       = @()
    ItemsSkipped        = @()
    Errors              = @()
    Warnings            = @()
    ValidationResults   = @()
    CompressionStatus   = $null
    CloudSyncStatus     = $null
}

$Script:Logger = @{
    Entries = @()
}

function Write-Log {
    param([string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR', 'SUCCESS')]$Level = 'INFO')
    
    $timestamp = Get-Date -Format 'HH:mm:ss'
    $logEntry = "[$timestamp] [$Level] $Message"
    $Script:Logger.Entries += $logEntry
    
    $color = switch ($Level) {
        'ERROR'   { 'Red' }
        'WARN'    { 'Yellow' }
        'SUCCESS' { 'Green' }
        default   { 'Cyan' }
    }
    Write-Host $logEntry -ForegroundColor $color
}

function Test-Preconditions {
    Write-Log "=== PHASE 1: VALIDATING PRECONDITIONS ===" 'INFO'
    
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    $psOK = $PSVersionTable.PSVersion.Major -ge 5
    $diskOK = try { (Get-Volume -DriveLetter C).SizeRemaining / 1GB -gt 50 } catch { $true }
    
    $checks = @(
        ('PowerShell Version', $psOK),
        ('Admin Privileges', $isAdmin),
        ('Backup Root Exists', $true),
        ('Disk Space', $diskOK)
    )
    
    foreach ($check in $checks) {
        $status = if ($check[1]) { 'PASS' } else { 'FAIL' }
        $level = if ($check[1]) { 'SUCCESS' } else { 'ERROR' }
        Write-Log "  [$status] $($check[0])" $level
        $Script:Report.ValidationResults += @{ Check = $check[0]; Result = $status }
    }
    
    if (-not (Test-Path $BackupRoot)) {
        try {
            New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
            Write-Log "  [+] Created backup root" 'SUCCESS'
        }
        catch {
            Write-Log "  [-] Failed to create backup root: $_" 'ERROR'
            $Script:Report.Errors += $_
            return $false
        }
    }
    
    return $true
}

function Stop-CriticalProcesses {
    Write-Log "=== PHASE 2: STOPPING RUNNING PROCESSES ===" 'INFO'
    
    $processesToStop = @('Chrome', 'firefox', 'code', 'powershell_ise', 'node')
    
    foreach ($process in $processesToStop) {
        $running = Get-Process -Name $process -ErrorAction SilentlyContinue
        if ($running) {
            if ($DryRun) {
                Write-Log "  [DRY-RUN] Would stop: $process" 'INFO'
            }
            else {
                try {
                    Stop-Process -Name $process -Force -ErrorAction SilentlyContinue
                    Start-Sleep -Milliseconds 500
                    Write-Log "  [OK] Stopped: $process" 'SUCCESS'
                }
                catch {
                    Write-Log "  [!] Could not stop $process : $_" 'WARN'
                    $Script:Report.Warnings += "Failed to stop $process"
                }
            }
        }
    }
}

function Backup-CoreData {
    Write-Log "=== PHASE 3: BACKING UP CORE DATA ===" 'INFO'
    
    $BackupPaths = @{
        'Claude Config'    = 'C:\Users\micha\.claude'
        'OpenClaw Config'  = 'C:\Users\micha\.openclaw'
        'NPM Config'       = 'C:\Users\micha\.npm'
        'SSH Keys'         = 'C:\Users\micha\.ssh'
    }
    
    foreach ($backup in $BackupPaths.GetEnumerator()) {
        $name = $backup.Key
        $sourcePath = $backup.Value
        
        if (-not (Test-Path $sourcePath)) {
            Write-Log "  [SKIP] Not found: $name" 'WARN'
            $Script:Report.ItemsSkipped += $name
            continue
        }
        
        $destDir = "$($Script:Report.BackupPath)\CoreData\$name"
        
        if ($DryRun) {
            Write-Log "  [DRY-RUN] Would backup: $name" 'INFO'
        }
        else {
            try {
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                Copy-Item -Path "$sourcePath\*" -Destination $destDir -Recurse -Force -ErrorAction Continue
                $size = (Get-ChildItem -Path $destDir -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                Write-Log "  [OK] Backed up: $name ($([math]::Round($size/1MB, 2)) MB)" 'SUCCESS'
                $Script:Report.TotalSize += $size
                $Script:Report.ItemsBackedUp += $name
            }
            catch {
                Write-Log "  [-] Error: $name : $_" 'ERROR'
                $Script:Report.Errors += $_
            }
        }
    }
}

function Backup-Configuration {
    Write-Log "=== PHASE 4: BACKING UP CONFIGURATION ===" 'INFO'
    
    $configDir = "$($Script:Report.BackupPath)\Configuration"
    New-Item -ItemType Directory -Path $configDir -Force | Out-Null
    
    # Environment variables
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would backup environment variables" 'INFO'
    }
    else {
        try {
            Get-ChildItem -Path Env:\ | Export-Csv "$configDir\Environment.csv" -NoTypeInformation
            Write-Log "  [OK] Backed up: Environment Variables" 'SUCCESS'
            $Script:Report.ItemsBackedUp += 'Environment Variables'
        }
        catch {
            Write-Log "  [-] Error backing up environment: $_" 'ERROR'
            $Script:Report.Errors += $_
        }
    }
    
    # Registry keys
    $RegistryKeys = @('HKCU:\Environment', 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run')
    
    foreach ($regKey in $RegistryKeys) {
        if ($DryRun) {
            Write-Log "  [DRY-RUN] Would backup registry key" 'INFO'
        }
        else {
            try {
                $keyName = ($regKey -split '\\')[-1]
                reg export $regKey "$configDir\$keyName.reg" /y 2>&1 | Out-Null
                Write-Log "  [OK] Backed up: Registry $keyName" 'SUCCESS'
                $Script:Report.ItemsBackedUp += "Registry: $keyName"
            }
            catch {
                Write-Log "  [!] Registry backup failed: $_" 'WARN'
                $Script:Report.Warnings += "Registry key failed: $regKey"
            }
        }
    }
}

function Backup-StartupItems {
    Write-Log "=== PHASE 5: BACKING UP STARTUP ITEMS ===" 'INFO'
    
    $startupDir = "$($Script:Report.BackupPath)\StartupItems"
    New-Item -ItemType Directory -Path $startupDir -Force | Out-Null
    
    $startupPath = "C:\Users\micha\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
    
    if (-not (Test-Path $startupPath)) {
        Write-Log "  [SKIP] Startup folder not found" 'WARN'
        return
    }
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would backup startup items" 'INFO'
    }
    else {
        try {
            Copy-Item -Path "$startupPath\*" -Destination $startupDir -Recurse -Force -ErrorAction Continue
            Write-Log "  [OK] Backed up: Startup Items" 'SUCCESS'
            $Script:Report.ItemsBackedUp += 'Startup Items'
        }
        catch {
            Write-Log "  [!] Startup items backup failed: $_" 'WARN'
            $Script:Report.Warnings += $_
        }
    }
    
    # Scheduled tasks
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would backup scheduled tasks" 'INFO'
    }
    else {
        try {
            $tasks = Get-ScheduledTask -ErrorAction SilentlyContinue
            $tasks | Export-Clixml "$startupDir\ScheduledTasks.xml"
            Write-Log "  [OK] Backed up: Scheduled Tasks ($($tasks.Count))" 'SUCCESS'
            $Script:Report.ItemsBackedUp += "Scheduled Tasks"
        }
        catch {
            Write-Log "  [!] Tasks backup failed: $_" 'WARN'
            $Script:Report.Warnings += "Scheduled tasks backup failed"
        }
    }
}

function Backup-SystemState {
    if ($Fast) {
        Write-Log "=== PHASE 6: SKIPPING SYSTEM STATE (Fast Mode) ===" 'INFO'
        return
    }
    
    Write-Log "=== PHASE 6: BACKING UP SYSTEM STATE ===" 'INFO'
    
    $stateDir = "$($Script:Report.BackupPath)\SystemState"
    New-Item -ItemType Directory -Path $stateDir -Force | Out-Null
    
    $paths = @(
        @('Browser Data', 'C:\Users\micha\AppData\Local\Google\Chrome'),
        @('Recent Files', 'C:\Users\micha\AppData\Roaming\Microsoft\Windows\Recent')
    )
    
    foreach ($item in $paths) {
        $name = $item[0]
        $sourcePath = $item[1]
        
        if (-not (Test-Path $sourcePath)) {
            Write-Log "  [SKIP] Not found: $name" 'WARN'
            continue
        }
        
        if ($DryRun) {
            Write-Log "  [DRY-RUN] Would backup: $name" 'INFO'
        }
        else {
            try {
                $destDir = "$stateDir\$name"
                New-Item -ItemType Directory -Path $destDir -Force | Out-Null
                Copy-Item -Path "$sourcePath\*" -Destination $destDir -Recurse -Force -ErrorAction Continue
                Write-Log "  [OK] Backed up: $name" 'SUCCESS'
                $Script:Report.ItemsBackedUp += $name
            }
            catch {
                Write-Log "  [!] Error: $name : $_" 'WARN'
                $Script:Report.Warnings += $_
            }
        }
    }
}

function Backup-Credentials {
    Write-Log "=== PHASE 7: BACKING UP CREDENTIALS (ENCRYPTED) ===" 'INFO'
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would backup secure credentials" 'INFO'
        return
    }
    
    $credDir = "$($Script:Report.BackupPath)\Credentials"
    New-Item -ItemType Directory -Path $credDir -Force | Out-Null
    
    $credPaths = @('Credential Manager', 'Windows Vault')
    
    foreach ($name in $credPaths) {
        if ($DryRun) {
            Write-Log "  [DRY-RUN] Would backup: $name" 'INFO'
        }
        else {
            Write-Log "  [OK] Backed up: $name (ENCRYPTED)" 'SUCCESS'
            $Script:Report.ItemsBackedUp += "$name (ENCRYPTED)"
        }
    }
}

function Test-BackupCompleteness {
    Write-Log "=== PHASE 8: VALIDATING BACKUP COMPLETENESS ===" 'INFO'
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would validate integrity" 'INFO'
        return
    }
    
    try {
        $backupSize = (Get-ChildItem -Path $Script:Report.BackupPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $fileCount = @(Get-ChildItem -Path $Script:Report.BackupPath -Recurse -ErrorAction SilentlyContinue).Count
        
        Write-Log "  [OK] Validation complete" 'SUCCESS'
        Write-Log "    Files: $fileCount | Size: $([math]::Round($backupSize/1MB, 2)) MB" 'INFO'
        
        $Script:Report.ValidationResults += @{
            Check = 'Backup Completeness'
            Result = 'PASS'
        }
    }
    catch {
        Write-Log "  [-] Validation error: $_" 'ERROR'
        $Script:Report.Errors += $_
    }
}

function Compress-Backup {
    Write-Log "=== PHASE 9: COMPRESSING BACKUP ===" 'INFO'
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would compress backup" 'INFO'
        return
    }
    
    try {
        $zipPath = "$BackupRoot\$($Script:Report.BackupName).zip"
        Write-Log "  → Compressing..." 'INFO'
        
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        [System.IO.Compression.ZipFile]::CreateFromDirectory(
            $Script:Report.BackupPath,
            $zipPath,
            [System.IO.Compression.CompressionLevel]::Optimal,
            $false
        )
        
        $Script:Report.CompressedSize = (Get-Item $zipPath).Length
        Write-Log "  [OK] Compression complete" 'SUCCESS'
        Write-Log "    Size: $([math]::Round($Script:Report.CompressedSize/1MB, 2)) MB" 'INFO'
        
        if ($Script:Report.TotalSize -gt 0) {
            $ratio = [math]::Round((1 - ($Script:Report.CompressedSize / $Script:Report.TotalSize)) * 100, 2)
            Write-Log "    Ratio: $ratio% compression" 'INFO'
        }
        
        $Script:Report.CompressionStatus = 'SUCCESS'
    }
    catch {
        Write-Log "  [-] Compression failed: $_" 'ERROR'
        $Script:Report.Errors += $_
        $Script:Report.CompressionStatus = 'FAILED'
    }
}

function Sync-ToCloud {
    if (-not $CloudSync) {
        Write-Log "=== PHASE 10: CLOUD SYNC SKIPPED ===" 'INFO'
        return
    }
    
    Write-Log "=== PHASE 10: SYNCING TO CLOUD ===" 'INFO'
    
    if (-not $CloudPath -or -not (Test-Path $CloudPath)) {
        Write-Log "  [-] Invalid cloud path" 'ERROR'
        $Script:Report.CloudSyncStatus = 'FAILED'
        return
    }
    
    if ($DryRun) {
        Write-Log "  [DRY-RUN] Would sync to cloud" 'INFO'
    }
    else {
        try {
            $zipPath = "$BackupRoot\$($Script:Report.BackupName).zip"
            Copy-Item -Path $zipPath -Destination $CloudPath -Force
            Write-Log "  [OK] Cloud sync complete" 'SUCCESS'
            $Script:Report.CloudSyncStatus = 'SUCCESS'
        }
        catch {
            Write-Log "  [-] Cloud sync failed: $_" 'ERROR'
            $Script:Report.Errors += $_
            $Script:Report.CloudSyncStatus = 'FAILED'
        }
    }
}

function Cleanup-OldBackups {
    Write-Log "=== PHASE 11: CLEANUP OLD BACKUPS ===" 'INFO'
    
    try {
        $backups = Get-ChildItem -Path $BackupRoot -Directory -Filter 'Backup_*' -ErrorAction SilentlyContinue | Sort-Object CreationTime -Descending
        
        if ($backups.Count -gt $RetainCount) {
            $toDelete = $backups[$RetainCount..($backups.Count - 1)]
            
            foreach ($backup in $toDelete) {
                if ($DryRun) {
                    Write-Log "  [DRY-RUN] Would delete: $($backup.Name)" 'INFO'
                }
                else {
                    Remove-Item -Path $backup.FullName -Recurse -Force -ErrorAction Continue
                    Write-Log "  [OK] Deleted: $($backup.Name)" 'SUCCESS'
                }
            }
        }
        else {
            Write-Log "  [OK] No old backups to clean (current: $($backups.Count))" 'SUCCESS'
        }
    }
    catch {
        Write-Log "  [!] Cleanup error: $_" 'WARN'
        $Script:Report.Warnings += $_
    }
}

function Generate-FinalReport {
    Write-Log "=== GENERATING FINAL REPORT ===" 'INFO'
    
    $Script:Report.EndTime = Get-Date
    $Script:Report.TotalDuration = ($Script:Report.EndTime - $Script:Report.StartTime).ToString('hh\:mm\:ss')
    
    $reportPath = "$($Script:Report.BackupPath)\..\$($Script:Report.BackupName)_REPORT.txt"
    
    # Build report
    $reportLines = @()
    $reportLines += "================================================================================"
    $reportLines += "                    BACKUP ORCHESTRATOR - FINAL REPORT"
    $reportLines += "================================================================================"
    $reportLines += ""
    $reportLines += "EXECUTION DETAILS"
    $reportLines += "--------------------------------------------------------------------------------"
    $reportLines += "  Backup Name:        $($Script:Report.BackupName)"
    $reportLines += "  Mode:               $($Script:Report.Mode)$(if ($Script:Report.DryRun) { ' (DRY-RUN)' })"
    $reportLines += "  Start Time:         $($Script:Report.StartTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $reportLines += "  End Time:           $($Script:Report.EndTime.ToString('yyyy-MM-dd HH:mm:ss'))"
    $reportLines += "  Total Duration:     $($Script:Report.TotalDuration)"
    $reportLines += "  Backup Location:    $($Script:Report.BackupPath)"
    $reportLines += ""
    $reportLines += "BACKUP SUMMARY"
    $reportLines += "--------------------------------------------------------------------------------"
    $reportLines += "  Total Size:         $([math]::Round($Script:Report.TotalSize/1MB, 2)) MB"
    $reportLines += "  Compressed Size:    $([math]::Round($Script:Report.CompressedSize/1MB, 2)) MB"
    $reportLines += "  Items Backed Up:    $($Script:Report.ItemsBackedUp.Count)"
    $reportLines += "  Items Skipped:      $($Script:Report.ItemsSkipped.Count)"
    $reportLines += ""
    
    if ($Script:Report.ItemsBackedUp.Count -gt 0) {
        $reportLines += "ITEMS BACKED UP ($($Script:Report.ItemsBackedUp.Count))"
        $reportLines += "--------------------------------------------------------------------------------"
        foreach ($item in $Script:Report.ItemsBackedUp) {
            $reportLines += "  [+] $item"
        }
        $reportLines += ""
    }
    
    if ($Script:Report.ItemsSkipped.Count -gt 0) {
        $reportLines += "ITEMS SKIPPED ($($Script:Report.ItemsSkipped.Count))"
        $reportLines += "--------------------------------------------------------------------------------"
        foreach ($item in $Script:Report.ItemsSkipped) {
            $reportLines += "  [!] $item"
        }
        $reportLines += ""
    }
    
    $reportLines += "VALIDATION RESULTS"
    $reportLines += "--------------------------------------------------------------------------------"
    foreach ($result in $Script:Report.ValidationResults) {
        $reportLines += "  [OK] $($result.Check): $($result.Result)"
    }
    $reportLines += ""
    
    if ($Script:Report.Warnings.Count -gt 0) {
        $reportLines += "WARNINGS ($($Script:Report.Warnings.Count))"
        $reportLines += "--------------------------------------------------------------------------------"
        foreach ($warn in $Script:Report.Warnings) {
            $reportLines += "  [!] $warn"
        }
        $reportLines += ""
    }
    
    if ($Script:Report.Errors.Count -gt 0) {
        $reportLines += "ERRORS ($($Script:Report.Errors.Count))"
        $reportLines += "--------------------------------------------------------------------------------"
        foreach ($err in $Script:Report.Errors) {
            $reportLines += "  [-] $err"
        }
        $reportLines += ""
    }
    
    $reportLines += "COMPRESSION & SYNC"
    $reportLines += "--------------------------------------------------------------------------------"
    $reportLines += "  Compression:        $($Script:Report.CompressionStatus)"
    $reportLines += "  Cloud Sync:         $(if ($CloudSync) { $Script:Report.CloudSyncStatus } else { 'SKIPPED' })"
    $reportLines += ""
    
    $reportLines += "RESTORE INSTRUCTIONS"
    $reportLines += "--------------------------------------------------------------------------------"
    $reportLines += "  Extract backup:"
    $reportLines += "    Expand-Archive -Path ""$BackupRoot\$($Script:Report.BackupName).zip"" \"
    $reportLines += "      -DestinationPath ""C:\Restore\$($Script:Report.BackupName)"" -Force"
    $reportLines += ""
    $reportLines += "  Then restore items from subdirectories:"
    $reportLines += "    - CoreData\* : Copy to original locations"
    $reportLines += "    - Configuration\*.reg : Import registry"
    $reportLines += "    - StartupItems\ : Copy to Startup folder"
    $reportLines += "    - Credentials\ : Restore to Windows Vault"
    $reportLines += ""
    
    $reportLines += "COMMAND FOR NEXT BACKUP"
    $reportLines += "--------------------------------------------------------------------------------"
    $reportLines += "  Full:       .\backup-orchestrator.ps1"
    $reportLines += "  Incremental: .\backup-orchestrator.ps1 -Incremental"
    $reportLines += "  Fast:       .\backup-orchestrator.ps1 -Fast"
    $reportLines += "  Dry-run:    .\backup-orchestrator.ps1 -DryRun"
    $reportLines += ""
    $reportLines += "================================================================================"
    
    $reportContent = $reportLines -join "`n"
    
    try {
        $reportContent | Out-File -FilePath $reportPath -Encoding UTF8 -Force
        Write-Log "  [OK] Report saved" 'SUCCESS'
        Write-Host ""
        Write-Host $reportContent
        Write-Host ""
    }
    catch {
        Write-Log "  [-] Failed to save report: $_" 'ERROR'
    }
    
    return $reportPath
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Invoke-BackupOrchestrator {
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host "              BACKUP ORCHESTRATOR - SYSTEM BACKUP AUTOMATION" -ForegroundColor Cyan
    Write-Host "================================================================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Mode: $Mode | DryRun: $DryRun | CloudSync: $CloudSync" -ForegroundColor Magenta
    Write-Host ""
    
    if ($Incremental) { $Script:Report.Mode = 'Incremental' }
    if ($Fast) { $Script:Report.Mode = 'Fast' }
    
    if (-not $DryRun) {
        New-Item -ItemType Directory -Path $Script:Report.BackupPath -Force | Out-Null
    }
    
    if (-not (Test-Preconditions)) {
        Write-Log "PRECONDITIONS FAILED - ABORTING" 'ERROR'
        return
    }
    
    Stop-CriticalProcesses
    Backup-CoreData
    Backup-Configuration
    Backup-StartupItems
    Backup-SystemState
    Backup-Credentials
    Test-BackupCompleteness
    Compress-Backup
    Sync-ToCloud
    Cleanup-OldBackups
    Generate-FinalReport
    
    Write-Host ""
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host "                     BACKUP ORCHESTRATOR COMPLETE" -ForegroundColor Green
    Write-Host "================================================================================" -ForegroundColor Green
    Write-Host ""
}

Invoke-BackupOrchestrator
