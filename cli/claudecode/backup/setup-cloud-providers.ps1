#Requires -Version 5.1
<#
.SYNOPSIS
    Interactive setup wizard for cloud provider configuration
.DESCRIPTION
    Guides user through configuring OneDrive, Google Drive, AWS S3, and SMB
.EXAMPLE
    .\setup-cloud-providers.ps1
#>

param()

$ScriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$ConfigFile = Join-Path $ScriptRoot "backup-sync-cloud.json"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Section {
    param([string]$Title)
    Write-Host ""
    Write-Host "╔" + ("═" * ($Title.Length + 2)) + "╗" -ForegroundColor Cyan
    Write-Host "║ $Title ║" -ForegroundColor Cyan
    Write-Host "╚" + ("═" * ($Title.Length + 2)) + "╝" -ForegroundColor Cyan
}

function Write-Step {
    param(
        [int]$Number,
        [string]$Description
    )
    Write-Host "  [$Number] $Description" -ForegroundColor Yellow
}

function Get-YesNo {
    param([string]$Prompt = "Continue?")
    
    do {
        $response = Read-Host "$Prompt (y/n)"
        if ($response -match '^[yn]$') {
            return $response -eq 'y'
        }
    } while ($true)
}

# ============================================================================
# PROVIDER SETUP FUNCTIONS
# ============================================================================

function Setup-OneDrive {
    Write-Section "OneDrive Configuration"
    
    Write-Host @"
To set up OneDrive backup sync, you need:
1. Azure AD tenant ID
2. App registration (Client ID & Secret)
3. Proper permissions granted

Instructions:
"@
    
    Write-Step 1 "Go to https://portal.azure.com"
    Write-Step 2 "Select 'Azure Active Directory' > 'App registrations'"
    Write-Step 3 "Click 'New registration'"
    Write-Step 4 'Enter name: "BackupSync"'
    Write-Step 5 'Redirect URI (Web): https://localhost'
    Write-Step 6 'Create the app'
    Write-Step 7 'Copy Application (Client) ID'
    Write-Step 8 'Go to Certificates & secrets > New client secret'
    Write-Step 9 'Copy the secret value'
    Write-Step 10 'Select API permissions > Add permission'
    Write-Step 11 'Choose Microsoft Graph > Application permissions'
    Write-Step 12 'Search for and add: Files.ReadWrite.All'
    Write-Step 13 'Grant admin consent'
    
    Write-Host ""
    if (-not (Get-YesNo "Have you completed these steps?")) {
        return $false
    }
    
    Write-Host ""
    $tenantId = Read-Host "Azure Tenant ID"
    if (-not $tenantId) { return $false }
    
    $appId = Read-Host "Application (Client) ID"
    if (-not $appId) { return $false }
    
    $secret = Read-Host "Client Secret (will be encrypted)" -AsSecureString
    if (-not $secret) { return $false }
    
    $folderId = Read-Host "OneDrive Folder ID (default: root)" 
    if (-not $folderId) { $folderId = "root" }
    
    $retention = Read-Host "Retention days (default: 30)"
    if (-not $retention) { $retention = 30 } else { $retention = [int]$retention }
    
    return @{
        enabled    = $true
        tenant_id  = $tenantId
        app_id     = $appId
        secret     = ConvertFrom-SecureString $secret
        folder_id  = $folderId
        retention_days = $retention
    }
}

function Setup-GoogleDrive {
    Write-Section "Google Drive Configuration"
    
    Write-Host @"
To set up Google Drive backup sync, you need:
1. Google Cloud Project with Drive API enabled
2. Service Account with JSON credentials

Instructions:
"@
    
    Write-Step 1 "Go to https://console.cloud.google.com"
    Write-Step 2 "Create a new project or select existing"
    Write-Step 3 "Enable Google Drive API"
    Write-Step 4 "Create Service Account"
    Write-Step 5 "Generate JSON key file"
    Write-Step 6 "Create a folder in Google Drive"
    Write-Step 7 "Share it with the service account email"
    
    Write-Host ""
    if (-not (Get-YesNo "Have you completed these steps?")) {
        return $false
    }
    
    Write-Host ""
    $credPath = Read-Host "Path to credentials.json"
    
    if (-not (Test-Path $credPath)) {
        Write-Error "Credentials file not found: $credPath"
        return $false
    }
    
    if (-not ($credPath -match "\.json$")) {
        Write-Error "File must be JSON format"
        return $false
    }
    
    $folderId = Read-Host "Google Drive Folder ID (get from URL)"
    if (-not $folderId) { return $false }
    
    $retention = Read-Host "Retention days (default: 30)"
    if (-not $retention) { $retention = 30 } else { $retention = [int]$retention }
    
    return @{
        enabled      = $true
        credentials  = $credPath
        folder_id    = $folderId
        retention_days = $retention
    }
}

