#Requires -Version 5.1
<#
.SYNOPSIS
    Integration helper for backup-sync-cloud.ps1
.DESCRIPTION
    Provides easy-to-use functions for calling the sync utility from other scripts.
.EXAMPLES
    Sync-BackupToCloud -Verify -Resume
    Sync-BackupToCloud -Provider s3 -Cleanup
    Sync-BackupToCloud -Verify
#>

param()

# ============================================================================
# CONFIGURATION
# ============================================================================

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$SyncScript = Join-Path $ScriptRoot "backup-sync-cloud.ps1"

# ============================================================================
# PUBLIC FUNCTIONS
# ============================================================================

function Sync-BackupToCloud {
    <#
    .SYNOPSIS
        Sync latest backup to configured cloud providers
    .PARAMETER Provider
        Target provider: onedrive, gdrive, s3, smb, or all
    .PARAMETER BackupPath
        Specific backup file to sync (auto-detect if not specified)
    .PARAMETER Resume
        Resume interrupted upload from last known position
    .PARAMETER Verify
        Verify backup integrity before syncing
    .PARAMETER Cleanup
        Remove old backups from cloud based on retention policy
    .PARAMETER DryRun
        Preview sync without uploading
    #>
    
    param(
        [ValidateSet('onedrive', 'gdrive', 's3', 'smb')]
        [string]$Provider,
        
        [string]$BackupPath,
        
        [switch]$Resume,
        [switch]$Verify,
        [switch]$Cleanup,
        [switch]$DryRun,
        [switch]$Wait
    )
    
    $args = @{}
    
    if ($Provider) { $args['CloudProvider'] = $Provider }
    if ($BackupPath) { $args['BackupPath'] = $BackupPath }
    if ($Resume) { $args['Resume'] = $true }
    if ($Cleanup) { $args['Cleanup'] = $true }
    if ($DryRun) { $args['DryRun'] = $true }
    
    if ($Verify) {
        $args['VerifyOnly'] = $true
    }
    
    Write-Host "Syncing backup to cloud..." -ForegroundColor Cyan
    
    $job = Start-Job -FilePath $SyncScript -ArgumentList $args
    
    if ($Wait) {
        $job | Wait-Job | Receive-Job
        Remove-Job $job
    }
    else {
        return $job
    }
}

