# 🔐 Credential Backup & Restore System

Comprehensive security solution for backing up and restoring ALL credentials, secrets, and sensitive configurations from your Windows system.

---

## 📋 What Gets Backed Up

### ✅ Backed Up (Fully)
1. **Windows Credential Manager** - Claude, Anthropic, OpenClaw, GitHub entries
2. **SSH Keys** - All keys from `~/.ssh` with correct permissions
3. **GitHub Credentials** - `.git-credentials` and `gh` CLI configs
4. **MCP Server Config** - `.claude` configuration metadata
5. **File Metadata** - Hashes, sizes, timestamps for integrity checking

### ⚠️ Backed Up (Metadata Only)
- **.env files** - Paths and hashes only (not contents for security)
- **Telegram tokens** - Config file paths only (tokens excluded)
- **Discord tokens** - Config file paths only (tokens excluded)

### ❌ NOT Backed Up
- Plain-text secret values in config files
- Bot tokens (for security)
- Database passwords
- API keys (except as file metadata)

---

## 🚀 Quick Start

### Backup
```powershell
# Simple backup (unencrypted)
powershell -ExecutionPolicy Bypass -File "backup-credentials-secure.ps1"

# Encrypted backup with 7-Zip password
powershell -ExecutionPolicy Bypass -File "backup-credentials-secure.ps1" -Encrypt -EncryptPassword "MySecurePassword123"
```

### Restore
```powershell
# Restore from encrypted backup
powershell -ExecutionPolicy Bypass -File "restore-credentials-secure.ps1" -BackupPath "C:\backup-20240323-154230.7z"

# Dry-run (preview without changes)
powershell -ExecutionPolicy Bypass -File "restore-credentials-secure.ps1" -BackupPath "C:\backup-20240323-154230.7z" -DryRun
```

---

## 📦 Backup Workflow

### Step 1: Run Backup Script
```powershell
cd "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
./backup-credentials-secure.ps1
```

**Output:**
- `backup-YYYYMMDD-HHMMSS.zip` (or `.7z` if encrypted)
- `backup-audit.log` - Complete audit trail
- Console report with summary

### Step 2: Review Audit Log
```powershell
Get-Content backup-audit.log -Tail 50
```

### Step 3: Secure the Backup
- Move to **encrypted drive** or **external storage**
- Store **encryption password** separately (password manager)
- Verify backup integrity: `Test-Path backup-YYYYMMDD-HHMMSS.zip`

### Step 4: Verify Contents (Optional)
```powershell
# List backup contents
Expand-Archive -Path "backup-YYYYMMDD-HHMMSS.zip" -DestinationPath "C:\temp\verify" -Force
Get-Content "C:\temp\verify\credentials.json" | ConvertFrom-Json | Format-Table
Remove-Item "C:\temp\verify" -Recurse
```

---

## 🔓 Restore Workflow

### Step 1: Verify Backup File
```powershell
Test-Path "C:\path\to\backup-YYYYMMDD-HHMMSS.7z"
ls "C:\path\to\backup-YYYYMMDD-HHMMSS.7z" -lh  # Check size
```

### Step 2: Run Restore Script (Dry-Run First)
```powershell
cd "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
./restore-credentials-secure.ps1 -BackupPath "C:\path\to\backup-20240323-154230.7z" -DryRun
```

This shows you WHAT will be restored WITHOUT making changes.

### Step 3: Review & Confirm
- Check the dry-run output for expected items
- Read the warnings about manual restoration steps

### Step 4: Execute Full Restore
```powershell
./restore-credentials-secure.ps1 -BackupPath "C:\path\to\backup-20240323-154230.7z"
```

When prompted:
```
Confirm restore? Type 'RESTORE' to confirm (or 'cancel' to abort)
> RESTORE
```

### Step 5: Manual Credential Re-Entry
Some credentials require manual setup for security:

#### GitHub
```powershell
gh auth login
# Follow prompts for GitHub authentication
gh auth status  # Verify
```

