# CCC - Context & Cache Cleanup

**Purpose:** Delete ALL garbage and cache to reduce disk space and context usage to MINIMUM while keeping ALL essential data safe.

---

## What Gets DELETED (Garbage)

### 1. Old Transcripts
- **Path:** `.openclaw/agents/*/transcripts/*.json`
- **Rule:** Older than 30 days
- **Why:** Chat history accumulates, old sessions aren't needed

### 2. Media Cache
- **Path:** `.openclaw/media/inbound/*`
- **Rule:** Older than 7 days
- **Why:** Downloaded files, temporary images

### 3. Screenshots
- **Path:** `.openclaw/media/outbound/screenshot_*.png`
- **Rule:** Older than 3 days
- **Why:** Monitoring screenshots pile up fast

### 4. Session Snapshots
- **Path:** `.openclaw/workspace/.snapshots`
- **Rule:** All (regenerated as needed)
- **Why:** Temporary workspace state

### 5. Debug Logs
- **Path:** `.openclaw/logs/*.log`
- **Rule:** Older than 7 days
- **Why:** Debugging data not needed long-term

### 6. Claude Code Cache
- **Paths:**
  - `~/.claude/cache`
  - `~/.claude/debug`
  - `~/.claude/telemetry`
  - `~/.claude/statsig`
  - `~/.claude/nul`
  - `%LOCALAPPDATA%\Temp\claude*`
- **Rule:** All
- **Why:** Temporary analytics, debug data

### 7. OpenCode Cache
- **Paths:**
  - `~/.local/share/opencode/cache`
  - `~/.cache/opencode`
  - `%LOCALAPPDATA%\Temp\opencode*`
- **Rule:** All
- **Why:** Temporary caching

### 8. NPM Cache
- **Path:** `%APPDATA%\npm-cache`
- **Rule:** All (runs `npm cache clean --force`)
- **Why:** Downloaded packages cache

### 9. Python Cache
- **Paths:**
  - `~/.cache`
  - `%LOCALAPPDATA%\pip\cache`
  - `__pycache__` directories
  - `*.pyc` files
- **Rule:** All
- **Why:** Compiled Python bytecode

### 10. Temp Files
- **Paths:**
  - `.openclaw/workspace/temp`
  - `.openclaw/temp`
  - `~/.openclaw/temp`
- **Rule:** All
- **Why:** Temporary files

### 11. Old Memory Archives
- **Path:** `.openclaw/workspace/archive/MEMORY-backup-*.md`
- **Rule:** Keep last 3, delete rest
- **Why:** Backup history accumulates

### 12. Corrupted/Backup Files
- **Patterns:** `*.corrupted.*`, `*.backup*`, `*.bak`, `*.tmp`
- **Rule:** All (if related to claude/openclaw/opencode)
- **Why:** Failed operations, temp backups

### 13. Browser Cache
- **Paths:**
  - `.openclaw/browser/openclaw/user-data/Default/Cache`
  - `.openclaw/browser/openclaw/user-data/Default/Code Cache`
  - `.openclaw/browser/openclaw/user-data/Default/GPUCache`
  - `.openclaw/browser/openclaw/user-data/ShaderCache`
- **Rule:** All
- **Why:** Browser caching

### 14. Old CCC Backups
- **Path:** `.openclaw/backups/ccc-*`
- **Rule:** Keep last 5, delete rest
- **Why:** Backup redundancy

### 15. Old Daily Memory Files
- **Path:** `.openclaw/workspace/memory/*.md`
- **Rule:** Older than 30 days (archived to `memory-old/`)
- **Why:** Daily logs accumulate

---

## What Gets KEPT (Essential)

### Critical Workspace Files
- ✅ **SOUL.md** - Agent personality and identity
- ✅ **USER.md** - User preferences and info
- ✅ **MEMORY.md** - Core persistent memory
- ✅ **AGENTS.md** - Agent configuration
- ✅ **IDENTITY.md** - Agent identity
- ✅ **TOOLS.md** - Tool configuration
- ✅ **HEARTBEAT.md** - Maintenance tasks
- ✅ **BOOTSTRAP.md** - Initialization

### Memory & History
- ✅ **memory/*.md** (last 30 days) - Recent daily memory
- ✅ **memory/slash-commands-reference.md** - Command docs
- ✅ Recent transcripts (last 30 days)

### Credentials & Auth
- ✅ **openclaw.json** - Gateway config (Telegram customCommands, channels)
- ✅ **config.yaml** - OpenClaw gateway config
- ✅ **credentials/** - Auth tokens (WhatsApp, Telegram, Discord)
- ✅ **.credentials.json** - OAuth tokens

### Scripts & Functions
- ✅ **scripts/*.ps1** - All PowerShell scripts (todoist-done.ps1, etc.)
- ✅ **hooks/** - Custom hooks
- ✅ **rules/** - Agent rules

### Recent Data
- ✅ Recent sessions (last 30 days)
- ✅ Recent media (last 7 days)
- ✅ Recent logs (last 7 days)
- ✅ Recent memory (last 30 days)

---

## Safety Features

1. **Automatic Backup:** Before deleting anything, backs up all critical files to `.openclaw/backups/ccc-YYYYMMDD-HHMM`
2. **Keeps Last 5 CCC Backups:** Can restore if needed
3. **Archives Instead of Deletes:** Old memory files moved to `archive/memory-old/` instead of deleted
4. **Dry Run Mode:** Run with `-DryRun` to see what would be deleted without actually deleting

---

## Usage

### Run Cleanup
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\micha\.openclaw\workspace\scripts\ccc-cleanup.ps1"
```

### Dry Run (See What Would Be Deleted)
```powershell
powershell -ExecutionPolicy Bypass -File "C:\Users\micha\.openclaw\workspace\scripts\ccc-cleanup.ps1" -DryRun
```

### Via Slash Command
In any OpenClaw session, just type:
```
/ccc
```

---

## When to Run

1. **Before Backup:** Always run `/ccc` before running backup script to ensure minimal backup size
2. **Weekly Maintenance:** Run once per week to keep context clean
3. **Context Overload:** If you notice slow responses or large file sizes
4. **Before Major Tasks:** Clean slate for important work

---

## Size Limits

Files are checked after cleanup:

| File | Max Size | Purpose |
|------|----------|---------|
| AGENTS.md | 8 KB | Agent configuration |
| MEMORY.md | 2 KB | Core memory (archive old content) |
| SOUL.md | 3 KB | Personality (should be concise) |
| USER.md | 3 KB | User info (keep minimal) |
| TOOLS.md | 3 KB | Tool notes (reference only) |

**⚠️ If files exceed limits, manually archive old content to `archive/` directory.**

---

## Recovery

If cleanup deletes something important:

1. Check latest backup: `.openclaw/backups/ccc-YYYYMMDD-HHMM/`
2. Restore from there
3. Last 5 CCC backups are always kept

---

## Notes

- This script is **aggressive** but **safe**
- ALL essential data is preserved
- Garbage accumulates fast (run weekly)
- Context size directly affects AI performance
- Smaller context = faster responses, lower cost
- After cleanup, safe to run full backup

---

**Last Updated:** 2026-02-11  
**Version:** 2.0 - Comprehensive Garbage Deletion