function Setup-S3 {
    Write-Section "AWS S3 Configuration"
    
    Write-Host @"
To set up AWS S3 backup sync, you need:
1. AWS Account with S3 access
2. S3 bucket created
3. IAM user with appropriate permissions

Instructions:
"@
    
    Write-Step 1 "Go to https://aws.amazon.com"
    Write-Step 2 "Create S3 bucket in your preferred region"
    Write-Step 3 "Create IAM user for backup access"
    Write-Step 4 "Attach policy: AmazonS3FullAccess (or custom)"
    Write-Step 5 "Generate Access Key ID and Secret"
    Write-Step 6 "Install AWS CLI or AWSPowerShell module"
    
    Write-Host ""
    Write-Host "AWS CLI: https://aws.amazon.com/cli/" -ForegroundColor Magenta
    Write-Host "AWSPowerShell: Install-Module -Name AWSPowerShell" -ForegroundColor Magenta
    Write-Host ""
    
    if (-not (Get-YesNo "Have you completed these steps?")) {
        return $false
    }
    
    Write-Host ""
    $bucket = Read-Host "S3 Bucket Name"
    if (-not $bucket) { return $false }
    
    $region = Read-Host "AWS Region (default: us-east-1)"
    if (-not $region) { $region = "us-east-1" }
    
    $prefix = Read-Host "S3 Prefix/Folder (default: backups/)"
    if (-not $prefix) { $prefix = "backups/" }
    
    $accessKey = Read-Host "AWS Access Key ID"
    if (-not $accessKey) { return $false }
    
    $secretKey = Read-Host "AWS Secret Access Key" -AsSecureString
    if (-not $secretKey) { return $false }
    
    $storageClass = Read-Host "Storage Class - STANDARD|GLACIER (default: GLACIER)"
    if ($storageClass -notin @('STANDARD', 'GLACIER')) { $storageClass = 'GLACIER' }
    
    $retention = Read-Host "Retention days (default: 30)"
    if (-not $retention) { $retention = 30 } else { $retention = [int]$retention }
    
    return @{
        enabled       = $true
        bucket        = $bucket
        region        = $region
        prefix        = $prefix
        access_key    = $accessKey
        secret_key    = ConvertFrom-SecureString $secretKey
        storage_class = $storageClass
        retention_days = $retention
    }
}

function Setup-SMB {
    Write-Section "SMB Network Share Configuration"
    
    Write-Host @"
To set up SMB backup sync, you need:
1. Network share on Windows server or NAS
2. Username and password for access
3. Network connectivity to the share

Instructions:
"@
    
    Write-Step 1 "Ensure network share is created and accessible"
    Write-Step 2 "Test access manually: net use \\server\share password /user:domain\user"
    Write-Step 3 "Note the server path, username, and password"
    
    Write-Host ""
    if (-not (Get-YesNo "Have you verified network access?")) {
        return $false
    }
    
    Write-Host ""
    $server = Read-Host "SMB Server Path (e.g., \\backup-server\share)"
    if (-not $server) { return $false }
    
    # Test connectivity
    Write-Host "Testing SMB connectivity..." -ForegroundColor Yellow
    if (-not (Test-Path $server -ErrorAction SilentlyContinue)) {
        Write-Warning "Could not immediately access $server"
        Write-Host "This may require credentials. They will be used at sync time." -ForegroundColor Yellow
    }
    
    $username = Read-Host "Username (domain\user or user)"
    if (-not $username) { return $false }
    
    $password = Read-Host "Password" -AsSecureString
    if (-not $password) { return $false }
    
    $retention = Read-Host "Retention days (default: 30)"
    if (-not $retention) { $retention = 30 } else { $retention = [int]$retention }
    
    return @{
        enabled        = $true
        server         = $server
        username       = $username
        password       = ConvertFrom-SecureString $password
        retention_days = $retention
    }
}

function Setup-GlobalSettings {
    Write-Section "Global Settings"
    
    Write-Host ""
    $backupPath = Read-Host "Backup source path (default: C:\Backups)"
    if (-not $backupPath) { $backupPath = "C:\Backups" }
    
    $maxBandwidth = Read-Host "Max bandwidth in Mbps (default: 50, 0=unlimited)"
    if (-not $maxBandwidth) { $maxBandwidth = 50 } else { $maxBandwidth = [int]$maxBandwidth }
    
    $concurrent = Read-Host "Concurrent uploads (default: 3)"
    if (-not $concurrent) { $concurrent = 3 } else { $concurrent = [int]$concurrent }
    
    $retries = Read-Host "Retry attempts (default: 3)"
    if (-not $retries) { $retries = 3 } else { $retries = [int]$retries }
    
    $retryDelay = Read-Host "Retry delay in seconds (default: 5)"
    if (-not $retryDelay) { $retryDelay = 5 } else { $retryDelay = [int]$retryDelay }
    
    return @{
        backup_path        = $backupPath
        max_bandwidth_mbps = $maxBandwidth
        concurrent_uploads = $concurrent
        retry_attempts     = $retries
        retry_delay_seconds = $retryDelay
    }
}

# ============================================================================
# MAIN SETUP FLOW
# ============================================================================

