# Claude Code + OpenClaw Backup System — ADMIN GUIDE

**Version:** 21.0 LEAN BLITZ  
**Audience:** System administrators, power users, CI/CD pipeline builders  
**Last Updated:** 2026-03-23

---

## Table of Contents

1. [Architecture Overview](#architecture-overview)
2. [System Components](#system-components)
3. [Internal Design](#internal-design)
4. [Configuration & Customization](#configuration--customization)
5. [Performance Tuning](#performance-tuning)
6. [Security Considerations](#security-considerations)
7. [Integration with External Systems](#integration-with-external-systems)
8. [Monitoring & Logging](#monitoring--logging)
9. [Scaling for Large Teams](#scaling-for-large-teams)

---

## Architecture Overview

### High-Level Flow

```
┌─────────────────────────────────────────────────────────────┐
│              Claude Code + OpenClaw v21.0 Backup            │
└─────────────────────────────────────────────────────────────┘

User Input (Telegram /backclau)
         │
         ▼
  PowerShell Script Launch
         │
    ┌────┴────────────────────────────────────────────┐
    │                                                  │
    ▼                                                  ▼
[P0] Cache Commands            [P1] Main Copy Phase
  - npm info                         - RoboCopy x32 parallel
  - tool versions                    - 150+ directories
  - pip freeze                       - Real-time progress
  - schtasks                         - Task timeout: 120-300s
    │                                - Error tracking
    │                                ├─ .claude (50 MB)
    │                                ├─ .openclaw (800 MB)
    │                                ├─ AppData (500 MB)
    │                                ├─ Browser IndexedDB
    │                                └─ Configs & keys
    │
    ├─────────────────────────────────────────┐
    │                                          │
    ▼                                          ▼
[P2] Small Files              [P3] Metadata Generation
  - 30+ individual files         - BACKUP-METADATA.json
  - npm config                   - Tool versions
  - MCP config                   - Registry dumps
  - Registry exports             - Credential manifest
  - Credentials dir              - Environment variables
    │
    ├─────────────────────────────────────────┐
    │                                          │
    ▼                                          ▼
[P4] Project .claude Scan     [P5] Optional Cleanup
  - Recursive search (depth 5)   - Remove caches
  - Exclude: .git, node_modules  - Remove logs
  - Per-project backup           - Remove old CLI bins
                                  - Free 850+ MB
                                  
                                  ▼
                         Backup Summary Report
```

### Design Principles

**LEAN BLITZ (v21.0):**
- **Exclude garbage:** ~850 MB of regeneratable caches removed
- **Parallel execution:** 32 concurrent RoboCopy tasks (configurable)
- **Real-time progress:** Print completed tasks as they finish
- **Smart timeout:** Per-task timeout to prevent hangs
- **Comprehensive coverage:** 150+ directories + catch-all scanners

---

## System Components

### Phase 0: Command Caching

**Purpose:** Gather version info, environment state BEFORE any copying.

**What it caches:**
```
npm:
  - node --version
  - npm --version
  - npm config get prefix
  - npm list -g --json          (dependency tree)

versions:
  - claude --version
  - openclaw --version
  - clawdbot --version
  - moltbot --version
  - opencode --version
  (with PATH lookups)

schtasks:
  - schtasks /query /fo CSV /v  (all scheduled tasks)

cmdkey:
  - cmdkey /list                (stored Windows credentials)

pip:
  - pip freeze                  (Python packages)
```

**Implementation:**
```powershell
$cp = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 5)
$cp.Open()
# 5 parallel runspace pools to execute commands simultaneously
# 15-second timeout per command
```

**Output:** `cmdCache` hashtable (stored in BACKUP-METADATA.json)

---

### Phase 1: Main Copy Phase

**Purpose:** Copy all directories and large files in parallel.

**Key Features:**

#### RoboCopy Configuration
```powershell
robocopy "$src" "$dst" /E /R:0 /W:0 /MT:32 /NFL /NDL /NJH /NJS
  │       │      │      │    │     │     │     │   │   │   │
  │       │      │      │    │     │     │     │   │   │   └─ No Job Summary
  │       │      │      │    │     │     │     │   │   └───── No Job Header
  │       │      │      │    │     │     │     │   └───────── No File List
  │       │      │      │    │     │     │     └───────────── Multithreaded (32 threads)
  │       │      │      │    │     │     └─────────────────── Wait 0ms between retries
  │       │      │      │    │     └───────────────────────── Retry 0 times
  │       │      │      │    └───────────────────────────── Copy subfolders
  │       │      │      └───────────────────────────────── Exclude dirs (XD)
  │       │      └──────────────────────────────────────── Destination
  │       └─────────────────────────────────────────────── Source
  └──────────────────────────────────────────────────────── Binary copy tool
```

#### Excluded Directories

**From `.claude` directory:**
```
file-history    (26 MB of edit history cache)
cache           (8 MB of computed caches)
paste-cache     (1 MB clipboard cache)
image-cache     (4 MB cached images)
shell-snapshots (5 MB shell output snapshots)
debug           (logs)
test-logs       (logs)
downloads       (old downloads)
session-env     (temp env state)
telemetry       (telemetry data)
statsig         (feature flag cache)
```

**From `AppData\Roaming\Claude`:**
```
Code Cache      (50 MB VS Code extension cache)
GPUCache        (unused GPU cache)
DawnGraphiteCache, DawnWebGPUCache (GPU caches)
Crashpad        (crash dumps)
Network         (networking cache)
blob_storage    (blob cache)
Session Storage (session cache)
Local Storage   (local storage cache)
```

**Rationale:**
- These are **regenerated on next app launch**
- Excluding them saves ~850 MB per backup
- No user data is lost

#### Dynamic Directory Scanning

The script does **automatic discovery** of unknown directories:

```powershell
# Scan for unknown .openclaw subdirectories
Get-ChildItem "$HOME\.openclaw" -Directory | Where-Object {
    $knownOC -notcontains $_.Name    # Not in known list
}

# Scan for unknown .config/claude* directories
Get-ChildItem "$HOME\.config" -Directory | Where-Object {
    $_.Name -match "claude|openclaw|cagent|browserclaw"
}

# Scan for unknown AppData\Roaming entries
Get-ChildItem $env:APPDATA -Directory | Where-Object {
    $_.Name -match "claude|openclaw|anthropic"
}
```

**Benefits:**
- No manual updating when new tools are installed
- New Claude versions automatically included
- Plugin/extension directories discovered automatically

#### Parallel Execution (Runspace Pool)

```powershell
$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxJobs)
$pool.ApartmentState = "MTA"
$pool.Open()

# Submit all tasks at once
foreach ($task in $allTasks) {
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    $ps.AddScript($copyScript).AddArgument(...) | Out-Null
    $handles.Add(@{ PS=$ps; Handle=$ps.BeginInvoke(); Desc=$task.Desc })
}

# Poll for completion
while ($pending.Count -gt 0) {
    foreach ($h in $pending) {
        if ($h.Handle.IsCompleted) {
            $h.PS.EndInvoke($h.Handle)
            $h.PS.Dispose()
        }
    }
}
```

**Design:**
- Default 32 parallel workers (configurable via `-MaxJobs`)
- Each worker manages one RoboCopy task
- Workers complete independently (no blocking)
- Real-time progress queue (ConcurrentBag + ConcurrentQueue)

#### Global Timeout

```powershell
$globalDeadline = (Get-Date).AddMinutes(10)  # Hard 10-minute limit

while ($pending.Count -gt 0) {
    if ((Get-Date) -gt $globalDeadline) {
        # Kill all remaining tasks
        foreach ($h in $pending) { $h.PS.Stop() }
        break
    }
}
```

- Prevents infinite hangs
- Can be adjusted in config
- Per-task timeouts still apply

---

### Phase 2: Small Files

**Purpose:** Copy individual config files, credentials, and metadata.

**Files included:**
- `.gitconfig`, `.npmrc`, `.ssh` keys
- PowerShell profiles
- MCP `claude_desktop_config.json`
- OpenClaw config files (30+ JSON/XML files)
- Windows Terminal settings
- Startup shortcuts

**Why separate from Phase 1?**
- Small files don't benefit from parallel RoboCopy
- Can use direct `[System.IO.File]::Copy()` (faster for small files)
- Easier to handle individually

---

### Phase 3: Metadata Generation

**Purpose:** Generate manifest files for verification and recovery.

**Generated files:**

#### BACKUP-METADATA.json
```json
{
  "Version": "21.0 LEAN BLITZ",
  "Timestamp": "2026-03-23T14:30:15.0000000Z",
  "Computer": "HOSTNAME",
  "User": "username",
  "BackupPath": "F:\\backup\\claudecode\\backup_2026_03_23_14_30_15",
  "Items": 14532,
  "SizeMB": 2847.50,
  "Errors": [
    "TIMEOUT: /chrome/p1-blob (file locked)",
    "FAIL: /node_modules/xyz (access denied)"
  ],
  "Duration": 187.5,
  "Excluded": [
    "file-history",
    "cache",
    "Code Cache",
    "...850MB+ of regeneratable items"
  ]
}
```

#### tool-versions.json
```json
{
  "claude": {
    "Path": "C:\\Users\\user\\AppData\\Roaming\\npm\\claude.cmd",
    "Version": "0.8.5"
  },
  "openclaw": {
    "Path": "C:\\Users\\user\\AppData\\Roaming\\npm\\openclaw.cmd",
    "Version": "2.1.3"
  }
}
```

#### node-info.json
```json
{
  "NodeVersion": "v24.13.0",
  "NpmVersion": "10.8.3",
  "NpmPrefix": "C:\\Users\\user\\AppData\\Roaming\\npm",
  "Timestamp": "2026-03-23T14:30:15.0000000Z"
}
```

#### global-packages.json
```json
{
  "dependencies": {
    "claude": { "version": "0.8.5" },
    "openclaw": { "version": "2.1.3" },
    "moltbot": { "version": "1.2.4" }
  }
}
```

#### REINSTALL-ALL.ps1
```powershell
# Auto-generated script to reinstall all npm packages
npm install -g claude@0.8.5
npm install -g openclaw@2.1.3
npm install -g moltbot@1.2.4
# ... all global packages
```

#### environment-variables.json
```json
{
  "USER_CLAUDE_API_KEY": "sk-***",
  "USER_OPENAI_API_KEY": "sk-***",
  "USER_PATH": "C:\\Program Files\\...",
  "USER_PYTHONPATH": "..."
}
```

#### Registry Exports
```powershell
# HKCU-Environment.reg
# HKCU-Software-Claude.reg
# Exported via: reg export HKEY_CURRENT_USER\<key> file.reg
```

---

### Phase 4: Project .claude Scanning

**Purpose:** Discover and backup `.claude` directories in project repos.

**Search paths:**
```
$HOME\Projects            (depth 5)
$HOME\repos              (depth 5)
$HOME\dev                (depth 5)
$HOME\code               (depth 5)
F:\Projects              (depth 5)
D:\Projects              (depth 5)
F:\study                 (depth 5)
```

**Filters:**
- Must be directory named `.claude`
- Must not be inside: `node_modules`, `.git`, `__pycache__`, `.venv`, `venv`, `dist`, `build`

**Output structure:**
```
backup/
└─ project-claude/
   ├─ F_study_AI_ML_..._project1_.claude/  (sanitized path)
   ├─ F_Projects_project2_.claude/
   └─ ...
```

**Rationale:**
- Each project may have Claude-specific hooks, commands, settings
- Useful for developers switching between projects
- Paths are sanitized (`:` → `_`, `\` → `_`) for Windows compatibility

---

### Phase 5: Optional Cleanup

**Purpose:** Free space on live system by removing regeneratable garbage.

**Safe cleanup targets:**
```
$HOME\.claude\file-history      (26 MB)
$HOME\.claude\cache             (8 MB)
$HOME\.claude\paste-cache       (1 MB)
$HOME\.claude\image-cache       (4 MB)
$HOME\.claude\shell-snapshots   (5 MB)
$APPDATA\Claude\Code Cache      (50 MB)
$APPDATA\Claude\GPUCache        (8 MB)
$HOME\.cache\opencode           (varies)
$HOME\.openclaw\logs            (varies)
Old CLI version binaries        (230+ MB)
```

**Smart version management:**
```powershell
# Keep only latest CLI version, delete old ones
$versions = Get-ChildItem "$HOME\.local\share\claude\versions" | Sort-Object -Descending
$keep = $versions[0]
$versions | Select-Object -Skip 1 | Remove-Item -Recurse -Force
```

**Locked file handling:**
```powershell
try {
    Remove-Item $path -Recurse -Force -ErrorAction Stop
} catch {
    Write-Host "[LOCKED] $path - in use" -ForegroundColor Yellow
    # Skip locked files, don't fail
}
```

**Safety:**
- Only removes items known to be **regeneratable**
- Asks for confirmation before deletion (via `-Cleanup` flag)
- Logs all deletions
- Skips locked files gracefully

---

## Internal Design

### Error Handling Strategy

**Concurrent error collection:**
```powershell
$script:Errors = [System.Collections.Concurrent.ConcurrentBag[string]]::new()

# From worker threads:
$errBag.Add("TIMEOUT: /some/path")
$errBag.Add("FAIL: /another/path")
```

**Real-time logging:**
```powershell
$script:DoneLog = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()

# Worker outputs:
$doneLog.Enqueue("[OK] .claude settings")
$doneLog.Enqueue("[FAIL] /locked/file")

# Main thread drains periodically:
while ($doneLog.TryDequeue([ref]$msg)) {
    Write-Host "  [$completed/$total] $msg" -ForegroundColor DarkGray
}
```

**Error tolerance:**
- Errors are **recorded but non-fatal**
- Backup completes even if some files fail
- Summary shows error count at end
- User can retry failed items

### Performance Characteristics

**Time complexity:**
- Single file: O(1) (1-2 KB overhead per file)
- Directory tree: O(n) where n = file count
- Parallel overhead: O(n/m) where m = thread count

**Typical performance:**
```
Backup size      Time        Speed
─────────────────────────────────────
1 GB            30-60s       16-33 MB/s
2 GB            60-120s      16-33 MB/s
5 GB            2-4 min      20-40 MB/s
10 GB           4-8 min      20-40 MB/s
```

**Bottlenecks (in order):**
1. Disk I/O (slow HDD vs fast SSD = 2-4x difference)
2. Parallel thread count (32 threads is optimal, diminishing returns beyond 64)
3. File count (many small files slower than few large files)
4. Antivirus scanning (can add 50% overhead)

### Memory Usage

**Runspace pool:**
- Per thread: ~5-10 MB
- 32 threads = 160-320 MB

**Concurrent collections:**
- Error bag: varies (typically <1 MB)
- Done queue: varies (typically <5 MB)

**Total:** ~400-500 MB average, peak 800 MB

### File Locking Strategy

**Problem:** Files locked by running processes cause timeouts.

**Solutions implemented:**

1. **Per-task timeout (120-300s)**
   - If RoboCopy doesn't finish in time, kill it
   - Don't wait forever for locked files

2. **No retry queue**
   - Retrying locked files wastes time
   - Mark as [FAIL] and continue
   - User can retry manually if needed

3. **Global timeout (10 minutes)**
   - Entire backup has hard deadline
   - Prevents runaway processes

4. **Graceful degradation**
   - Missing files ≠ backup failure
   - Missing 5% of files ≠ unusable backup
   - Most failures are logs, caches, temp files

---

## Configuration & Customization

### Script Parameters

```powershell
param(
    [string]$BackupPath = "F:\backup\claudecode\backup_$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss')",
    [int]$MaxJobs = 32,
    [switch]$Cleanup
)
```

### Environment Variables

**Override backup location:**
```powershell
$env:BACKUP_PATH = "D:\my-backups"
```

**Skip project scanning (for speed):**
```powershell
$env:SKIP_PROJECT_SEARCH = "1"
```

**Increase verbosity (for debugging):**
```powershell
$DebugPreference = "Continue"
```

### Modifying Exclusion Lists

**Add directories to exclude from `.claude` backup:**
```powershell
$claudeExcludeDirs = @(
    'file-history',
    'cache',
    'paste-cache',
    'image-cache',
    'shell-snapshots',
    'debug',
    'test-logs',
    'downloads',
    'session-env',
    'telemetry',
    'statsig',
    'my-custom-cache'    # ← Add here
)
```

**Add files to small-files phase:**
```powershell
$smallFiles = @(
    @("$HP\.gitconfig", "$BackupPath\git\gitconfig"),
    @("$HP\.my-config.json", "$BackupPath\special\my-config.json"),  # ← Add here
)
```

**Add directories to full backup:**
```powershell
Add-Task "$HP\my-important-dir" "$BackupPath\custom\my-dir" "My custom directory" 120
```

---

## Performance Tuning

### Optimize for Speed

**Increase parallel jobs (if you have CPU to spare):**
```powershell
powershell -File "backup-claudecode.ps1" -MaxJobs 64
# Expected: 30-50% faster on 8+ core systems
# Risk: Uses more RAM, more disk I/O contention
```

**Reduce source I/O contention:**
```powershell
# Close antivirus scanner
# Stop Node.js servers
# Close IDE/editor
# Stop Docker
# Then run backup
```

**Use faster destination disk:**
```powershell
# SSD backup is 2-4x faster than HDD
powershell -File "backup-claudecode.ps1" -BackupPath "C:\fast-ssd\backup"
```

**Profile CPU/disk:**
```powershell
# Windows Performance Monitor
perfmon.msc

# Watch: %CPU, Disk I/O, Memory during backup
```

### Optimize for Reliability

**Reduce parallel jobs (for slow/fragmented systems):**
```powershell
powershell -File "backup-claudecode.ps1" -MaxJobs 8
# Trade speed for stability
```

**Increase per-task timeout:**
```powershell
# Edit backup-claudecode.ps1
# Find: Add-Task ... -T 120
# Change 120 to 300 (5 minutes)
```

**Run in low-priority mode:**
```powershell
$proc = Start-Process powershell -ArgumentList @(
    '-NoProfile'
    '-File "...\backup-claudecode.ps1"'
) -PassThru
(Get-Process -Id $proc.Id).PriorityClass = "BelowNormal"
```

### Monitor During Backup

**Real-time task manager view:**
```powershell
# Open Task Manager
taskmgr.exe

# Watch: Resource Monitor tab
# CPU: should spike to 40-70%
# Disk: should show heavy activity
# Memory: should be 500-1000 MB
```

**Log to file:**
```powershell
powershell -File "backup-claudecode.ps1" | Tee-Object "backup-$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
```

---

## Security Considerations

### Credential Handling

**Credentials ARE backed up:**
- `.claude.json` (may contain API keys)
- `.openclaw/credentials` (authentication tokens)
- `.ssh` (SSH keys)
- Credential Manager dump

**Risks:**
- Backup contains sensitive data
- If backup is stolen, attacker has credentials
- Credentials never expire from old backups

**Mitigations:**

1. **Encrypt backup storage:**
   ```powershell
   # Use Windows encryption (BitLocker)
   manage-bde -status
   manage-bde -on F:  # Encrypt F: drive
   ```

2. **Restrict backup folder permissions:**
   ```powershell
   $acl = Get-Acl "F:\backup\claudecode"
   $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
       "$env:USERNAME",
       "FullControl",
       "ContainerInherit,ObjectInherit",
       "None",
       "Allow"
   )
   $acl.SetAccessRule($rule)
   Set-Acl -Path "F:\backup\claudecode" -AclObject $acl
   ```

3. **Rotate credentials periodically:**
   ```
   Every 90 days:
   - Regenerate API keys
   - Update .claude.json
   - Create new backup (old backup has stale keys)
   ```

4. **For cloud backups, encrypt before uploading:**
   ```powershell
   # Zip + encrypt locally, upload encrypted file
   $plainBackup = "F:\backup\claudecode\backup_xxx"
   $zipPath = "$plainBackup.zip"
   $encPath = "$zipPath.encrypted"
   
   Compress-Archive $plainBackup $zipPath
   
   # Use gpg or similar
   gpg --encrypt --recipient "your-key" $zipPath
   ```

### Access Control

**Who can access backups?**
```powershell
# Current user only (recommended)
icacls "F:\backup\claudecode" /grant:r "$env:USERNAME:(F)" /T /C
icacls "F:\backup\claudecode" /remove "Builtin\Users" /T /C
```

**Audit access:**
```powershell
# Enable audit on backup folder
auditpol.exe /set /category:"Object Access" /subcategory:"File System" /success:enable /failure:enable
```

### External Storage

**For USB drives:**
- Encrypt with BitLocker (Windows)
- Or 7-Zip with AES-256 encryption

**For cloud (OneDrive, Google Drive):**
- Don't upload unencrypted
- Encrypt locally first (7-Zip, VeraCrypt)
- Keep API keys out of backup if possible

**For NAS:**
- Backups should be on encrypted NAS volume
- Restrict NAS folder permissions
- Use SSH/VPN for network access

### Compliance & Privacy

**GDPR/Privacy:**
- Backup contains PII (paths, environment variables, browser history)
- If handling others' data, ensure backups are encrypted
- Retention policy: delete old backups after 1 year

**Credential exposure audit:**
```powershell
# Search backup for potential secrets
$backupPath = "F:\backup\claudecode\backup_xxx"

Get-ChildItem $backupPath -Recurse -File -Include "*.json","*.conf","*.cfg","*.ini" -EA SilentlyContinue |
    ForEach-Object {
        $content = Get-Content $_.FullName -Raw -EA SilentlyContinue
        if ($content -match 'password|token|secret|api.?key|bearer') {
            Write-Host "⚠ Potential secret in: $($_.FullName)" -ForegroundColor Yellow
        }
    }
```

---

## Integration with External Systems

### Backup to Network Shares

**Map network drive:**
```powershell
New-PSDrive -Name "B" -PSProvider FileSystem -Root "\\server\backups" -Credential $(Get-Credential)
powershell -File "backup-claudecode.ps1" -BackupPath "B:\claudecode_$(Get-Date -Format 'yyyy_MM_dd')"
```

**Using UNC paths directly:**
```powershell
powershell -File "backup-claudecode.ps1" -BackupPath "\\192.168.1.100\backups\claudecode_$(Get-Date -Format 'yyyy_MM_dd')"
```

### Backup to Cloud Storage

**Azure Blob Storage:**
```powershell
# Upload backup to Azure
$backup = "F:\backup\claudecode\backup_xxx"
$storageAccount = "mybackups"
$container = "claudecode"

Get-ChildItem $backup -Recurse -File | ForEach-Object {
    $blobName = $_.FullName.Replace($backup, '').TrimStart('\')
    az storage blob upload `
        --account-name $storageAccount `
        --container-name $container `
        --name $blobName `
        --file $_.FullName
}
```

**AWS S3:**
```powershell
# Sync backup to S3
$backup = "F:\backup\claudecode\backup_xxx"
aws s3 sync $backup s3://my-claudecode-backups/$(Split-Path $backup -Leaf) `
    --include "*" `
    --exclude "*.log"
```

**Backblaze B2:**
```powershell
# Upload via rclone
rclone sync "F:\backup\claudecode" "b2:my-backups/claudecode"
```

### Integration with CI/CD

**GitHub Actions:**
```yaml
# .github/workflows/backup.yml
name: Backup

on:
  schedule:
    - cron: '0 2 * * 0'  # Weekly Sunday 2 AM

jobs:
  backup:
    runs-on: windows-latest
    steps:
      - name: Checkout backup script
        uses: actions/checkout@v3
      
      - name: Run backup
        run: |
          powershell -File "backup/backup-claudecode.ps1" -BackupPath "D:\backups"
      
      - name: Upload to Azure
        run: |
          az storage blob upload-batch `
            -d "claudecode" `
            -s "D:\backups"
            -account-name "${{ secrets.BACKUP_STORAGE }}"
```

### Jenkins Pipeline

```groovy
pipeline {
    triggers {
        cron('0 2 * * 0')  // Weekly
    }
    
    stages {
        stage('Backup') {
            steps {
                powershell '''
                    & "C:\\scripts\\backup-claudecode.ps1" `
                        -BackupPath "D:\\jenkins-backups" `
                        -Cleanup
                '''
            }
        }
        
        stage('Verify') {
            steps {
                powershell '''
                    $backup = Get-ChildItem D:\\jenkins-backups -Directory | Sort-Object -Descending | Select-Object -First 1
                    $meta = Get-Content "$($backup.FullName)\\BACKUP-METADATA.json" | ConvertFrom-Json
                    if ($meta.Errors.Count -gt 0) {
                        Write-Host "⚠ Backup has $($meta.Errors.Count) errors" -ForegroundColor Yellow
                        exit 1
                    }
                '''
            }
        }
        
        stage('Upload') {
            steps {
                powershell '''
                    $backup = Get-ChildItem D:\\jenkins-backups -Directory | Sort-Object -Descending | Select-Object -First 1
                    aws s3 sync $backup.FullName s3://company-backups/claudecode/
                '''
            }
        }
    }
}
```

---

## Monitoring & Logging

### Backup Success Metrics

**Track:**
```powershell
# Extract from BACKUP-METADATA.json
$meta = Get-Content "backup_xxx/BACKUP-METADATA.json" | ConvertFrom-Json

Write-Host "Items backed up: $($meta.Items)"
Write-Host "Size: $($meta.SizeMB) MB"
Write-Host "Duration: $($meta.Duration)s"
Write-Host "Error count: $($meta.Errors.Count)"
Write-Host "Success rate: $(100 - ($meta.Errors.Count / $meta.Items * 100))%"
```

**Expected values:**
```
Items:          13,000-15,000
Size:           2,500-3,500 MB
Duration:       120-300 seconds
Error count:    0-10 (mostly logs/temp)
Success rate:   99%+
```

### Log Aggregation

**Centralized logging:**
```powershell
# Create a log database
$logFile = "F:\backup\claudecode\backup-history.json"
$history = @()

if (Test-Path $logFile) {
    $history = Get-Content $logFile | ConvertFrom-Json
}

# Add latest backup
$backup = Get-ChildItem "F:\backup\claudecode\backup_*" -Directory | Sort-Object -Descending | Select-Object -First 1
$meta = Get-Content "$($backup.FullName)\BACKUP-METADATA.json" | ConvertFrom-Json

$history += @{
    Timestamp = $meta.Timestamp
    Items = $meta.Items
    SizeMB = $meta.SizeMB
    Duration = $meta.Duration
    Errors = $meta.Errors.Count
}

$history | ConvertTo-Json | Out-File $logFile
```

### Alerting

**Email on failure:**
```powershell
$backup = Get-ChildItem "F:\backup\claudecode" -Directory | Sort-Object -Descending | Select-Object -First 1
$meta = Get-Content "$($backup.FullName)\BACKUP-METADATA.json" | ConvertFrom-Json

if ($meta.Errors.Count -gt 5) {
    $params = @{
        To = 'admin@example.com'
        From = 'backup@example.com'
        Subject = "⚠ Backup has errors: $($meta.Errors.Count)"
        Body = ($meta.Errors | ConvertTo-Json)
        SmtpServer = 'smtp.example.com'
    }
    Send-MailMessage @params
}
```

### Grafana Dashboard

```json
{
  "dashboard": {
    "title": "Claude Code Backup Health",
    "panels": [
      {
        "title": "Backup Size Trend",
        "targets": [{"expr": "backup_size_mb"}]
      },
      {
        "title": "Duration Trend",
        "targets": [{"expr": "backup_duration_seconds"}]
      },
      {
        "title": "Error Rate",
        "targets": [{"expr": "backup_errors / backup_items"}]
      }
    ]
  }
}
```

---

## Scaling for Large Teams

### Multi-User Environment

**Backup all users on a system:**
```powershell
$users = Get-ChildItem "C:\Users" -Directory | Where-Object { $_.Name -notmatch "^(Public|Default|All Users|System|NetworkService)" }

foreach ($user in $users) {
    Write-Host "Backing up $($user.Name)..." -ForegroundColor Cyan
    
    $backupPath = "F:\backup\all-users\$($user.Name)_$(Get-Date -Format 'yyyy_MM_dd')"
    
    # Run backup as that user
    $cred = Get-Credential -UserName "$env:COMPUTERNAME\$($user.Name)" -Message "Enter password for $($user.Name)"
    
    Start-Process powershell -ArgumentList @(
        '-NoProfile'
        '-File "backup-claudecode.ps1"'
        "-BackupPath `"$backupPath`""
    ) -Credential $cred
}
```

### Centralized Backup Server

**Pull backups from all machines:**
```powershell
# On backup server
$machines = @('workstation1', 'workstation2', 'laptop1')

foreach ($machine in $machines) {
    $path = "\\$machine\c$\Users\<user>\.claude"
    $dest = "F:\backups\central\$machine\claude"
    
    robocopy $path $dest /E /R:3 /W:1 /MT:32
}
```

### Incremental Backups at Scale

```powershell
# Use VSS snapshots for consistency
$shadow = (Get-WmiObject Win32_ShadowCopy -Filter "ID='<snapshot-id>'").DeviceObject + "\"
robocopy "$shadow`Users\user\.claude" "F:\incremental\claude" /E /M  # /M = only changed files
```

### Deduplication

```powershell
# If backup storage supports deduplication
# (e.g., Windows Data Deduplication, ZFS, etc.)
# Multiple similar backups take minimal extra space

Enable-DedupVolume F:
Start-DedupJob -Type Optimization -Volume F: -Priority High
```

---

## Reference

### File Manifest

```
backup_YYYY_MM_DD_HH_MM_SS/
├── BACKUP-METADATA.json          ← Key metadata file
├── core/
│   ├── claude-home/               (.claude full directory)
│   ├── claude.json
│   └── claude.json.backup
├── openclaw/
│   ├── workspace-main/
│   ├── workspace-moltbot2/
│   ├── workspace-openclaw/
│   ├── credentials-dir/
│   ├── extensions/
│   ├── skills/
│   ├── sessions-dir/
│   └── rolling-backups/           (config snapshots)
├── appdata/
│   ├── roaming-claude/            (AppData\Roaming\Claude)
│   └── roaming-claude-code/
├── chrome/
│   ├── p1-blob/                   (IndexedDB blob storage)
│   ├── p1-leveldb/
│   ├── p2-blob/
│   └── p2-leveldb/
├── npm-global/
│   ├── node-info.json
│   ├── global-packages.json
│   ├── global-packages.txt
│   ├── REINSTALL-ALL.ps1
│   └── npmrc
├── meta/
│   ├── tool-versions.json
│   ├── software-info.json
│   └── BACKUP-METADATA.json (copy)
├── credentials/
│   ├── claude-credentials.json
│   ├── openclaw-auth/
│   ├── claude-json-auth/
│   └── credential-manager-full.txt
├── env/
│   └── environment-variables.json
├── registry/
│   ├── HKCU-Environment.reg
│   └── HKCU-Software-Claude.reg
└── scheduled-tasks/
    └── relevant-tasks.json
```

### Performance Tuning Checklist

- [ ] Increase `-MaxJobs` for faster backups (if CPU available)
- [ ] Schedule backups during off-hours
- [ ] Use SSD for destination (2-4x faster)
- [ ] Exclude network drives from backup
- [ ] Enable hardware compression if supported
- [ ] Use `-Cleanup` to reclaim space
- [ ] Monitor `perfmon.msc` during backup
- [ ] Test restore on staging system first
- [ ] Verify backup before marking as successful
- [ ] Rotate old backups to save space

---

**For user documentation, see [USER_GUIDE.md](USER_GUIDE.md)**  
**For troubleshooting, see [TROUBLESHOOTING.md](TROUBLESHOOTING.md)**