#### Telegram & Discord
```powershell
# Re-enter bot tokens in config files:
# ~/.openclaw/openclaw.json (Telegram tokens)
# ~/.discord/config.json (Discord tokens)
```

#### .env Files
```powershell
# Manually restore from secure backup or create new:
# Re-enter API keys, secrets, etc.
# Files: ~/.env, ~/.claude/.env, ~/.openclaw/.env
```

#### MCP Servers
```powershell
# Edit ~/.claude/claude.json
# Re-enter any MCP server secrets/API keys
```

### Step 6: Validate Everything
```powershell
# Test SSH keys
ssh -T git@github.com

# Test GitHub CLI
gh auth status

# Test credentials
cmdkey /list  # List Credential Manager entries
```

---

## 🔐 Security Best Practices

### Encryption
✅ **Always use encryption** for backups:
```powershell
./backup-credentials-secure.ps1 -Encrypt -EncryptPassword "ComplexPassword123!"
```

Requirements:
- 7-Zip must be installed: https://www.7-zip.org/
- Use **strong password** (16+ characters, mixed case, numbers, symbols)
- Store password separately from backup file

### Backup Storage
✅ **Store backups securely:**
- ❌ NOT on unencrypted external drives
- ❌ NOT in cloud (without encryption)
- ❌ NOT in shared drives
- ✅ **Encrypted local drive** (BitLocker, LUKS)
- ✅ **Encrypted USB drive** (VeraCrypt, BitLocker)
- ✅ **Private encrypted cloud** (OneDrive w/ encryption key)

### Access Control
✅ **Protect backup files:**
```powershell
# Set permissions (owner only)
icacls "backup-*.zip" /inheritance:r /grant:r "$($env:USERNAME):(F)"
```

✅ **Store password separately:**
- Password manager (1Password, KeePass, Bitwarden)
- NOT in same location as backup
- NOT in plaintext files

### Regular Backups
✅ **Schedule backups:**
```powershell
# Create Windows Task Scheduler job for monthly backups
# Or use: Task Scheduler > Create Task > Run backup-credentials-secure.ps1
```

---

## 📊 Backup Structure

### Backup File Contents
```
backup-YYYYMMDD-HHMMSS.zip (or .7z)
├── credentials.json
│   ├── WindowsCredentialManager
│   │   └── [Credential Manager entries]
│   ├── EnvironmentFiles
│   │   └── [.env file metadata]
│   ├── GitCredentials
│   │   └── [GitHub auth metadata]
│   ├── SSHKeys
│   │   └── [SSH key files]
│   ├── MCPServers
│   │   └── [MCP config metadata]
│   ├── TelegramTokens
│   │   └── [Telegram config metadata]
│   └── DiscordTokens
│       └── [Discord config metadata]
```

### Audit Logs
```
backup-audit.log (created during backup)
restore-audit.log (created during restore)

Contains:
- Timestamp of all operations
- Files processed
- Errors and warnings
- Security events
```

---

## 🐛 Troubleshooting

### "7-Zip not found"
**Error:** Encryption fails, 7-Zip not installed

**Solution:**
```powershell
# Install 7-Zip from: https://www.7-zip.org/
# Or use Chocolatey:
choco install 7zip

# Then re-run backup with encryption
```

### "Cannot access Credential Manager"
**Error:** Credential Manager entries cannot be read

**Possible causes:**
- Running without admin privileges
- Antivirus blocking access
- Credential Manager corrupted

**Solution:**
```powershell
# Run as Administrator
# Check antivirus exclusions
# Manually add credentials: cmdkey /add:...
```

### "SSH key permissions incorrect"
**Error:** SSH keys restore but have wrong permissions

**Solution:**
```powershell
# After restore, fix permissions:
$sshDir = "$env:USERPROFILE\.ssh"
Get-ChildItem $sshDir | Where-Object { $_.Name -notmatch "\.pub$" } | ForEach-Object {
    icacls $_.FullName /inheritance:r /grant:r "$($env:USERNAME):(F)" | Out-Null
}
```

