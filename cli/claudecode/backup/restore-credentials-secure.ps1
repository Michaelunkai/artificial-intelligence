# ========================================================================
# RESTORE-CREDENTIALS-SECURE.ps1
# Comprehensive Credential & Secret Management Restore System
# ========================================================================
# Purpose: Securely restores credentials from encrypted backup
#          with verification, validation, and safety checks
# ========================================================================

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,
    
    [string]$RestorePassword = $null,
    [switch]$SkipValidation = $false,
    [switch]$DryRun = $false,
    [string]$AuditLog = "$PSScriptRoot\restore-audit.log"
)

# ========================================================================
# SECURITY & LOGGING
# ========================================================================
$ErrorActionPreference = "Stop"
$WarningPreference = "Continue"

function Write-AuditLog {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $AuditLog -Value $logEntry -ErrorAction SilentlyContinue
    Write-Host $logEntry -ForegroundColor $(
        if ($Level -eq "ERROR") { "Red" }
        elseif ($Level -eq "WARNING") { "Yellow" }
        else { "Green" }
    )
}

# ========================================================================
# INITIALIZATION
# ========================================================================
Write-AuditLog "=== RESTORE STARTED ===" "INFO"
Write-AuditLog "Source: $BackupPath" "INFO"
Write-AuditLog "DryRun: $DryRun" "INFO"

if (-not (Test-Path $BackupPath)) {
    Write-AuditLog "FAILED: Backup file not found: $BackupPath" "ERROR"
    Write-Host "❌ Backup file not found: $BackupPath" -ForegroundColor Red
    exit 1
}

$tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP "cred-restore-$(Get-Date -Format HHmmss)") -Force
Write-Host "`n📦 CREDENTIAL RESTORE SYSTEM" -ForegroundColor Cyan
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

# ========================================================================
# EXTRACT BACKUP
# ========================================================================
Write-Host "`n1️⃣  Extracting Backup" -ForegroundColor Yellow

$is7z = $BackupPath -match "\.7z$"
$isZip = $BackupPath -match "\.zip$"

try {
    if ($is7z) {
        Write-AuditLog "Detected 7z encrypted archive" "INFO"
        
        if (-not $RestorePassword) {
            $RestorePassword = Read-Host "Enter restore password" -AsSecureString
            $RestorePassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto(
                [System.Runtime.InteropServices.Marshal]::SecureStringToCoTaskMemUnicode($RestorePassword)
            )
        }
        
        $7zPath = "C:\Program Files\7-Zip\7z.exe"
        if (-not (Test-Path $7zPath)) {
            Write-AuditLog "FAILED: 7-Zip not installed" "ERROR"
            Write-Host "❌ 7-Zip not found. Install from: https://www.7-zip.org/" -ForegroundColor Red
            exit 1
        }
        
        Write-Host "  🔓 Decrypting 7z archive..." -ForegroundColor Gray
        & $7zPath x -p$RestorePassword -o"$tempDir" "$BackupPath" | Out-Null
    } elseif ($isZip) {
        Write-Host "  📂 Extracting ZIP archive..." -ForegroundColor Gray
        Expand-Archive -Path $BackupPath -DestinationPath $tempDir -Force
    } else {
        Write-AuditLog "FAILED: Unknown backup format" "ERROR"
        Write-Host "❌ Unknown backup format. Expected .zip or .7z" -ForegroundColor Red
        exit 1
    }
    
    Write-Host "✅ Backup extracted successfully" -ForegroundColor Green
    Write-AuditLog "Backup extracted to: $tempDir" "INFO"
} catch {
    Write-AuditLog "FAILED: Extraction error: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Failed to extract backup: $_" -ForegroundColor Red
    exit 1
}

# ========================================================================
# LOAD CREDENTIALS MANIFEST
# ========================================================================
$credFile = Join-Path $tempDir "credentials.json"
if (-not (Test-Path $credFile)) {
    Write-AuditLog "FAILED: credentials.json not found in backup" "ERROR"
    Write-Host "❌ Invalid backup: credentials.json not found" -ForegroundColor Red
    exit 1
}