function Initialize-Setup {
    Write-Host ""
    Write-Section "Backup Sync Cloud - Setup Wizard"
    
    Write-Host @"
This wizard will guide you through configuring cloud storage providers
for automated backup synchronization.

What you can set up:
  • OneDrive (Microsoft 365)
  • Google Drive
  • AWS S3
  • Custom SMB Networks shares

Let's get started!
"@
    
    Write-Host ""
    if (-not (Get-YesNo "Continue with setup?")) {
        Write-Host "Setup cancelled." -ForegroundColor Yellow
        exit 0
    }
    
    # Build configuration
    $config = @{
        backup_path         = ""
        checksum_algorithm  = "SHA256"
        providers           = @{
            onedrive = @{ enabled = $false }
            gdrive   = @{ enabled = $false }
            s3       = @{ enabled = $false }
            smb      = @{ enabled = $false }
        }
        selective_sync      = @{
            enabled    = $false
            components = @()
        }
    }
    
    # Global settings
    Write-Section "Step 1: Global Settings"
    $global = Setup-GlobalSettings
    $config.backup_path = $global.backup_path
    $config.max_bandwidth_mbps = $global.max_bandwidth_mbps
    $config.concurrent_uploads = $global.concurrent_uploads
    $config.retry_attempts = $global.retry_attempts
    $config.retry_delay_seconds = $global.retry_delay_seconds
    
    # Provider setup
    Write-Section "Step 2: Cloud Providers"
    
    Write-Host ""
    Write-Host "Select providers to configure:" -ForegroundColor Cyan
    
    if (Get-YesNo "Configure OneDrive?") {
        $od = Setup-OneDrive
        if ($od) {
            $config.providers.onedrive = $od
            Write-Host "✓ OneDrive configured" -ForegroundColor Green
        }
    }
    
    if (Get-YesNo "Configure Google Drive?") {
        $gd = Setup-GoogleDrive
        if ($gd) {
            $config.providers.gdrive = $gd
            Write-Host "✓ Google Drive configured" -ForegroundColor Green
        }
    }
    
    if (Get-YesNo "Configure AWS S3?") {
        $s3 = Setup-S3
        if ($s3) {
            $config.providers.s3 = $s3
            Write-Host "✓ AWS S3 configured" -ForegroundColor Green
        }
    }
    
    if (Get-YesNo "Configure SMB?") {
        $smb = Setup-SMB
        if ($smb) {
            $config.providers.smb = $smb
            Write-Host "✓ SMB configured" -ForegroundColor Green
        }
    }
    
    # Selective sync
    Write-Section "Step 3: Advanced Options"
    
    if (Get-YesNo "Enable selective sync (sync specific backup components only)?") {
        $config.selective_sync.enabled = $true
        
        Write-Host ""
        Write-Host "Enter backup components to include (comma-separated):" -ForegroundColor Yellow
        Write-Host "Example: database,documents,configuration" -ForegroundColor Gray
        
        $components = Read-Host "Components"
        if ($components) {
            $config.selective_sync.components = @($components -split "," | ForEach-Object { $_.Trim() })
        }
    }
    
    # Summary and save
    Write-Section "Setup Summary"
    
    Write-Host ""
    Write-Host "Configuration:" -ForegroundColor Cyan
    Write-Host "  Backup Path: $($config.backup_path)"
    Write-Host "  Max Bandwidth: $($config.max_bandwidth_mbps) Mbps"
    Write-Host "  Concurrent Uploads: $($config.concurrent_uploads)"
    Write-Host ""
    
    Write-Host "Enabled Providers:" -ForegroundColor Cyan
    $enabledProviders = $config.providers.PSObject.Properties | 
                       Where-Object { $_.Value.enabled } | 
                       Select-Object -ExpandProperty Name
    
    if ($enabledProviders) {
        $enabledProviders | ForEach-Object { Write-Host "  ✓ $_" -ForegroundColor Green }
    }
    else {
        Write-Host "  (none)" -ForegroundColor Yellow
    }
    
    Write-Host ""
    
    if (-not (Get-YesNo "Save configuration to $ConfigFile`?")) {
        Write-Host "Configuration not saved." -ForegroundColor Yellow
        exit 0
    }
    
    # Save config
    try {
        $config | ConvertTo-Json -Depth 10 | Set-Content $ConfigFile
        Write-Host ""
        Write-Host "✓ Configuration saved successfully!" -ForegroundColor Green
        Write-Host "  Location: $ConfigFile" -ForegroundColor Gray
        
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "  1. Review the configuration file if needed"
        Write-Host "  2. Run the sync: .\backup-sync-cloud.ps1 -DryRun"
        Write-Host "  3. If happy, run: .\backup-sync-cloud.ps1 -Cleanup"
        Write-Host "  4. Schedule with Windows Task Scheduler for daily runs"
    }
    catch {
        Write-Host "✗ Failed to save configuration: $_" -ForegroundColor Red
        exit 1
    }
}

# ============================================================================
# ENTRY POINT
# ============================================================================

Initialize-Setup