### "Decryption password incorrect"
**Error:** Cannot extract 7z backup with wrong password

**Solution:**
- Verify password is correct (case-sensitive)
- Ensure backup file is not corrupted
- Try restoring from different backup if available

### "Backup file corrupted"
**Error:** Backup extraction fails

**Diagnosis:**
```powershell
# Test backup integrity
Test-Path "C:\path\to\backup.7z"
(Get-Item "C:\path\to\backup.7z").Length  # Should be > 0

# Try extraction with 7z
& "C:\Program Files\7-Zip\7z.exe" t "C:\path\to\backup.7z"
```

**Solution:**
- Use previous backup if available
- Check disk space
- Try on different computer if possible

---

## 🔄 Automation

### Monthly Backup Task
```powershell
# Create scheduled task for monthly backups
$action = New-ScheduledTaskAction -Execute "powershell.exe" `
  -Argument "-ExecutionPolicy Bypass -File 'F:\...\backup-credentials-secure.ps1' -Encrypt"

$trigger = New-ScheduledTaskTrigger -Monthly -DayOfMonth 1 -At 2:00AM

Register-ScheduledTask -TaskName "Monthly Credential Backup" `
  -Action $action -Trigger $trigger -RunLevel Highest
```

### Automated Encryption
```powershell
# Use environment variable for password (more secure than hardcoding)
$env:BACKUP_PASSWORD = "MySecurePassword"
./backup-credentials-secure.ps1 -Encrypt -EncryptPassword $env:BACKUP_PASSWORD
```

---

## 📝 Audit Trail

Every operation is logged to `backup-audit.log` and `restore-audit.log`:

```
[2024-03-23 19:30:45] [INFO] === BACKUP STARTED ===
[2024-03-23 19:30:45] [INFO] Target: C:\backup-20240323-193045.7z
[2024-03-23 19:30:45] [INFO] Encryption: ENABLED
[2024-03-23 19:30:47] [INFO] Found Credential Manager entry: Claude
[2024-03-23 19:30:48] [INFO] Found .env file: C:\Users\micha\.claude\.env
[2024-03-23 19:30:49] [INFO] SSH key: id_rsa (3.5 KB)
[2024-03-23 19:30:50] [INFO] === BACKUP COMPLETED ===
```

View logs:
```powershell
Get-Content backup-audit.log
Get-Content backup-audit.log -Tail 30  # Last 30 lines
Select-String "ERROR" backup-audit.log  # Only errors
```

---

## ✅ Verification Checklist

After backup:
- [ ] Backup file created
- [ ] Backup file size > 100KB (non-empty)
- [ ] Audit log shows no critical errors
- [ ] Backup moved to secure location
- [ ] Encryption password stored safely

After restore:
- [ ] Audit log shows successful restore
- [ ] `cmdkey /list` shows restored credentials
- [ ] SSH keys present in `~/.ssh`
- [ ] SSH key permissions correct (600 for private)
- [ ] GitHub CLI authenticates: `gh auth status`
- [ ] All applications can access restored credentials

---

## 🚨 Emergency Recovery

If your main computer is lost/damaged:

1. **Get backup file** from secure storage
2. **Move to new computer**
3. **Install 7-Zip** if using encrypted backups
4. **Run restore script:**
   ```powershell
   ./restore-credentials-secure.ps1 -BackupPath "C:\backup.7z"
   ```
5. **Re-authenticate services** (GitHub, Telegram, Discord)
6. **Update passwords** (if system was compromised)

---

## 📞 Support & Questions

For issues or questions:
1. Check **Troubleshooting** section above
2. Review **audit logs** for error details
3. Run **dry-run** to diagnose restore issues
4. Test credentials: `gh auth status`, `ssh -T git@github.com`

---

**Last Updated:** 2024-03-23 | **Version:** 1.0