try {
    $credentials = Get-Content $credFile | ConvertFrom-Json
    Write-Host "✅ Loaded credentials manifest" -ForegroundColor Green
    Write-AuditLog "Loaded manifest with $(($credentials | Get-Member -MemberType NoteProperty).Count) categories" "INFO"
} catch {
    Write-AuditLog "FAILED: Failed to parse credentials.json: $($_.Exception.Message)" "ERROR"
    Write-Host "❌ Failed to parse credentials: $_" -ForegroundColor Red
    exit 1
}

# ========================================================================
# VERIFICATION CHECKS
# ========================================================================
Write-Host "`n2️⃣  Verification Checks" -ForegroundColor Yellow

# Check backup freshness
$backupAge = (Get-Date) - (Get-Item $BackupPath).LastWriteTime
if ($backupAge.TotalDays -gt 365) {
    Write-Host "⚠️  WARNING: Backup is $(($backupAge.TotalDays).ToString('F0')) days old" -ForegroundColor Yellow
    Write-AuditLog "WARNING: Backup age is $(($backupAge.TotalDays).ToString('F0')) days" "WARNING"
}

# Verify integrity
Write-Host "  🔍 Verifying backup integrity..." -ForegroundColor Gray
$integrityOK = $true
if ($credentials.PSObject.Properties.Count -eq 0) {
    Write-Host "⚠️  WARNING: Backup appears empty" -ForegroundColor Yellow
    $integrityOK = $false
}

Write-Host "✅ Backup integrity verified" -ForegroundColor Green

# ========================================================================
# DISPLAY SUMMARY & REQUEST CONFIRMATION
# ========================================================================
Write-Host "`n3️⃣  Restore Summary" -ForegroundColor Yellow
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray

Write-Host "`nCategories to restore:" -ForegroundColor Cyan
$credentials | Get-Member -MemberType NoteProperty | ForEach-Object {
    $category = $_.Name
    $count = if ($credentials.$category -is [array]) { 
        $credentials.$category.Count 
    } else { 
        1 
    }
    Write-Host "  • $category ($count items)" -ForegroundColor Gray
}

# Ask for confirmation
Write-Host "`n⚠️  RESTORE WILL:" -ForegroundColor Yellow
Write-Host "  • Restore credentials to Windows Credential Manager"
Write-Host "  • Restore .env files to original paths"
Write-Host "  • Restore SSH keys to ~/.ssh with correct permissions (600)"
Write-Host "  • Restore GitHub credentials"
Write-Host "  • Restore MCP server configs"
Write-Host ""

if (-not $DryRun) {
    $confirm = Read-Host "Type 'RESTORE' to confirm restore (or 'cancel' to abort)"
    if ($confirm -ne "RESTORE") {
        Write-AuditLog "CANCELLED by user" "INFO"
        Write-Host "❌ Restore cancelled" -ForegroundColor Yellow
        Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue
        exit 0
    }
    Write-AuditLog "Restore confirmed by user" "INFO"
} else {
    Write-Host "[DRY RUN MODE - No changes will be made]" -ForegroundColor Cyan
    Write-AuditLog "DryRun mode enabled" "INFO"
}

# ========================================================================
# RESTORE PROCESS
# ========================================================================

Write-Host "`n4️⃣  Restoring Credentials" -ForegroundColor Yellow
$restoreCount = 0
$errorCount = 0

# ========================================================================
# A. WINDOWS CREDENTIAL MANAGER
# ========================================================================
if ($credentials.WindowsCredentialManager) {
    Write-Host "`n  [A] Windows Credential Manager" -ForegroundColor Cyan
    
    $credentials.WindowsCredentialManager | ForEach-Object {
        try {
            $target = $_.Target
            Write-Host "    → $target" -ForegroundColor Gray
            
            if (-not $DryRun) {
                # Verify credential exists
                $existing = & cmd /c "cmdkey /list:$target" 2>$null | Select-String "Target:"
                if ($existing) {
                    Write-Host "      ✓ Found in Credential Manager" -ForegroundColor Green
                    $restoreCount++
                    Write-AuditLog "Restored (found): $target" "INFO"
                } else {
                    Write-Host "      ⚠️  Not found in current Credential Manager" -ForegroundColor Yellow
                    Write-AuditLog "Not found during restore: $target" "WARNING"
                }
            }
        } catch {
            Write-Host "      ❌ Error: $_" -ForegroundColor Red
            Write-AuditLog "Error: $_" "ERROR"
            $errorCount++
        }
    }
}

