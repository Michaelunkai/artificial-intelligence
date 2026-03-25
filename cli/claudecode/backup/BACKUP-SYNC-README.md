# Backup Sync to Cloud - User Guide

A comprehensive PowerShell utility for synchronizing backups to multiple cloud providers with advanced features like resume support, checksum verification, retention policies, and bandwidth limiting.

## Features

✅ **Multi-Cloud Support**
- OneDrive (Microsoft Graph API)
- Google Drive (Credentials-based)
- AWS S3 (Multipart upload with resumable sessions)
- Custom SMB servers (Network shares)

✅ **Reliable Uploads**
- Automatic checksum verification (SHA256)
- Resume interrupted uploads
- Retry logic with configurable delays
- Bandwidth throttling to avoid network saturation
- Concurrent upload support

✅ **Smart Backup Management**
- Auto-detect latest backup
- Selective sync (upload specific components only)
- Cloud-side retention policies (auto-cleanup old files)
- Checksum caching for faster comparisons
- Detailed logging and progress tracking

## Installation

1. **Place the script** in your backup tools directory:
   ```powershell
   F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\
   ```

2. **Configure** your cloud providers in `backup-sync-cloud.json`

3. **Set execution policy** (if needed):
   ```powershell
   Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
   ```

## Configuration

Edit `backup-sync-cloud.json` to enable and configure cloud providers:

### OneDrive (Microsoft 365)
```json
"onedrive": {
  "enabled": true,
  "tenant_id": "your-azure-tenant-id",
  "app_id": "your-app-registration-id",
  "secret": "your-app-secret",
  "folder_id": "root",
  "retention_days": 30
}
```

**Setup:**
1. Register an app in Azure Portal (apps.dev.microsoft.com)
2. Create a client secret
3. Grant `Files.ReadWrite.All` permission
4. Replace tenant_id, app_id, and secret

### Google Drive
```json
"gdrive": {
  "enabled": true,
  "credentials": "C:\\Path\\To\\credentials.json",
  "folder_id": "root",
  "retention_days": 30
}
```

**Setup:**
1. Create a service account in Google Cloud Console
2. Download the JSON credentials file
3. Share a Drive folder with the service account email
4. Update the credentials path and folder_id

### AWS S3
```json
"s3": {
  "enabled": true,
  "bucket": "my-backup-bucket",
  "region": "us-east-1",
  "prefix": "backups/",
  "access_key": "AKIA...",
  "secret_key": "wJal...",
  "storage_class": "GLACIER",
  "retention_days": 30
}
```

**Setup:**
1. Create an S3 bucket in your AWS account
2. Create an IAM user with S3 access
3. Generate access keys
4. Install AWS CLI: `choco install awscli` or `pip install awscli`
5. Or use AWS PowerShell module: `Install-Module -Name AWSPowerShell`

### Custom SMB Server
```json
"smb": {
  "enabled": true,
  "server": "\\\\backup-server\\share",
  "username": "domain\\user",
  "password": "your-password",
  "retention_days": 30
}
```

**Setup:**
1. Ensure network share is accessible
2. Use domain credentials if in Active Directory environment
3. Test with: `net use \\backup-server\share password /user:domain\user`

### Global Settings
```json
{
  "backup_path": "C:\\Backups",           # Where backups are stored
  "checksum_algorithm": "SHA256",          # Verification algorithm
  "max_bandwidth_mbps": 50,                # Network throttle (0 = unlimited)
  "concurrent_uploads": 3,                 # Parallel upload threads
  "retry_attempts": 3,                     # Failed upload retries
  "retry_delay_seconds": 5                 # Wait between retries
}
```

## Usage

### Basic Sync (All Enabled Providers)
```powershell
.\backup-sync-cloud.ps1
```
Auto-detects latest backup in configured backup_path and syncs to all enabled providers.

### Sync Specific File
```powershell
.\backup-sync-cloud.ps1 -BackupPath "C:\Backups\backup-2026-03-23.zip"
```

### Sync to Specific Provider
```powershell
.\backup-sync-cloud.ps1 -Provider s3
.\backup-sync-cloud.ps1 -Provider smb
```

### Resume Interrupted Upload
```powershell
.\backup-sync-cloud.ps1 -Resume
```
Checks the progress file and resumes from the last byte transferred.

### Dry Run (Preview Only)
```powershell
.\backup-sync-cloud.ps1 -DryRun
```
Shows what would be uploaded without actually transferring files.

### Verify Backup Only
```powershell
.\backup-sync-cloud.ps1 -BackupPath "C:\Backups\backup.zip" -VerifyOnly
```
Checks backup integrity (SHA256 checksum) without uploading.

### Cleanup Old Backups
```powershell
.\backup-sync-cloud.ps1 -Cleanup
```
Removes backups older than the retention_days setting from cloud providers.

## Advanced Features

### Selective Sync
Enable in config to sync only specific components:

```json
"selective_sync": {
  "enabled": true,
  "components": ["database", "documents", "configuration"]
}
```

Then run:
```powershell
.\backup-sync-cloud.ps1
```

Only the specified components from the backup archive will be extracted and uploaded.

