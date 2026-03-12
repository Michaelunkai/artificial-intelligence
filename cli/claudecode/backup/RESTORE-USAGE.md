# restore-claudecode.ps1 v18.0 - USAGE GUIDE

## Quick Start

### Option 1: PowerShell Function (Recommended)
```powershell
resclau
```

### Option 2: Direct Script Execution
```powershell
F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-claudecode.ps1 -Force
```

## Parameters

| Parameter | Type | Description |
|-----------|------|-------------|
| `-BackupPath` | String | Path to specific backup (auto-detects latest if omitted) |
| `-Force` | Switch | Skip confirmation prompts |
| `-SkipPrerequisites` | Switch | Don't install Node.js/Git/Python |
| `-SkipSoftwareInstall` | Switch | Skip npm package installation |
| `-SkipCredentials` | Switch | Don't restore credentials (security consideration) |
| `-SkipRegistry` | Switch | Don't restore registry keys |
| `-SkipEnvVars` | Switch | Don't restore environment variables |
| `-MaxParallelJobs` | Int | Max parallel threads (default: 64) |

## Examples

### Full restore with defaults
```powershell
resclau
```

### Restore from specific backup
```powershell
.\restore-claudecode.ps1 -BackupPath "F:\backup\claudecode\backup_2026_03_09_123456"
```

### Restore without credentials (security consideration)
```powershell
.\restore-claudecode.ps1 -SkipCredentials -Force
```

### Fresh PC install (auto-installs everything)
```powershell
.\restore-claudecode.ps1 -Force
```

## Execution Flow

1. **Pre-Flight Checks** (validates system compatibility)
2. **Rollback Snapshot** (saves current config for safety)
3. **Prerequisites** (installs Node.js, Git, Python if missing)
4. **npm Batch Install** (all global packages in one command)
5. **Parallel File Restore** (64-thread RunspacePool)
6. **Post-Copy Config** (PATH, SSH permissions, registry)
7. **Verification Phase** (tests every tool)
8. **Auto-Repair** (reinstalls broken tools)
9. **Auto-Configuration** (starts services, fixes settings)
10. **Health Score Report** (0-100 with status)

## Health Score Interpretation

| Score | Status | Meaning |
|-------|--------|---------|
| 90-100 | EXCELLENT | Perfect restoration, all systems nominal |
| 70-89 | GOOD | Successful with minor issues |
| 50-69 | FAIR | Significant issues, manual review needed |
| 30-49 | POOR | Critical issues, troubleshooting required |
| 0-29 | CRITICAL | Major failure, manual intervention required |

## What Gets Verified

- ✅ Tool executability (claude, openclaw, moltbot, clawdbot, opencode)
- ✅ OpenClaw Gateway running status
- ✅ Critical file existence + non-empty validation
- ✅ JSON configuration validity
- ✅ Claude API connectivity
- ✅ Git configuration completeness
- ✅ SSH key presence
- ✅ npm package installation
- ✅ Workspace read/write access

## Auto-Repair Actions

If verification detects issues, the script automatically:

- 🔧 Reinstalls broken npm packages
- 🔧 Starts OpenClaw Gateway if down
- 🔧 Configures Git from .gitconfig
- 🔧 Unblocks PowerShell profiles
- 🔧 Cleans npm cache
- 🔧 Fixes PATH environment variable
- 🔧 Sets execution policy to RemoteSigned
- 🔧 Creates missing critical directories

## Rollback (If Needed)

If restoration fails, manually restore from rollback:

```powershell
# Rollback directory is created at:
# C:\Users\<USERNAME>\.openclaw-restore-rollback-<TIMESTAMP>

# Example manual rollback:
Copy-Item -Path "C:\Users\micha\.openclaw-restore-rollback-20260310-184500\openclaw.json" `
          -Destination "C:\Users\micha\.openclaw\openclaw.json" -Force
```

## Logs & Reports

- **Health Report**: `C:\Users\<USERNAME>\.openclaw\restore-report-<TIMESTAMP>.json`
- **Rollback Snapshot**: `C:\Users\<USERNAME>\.openclaw-restore-rollback-<TIMESTAMP>\`

## Troubleshooting

### "Script failed with errors"
- Check health report JSON for details
- Review error list in terminal output
- Check rollback directory for original configs

### "Tools not found after restore"
- Restart PowerShell terminal (PATH changes require new session)
- Run: `refreshenv` or close/reopen terminal

### "OpenClaw Gateway won't start"
- Check: `openclaw gateway status`
- Manual start: `openclaw gateway start`
- Logs: `openclaw gateway logs`

### "npm packages missing"
- Run: `npm list -g --depth=0`
- Manual reinstall: `npm install -g @anthropic-ai/claude-code openclaw moltbot clawdbot`

## Fresh Windows 11 Install Workflow

1. Install Windows 11
2. Open PowerShell as Administrator
3. Run: `Set-ExecutionPolicy RemoteSigned -Scope CurrentUser -Force`
4. Copy restore script to machine
5. Run: `.\restore-claudecode.ps1 -Force`
6. Wait for completion (script auto-installs everything)
7. Check health score (should be 90-100)
8. Restart terminal
9. Verify: `claude --version`, `openclaw --version`

## Version History

- **v18.0 (2026-03-10)**: BULLETPROOF EDITION
  - Added pre-flight checks
  - Added rollback protection
  - Added verification phase
  - Added auto-repair
  - Added auto-configuration
  - Added health score system
  
- **v17.0**: TURBO PARALLEL EDITION
  - 64-thread RunspacePool
  - npm batch install
  - Fast file operations

## Support

For issues, check:
1. Health report JSON (detailed diagnostics)
2. Terminal error output
3. Rollback directory (original configs)
4. OpenClaw logs: `openclaw gateway logs`
