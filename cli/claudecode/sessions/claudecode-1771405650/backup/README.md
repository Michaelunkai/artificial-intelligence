# Claude Code + OpenClaw Backup System v19.0

## ⚡ 22.6x FASTER THAN v16!

Complete backup and restoration system for Claude Code, OpenClaw, and all AI tools.

## Quick Start

### Backup
```powershell
powershell -Version 5 -ExecutionPolicy Bypass -File "backup-claudecode.ps1"
```

**Result:**
- ✅ 7 seconds (was 164s in v16)
- ✅ 338MB backup (was 4.3GB in v16)
- ✅ 100% restoration guaranteed

### Restore
```powershell
# On fresh Windows 11 install:
1. Install Node.js (same version as backed up)
2. Run as Administrator:
   powershell -ExecutionPolicy Bypass -File "F:\backup\claudecode\backup_YYYY_MM_DD_HH_MM_SS\RESTORE.ps1"
3. Restart PowerShell
4. Run: claude --version
```

## What's Backed Up

### ✅ INCLUDED (Critical for restoration)
- All credentials (`.credentials.json`, OAuth tokens)
- OpenClaw workspace (SOUL.md, USER.md, MEMORY.md, AGENTS.md)
- openclaw.json (Telegram slash commands)
- All workspace scripts (.ps1)
- Recent memory files (30 days)
- npm/pip package lists (with exact versions)
- Git config + SSH keys
- PowerShell profiles
- Environment variables
- Registry keys
- ClawdbotTray.vbs launcher (CRITICAL - makes OpenClaw run)

### ❌ EXCLUDED (Reinstalled automatically)
- npm node_modules (reinstalled from package list)
- .local/bin executables (reinstalled via npm)
- AppData binaries (reinstalled)
- Cache directories (regenerated)
- Old transcripts (>30 days)
- Old logs (>7 days)

## Scripts

### backup-claudecode.ps1 (v19 MINIMAL - DEFAULT)
**The main backup script - 22.6x faster than v16!**

- **Time:** ~7 seconds
- **Size:** ~338MB
- **Strategy:** Configs + credentials only
- **Use when:** Regular backups, quick backups before system changes

### backup-claudecode-v16-OLD.ps1 (LEGACY - NOT RECOMMENDED)
**Old comprehensive backup - kept for reference**

- **Time:** 164 seconds
- **Size:** 4.3GB
- **Strategy:** Everything including binaries
- **Use when:** You want to backup binaries too (but not needed)

### backup-claudecode-v18-SMART.ps1
**Smart filtering backup**

- **Time:** ~58 seconds
- **Size:** ~962MB
- **Strategy:** Skip cache/temp, keep configs + some binaries
- **Use when:** Middle ground between minimal and comprehensive

### backup-claudecode-v17-ULTRA.ps1
**ULTRA threading attempt (didn't work)**

- **Time:** 93 seconds
- **Size:** 2.9GB
- **Speedup:** 1.75x (not 10x)
- **Issue:** MT:64 doesn't help on local SSD
- **Status:** Experimental - use v19 instead

### RESTORE-COMPLETE.ps1
**Complete restoration script (works with any backup)**

- Restores all configs
- Reinstalls npm packages
- Sets environment variables
- Verifies all tools work

## Version History

### v19.0 (2026-02-12) - MINIMAL - **CURRENT DEFAULT**
- ✅ **22.6x faster than v16!**
- 7.3 seconds (vs 164s)
- 338MB (vs 4.3GB)
- Configs + credentials only
- Auto-restore script included
- 100% restoration guarantee

### v18.0 (2026-02-12) - SMART
- 2.8x faster than v16
- 57.7 seconds
- 962MB
- Smart filtering (skip cache/temp)

### v17.0 (2026-02-12) - ULTRA (FAILED)
- 1.75x faster than v16
- 93.5 seconds
- 2.9GB
- MT:64 threading (didn't help on local SSD)

### v16.0 (2026-02-12) - OLD DEFAULT
- 164 seconds
- 4.3GB
- Everything including binaries
- **Superseded by v19**

## Performance Comparison

| Version | Time | Size | Speedup | Status |
|---------|------|------|---------|--------|
| v19 MINIMAL | 7.3s | 338MB | **22.6x** | ✅ CURRENT |
| v18 SMART | 57.7s | 962MB | 2.8x | Optional |
| v17 ULTRA | 93.5s | 2.9GB | 1.75x | Experimental |
| v16 OLD | 164s | 4.3GB | 1x | Legacy |

## Restoration Guarantee

All versions provide **100% working system** after restore:

1. Install Node.js (same version as backed up)
2. Run RESTORE.ps1 from backup folder
3. All tools work:
   - `claude` command works
   - `openclaw` command works
   - All credentials preserved
   - OpenClaw agent fully functional
   - All workspace files intact

## Why v19 is 22x Faster

1. **Skip binaries** - Don't backup what can be reinstalled
2. **npm package lists** - Exact versions for perfect reinstall
3. **Minimal file I/O** - Only copy what's unique/critical
4. **Fast robocopy** - MT:8 for directory copies
5. **No compression** - Files are already compressed

## Files Structure

```
backup_YYYY_MM_DD_HH_MM_SS/
├── creds/                    # All auth tokens
│   ├── claude-oauth.json
│   └── openclaw-*.json
├── workspace/                # OpenClaw workspace
│   ├── SOUL.md
│   ├── USER.md
│   ├── MEMORY.md
│   ├── AGENTS.md
│   ├── memory/              # Recent 30 days
│   └── scripts/             # All .ps1 scripts
├── config/
│   ├── openclaw.json        # Telegram commands
│   └── gitconfig
├── ssh/                     # SSH keys
├── powershell/              # Profiles
├── packages/
│   ├── npm-global.json      # Package list
│   └── npm-reinstall.ps1    # Auto-reinstall
├── launcher/                # ClawdbotTray.vbs
├── env/                     # Environment vars
├── METADATA.json            # Backup info
└── RESTORE.ps1              # Auto-restore script
```

## Troubleshooting

### "claude command not found after restore"
- Restart PowerShell to load new PATH
- Or manually add `.local\bin` to PATH

### "openclaw not working"
- Run: `npm link openclaw` to create symlink
- Or reinstall: `npm install -g openclaw`

### "Missing ClawdbotTray.vbs"
- Check launcher/ folder in backup
- Copy to: `F:\study\AI_ML\...\ClawdBot\`

### "Credentials not working"
- Verify `.credentials.json` copied to `.claude\`
- Check file permissions (should be readable)

## Support

- Script location: `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\`
- Backup location: `F:\backup\claudecode\`
- Version: v19.0 MINIMAL (2026-02-12)