### Bandwidth Limiting
Prevent network saturation by setting max_bandwidth_mbps:

```json
"max_bandwidth_mbps": 25  # Limit to 25 Mbps
```

This is particularly useful for SMB uploads to avoid impacting other network users.

### Checksum Verification
Every uploaded file is verified post-upload:
- Source file checksum calculated before upload
- Destination file checksum calculated after upload
- Comparison confirms bit-perfect copy
- Cached for future comparisons

### Retry Logic
Failed uploads automatically retry:
```json
"retry_attempts": 3,
"retry_delay_seconds": 5
```

Network timeouts or transient errors trigger automatic retries with exponential backoff.

## Logs and State

### Log Files
```
F:\study\AI_ML\...\cli\claudecode\backup\logs\sync-YYYY-MM-DD_HH-mm-ss.log
```

Each sync operation creates a timestamped log with all details:
- File sizes and checksums
- Upload progress and speeds
- Errors and warnings
- Retention policy actions

### Progress Tracking
```
F:\study\AI_ML\...\cli\claudecode\backup\state\sync-progress.json
```

Used for resume functionality - tracks:
- Current upload position (in bytes)
- Remote file ID/path
- Last update timestamp
- Provider information

### Checksum Cache
```
F:\study\AI_ML\...\cli\claudecode\backup\state\checksum-cache.json
```

Speeds up future syncs by remembering checksums of previously uploaded files.

## Scheduling

### Windows Task Scheduler
Create a daily backup sync task:

```powershell
# Run as administrator
$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-File 'F:\study\...\backup-sync-cloud.ps1'"
$trigger = New-ScheduledTaskTrigger -Daily -At 2:00AM
Register-ScheduledTask -Action $action -Trigger $trigger -TaskName "Daily Backup Sync" -Description "Sync backups to cloud"
```

### Via Backup Script
Modify your main backup script to call sync after completing:

```powershell
# In your backup-claudecode.ps1:
& 'F:\study\...\backup-sync-cloud.ps1' -Provider s3 -Cleanup
```

## Troubleshooting

### "AWS CLI or AWSPowerShell module required"
Install AWS tools:
```powershell
# Option 1: AWS CLI
choco install awscli

# Option 2: PowerShell module
Install-Module -Name AWSPowerShell -Force
```

### S3 Upload Fails - Access Denied
Check AWS credentials and permissions:
```powershell
aws s3 ls --profile default
aws s3api head-bucket --bucket my-backup-bucket
```

### SMB Upload Slow
Check network speed and reduce bandwidth limit if needed:
```json
"max_bandwidth_mbps": 100
```

Or increase concurrent uploads:
```json
"concurrent_uploads": 5
```

### Checksum Mismatch After Upload
May indicate corruption in transit. The script will:
1. Log the mismatch as an error
2. Retry the upload (per retry_attempts setting)
3. Report failure in final summary

### Config File Not Found
The script expects `backup-sync-cloud.json` in the same directory. You can:
1. Copy from workspace if it doesn't exist
2. Or specify path: `.\backup-sync-cloud.ps1 -ConfigPath "C:\Config\sync.json"`

## Architecture

### Throttler
Custom bandwidth throttler ensures:
- Max throughput = max_bandwidth_mbps
- Smooth rate limiting (no burst/starve)
- Automatic sleep between chunks
- Per-second accounting

### Checksum Management
- Pre-upload: SHA256 of source file
- Post-upload: SHA256 of remote file
- Cached: Stored for next time (if size unchanged)
- Verification: Byte-for-byte integrity check

### Resume Support
- Tracks current upload byte position
- Stores remote file ID/path
- Resumes from last known position
- Works for: SMB, S3 (with boto3/AWS CLI)

### Retention Policies
- Per-provider retention_days setting
- Automatic cleanup on sync
- Preserves recent backups
- Saves cloud storage costs (especially GLACIER)

## Performance Tips

1. **Batch uploads during off-hours**: Schedule around high-traffic times
2. **Use GLACIER for S3**: Cold storage is cheaper for long-term retention
3. **Enable selective sync**: Upload only critical components
4. **Increase bandwidth if available**: Won't hurt other services if isolated backup network
5. **Concurrent uploads**: Increase for high-speed links, decrease for limited bandwidth

## Security Notes

⚠️ **Passwords in JSON**: Consider encrypting before production use:
```powershell
$password = Read-Host -AsSecureString
$encrypted = ConvertFrom-SecureString $password
```

🔐 **API Keys**: Keep credentials.json and secrets safe:
- Store outside repo
- Use Azure Key Vault / AWS Secrets Manager in production
- Rotate keys regularly

🛡️ **SMB Shares**: Use strong domain passwords and restrict share permissions

## Support

For issues or enhancements, check:
1. Log files for detailed error messages
2. Configuration syntax (must be valid JSON)
3. Cloud provider credentials and permissions
4. Network connectivity to cloud services
5. Local disk space for temporary files

## License

MIT License - Use freely for personal and commercial purposes.

---

**Version**: 1.0.0  
**Last Updated**: 2026-03-23  
**PowerShell**: 5.1+  
**OS**: Windows 10/11 (Server 2016+)
