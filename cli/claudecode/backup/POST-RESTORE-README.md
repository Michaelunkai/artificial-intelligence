# Post-Restore Setup Script

**Location:** `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\post-restore-setup.ps1`

**Version:** 1.0  
**Last Updated:** 2025-03-23

## Overview

This script runs **AFTER** `restore-claudecode.ps1` completes. It handles all post-restore verification, configuration, and testing to ensure your Claude Code CLI and OpenClaw environment are fully functional.

## What It Does

### ✅ 10 Restoration Steps

1. **NPM Package Re-Registration** — Re-links globally installed NPM packages using `npm link`
2. **Credential Re-Authentication** — Verifies GitHub, Anthropic API, and OpenClaw credentials
3. **MCP Server Path Verification** — Checks all MCP server executable paths exist
4. **OpenClaw Gateway Service** — Registers OpenClaw Gateway as Windows service (requires admin)
5. **Scheduled Tasks** — Creates 3 automated tasks:
   - Daily backup (2 AM)
   - OpenClaw startup (at login)
   - Auto-sync dotfiles (every 6 hours)
6. **Desktop Shortcuts** — Recreates Claude Code and OpenClaw shortcuts on desktop
7. **Startup Shortcuts** — Creates OpenClaw auto-start shortcut in Windows Startup folder
8. **Environment Variables** — Validates critical ENV vars (ANTHROPIC_API_KEY, PATH)
9. **Claude Code CLI Test** — Runs `claude --version` to verify installation
10. **OpenClaw Test** — Runs `openclaw status` to verify CLI accessibility

### 📊 Final Checklist

Displays comprehensive results including:
- Success/failure count
- Item-by-item status
- Next steps for manual verification
- Log file locations for debugging

## Usage

### Basic (Interactive)
```powershell
# Call AFTER restore-claudecode.ps1 completes
. "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\post-restore-setup.ps1"
```

### With Verbose Output
```powershell
. "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\post-restore-setup.ps1" -Verbose
```

### Skip Interactive Prompts
```powershell
. "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\post-restore-setup.ps1" -SkipInteractive
```

## Logging

Two log files are created in the same directory as the script:

- **`post-restore-setup_YYYY-MM-DD_HHMMSS.log`** — Complete execution log
- **`post-restore-setup_errors_YYYY-MM-DD_HHMMSS.log`** — Errors only (for debugging)

## Requirements

### Required
- Windows PowerShell 5.1+
- Python 3.8+
- NPM (for package re-registration)
- Git (for credential verification)

### Optional (but recommended)
- Administrator privileges (for service registration and scheduled tasks)
- Internet connection (for credential re-authentication)

## Configuration Files

The script checks/creates the following:

| Item | Location | Purpose |
|------|----------|---------|
| NPM packages | `npm list -g` | Re-registers global packages |
| Git config | `~\.gitconfig` | GitHub credentials |
| Anthropic API key | `~\.anthropic\api_key` | API authentication |
| OpenClaw config | `~\.openclaw\openclaw.json` | Gateway settings |
| MCP servers | `%APPDATA%\Local\Claude\mcp.json` | MCP configuration |

## Exit Codes

The script uses `$ErrorActionPreference = "Continue"` to continue on errors rather than stopping. Check the log files for details.

## Service Registration

If running as admin, OpenClaw Gateway will be registered as a Windows service:

```powershell
# Verify service exists
Get-Service -Name OpenClawGateway

# Manually start/stop
Start-Service -Name OpenClawGateway
Stop-Service -Name OpenClawGateway

# Check status
Get-Service -Name OpenClawGateway | Select-Object Status
```

## Scheduled Tasks

Three scheduled tasks are created (if admin):

| Task Name | Trigger | Action |
|-----------|---------|--------|
| `ClaudeCodeDailyBackup` | Daily at 2 AM | Runs backup-claudecode.ps1 |
| `OpenClawStartup` | At login | Starts OpenClaw gateway |
| `DotfilesAutoSync` | Every 6 hours | Runs sync-all-bots.ps1 |

View in Task Scheduler:
```powershell
Get-ScheduledTask | Where-Object TaskName -Match "ClaudeCode|OpenClaw|Dotfiles"
```

## Troubleshooting

### "This script cannot be executed because it is disabled on this system"
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### "Not running as admin" warning
Some features (services, scheduled tasks) require admin. Run PowerShell as Administrator.

### NPM link fails
NPM packages may already be linked. The script logs warnings but continues.

### Claude CLI not found
Ensure `C:\Users\<username>\.claude\bin` is in your PATH.

### OpenClaw CLI not found
Ensure `C:\Users\<username>\.openclaw` is in your PATH or accessible.

## Log File Format

Each log entry includes timestamp, level, and message:
```
[2025-03-23 19:41:30] [INFO] Starting post-restore setup...
[2025-03-23 19:41:31] [SUCCESS] ✓ Claude CLI works: claude v0.1.0
[2025-03-23 19:41:32] [WARN] ⚠ Anthropic API key not found
```

## Integration with restore-claudecode.ps1

The parent script calls this automatically:

```powershell
# In restore-claudecode.ps1:
. "$backupDir\post-restore-setup.ps1"
```

Or manually after restore:

```powershell
$backupDir = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
. "$backupDir\post-restore-setup.ps1"
```

## Next Steps After Script Completes

1. **Review the final checklist** output on screen
2. **Check log files** for any ⚠️ warnings or ✗ errors
3. **Manually re-authenticate** if credentials show as incomplete
4. **Test manually:**
   ```powershell
   claude --version
   openclaw status
   ```
5. **Restart your system** for all changes to take full effect

## Support

For issues:
1. Check the error log file
2. Run with `-Verbose` flag for detailed output
3. Review the relevant section in this README
4. Run individual checks manually

---

**Created:** 2025-03-23  
**Compatible with:** Windows 10+, PowerShell 5.1+