function Test-BackupIntegrity {
    <#
    .SYNOPSIS
        Verify backup file integrity
    .PARAMETER Path
        Path to backup file to verify
    #>
    
    param([Parameter(Mandatory = $true)][string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Error "Backup file not found: $Path"
        return $false
    }
    
    Write-Host "Verifying backup integrity..." -ForegroundColor Yellow
    
    $job = Start-Job -FilePath $SyncScript -ArgumentList @{
        BackupPath  = $Path
        VerifyOnly  = $true
    }
    
    $job | Wait-Job | Receive-Job
    Remove-Job $job
}

function Get-BackupSyncStatus {
    <#
    .SYNOPSIS
        Get status of current or recent sync operations
    #>
    
    $logDir = Join-Path $ScriptRoot "logs"
    $stateDir = Join-Path $ScriptRoot "state"
    
    $status = @{
        LatestLog         = $null
        InProgress        = $false
        LastChecksumCache = $null
    }
    
    if (Test-Path $logDir) {
        $latestLog = Get-ChildItem -Path $logDir -Filter "*.log" | 
                     Sort-Object -Property LastWriteTime -Descending | 
                     Select-Object -First 1
        
        if ($latestLog) {
            $status.LatestLog = @{
                Path     = $latestLog.FullName
                Modified = $latestLog.LastWriteTime
                Content  = (Get-Content -Path $latestLog.FullName -Tail 10)
            }
        }
    }
    
    $progressFile = Join-Path $stateDir "sync-progress.json"
    if (Test-Path $progressFile) {
        try {
            $progress = Get-Content $progressFile -Raw | ConvertFrom-Json
            $status.InProgress = $progress.status -eq 'in_progress'
        }
        catch {}
    }
    
    return $status
}

function Invoke-CloudSync {
    <#
    .SYNOPSIS
        High-level wrapper for backup sync
    .EXAMPLE
        Invoke-CloudSync -Provider s3 -Cleanup -Wait
    #>
    
    param(
        [ValidateSet('onedrive', 'gdrive', 's3', 'smb')]
        [string]$Provider,
        
        [switch]$Resume,
        [switch]$Cleanup,
        [switch]$DryRun,
        [switch]$Wait
    )
    
    Sync-BackupToCloud @PSBoundParameters
}

function Get-LatestBackupFile {
    <#
    .SYNOPSIS
        Find the latest backup file in the configured backup path
    #>
    
    try {
        $config = Get-Content (Join-Path $ScriptRoot "backup-sync-cloud.json") -Raw | ConvertFrom-Json
        $backupPath = $config.backup_path
        
        if (-not (Test-Path $backupPath)) {
            Write-Warning "Backup path not found: $backupPath"
            return $null
        }
        
        $latest = Get-ChildItem -Path $backupPath -File -Include '*.bak', '*.zip', '*.7z', '*.tar.gz' |
                  Sort-Object -Property LastWriteTime -Descending |
                  Select-Object -First 1
        
        return $latest
    }
    catch {
        Write-Error "Failed to get latest backup: $_"
        return $null
    }
}

function Get-SyncConfiguration {
    <#
    .SYNOPSIS
        Get current sync configuration
    #>
    
    try {
        $configPath = Join-Path $ScriptRoot "backup-sync-cloud.json"
        if (Test-Path $configPath) {
            Get-Content $configPath -Raw | ConvertFrom-Json
        }
        else {
            Write-Warning "Configuration file not found: $configPath"
        }
    }
    catch {
        Write-Error "Failed to load configuration: $_"
    }
}

function Set-SyncConfiguration {
    <#
    .SYNOPSIS
        Update sync configuration
    .EXAMPLE
        $config = Get-SyncConfiguration
        $config.max_bandwidth_mbps = 100
        Set-SyncConfiguration $config
    #>
    
    param([Parameter(Mandatory = $true)]$Config)
    
    try {
        $configPath = Join-Path $ScriptRoot "backup-sync-cloud.json"
        $Config | ConvertTo-Json -Depth 10 | Set-Content $configPath
        Write-Host "Configuration updated" -ForegroundColor Green
    }
    catch {
        Write-Error "Failed to save configuration: $_"
    }
}

# ============================================================================
# EXAMPLE USAGE (if run directly)
# ============================================================================

if ($PSBoundParameters.Count -eq 0) {
    Write-Host @"
Backup Sync Cloud Integration Utility

Available Functions:

1. Sync-BackupToCloud
   Sync backup to cloud providers
   
   Example:
   Sync-BackupToCloud -Provider s3 -Cleanup -Wait
   Sync-BackupToCloud -Verify -Resume

2. Test-BackupIntegrity
   Verify backup file is valid
   
   Example:
   Test-BackupIntegrity -Path "C:\Backups\backup.zip"

3. Get-BackupSyncStatus
   Get latest sync status and logs
   
   Example:
   Get-BackupSyncStatus

4. Invoke-CloudSync
   Alias for Sync-BackupToCloud
   
   Example:
   Invoke-CloudSync -Provider smb -DryRun

5. Get-LatestBackupFile
   Find most recent backup
   
   Example:
   Get-LatestBackupFile

6. Get-SyncConfiguration
   View current configuration
   
   Example:
   Get-SyncConfiguration | Format-List

7. Set-SyncConfiguration
   Update configuration
   
   Example:
   `$config = Get-SyncConfiguration
   `$config.max_bandwidth_mbps = 100
   Set-SyncConfiguration `$config

For help on any function:
Get-Help Sync-BackupToCloud -Full
Get-Help Test-BackupIntegrity -Full
etc.
"@
}

Export-ModuleMembers -Function @(
    'Sync-BackupToCloud',
    'Test-BackupIntegrity',
    'Get-BackupSyncStatus',
    'Invoke-CloudSync',
    'Get-LatestBackupFile',
    'Get-SyncConfiguration',
    'Set-SyncConfiguration'
)
