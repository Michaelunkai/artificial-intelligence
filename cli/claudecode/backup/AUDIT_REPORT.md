# Backup Script Audit Report
Generated: 2026-04-02

## Files Analyzed
- `backup-claudecode.bat` — thin launcher wrapper
- `backup-claudecode.ps1` — main backup engine (v23.0 BLITZ INCREMENTAL)
- `restore-claudecode.bat` — thin restore launcher wrapper (analyzed todo #155)

---

## backup-claudecode.bat — What It Does

1. Checks for admin elevation via `net session`; exits if not elevated.
2. Generates a timestamp using PowerShell `Get-Date -Format 'yyyy_MM_dd_HH_mm_ss'`.
3. Sets `_BACKUPPATH=F:\backup\claudecode\backup_<timestamp>`.
4. Delegates to `backup-claudecode.ps1 -BackupPath <_BACKUPPATH>` with all forwarded args (`%*`).

The BAT file is purely a launcher — all logic lives in the PS1.

---

## backup-claudecode.ps1 — What It Backs Up

### Execution Model
- Parallel RunspacePool (default 32 threads, configurable via `-MaxJobs`)
- Global 10-minute deadline; per-task timeouts (5–300s)
- Hash-based sentinel skip: if `~\.claude\settings.json` hash matches last manifest, run is skipped
- Optional `-Cleanup` switch removes regeneratable caches after backup

### Phase 0 — Pre-cache (parallel, 15s timeout each)
- `node --version`, `npm --version`, `npm list -g --json`
- Tool versions for: claude, openclaw, moltbot, clawdbot, opencode
- `schtasks /query /fo CSV /v`
- `cmdkey /list`
- `pip freeze`

### Phase 1 — Directory Copies (robocopy /MIR /XO /MT:128)
| Category | Paths |
|---|---|
| Core Claude Code | `~\.claude`, `~\.claude.json`, `~\.claude.json.backup`, `~\.config\claude\projects` |
| OpenClaw (selective + full-tree) | 25+ named subdirs of `~\.openclaw`, plus full-tree catch-all |
| OpenClaw dynamic | Any `workspace-*` dirs not in known list |
| OpenClaw catch-all | Any unknown subdirs not in known list |
| OpenClaw npm | `%APPDATA%\npm\node_modules\openclaw` |
| OpenClaw mission-control | `~\openclaw-mission-control` |
| OpenCode | `~\.local\share\opencode`, `~\.config\opencode`, `~\.sisyphus`, `~\.local\state\opencode` |
| AppData | `%APPDATA%\Claude` (excl. caches), `%APPDATA%\Claude Code` |
| CLI state | `~\.local\state\claude`, `~\.local\bin`, `~\.local\share\claude` (excl. versions/) |
| MoltBot / ClawdBot / Clawd | `~\.moltbot`, `~\.clawdbot`, `~\clawd`, npm modules for each |
| npm global | `@anthropic-ai`, `opencode-ai`, `opencode-antigravity-auth` |
| Startup VBS | ClawdBot_Startup.vbs, gateway-silent.vbs, silent-runner.vbs, typing-daemon-silent.vbs |
| Other dot-dirs | `~\.claudegram`, `~\.claude-server-commander`, `~\.cagent`, `~\.anthropic` |
| Git / SSH | `~\.config\gh` (SSH via Phase 2 individual files) |
| Python | `~\.local\share\uv` |
| PowerShell modules | ClaudeUsage (PS5 + PS7) |
| Config dirs | `~\.config\browserclaw`, `~\.config\cagent`, `~\.config\configstore` |
| Chrome IndexedDB | claude.ai blob+leveldb for Profiles 1 & 2; catch-all for Profile 3+ and Default |
| Edge / Brave / Firefox | claude.ai IndexedDB in all profiles |
| Catch-all scanners | Home dot-dirs, AppData (Roaming+Local), npm global, .local/share+state, .config, ProgramData, LocalLow, Temp, WSL rootfs |
| Drive scanner | D:\, E:\, F:\ (depth 1) for claude/openclaw/clawd/moltbot dirs |
| Restore rollbacks | `~\.openclaw-restore-rollback*` dirs |
| Windows Store Claude | Settings + Roaming cache (excl. vm_bundles) |
| TgTray + Channels | `F:\study\Dev_Toolchain\programming\.net\projects\c#\TgTray`, `tg.exe`, `~\.claude\channels` |
| Shell:Startup shortcuts | Claude Channel.lnk, TgTray.lnk, ClawdBot Tray.lnk |

### Phase 2 — Small Files (individual [System.IO.File]::Copy)
- `.gitconfig`, `.gitignore_global`, `.git-credentials`, `.npmrc`
- `CLAUDE.md`, `AGENTS.md`, `claude-wrapper.ps1`, `mcp-ondemand.ps1`
- PS5 + PS7 profiles
- `claude_desktop_config.json`
- 20+ OpenClaw root config/auth/json files
- Windows Terminal settings (stable + preview)
- All `*.env` files from `~`, `~\.openclaw`, `~\.claude`
- All `*.db` files from `~\.claude`
- `~\.claude\history.jsonl`
- SSH keys from `~\.ssh` (with admin fallback)
- Rolling backup files (`openclaw.json.*`, etc.)
- All root files from `~\.openclaw`
- MCP `.cmd` wrapper files from `~`
- npm bin shims (claude, openclaw, clawdbot, opencode, moltbot — .cmd, .ps1 variants)
- Startup folder + Desktop shortcuts matching claude/openclaw/etc.
- Task Scheduler XML exports: TgChannel, TgTray, all claude/openclaw/moltbot tasks

### Phase 3 — Metadata
- `meta\tool-versions.json` — versions of all tools
- `npm-global\node-info.json`, `global-packages.txt`, `global-packages.json`, `REINSTALL-ALL.ps1`
- `python\requirements.txt` (pip freeze)
- `env\environment-variables.json/txt` — user env vars matching CLAUDE/ANTHROPIC/OPENAI/MCP/NODE/NPM/PYTHON/UV/PATH
- Registry exports: `HKCU\Environment`, `HKCU\Software\Claude`, `HKCU\Software\Microsoft\Windows\CurrentVersion\Run`
- Credential files for claude, opencode, anthropic, moltbot, clawdbot
- OpenClaw + Claude auth files (pattern: auth|cred|token|secret|.key)
- Windows Credential Manager text dump
- Scheduled tasks: CSV list + individual XML + verbose LIST dump
- `meta\software-info.json` — install status + version for all tools

### Phase 4 — Project .claude Dirs
- Recursively scans `~\Projects`, `~\repos`, `~\dev`, `~\code`, `F:\Projects`, `D:\Projects`, `F:\study` (depth 5)
- Backs up any `.claude` directory found (excluding node_modules/.git/etc.)
- Skipped if `SKIP_PROJECT_SEARCH != "0"` (note: logic is inverted — `!= "0"` means skip when env var is set to anything except "0", which is the default when unset)

### Phase 5 — Optional Cleanup (`-Cleanup` flag)
Removes from live system: `.claude` caches, AppData\Claude caches, `claude-cli-nodejs`, OpenCode cache, OpenClaw logs, old CLI version binaries (keeps newest).

---

## What Is Intentionally Excluded (Documented)
- `.claude\file-history`, `cache`, `paste-cache`, `image-cache`, `shell-snapshots`, `debug`, `test-logs`, `downloads`, `session-env`, `telemetry`, `statsig`
- `AppData\Roaming\Claude`: Code Cache, GPUCache, DawnGraphiteCache, DawnWebGPUCache, Cache, Crashpad, Network, blob_storage, Session Storage, Local Storage, WebStorage, IndexedDB, Service Worker
- `.openclaw\logs`, `.openclaw\backups`
- `node_modules`, `.git`, `__pycache__`, `.venv`, `venv`, `platform-tools`, `outbound`, `canvas`
- `~\.local\share\claude\versions` (230MB old CLI binaries — reinstallable via npm)
- `%LOCALAPPDATA%\AnthropicClaude` (546MB reinstallable app)
- `%LOCALAPPDATA%\claude-cli-nodejs` (cache)
- `.cache\opencode`

---

## Issues / Gaps Identified

### Bug: SKIP_PROJECT_SEARCH Logic Is Inverted
```powershell
if($env:SKIP_PROJECT_SEARCH -ne "0"){
    Write-Host "  Skipped (SKIP_PROJECT_SEARCH!=0)" -ForegroundColor Yellow
```
Phase 4 is skipped whenever `SKIP_PROJECT_SEARCH` is NOT "0" — including when the variable is unset (empty string). This means project `.claude` dirs are NEVER scanned in a default run. Condition should be `$env:SKIP_PROJECT_SEARCH -eq "1"` or similar opt-in.

### Missing: `F:\downloads` and `F:\backup` Shallow Scan
The drive scanner covers D:\, E:\, F:\ at depth 1 but only matches dirs named with claude/openclaw/etc. keywords. `F:\downloads` is the working directory for this session and may contain project-specific `.claude` dirs not caught by Phase 4 (which is broken — see above).

### Missing: `~\.claude\memory` Explicit Backup Verification
`~\.claude` is backed up in Phase 1 excluding enumerated garbage dirs, but `memory\` is not in the exclusion list, so it should be included. No explicit test or verification step confirms the memory subdirectory is copied correctly.

### Minor: Version string in summary metadata says "22.0 LEAN BLITZ" but banner says "23.0 BLITZ INCREMENTAL"
Line 983: `Version = "22.0 LEAN BLITZ"` — stale string, does not match the v23.0 banner.

### Sentinel Skip Can Cause Missed Backups
If only a non-sentinel file changes (e.g., a workspace memory file, credentials, or a channel script) but `settings.json` is unchanged, the entire backup run is skipped. This is by design for performance but is a correctness risk.

### No Backup Rotation / Pruning
The script creates dated `backup_<timestamp>` folders but never prunes old ones. `F:\backup\claudecode` will grow unboundedly unless managed externally.

---

## Backup Destination
All data written to: `F:\backup\claudecode\backup_<yyyy_MM_dd_HH_mm_ss>\`
Manifest/sentinel stored at: `F:\backup\claudecode\backup-manifest.json`

---

## Todo #154 — restore-claudecode.ps1 Audit (2026-04-02)

### What restore-claudecode.ps1 Restores

**Version:** v23.0 BLITZ INCREMENTAL
**Execution model:** 128-thread RunspacePool; robocopy `/MIR /XO /MT:128 /FFT` for dirs; `[System.IO.File]::Copy` for individual files.

#### Phases

| Phase | What |
|---|---|
| Pre-flight | Admin check, disk space, PS version, required tools (robocopy/reg/icacls) |
| Prerequisites | Node.js, Git, Python, Chrome via winget (new-PC only) |
| Claude CLI bootstrap | npm install -g @anthropic-ai/claude-code if not found |
| npm packages | Reads REINSTALL-ALL.ps1 + npm-globals.txt; installs missing packages |
| Dir restores (robocopy) | ~50+ named dir mappings + dynamic catchall scanners for all backup versions (v20/v21/v22/v23) |
| File restores (File::Copy) | Individual files: .gitconfig, profiles, credentials, desktop config, history.jsonl, terminal settings, shortcuts, DB files, MCP wrappers, npm shims |
| Post-config | SSH ACL fix, PATH update (.local\bin), env vars from JSON+TXT, registry .reg imports, scheduled tasks XML, NGEN tg.exe, startup shortcuts (Claude Channel, TgTray, ClawdBot), execution policy, npm install in .openclaw, unblock executables, Chrome CDP setup |
| Verification | --version check on 5 tools; auto-repair via npm if broken; critical path existence checks |

#### Sentinel SkipGuard
Three files are hashed (CLAUDE.md, claude_desktop_config.json, settings.json). If all match between backup and live, the entire run exits 0 immediately. This is faster than the backup sentinel but covers fewer files.

---

### Gaps Identified in restore-claudecode.ps1

#### Gap 1: Sentinel SkipGuard Only Checks 3 Files
Checks only CLAUDE.md, claude_desktop_config.json, settings.json. Any other content changed (credentials, channel scripts, memory files, profile) but with these three files identical causes the entire restore to be silently skipped.

#### Gap 2: Project .claude Dir Path Reconstruction Is Fragile
Line 621: `$_.Name -replace '^(\w)_', '$1:\' -replace '_', '\'`
Sanitized backup names use `_` as separator. Folder names with underscores (e.g., `AI_and_Machine_Learning`) reconstruct incorrectly — `F_study_AI_ML_AI_and_Machine_Learning` becomes `F:\study\AI\ML\AI\and\Machine\Learning` instead of `F:\study\AI_ML\AI_and_Machine_Learning`.

#### Gap 3: WSL Rootfs Silently Skipped
Catchall scanner sets `$dest = $null` for `wsl-*` backup dirs (line 453) with comment "WSL restore is complex, skip auto". No warning is emitted. WSL data backed up is never restored.

#### Gap 4: Environment Variables Scope Is Incomplete
The JSON env-var path (lines 770-771) only processes vars matching `CLAUDE|OPENCLAW|ANTHROPIC|OPENCODE|NODE|NPM|UV`. Variables for `PYTHON`, `MCP`, `TELEGRAM_BOT_TOKEN`, `OPENAI_API_KEY`, and other project vars are silently skipped.

#### Gap 5: PATH Environment Variable Never Restored
Both env restore paths explicitly skip `Path`. The backup captures PATH but it is never written back. On a new PC, PATH is default/incomplete. Only `.local\bin` is added programmatically.

#### Gap 6: Scheduled Tasks Require Admin; Silent Failure
`schtasks /create ... /xml` silently fails without elevation. The script warns at pre-flight if non-admin but does not abort task import. Failed imports get only a WARN line with no summary count.

#### Gap 7: No Rollback / Dry-Run Mode
No `-WhatIf` or `-DryRun` parameter and no rollback on failure. Robocopy `/MIR` deletes files in destination dirs that are not in backup source. Files created after the backup date in `.openclaw` or `.claude` subdirectories will be deleted with no recovery path.

#### Gap 8: No Verification of Restored Credential Files
The verify phase only checks dir/binary existence and runs `--version` on 5 CLIs. Credential files (`.credentials.json`, `auth.json`, `settings.local.json`) are not verified. A zero-byte or corrupt credential file passes verification silently.

#### Gap 9: F:\downloads Project .claude Dirs Not Restored
`F:\downloads` is not scanned by the backup (only `F:\study` at depth 5). Compound issue: the backup's SKIP_PROJECT_SEARCH bug means project dirs may not have been captured at all, so restore has nothing to work with.

#### Gap 10: NGEN 30s Timeout May Be Insufficient; Requires Admin
NGEN runs with 30,000ms timeout (line 860). On a new PC with large assemblies this can exceed 30s. NGEN also requires elevation; without admin the pre-compile silently fails (WARN only).

---

### Summary of Restore Scope vs Backup Scope

| Category | Backed Up | Restored | Gap |
|---|---|---|---|
| Core .claude | Yes | Yes | None |
| OpenClaw all subdirs | Yes | Yes | None |
| Credentials / auth | Yes | Yes (unless -SkipCredentials) | Gap 8: no integrity check |
| Project .claude dirs | Yes (if backup bug fixed) | Yes (if path reconstruction works) | Gap 2, Gap 9 |
| WSL rootfs | Yes | NO | Gap 3 |
| Environment variables | Yes | Partial (filtered keys, no PATH) | Gap 4, Gap 5 |
| Scheduled tasks | Yes | Partial (needs admin) | Gap 6 |
| npm packages | Version list only | Reinstalled from list | Normal |
| Browsers (Chrome/Edge/Brave/Firefox) | Yes | Yes | None |
| TgTray + channels | Yes | Yes | None |
| Registry | Yes (.reg exports) | Yes | None |
| SSH keys + ACL | Yes | Yes + ACL fix | None |
| PowerShell profiles | Yes | Yes + Unblock-File | None |

---

## Todo #153 Gap Analysis — Specific Path Coverage (backup-claudecode.ps1)

Audit of whether key paths (memory/, workspace/, scripts/, commands/, hooks, CLAUDE.md, learned.md, openclaw paths) are actually covered:

| Path | Covered? | How |
|---|---|---|
| `~\.claude\memory\` | YES | Included inside full `~\.claude` Phase 1 robocopy; `memory` is not in exclusion list |
| `~\.claude\commands\` | YES | Same full `~\.claude` robocopy |
| `~\.claude\hooks\` | YES | Same full `~\.claude` robocopy |
| `~\.claude\settings.json` | YES | Covered by robocopy AND used as sentinel hash file |
| `~\CLAUDE.md` | YES | Phase 2 small file explicit copy to `agents\CLAUDE.md` |
| `~\.claude\CLAUDE.md` (project-level) | YES | Captured inside `~\.claude` robocopy |
| `~\.claude\learned.md` | INFERRED YES | No dedicated entry; captured if file lives inside `~\.claude` (likely) |
| `~\.openclaw\workspace*` (8 named + dynamic) | YES | 8 explicit Add-Task entries + dynamic workspace-* scanner |
| `~\.openclaw\scripts\` | YES | Explicit Add-Task at line 200 |
| `~\.openclaw\memory\` | YES | Explicit Add-Task at line 196 |
| `~\.openclaw\hooks\` | YES | Explicit Add-Task at line 210 |
| `~\.openclaw\.claude\` (nested) | YES | Explicit Add-Task at line 205 |
| OpenClaw full-tree catch-all | YES | Line 221: full `~\.openclaw` robocopy excluding logs+backups+node_modules+.git |
| `~\.claude\history.jsonl` | YES | Phase 2 explicit individual file copy |
| `~\.claude\*.db` files | YES | Phase 2 glob: all `*.db` from `~\.claude` |

### Remaining Gaps

1. **`learned.md` location ambiguity** — If stored at `~\.claude\learned.md` it is covered. If stored at `F:\downloads\.claude\learned.md` (this session's working dir), it is NOT backed up in a default run because Phase 4 (project .claude dir scanner) is broken — its SKIP condition (`-ne "0"`) skips when the env var is unset, which is always in a default run.

2. **`F:\downloads\.claude\` not scanned** — Drive scanner at F:\ only scans depth 1 for dirs matching keywords; `F:\downloads\.claude` is not depth 1. Phase 4 broken (see above). Any local CLAUDE.md, learned.md, settings.json in `F:\downloads\.claude` are NOT backed up by default.

3. **No post-backup integrity check on memory/ or commands/** — No verification that these critical subdirs are non-empty in the backup destination after the robocopy completes.

4. **Sentinel skip risk** — If only workspace/memory/commands files change but `~\.claude\settings.json` is unchanged, the entire backup run is skipped silently.

Analyzed: 2026-04-02 (todo #153)

---

## restore-claudecode.bat — What It Does (todo #155)

File: `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-claudecode.bat`

### Summary
A thin UAC-elevation launcher (22 lines). All restore logic lives in `restore-claudecode.ps1`.

### Step-by-Step Behavior
1. **UAC elevation check** — Runs `net session >nul 2>&1`; if `errorlevel != 0` (not admin), re-launches itself via PowerShell `Start-Process ... -Verb RunAs` and exits.
2. **Pre-check: winget** — Runs `where winget`; if not found, prints a WARNING (non-fatal). Winget is needed for package reinstalls during restore.
3. **Pre-check: Node.js** — Runs `where node`; if not found, prints a WARNING (non-fatal). Node.js is needed to reinstall Claude Code via npm.
4. **Delegate to PS1** — Calls `powershell -ExecutionPolicy Bypass -NoProfile -File "%~dp0restore-claudecode.ps1" -Force %*` with all forwarded CLI arguments.
5. **Pause** — Holds the console open after completion so the user can read output.

### Key Observations
- `-ExecutionPolicy Bypass -NoProfile` matches the pattern used by `backup-claudecode.bat` — consistent launcher style.
- `-Force` is always passed to the PS1; it suppresses interactive confirmation prompts during restore.
- `%*` forwards any extra arguments the user passes to the BAT directly into the PS1 (e.g., `-BackupPath`, `-DryRun`, etc.).
- The file uses `%~dp0` (directory of the BAT) to locate the PS1, so both files must reside in the same folder.
- No timestamp is generated here (unlike backup-claudecode.bat which creates a timestamped path) — the restore PS1 presumably accepts a `-BackupPath` argument to target a specific backup.
- Warnings for missing winget/node are advisory only; restore proceeds regardless.

### Gaps / Risks
- **No explicit check for restore-claudecode.ps1 existence** — if the PS1 is missing, PowerShell exits with an error but the BAT does not catch or report it clearly.
- **No backup path prompt** — without a `-BackupPath` argument the behavior depends entirely on the PS1's default logic (not yet audited).
- **pause at end** — may be undesirable in automated/scripted invocations.

Analyzed: 2026-04-02 (todo #155)