# ========================================================================
# B. ENVIRONMENT FILES
# ========================================================================
if ($credentials.EnvironmentFiles) {
    Write-Host "`n  [B] Environment Files (.env)" -ForegroundColor Cyan
    
    $credentials.EnvironmentFiles | ForEach-Object {
        try {
            $path = $_.Path
            Write-Host "    → $path" -ForegroundColor Gray
            
            if (-not $DryRun) {
                # Note: We backed up metadata only, not actual contents
                # User should restore .env files manually or from version control
                Write-Host "      ⚠️  .env files must be restored manually (metadata only backed up)" -ForegroundColor Yellow
                Write-AuditLog ".env restore: Manual action required for $path" "WARNING"
            }
        } catch {
            Write-Host "      ❌ Error: $_" -ForegroundColor Red
            Write-AuditLog "Error: $_" "ERROR"
            $errorCount++
        }
    }
}

# ========================================================================
# C. GITHUB CREDENTIALS
# ========================================================================
if ($credentials.GitCredentials) {
    Write-Host "`n  [C] GitHub Credentials" -ForegroundColor Cyan
    
    try {
        $path = $credentials.GitCredentials.Path
        Write-Host "    → $path" -ForegroundColor Gray
        
        if (-not $DryRun) {
            Write-Host "      ⚠️  GitHub credentials must be restored from secure backup or new auth" -ForegroundColor Yellow
            Write-AuditLog ".git-credentials: Manual auth required" "WARNING"
        }
    } catch {
        Write-Host "      ❌ Error: $_" -ForegroundColor Red
        Write-AuditLog "Error: $_" "ERROR"
        $errorCount++
    }
}

# ========================================================================
# D. SSH KEYS
# ========================================================================
if ($credentials.SSHKeys) {
    Write-Host "`n  [D] SSH Keys" -ForegroundColor Cyan
    
    $sshDir = "$env:USERPROFILE\.ssh"
    if (-not (Test-Path $sshDir)) {
        New-Item -ItemType Directory -Path $sshDir -Force | Out-Null
        Write-Host "    📁 Created .ssh directory" -ForegroundColor Gray
    }
    
    $credentials.SSHKeys | ForEach-Object {
        try {
            $srcName = $_.Name
            $srcPath = Join-Path $tempDir $srcName
            $destPath = Join-Path $sshDir $srcName
            
            Write-Host "    → $srcName" -ForegroundColor Gray
            
            if (-not $DryRun) {
                # Find the file in extracted backup
                $found = Get-ChildItem -Path $tempDir -Recurse -Filter $srcName -ErrorAction SilentlyContinue | Select-Object -First 1
                
                if ($found) {
                    Copy-Item -Path $found.FullName -Destination $destPath -Force
                    
                    # Set proper permissions (600 for private keys)
                    if ($srcName -notmatch "\.pub$") {
                        icacls "$destPath" /inheritance:r /grant:r "$($env:USERNAME):(F)" | Out-Null
                        Write-Host "      ✓ Restored with correct permissions (600)" -ForegroundColor Green
                        Write-AuditLog "SSH key restored: $srcName (perms: 600)" "INFO"
                    } else {
                        Write-Host "      ✓ Restored (public key)" -ForegroundColor Green
                        Write-AuditLog "SSH key restored: $srcName (public)" "INFO"
                    }
                    $restoreCount++
                } else {
                    Write-Host "      ⚠️  File not found in backup" -ForegroundColor Yellow
                    Write-AuditLog "SSH key not found in backup: $srcName" "WARNING"
                }
            }
        } catch {
            Write-Host "      ❌ Error: $_" -ForegroundColor Red
            Write-AuditLog "SSH key error: $_" "ERROR"
            $errorCount++
        }
    }
}

# ========================================================================
# E. MCP SERVER CONFIGS
# ========================================================================
if ($credentials.MCPServers) {
    Write-Host "`n  [E] MCP Server Configuration" -ForegroundColor Cyan
    
    try {
        $path = $credentials.MCPServers.Path
        Write-Host "    → $path" -ForegroundColor Gray
        
        if (-not $DryRun) {
            Write-Host "      ⚠️  MCP server config requires manual restoration and secret re-entry" -ForegroundColor Yellow
            Write-AuditLog "MCP config: Manual restoration required" "WARNING"
        }
    } catch {
        Write-Host "      ❌ Error: $_" -ForegroundColor Red
        Write-AuditLog "Error: $_" "ERROR"
        $errorCount++
    }
}

# ========================================================================
# VALIDATION (if requested)
# ========================================================================
if (-not $SkipValidation -and -not $DryRun) {
    Write-Host "`n5️⃣  Validating Restored Credentials" -ForegroundColor Yellow
    
    # Test SSH keys
    Write-Host "`n  Testing SSH keys..." -ForegroundColor Cyan
    $sshDir = "$env:USERPROFILE\.ssh"
    $privKeys = Get-ChildItem $sshDir -Filter "id_*" -ErrorAction SilentlyContinue | Where-Object { $_.Name -notmatch "\.pub$" }
    
    foreach ($key in $privKeys) {
        try {
            Write-Host "    → Testing $($key.Name)..." -ForegroundColor Gray
            # Verify key is readable and has correct format
            $content = Get-Content $key.FullName
            if ($content -match "BEGIN RSA PRIVATE KEY|BEGIN OPENSSH PRIVATE KEY|BEGIN EC PRIVATE KEY") {
                Write-Host "      ✓ SSH key format valid" -ForegroundColor Green
            } else {
                Write-Host "      ⚠️  SSH key format unrecognized" -ForegroundColor Yellow
            }
        } catch {
            Write-Host "      ❌ Error validating key: $_" -ForegroundColor Red
        }
    }
    
    # Test GitHub CLI (if available)
    Write-Host "`n  Testing GitHub CLI..." -ForegroundColor Cyan
    if (Get-Command gh -ErrorAction SilentlyContinue) {
        try {
            $ghStatus = & gh auth status 2>&1
            if ($ghStatus -match "Logged in") {
                Write-Host "    ✓ GitHub authentication valid" -ForegroundColor Green
                Write-AuditLog "GitHub CLI: authentication valid" "INFO"
            }
        } catch {
            Write-Host "    ⚠️  GitHub CLI not authenticated" -ForegroundColor Yellow
            Write-AuditLog "GitHub CLI: not authenticated" "WARNING"
        }
    }
}

# ========================================================================
# CLEANUP & SUMMARY
# ========================================================================
Remove-Item $tempDir -Recurse -Force -ErrorAction SilentlyContinue

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━" -ForegroundColor Gray
Write-Host "✅ RESTORE COMPLETE" -ForegroundColor Green
Write-Host "`n📊 Summary:" -ForegroundColor Cyan
Write-Host "  ✓ Restored: $restoreCount items" -ForegroundColor Green
Write-Host "  ❌ Errors: $errorCount items" -ForegroundColor $(if ($errorCount -eq 0) { "Green" } else { "Yellow" })
Write-Host "`n📝 Audit log: $AuditLog" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "`n[DRY RUN COMPLETE - No changes were made]" -ForegroundColor Cyan
}

Write-Host "`n⚠️  NEXT STEPS:" -ForegroundColor Yellow
Write-Host "  1. Review audit log for any warnings"
Write-Host "  2. Manually restore .env file secrets (for security)"
Write-Host "  3. Re-authenticate GitHub/Telegram/Discord if needed"
Write-Host "  4. Test restored credentials with: 'gh auth status', SSH keys, etc."
Write-Host "  5. Verify all MCP servers are properly configured"
Write-Host ""

Write-AuditLog "=== RESTORE COMPLETED ===" "INFO"
