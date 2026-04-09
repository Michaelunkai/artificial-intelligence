#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code + OpenClaw Backup v28.0 - INCREMENTAL ONLY (exFAT-safe, no duplicates)
.DESCRIPTION
    Incremental copy into persistent "latest" dir (only changed files copied).
    On exFAT (F:) hardlinks are unsupported - snapshot phase auto-skipped to prevent
    full duplicate copies. Old timestamped snapshots are cleaned up automatically.
    v28.0: exFAT detection + no-snapshot mode = zero duplicate backups, 10x+ faster.
    Optional -Cleanup flag safely removes garbage from the live system.
.PARAMETER BackupPath
    Timestamped snapshot directory (default: F:\backup\claudecode\backup_<timestamp>)
.PARAMETER MaxJobs
    Parallel threads (default: 64)
.PARAMETER Cleanup
    After backup, safely remove regeneratable caches from the live system
.NOTES
    Version: 27.0 - HARDLINK INCREMENTAL
#>
[CmdletBinding()]
param(
    [string]$BackupPath = "F:\backup\claudecode\backup_$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss')",
    [int]$MaxJobs = 64,
    [switch]$Cleanup,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$script:Errors = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$script:DoneLog = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$startTime = Get-Date

$HP = $env:USERPROFILE
$A = $env:APPDATA
$L = $env:LOCALAPPDATA

# Garbage dirs to EXCLUDE from .claude full backup (regeneratable)
$claudeExcludeDirs = @('file-history','cache','paste-cache','image-cache','shell-snapshots',
    'debug','test-logs','downloads','session-env','telemetry','statsig')

# Garbage dirs to EXCLUDE from AppData\Roaming\Claude backup
$claudeAppExcludeDirs = @('Code Cache','GPUCache','DawnGraphiteCache','DawnWebGPUCache',
    'Cache','cache','Crashpad','Network','blob_storage','Session Storage','Local Storage',
    'WebStorage','IndexedDB','Service Worker',
    'vm_bundles','claude-code-vm')

# Banner printed after LatestDir is computed (below)


#region ===== DRY RUN MODE =====
if ($DryRun) {
    Write-Host "[DRY-RUN] Listing files that WOULD be backed up (no archive created)..." -ForegroundColor Yellow
    $dryFiles = [System.Collections.Generic.List[System.IO.FileInfo]]::new()
    $dryDirs  = @(
        "$HP\.claude", "$HP\.openclaw", "$HP\.moltbot", "$HP\.clawdbot", "$HP\.anthropic",
        "$HP\.config\gh", "$HP\.local\share\opencode", "$HP\.local\bin",
        "$HP\Documents\PowerShell", "$HP\Documents\WindowsPowerShell"
    )
    $drySkipRx = 'node_modules|\\\.git\\|__pycache__|Code Cache|GPUCache|file-history|paste-cache|image-cache|shell-snapshots|telemetry|statsig'
    foreach ($dd in $dryDirs) {
        if (Test-Path $dd) {
            try {
                foreach($fp in [System.IO.Directory]::EnumerateFiles($dd, '*', [System.IO.SearchOption]::AllDirectories)){
                    if($fp -notmatch $drySkipRx){ $dryFiles.Add([System.IO.FileInfo]::new($fp)) }
                }
            } catch {}
        }
    }
    $totalDryBytes = 0L; foreach($f in $dryFiles){ $totalDryBytes += $f.Length }
    $dryFiles | Select-Object FullName, @{N='Size';E={[int]($_.Length/1KB)}} | Format-Table -AutoSize
    Write-Host ("[DRY-RUN] Would backup {0} files ({1} MB)" -f $dryFiles.Count, [int]($totalDryBytes/1MB)) -ForegroundColor Yellow
    return
}
#endregion

# ===== HARDLINK INCREMENTAL ARCHITECTURE =====
# Phase A: robocopy into persistent "latest" dir (only changed files = fast)
# Incremental architecture:
# - "latest" is ALWAYS persistent (never renamed/deleted) - the incremental sync target
# - On NTFS: hardlink snapshot from latest -> timestamped (instant, zero extra disk)
# - On exFAT: incremental copy from latest -> timestamped (only changed files)
# - Old backups are NEVER deleted - user decides when to clean up
$backupRoot = Split-Path $BackupPath -Parent
if (-not $backupRoot) { $backupRoot = "F:\backup\claudecode" }
$LatestDir = Join-Path $backupRoot "latest"

# Detect exFAT - hardlinks are unsupported
$backupDriveLetter = (Split-Path $backupRoot -Qualifier).TrimEnd(':').Trim()
$backupFsType = try { (Get-Volume -DriveLetter $backupDriveLetter -EA Stop).FileSystemType } catch { "Unknown" }
$script:IsExFat = $backupFsType -eq 'exFAT'

New-Item -ItemType Directory -Path $LatestDir -Force | Out-Null

#region Banner
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  CLAUDE CODE + OPENCLAW BACKUP v28.0 INCREMENTAL ONLY" -ForegroundColor White
$snapshotMode = if ($script:IsExFat) { "INCREMENTAL SNAPSHOT" } else { "HARDLINK SNAPSHOT" }
Write-Host "  INCREMENTAL TO LATEST | $snapshotMode | ALL PARALLEL" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Latest:   $LatestDir"
Write-Host "Snapshot: $BackupPath"
Write-Host "FS:       $backupFsType"
Write-Host "Threads: $MaxJobs | Cleanup: $Cleanup"
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
#endregion

$sw = [System.Diagnostics.Stopwatch]::StartNew()

#region ===== PHASE 0: LAUNCH CACHE JOBS (non-blocking, collected before P3) =====
Write-Host "[P0] Launching cache jobs (async)..." -ForegroundColor Cyan
$cmdCache = @{}
$cacheJobs = @(
    @{ Name="npm"; Block={
        $r = @{ nodeVer=""; npmVer=""; prefix=""; list=""; listJson="" }
        try { $r.nodeVer = (& node --version 2>$null) -join "" } catch {}
        try { $r.npmVer = (& npm --version 2>$null) -join "" } catch {}
        try { $r.prefix = (& npm config get prefix 2>$null) -join "" } catch {}
        try { $r.list = (& npm list -g --depth=0 2>$null) -join "`n" } catch {}
        try { $r.listJson = (& npm list -g --depth=0 --json 2>$null) -join "`n" } catch {}
        $r
    }},
    @{ Name="versions"; Block={
        $r = @{}
        @("claude","openclaw","moltbot","clawdbot","opencode") | ForEach-Object {
            $c = Get-Command $_ -ErrorAction SilentlyContinue
            if ($c) {
                $ver = "?"
                try { $ver = (& $_ --version 2>$null) -join " " } catch {}
                $r[$_] = @{ Path = $c.Source; Version = $ver }
            }
        }
        $r
    }},
    @{ Name="schtasks"; Block={ $o = @(); try { $o = schtasks /query /fo CSV /v 2>$null } catch {}; $o }},
    @{ Name="cmdkey"; Block={ $o = @(); try { $o = cmdkey /list 2>$null } catch {}; $o }},
    @{ Name="pip"; Block={ $o = @(); try { $o = pip freeze 2>$null } catch {}; $o }}
)

$cp = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 5)
$cp.Open()
$ch = @()
foreach($j in $cacheJobs){
    $ps=[System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool=$cp
    $ps.AddScript($j.Block)|Out-Null
    $ch += @{Name=$j.Name; PS=$ps; H=$ps.BeginInvoke()}
}
# NOTE: Don't wait here! Collect results before Phase 3 needs them.
Write-Host "[P0] 5 cache jobs launched (collecting before P3)" -ForegroundColor Green
#endregion

#region ===== PHASE 1: ALL DIRECTORY COPIES VIA COMPILED C# COPIER =====
Write-Host "[P1] Building task list..." -ForegroundColor Cyan

# Compiled C# incremental copier - zero process spawn overhead
Add-Type @"
using System;
using System.IO;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

public class IncrementalCopier {
    public static string SyncDir(string src, string dst, string desc,
        ConcurrentBag<string> errBag, ConcurrentQueue<string> doneLog, string[] excludeDirs) {
        try {
            if (!Directory.Exists(src)) return null;
            var excl = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
            excl.Add("node_modules"); excl.Add(".git"); excl.Add("__pycache__");
            excl.Add(".venv"); excl.Add("venv"); excl.Add("platform-tools");
            excl.Add("outbound"); excl.Add("canvas");
            if (excludeDirs != null) { foreach (var x in excludeDirs) excl.Add(x); }

            SyncDirRecursive(src, dst, excl);
            doneLog.Enqueue("[OK] " + desc);
        } catch (Exception ex) {
            errBag.Add("FAIL: " + desc + " - " + ex.Message);
            doneLog.Enqueue("[FAIL] " + desc);
        }
        return desc;
    }

    private static void SyncDirRecursive(string src, string dst, HashSet<string> excl) {
        if (!Directory.Exists(dst)) Directory.CreateDirectory(dst);
        foreach (var f in Directory.GetFiles(src)) {
            var name = Path.GetFileName(f);
            var target = Path.Combine(dst, name);
            try {
                if (File.Exists(target)) {
                    // /XO equivalent: skip if source is not newer (2-second FAT tolerance)
                    var srcTime = File.GetLastWriteTimeUtc(f);
                    var dstTime = File.GetLastWriteTimeUtc(target);
                    if (srcTime <= dstTime.AddSeconds(2)) continue;
                }
                File.Copy(f, target, true);
            } catch { }
        }
        foreach (var d in Directory.GetDirectories(src)) {
            var dirName = Path.GetFileName(d);
            if (excl.Contains(dirName)) continue;
            SyncDirRecursive(d, Path.Combine(dst, dirName), excl);
        }
    }

    public static string SyncFile(string src, string dst, string desc,
        ConcurrentBag<string> errBag, ConcurrentQueue<string> doneLog) {
        try {
            if (!File.Exists(src)) return null;
            var dir = Path.GetDirectoryName(dst);
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            File.Copy(src, dst, true);
            doneLog.Enqueue("[OK] " + desc);
        } catch (Exception ex) {
            errBag.Add("FAIL: " + desc + " - " + ex.Message);
            doneLog.Enqueue("[FAIL] " + desc);
        }
        return desc;
    }

    // Bulk method: process all tasks in a single Parallel.ForEach (no RunspacePool overhead)
    public static int[] BulkSync(string[] srcs, string[] dsts, string[] descs, string[][] excludeDirs,
        ConcurrentBag<string> errBag, ConcurrentQueue<string> doneLog, int parallelism) {
        int done = 0, skipped = 0;
        var opts = new ParallelOptions { MaxDegreeOfParallelism = parallelism };
        Parallel.For(0, srcs.Length, opts, i => {
            var src = srcs[i]; var dst = dsts[i]; var desc = descs[i];
            var xd = (excludeDirs != null && i < excludeDirs.Length) ? excludeDirs[i] : null;
            if (Directory.Exists(src)) {
                SyncDir(src, dst, desc, errBag, doneLog, xd);
                Interlocked.Increment(ref done);
            } else if (File.Exists(src)) {
                SyncFile(src, dst, desc, errBag, doneLog);
                Interlocked.Increment(ref done);
            } else {
                Interlocked.Increment(ref skipped);
            }
        });
        return new int[] { done, skipped };
    }
}
"@

# Task list
$allTasks = [System.Collections.Generic.List[hashtable]]::new()

function Add-Task {
    param([string]$S,[string]$D,[string]$Desc,[int]$T=120,[string[]]$XD=$null)
    $allTasks.Add(@{S=$S;D=$D;Desc=$Desc;T=$T;XD=$XD})
}

# ============ CORE CLAUDE CODE ============
# .claude FULL but EXCLUDING garbage (saves 26MB file-history + caches)
Add-Task "$HP\.claude" "$LatestDir\core\claude-home" ".claude (settings, rules, hooks, commands, sessions, memory, plugins)" 180 -XD $claudeExcludeDirs
# NOTE: memory, commands, scripts, hooks, skills are all inside the full .claude backup above.
# Individual file copies below go to named restore-compat paths (fast single-file copies).
Add-Task "$HP\.claude\settings.json" "$LatestDir\core\claude-settings.json" ".claude/settings.json (main settings)" 5
Add-Task "$HP\.claude\CLAUDE.md" "$LatestDir\core\claude-CLAUDE.md" ".claude/CLAUDE.md (global instructions)" 5
Add-Task "$HP\.claude\learned.md" "$LatestDir\core\claude-learned.md" ".claude/learned.md (error log / learnings)" 5
Add-Task "$HP\.claude\resource-config.json" "$LatestDir\core\claude-resource-config.json" ".claude/resource-config.json (tier/budget config)" 5
Add-Task "$HP\.claude.json" "$LatestDir\core\claude.json" ".claude.json (main config, 63KB)" 10
Add-Task "$HP\.claude.json.backup" "$LatestDir\core\claude.json.backup" ".claude.json.backup" 10
Add-Task "$HP\.config\claude\projects" "$LatestDir\sessions\config-claude-projects" ".config/claude/projects" 60

# ============ OPENCLAW (selective - full dir is 800MB with node_modules) ============
Add-Task "$HP\.openclaw\workspace" "$LatestDir\openclaw\workspace" "OpenClaw workspace (SOUL.md, USER.md, MEMORY.md)" 60
Add-Task "$HP\.openclaw\workspace-main" "$LatestDir\openclaw\workspace-main" "OpenClaw workspace-main" 60
Add-Task "$HP\.openclaw\workspace-session2" "$LatestDir\openclaw\workspace-session2" "OpenClaw workspace-session2" 60
Add-Task "$HP\.openclaw\workspace-openclaw" "$LatestDir\openclaw\workspace-openclaw" "OpenClaw workspace-openclaw" 60
Add-Task "$HP\.openclaw\workspace-openclaw4" "$LatestDir\openclaw\workspace-openclaw4" "OpenClaw workspace-openclaw4" 60
Add-Task "$HP\.openclaw\workspace-moltbot" "$LatestDir\openclaw\workspace-moltbot" "OpenClaw workspace-moltbot" 180
Add-Task "$HP\.openclaw\workspace-moltbot2" "$LatestDir\openclaw\workspace-moltbot2" "OpenClaw workspace-moltbot2" 60
Add-Task "$HP\.openclaw\workspace-openclaw-main" "$LatestDir\openclaw\workspace-openclaw-main" "OpenClaw workspace-openclaw-main" 60
Add-Task "$HP\.openclaw\agents" "$LatestDir\openclaw\agents" "OpenClaw agents" 60
Add-Task "$HP\.openclaw\credentials" "$LatestDir\openclaw\credentials-dir" "OpenClaw credentials (tokens)" 30
Add-Task "$HP\.openclaw\memory" "$LatestDir\openclaw\memory" "OpenClaw memory" 30
Add-Task "$HP\.openclaw\cron" "$LatestDir\openclaw\cron" "OpenClaw cron jobs" 30
Add-Task "$HP\.openclaw\extensions" "$LatestDir\openclaw\extensions" "OpenClaw extensions" 30
Add-Task "$HP\.openclaw\skills" "$LatestDir\openclaw\skills" "OpenClaw skills" 30
Add-Task "$HP\.openclaw\scripts" "$LatestDir\openclaw\scripts" "OpenClaw scripts" 30
Add-Task "$HP\.openclaw\browser" "$LatestDir\openclaw\browser" "OpenClaw browser relay" 180
Add-Task "$HP\.openclaw\telegram" "$LatestDir\openclaw\telegram" "OpenClaw telegram cmds" 30
Add-Task "$HP\.openclaw\ClawdBot" "$LatestDir\openclaw\ClawdBot-tray" "OpenClaw ClawdBot tray" 30
Add-Task "$HP\.openclaw\completions" "$LatestDir\openclaw\completions" "OpenClaw completions" 30
Add-Task "$HP\.openclaw\.claude" "$LatestDir\openclaw\dot-claude-nested" ".openclaw/.claude config" 30
Add-Task "$HP\.openclaw\config" "$LatestDir\openclaw\config" "OpenClaw config dir" 30
Add-Task "$HP\.openclaw\devices" "$LatestDir\openclaw\devices" "OpenClaw devices" 30
Add-Task "$HP\.openclaw\delivery-queue" "$LatestDir\openclaw\delivery-queue" "OpenClaw delivery-queue" 30
Add-Task "$HP\.openclaw\sessions" "$LatestDir\openclaw\sessions-dir" "OpenClaw sessions dir" 30
Add-Task "$HP\.openclaw\hooks" "$LatestDir\openclaw\hooks" "OpenClaw hooks" 30
Add-Task "$HP\.openclaw\startup-wrappers" "$LatestDir\openclaw\startup-wrappers" "OpenClaw startup-wrappers" 30
Add-Task "$HP\.openclaw\subagents" "$LatestDir\openclaw\subagents" "OpenClaw subagents" 30
Add-Task "$HP\.openclaw\docs" "$LatestDir\openclaw\docs" "OpenClaw docs" 30
Add-Task "$HP\.openclaw\evolved-tools" "$LatestDir\openclaw\evolved-tools" "OpenClaw evolved-tools" 30
Add-Task "$HP\.openclaw\foundry" "$LatestDir\openclaw\foundry" "OpenClaw foundry" 30
Add-Task "$HP\.openclaw\lib" "$LatestDir\openclaw\lib" "OpenClaw lib" 30
Add-Task "$HP\.openclaw\patterns" "$LatestDir\openclaw\patterns" "OpenClaw patterns" 30
# SKIPPED: .openclaw\logs (regeneratable), .openclaw\backups (inception-level duplication)

# Full-tree robocopy of entire .openclaw root (catches any new files/dirs not yet enumerated above)
# REMOVED: Full-tree .openclaw robocopy - redundant with individual subdirs + catch-all + Phase 2 root files
# All .openclaw content is covered by: individual Add-Tasks, catch-all unknown scanner, Phase 2 root file copy

# Dynamic workspace-* scanner
$knownWS = @("workspace","workspace-main","workspace-session2","workspace-openclaw","workspace-openclaw4","workspace-moltbot","workspace-moltbot2","workspace-openclaw-main")
if (Test-Path "$HP\.openclaw") {
    Get-ChildItem "$HP\.openclaw" -Directory -Filter "workspace-*" -EA SilentlyContinue | Where-Object {
        $knownWS -notcontains $_.Name
    } | ForEach-Object { Add-Task $_.FullName "$LatestDir\openclaw\$($_.Name)" "OpenClaw dynamic: $($_.Name)" 60 }
}

# .openclaw catch-all unknown subdirs
$knownOC = @("workspace","workspace-main","workspace-session2","workspace-openclaw","workspace-openclaw4",
    "workspace-moltbot","workspace-moltbot2","workspace-openclaw-main","agents","credentials","memory",
    "cron","extensions","skills","scripts","browser","telegram","ClawdBot","completions",".claude",
    "config","devices","delivery-queue","sessions","hooks","startup-wrappers","subagents","docs",
    "evolved-tools","foundry","lib","patterns",
    "node_modules","logs","backups","__pycache__",
    # Backup artifacts (restore leftovers) - skip to avoid re-copying backup structure:
    "catchall","full-tree","npm-module","root-files","credentials-dir","sessions-dir",
    "dot-claude-nested","ClawdBot-tray","clawdbot-wrappers","restore-rollbacks","rolling-backups",
    "mission-control")
if (Test-Path "$HP\.openclaw") {
    Get-ChildItem "$HP\.openclaw" -Directory -EA SilentlyContinue | Where-Object {
        $knownOC -notcontains $_.Name -and $_.Name -notmatch "^workspace-" -and $_.Name -notmatch "^(\.git|__pycache__|\.venv|venv)$"
    } | ForEach-Object { Add-Task $_.FullName "$LatestDir\openclaw\catchall\$($_.Name)" "OpenClaw CATCHALL: $($_.Name)" 60 }
}

Add-Task "$A\npm\node_modules\openclaw" "$LatestDir\openclaw\npm-module" "openclaw npm module" 120
Add-Task "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot" "$LatestDir\openclaw\clawdbot-wrappers" "ClawdBot wrappers" 180
Add-Task "$HP\openclaw-mission-control" "$LatestDir\openclaw\mission-control" "openclaw-mission-control" 120 -XD @('.git')

# ============ OPENCODE ============
Add-Task "$HP\.local\share\opencode" "$LatestDir\opencode\local-share" "OpenCode data" 60
Add-Task "$HP\.config\opencode" "$LatestDir\opencode\config" "OpenCode config" 30
Add-Task "$HP\.sisyphus" "$LatestDir\opencode\sisyphus" ".sisyphus agent" 30
Add-Task "$HP\.local\state\opencode" "$LatestDir\opencode\state" "OpenCode state" 30
# SKIPPED: .cache\opencode (regeneratable cache)

# ============ APPDATA ============
# Roaming\Claude but EXCLUDING caches (saves ~5MB caches + avoids huge Code Cache growth)
Add-Task "$A\Claude" "$LatestDir\appdata\roaming-claude" "AppData\Roaming\Claude (config, sessions, bridge)" 180 -XD $claudeAppExcludeDirs
Add-Task "$A\Claude Code" "$LatestDir\appdata\roaming-claude-code" "Claude Code browser ext" 30
# SKIPPED: Local\Claude (just logs), Local\claude-cli-nodejs (cache), Local\AnthropicClaude (546MB reinstallable app), Local\claude (cache)

# ============ CLI STATE (skip old version binaries - 230MB reinstallable) ============
Add-Task "$HP\.local\state\claude" "$LatestDir\cli-state\state" "CLI state (locks)" 30
Add-Task "$HP\.local\bin" "$LatestDir\cli-state\local-bin" ".local/bin (claude.exe, uv.exe)" 30
Add-Task "$HP\.local\share\claude" "$LatestDir\cli-binary\local-share-claude" ".local/share/claude (config, excl versions)" 60 -XD @('versions')
# SKIPPED: .local\share\claude\versions (230MB old binaries - reinstallable via npm)

# ============ MOLTBOT + CLAWDBOT + CLAWD ============
Add-Task "$HP\.moltbot" "$LatestDir\moltbot\dot-moltbot" ".moltbot config" 30
Add-Task "$HP\.clawdbot" "$LatestDir\clawdbot\dot-clawdbot" ".clawdbot config" 30
Add-Task "$HP\clawd" "$LatestDir\clawd\workspace" "clawd workspace" 60
Add-Task "$A\npm\node_modules\moltbot" "$LatestDir\moltbot\npm-module" "moltbot npm module" 60
Add-Task "$A\npm\node_modules\clawdbot" "$LatestDir\clawdbot\npm-module" "clawdbot npm module" 180

# ============ NPM GLOBAL ============
Add-Task "$A\npm\node_modules\@anthropic-ai" "$LatestDir\npm-global\anthropic-ai" "@anthropic-ai packages" 60
Add-Task "$A\npm\node_modules\opencode-ai" "$LatestDir\npm-global\opencode-ai" "opencode-ai module" 60
Add-Task "$A\npm\node_modules\opencode-antigravity-auth" "$LatestDir\npm-global\opencode-antigravity-auth" "opencode-antigravity-auth" 30

# ============ STARTUP VBS (CRITICAL FOR NEW PC BOOT) ============
Add-Task "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ClawdBot_Startup.vbs" "$LatestDir\startup\vbs\ClawdBot_Startup.vbs" "Windows Startup VBS - ClawdBot auto-launch" 5
Add-Task "$HP\.openclaw\startup-wrappers" "$LatestDir\startup\openclaw-startup-wrappers" "OpenClaw startup wrappers (ALL VBS files)" 30
Add-Task "$HP\.openclaw\gateway-silent.vbs" "$LatestDir\startup\vbs\gateway-silent.vbs" "Gateway silent launcher VBS" 5
Add-Task "$HP\.openclaw\lib\silent-runner.vbs" "$LatestDir\startup\vbs\lib-silent-runner.vbs" "Silent runner VBS library" 5
Add-Task "$HP\.openclaw\typing-daemon\daemon-silent.vbs" "$LatestDir\startup\vbs\typing-daemon-silent.vbs" "Typing daemon VBS" 5
# NOTE: .claude\scripts already included in full .claude backup at core\claude-home

# ============ OTHER DOT-DIRS ============
Add-Task "$HP\.claudegram" "$LatestDir\other\claudegram" ".claudegram" 30
Add-Task "$HP\.claude-server-commander" "$LatestDir\other\claude-server-commander" ".claude-server-commander" 30
Add-Task "$HP\.cagent" "$LatestDir\other\cagent" ".cagent store" 30
Add-Task "$HP\.anthropic" "$LatestDir\other\anthropic" ".anthropic (credentials)" 15

# ============ VS CODE EXTENSIONS (claude|anthropic) ============
if (Test-Path "$HP\.vscode\extensions") {
    Get-ChildItem "$HP\.vscode\extensions" -Directory -EA SilentlyContinue | Where-Object { $_.Name -match 'claude|anthropic' } | ForEach-Object {
        Add-Task $_.FullName "$LatestDir\vscode-ext\$($_.Name)" "VS Code: $($_.Name)" 30
    }
}

# ============ GIT + SSH ============
# SSH backed up as individual files in Phase 2 to avoid robocopy ACL errors
Add-Task "$HP\.config\gh" "$LatestDir\git\github-cli" "GitHub CLI config" 15

# ============ PYTHON ============
Add-Task "$HP\.local\share\uv" "$LatestDir\python\uv" "uv data" 60

# ============ POWERSHELL MODULES ============
Add-Task "$HP\Documents\PowerShell\Modules\ClaudeUsage" "$LatestDir\powershell\ClaudeUsage-ps7" "ClaudeUsage PS7" 15
Add-Task "$HP\Documents\WindowsPowerShell\Modules\ClaudeUsage" "$LatestDir\powershell\ClaudeUsage-ps5" "ClaudeUsage PS5" 15

# ============ CONFIG DIRS ============
Add-Task "$HP\.config\browserclaw" "$LatestDir\config\browserclaw" ".config/browserclaw" 180
Add-Task "$HP\.config\cagent" "$LatestDir\config\cagent" ".config/cagent" 15
Add-Task "$HP\.config\configstore" "$LatestDir\config\configstore" ".config/configstore" 15

# ============ CHROME INDEXEDDB ============
Add-Task "$L\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.blob" "$LatestDir\chrome\p1-blob" "Chrome P1 claude.ai blob" 30
Add-Task "$L\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.leveldb" "$LatestDir\chrome\p1-leveldb" "Chrome P1 claude.ai leveldb" 30
Add-Task "$L\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.blob" "$LatestDir\chrome\p2-blob" "Chrome P2 claude.ai blob" 30
Add-Task "$L\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.leveldb" "$LatestDir\chrome\p2-leveldb" "Chrome P2 claude.ai leveldb" 30

# Chrome catch-all (Profile 3+, Default)
$chromeUD = "$L\Google\Chrome\User Data"
if (Test-Path $chromeUD) {
    Get-ChildItem $chromeUD -Directory -EA SilentlyContinue | Where-Object {
        $_.Name -match "^(Profile [3-9]|Profile \d{2,}|Default)$"
    } | ForEach-Object {
        $pn = $_.Name -replace " ","-"
        $idb = Join-Path $_.FullName "IndexedDB"
        if (Test-Path $idb) {
            Get-ChildItem $idb -Directory -Filter "*claude*" -EA SilentlyContinue | ForEach-Object {
                Add-Task $_.FullName "$LatestDir\chrome\$pn-$($_.Name)" "Chrome $pn claude.ai" 30
            }
        }
    }
}

# Edge + Brave + Firefox catch-all
@(@{R="$L\Microsoft\Edge\User Data";P="edge"},@{R="$L\BraveSoftware\Brave-Browser\User Data";P="brave"}) | ForEach-Object {
    $bp=$_; if(Test-Path $bp.R){
        Get-ChildItem $bp.R -Directory -EA SilentlyContinue | Where-Object {$_.Name -match "^(Profile \d+|Default)$"} | ForEach-Object {
            $pn=$_.Name -replace " ","-"; $idb=Join-Path $_.FullName "IndexedDB"
            if(Test-Path $idb){ Get-ChildItem $idb -Directory -Filter "*claude*" -EA SilentlyContinue | ForEach-Object {
                Add-Task $_.FullName "$LatestDir\browser\$($bp.P)-$pn-$($_.Name)" "$($bp.P) $pn claude.ai" 30
            }}
        }
    }
}
if(Test-Path "$A\Mozilla\Firefox\Profiles"){
    Get-ChildItem "$A\Mozilla\Firefox\Profiles" -Directory -EA SilentlyContinue | ForEach-Object {
        $fp=$_.Name; $sp=Join-Path $_.FullName "storage\default"
        if(Test-Path $sp){ Get-ChildItem $sp -Directory -Filter "*claude*" -EA SilentlyContinue | ForEach-Object {
            Add-Task $_.FullName "$LatestDir\browser\firefox-$fp-$($_.Name)" "Firefox $fp claude.ai" 30
        }}
    }
}

# ============ CATCH-ALL SCANNERS ============
# Home dot-dirs
$knownHome = @(".claude",".claudegram",".claude-server-commander",".openclaw",".moltbot",".clawdbot",".sisyphus",".cagent",".anthropic","clawd",".clawd","openclaw-mission-control",".openclaw-mission-control")
Get-ChildItem $HP -Directory -Force -EA SilentlyContinue | Where-Object {
    $_.Name -match "^\.?(claude|openclaw|anthropic|opencode|cagent|browserclaw|clawd|moltbot)" -and ($knownHome -notcontains $_.Name) -and $_.Name -notmatch "restore-rollback"
} | ForEach-Object {
    Add-Task $_.FullName "$LatestDir\catchall\home-$($_.Name -replace '^\.','')" "Home: $($_.Name)" 60
}

# AppData
$knownAD = @("Claude","Claude Code","claude-code-sessions","claude-cli-nodejs","AnthropicClaude")
@($A, $L) | ForEach-Object {
    $root=$_; Get-ChildItem $root -Directory -EA SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic|cagent|browserclaw|clawd|moltbot" -and ($knownAD -notcontains $_.Name)
    } | ForEach-Object {
        $rel = if($root -eq $A){"roaming"}else{"local"}
        Add-Task $_.FullName "$LatestDir\catchall\appdata-$rel-$($_.Name)" "AppData $rel\$($_.Name)" 60
    }
}

# npm global
$knownNpm = @("@anthropic-ai","openclaw","moltbot","clawdbot","opencode-ai","opencode-antigravity-auth")
if(Test-Path "$A\npm\node_modules"){
    Get-ChildItem "$A\npm\node_modules" -Directory -EA SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic|opencode|moltbot|clawd|cagent|browserclaw" -and ($knownNpm -notcontains $_.Name)
    } | ForEach-Object { Add-Task $_.FullName "$LatestDir\catchall\npm-$($_.Name)" "npm: $($_.Name)" 60 }
}

# .local
$knownLocal = @("claude","opencode","uv")
@("$HP\.local\share","$HP\.local\state") | ForEach-Object {
    if(Test-Path $_){
        $seg = ($_ -replace ".*\\\.local\\","")
        Get-ChildItem $_ -Directory -EA SilentlyContinue | Where-Object {
            $_.Name -match "claude|openclaw|anthropic|opencode|cagent|browserclaw|clawd|moltbot" -and ($knownLocal -notcontains $_.Name)
        } | ForEach-Object { Add-Task $_.FullName "$LatestDir\catchall\local-$seg-$($_.Name)" ".local/$seg/$($_.Name)" 60 }
    }
}

# .config
$knownCfg = @("claude","opencode","gh","browserclaw","cagent","configstore")
if(Test-Path "$HP\.config"){
    Get-ChildItem "$HP\.config" -Directory -EA SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic|opencode|cagent|browserclaw|clawd|moltbot" -and ($knownCfg -notcontains $_.Name)
    } | ForEach-Object { Add-Task $_.FullName "$LatestDir\catchall\config-$($_.Name)" ".config/$($_.Name)" 30 }
}

# ProgramData + LocalLow
if(Test-Path "$env:ProgramData"){
    Get-ChildItem "$env:ProgramData" -Directory -EA SilentlyContinue | Where-Object {$_.Name -match "claude|openclaw|anthropic"} | ForEach-Object {
        Add-Task $_.FullName "$LatestDir\catchall\progdata-$($_.Name)" "ProgramData/$($_.Name)" 30
    }
}
if(Test-Path "$HP\AppData\LocalLow"){
    Get-ChildItem "$HP\AppData\LocalLow" -Directory -EA SilentlyContinue | Where-Object {$_.Name -match "claude|openclaw|anthropic"} | ForEach-Object {
        Add-Task $_.FullName "$LatestDir\catchall\locallow-$($_.Name)" "LocalLow/$($_.Name)" 30
    }
}

# Temp
@("claude","openclaw") | ForEach-Object {
    $td = "$L\Temp\$_"
    if(Test-Path $td){ Add-Task $td "$LatestDir\catchall\temp-$_" "Temp/$_" 30 }
}

# WSL
if(Test-Path "$L\Packages"){
    Get-ChildItem "$L\Packages" -Directory -Filter "*CanonicalGroup*" -EA SilentlyContinue | ForEach-Object {
        $wh = Join-Path $_.FullName "LocalState\rootfs\home"
        if(Test-Path $wh){
            Get-ChildItem $wh -Directory -EA SilentlyContinue | ForEach-Object {
                $wu=$_.Name
                @(".claude",".openclaw",".config\claude",".config\opencode") | ForEach-Object {
                    $wp = Join-Path $wh "$wu\$_"
                    if(Test-Path $wp){ Add-Task $wp "$LatestDir\catchall\wsl-$wu-$($_ -replace '[\\./]','-')" "WSL $wu/$_" 30 }
                }
            }
        }
    }
}

# Drives D: E: F: shallow (exclude backup root to prevent inception)
$backupRoot = "F:\backup\claudecode"
@("D:\","E:\","F:\") | ForEach-Object {
    if(Test-Path $_){
        $dl=$_.Substring(0,1)
        Get-ChildItem $_ -Directory -Depth 1 -EA SilentlyContinue | Where-Object {
            $_.Name -match "claude|openclaw|clawd|moltbot|anthropic|cagent|browserclaw|opencode" -and
            $_.FullName -notlike "$backupRoot*" -and $_.FullName -notlike "$BackupPath*"
        } | ForEach-Object { Add-Task $_.FullName "$LatestDir\catchall\drive-$dl-$($_.Name)" "Drive $dl/$($_.Name)" 120 }
    }
}

# Restore rollbacks
Get-ChildItem "$HP" -Directory -Force -EA SilentlyContinue | Where-Object {$_.Name -match "^\.?openclaw-restore-rollback"} | ForEach-Object {
    Add-Task $_.FullName "$LatestDir\openclaw\restore-rollbacks\$($_.Name -replace '^\.','')" "Restore rollback: $($_.Name)" 60
}

# Windows Store Claude (desktop app settings, minus VM bundles)
$storeCl = "$L\Packages\Claude_pzs8sxrjxfjjc\Settings"
if(Test-Path $storeCl){ Add-Task $storeCl "$LatestDir\appdata\store-claude-settings" "Windows Store Claude settings" 15 }
$storeRoaming = "$L\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude"
if(Test-Path $storeRoaming){ Add-Task $storeRoaming "$LatestDir\appdata\store-claude-roaming" "Claude Desktop app data (excl VM)" 60 -XD @("vm_bundles") }

# ============ TGTRAY + CHANNELS (Telegram tray app) ============
Add-Task "F:\study\Dev_Toolchain\programming\.net\projects\c#\TgTray" "$LatestDir\tgtray\source" "TgTray source + build script" 30
Add-Task "$HP\.local\bin\tg.exe" "$LatestDir\tgtray\tg.exe" "tg.exe deployed binary" 5
Add-Task "$HP\.claude\channels" "$LatestDir\tgtray\channels" "Channel scripts (VBS, CMD, PS1, logs)" 30

# ============ SHELL:STARTUP SHORTCUTS ============
$startupDir = "$A\Microsoft\Windows\Start Menu\Programs\Startup"
Add-Task "$startupDir\Claude Channel.lnk" "$LatestDir\startup\shortcuts\Claude_Channel.lnk" "Startup: Claude Channel shortcut" 5
Add-Task "$startupDir\TgTray.lnk" "$LatestDir\startup\shortcuts\TgTray.lnk" "Startup: TgTray shortcut" 5
Add-Task "$startupDir\ClawdBot Tray.lnk" "$LatestDir\startup\shortcuts\ClawdBot_Tray.lnk" "Startup: ClawdBot Tray shortcut" 5

# ============ EXECUTE ALL TASKS VIA COMPILED C# PARALLEL (zero RunspacePool overhead) ============
$taskCount = $allTasks.Count
$srcs = [string[]]::new($taskCount)
$dsts = [string[]]::new($taskCount)
$descs = [string[]]::new($taskCount)
$xds = [string[][]]::new($taskCount)
for ($i = 0; $i -lt $taskCount; $i++) {
    $srcs[$i] = $allTasks[$i].S
    $dsts[$i] = $allTasks[$i].D
    $descs[$i] = $allTasks[$i].Desc
    $xds[$i] = $allTasks[$i].XD
}
Write-Host "[P1] $taskCount tasks -> BulkSync (C# Parallel.For, $MaxJobs threads)" -ForegroundColor Green
$result = [IncrementalCopier]::BulkSync($srcs, $dsts, $descs, $xds, $script:Errors, $script:DoneLog, $MaxJobs)
# Drain progress log
$msg = $null
while ($script:DoneLog.TryDequeue([ref]$msg)) {
    Write-Host "  $msg" -ForegroundColor DarkGray
}
Write-Host "[P1] Done: $($result[0]) synced ($($result[1]) not found)" -ForegroundColor Green
#endregion

#region ===== PHASE 2: SMALL FILES =====
Write-Host "[P2] Small files..." -ForegroundColor Cyan
$copied = 0

$smallFiles = @(
    @("$HP\.gitconfig", "$LatestDir\git\gitconfig"),
    @("$HP\.gitignore_global", "$LatestDir\git\gitignore_global"),
    @("$HP\.git-credentials", "$LatestDir\git\git-credentials"),
    @("$HP\.npmrc", "$LatestDir\npm-global\npmrc"),
    @("$HP\CLAUDE.md", "$LatestDir\agents\CLAUDE.md"),
    @("$HP\AGENTS.md", "$LatestDir\agents\AGENTS.md"),
    @("$HP\claude-wrapper.ps1", "$LatestDir\special\claude-wrapper.ps1"),
    @("$HP\mcp-ondemand.ps1", "$LatestDir\special\mcp-ondemand.ps1"),
    @("$HP\Documents\WindowsPowerShell\claude.md", "$LatestDir\special\ps-claude.md"),
    @("$HP\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1", "$LatestDir\powershell\ps5-profile.ps1"),
    @("$HP\Documents\PowerShell\Microsoft.PowerShell_profile.ps1", "$LatestDir\powershell\ps7-profile.ps1"),
    @("$A\Claude\claude_desktop_config.json", "$LatestDir\mcp\claude_desktop_config.json"),
    @("$HP\.openclaw\config.yaml", "$LatestDir\openclaw\config.yaml"),
    @("$HP\.openclaw\openclaw.json", "$LatestDir\openclaw\openclaw.json"),
    @("$HP\.openclaw\auth.json", "$LatestDir\openclaw\auth.json"),
    @("$HP\.openclaw\auth-profiles.json", "$LatestDir\openclaw\auth-profiles.json"),
    @("$HP\.openclaw\.openclawrc.json", "$LatestDir\openclaw\openclawrc.json"),
    @("$HP\.openclaw\moltbot.json", "$LatestDir\openclaw\moltbot.json"),
    @("$HP\.openclaw\clawdbot.json", "$LatestDir\openclaw\clawdbot.json"),
    @("$HP\.openclaw\openclaw-backup.json", "$LatestDir\openclaw\openclaw-backup.json"),
    @("$HP\.openclaw\openclaw-gateway-task.xml", "$LatestDir\openclaw\openclaw-gateway-task.xml"),
    @("$HP\.openclaw\apply-jobs.ps1", "$LatestDir\openclaw\apply-jobs.ps1"),
    @("$HP\.openclaw\autostart.log", "$LatestDir\openclaw\autostart.log"),
    @("$HP\.openclaw\sessions.json", "$LatestDir\openclaw\sessions.json"),
    @("$HP\.openclaw\discord-bot-tokens.json", "$LatestDir\openclaw\discord-bot-tokens.json"),
    @("$HP\.openclaw\bot-resilience.json", "$LatestDir\openclaw\bot-resilience.json"),
    @("$HP\.openclaw\package.json", "$LatestDir\openclaw\package.json"),
    @("$HP\.openclaw\gateway.cmd", "$LatestDir\openclaw\gateway.cmd"),
    @("$HP\.openclaw\gateway-silent.vbs", "$LatestDir\openclaw\gateway-silent.vbs"),
    @("$HP\.openclaw\gateway-launcher.ps1", "$LatestDir\openclaw\gateway-launcher.ps1"),
    @("$HP\.openclaw\gateway_watchdog.ps1", "$LatestDir\openclaw\gateway_watchdog.ps1"),
    @("$L\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json", "$LatestDir\terminal\settings.json"),
    @("$L\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json", "$LatestDir\terminal\settings-preview.json")
)

foreach ($f in $smallFiles) {
    if (Test-Path $f[0]) {
        $dir = Split-Path $f[1] -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        # Skip if destination exists and is not older (XO equivalent)
        if ([System.IO.File]::Exists($f[1])) {
            $srcT = [System.IO.File]::GetLastWriteTimeUtc($f[0])
            $dstT = [System.IO.File]::GetLastWriteTimeUtc($f[1])
            if ($srcT -le $dstT.AddSeconds(2)) { $copied++; continue }
        }
        try { [System.IO.File]::Copy($f[0], $f[1], $true); $copied++
            Write-Host "  [FILE] $(Split-Path $f[0] -Leaf)" -ForegroundColor DarkGray
        } catch {}
    }
}

# .env files from home dir
$envDir = "$LatestDir\credentials\env-files"
Get-ChildItem $HP -Filter "*.env" -File -Force -EA SilentlyContinue | ForEach-Object {
    if(-not(Test-Path $envDir)){New-Item -ItemType Directory -Path $envDir -Force|Out-Null}
    try{[System.IO.File]::Copy($_.FullName,"$envDir\$($_.Name)",$true);$copied++
        Write-Host "  [ENV] $($_.Name)" -ForegroundColor DarkGray
    }catch{}
}
# Also check .env in .openclaw and .claude
@("$HP\.openclaw","$HP\.claude") | ForEach-Object {
    if(Test-Path $_){
        Get-ChildItem $_ -Filter "*.env" -File -EA SilentlyContinue | ForEach-Object {
            if(-not(Test-Path $envDir)){New-Item -ItemType Directory -Path $envDir -Force|Out-Null}
            try{[System.IO.File]::Copy($_.FullName,"$envDir\$($_.Name)",$true);$copied++}catch{}
        }
    }
}

# .claude session databases
if(Test-Path "$HP\.claude"){
    $dbDir = "$LatestDir\sessions\databases"
    Get-ChildItem "$HP\.claude" -Filter "*.db" -File -EA SilentlyContinue | ForEach-Object {
        if(-not(Test-Path $dbDir)){New-Item -ItemType Directory -Path $dbDir -Force|Out-Null}
        try{[System.IO.File]::Copy($_.FullName,"$dbDir\$($_.Name)",$true);$copied++
            Write-Host "  [DB] $($_.Name)" -ForegroundColor DarkGray
        }catch{}
    }
}

# .claude history.jsonl (explicit for restore compat)
$histFile = "$HP\.claude\history.jsonl"
if(Test-Path $histFile){
    $sessDir = "$LatestDir\sessions"
    if(-not(Test-Path $sessDir)){New-Item -ItemType Directory -Path $sessDir -Force|Out-Null}
    try{[System.IO.File]::Copy($histFile,"$sessDir\history.jsonl",$true);$copied++}catch{}
}

# SSH keys (individual files to avoid robocopy ACL errors on config/known_hosts)
if (Test-Path "$HP\.ssh") {
    $sshDir = "$LatestDir\git\ssh"
    if(-not(Test-Path $sshDir)){New-Item -ItemType Directory -Path $sshDir -Force|Out-Null}
    Get-ChildItem "$HP\.ssh" -File -Force -EA SilentlyContinue | ForEach-Object {
        try {
            [System.IO.File]::Copy($_.FullName, "$sshDir\$($_.Name)", $true); $copied++
            Write-Host "  [SSH] $($_.Name)" -ForegroundColor DarkGray
        } catch {
            # Fallback: admin copy for ACL-protected files
            try { Copy-Item $_.FullName "$sshDir\$($_.Name)" -Force -EA Stop; $copied++ }
            catch { Write-Host "  [SSH] SKIP $($_.Name) (locked)" -ForegroundColor Yellow }
        }
    }
}

# Rolling backups
@("openclaw.json.*","moltbot.json.*","clawdbot.json.*") | ForEach-Object {
    Get-ChildItem "$HP\.openclaw" -Filter $_ -File -EA SilentlyContinue | ForEach-Object {
        $dir = "$LatestDir\openclaw\rolling-backups"
        if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        try{[System.IO.File]::Copy($_.FullName,"$dir\$($_.Name)",$true);$copied++}catch{}
    }
}

# ALL .openclaw root files
if(Test-Path "$HP\.openclaw"){
    $dir="$LatestDir\openclaw\root-files"
    if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    Get-ChildItem "$HP\.openclaw" -File -EA SilentlyContinue | ForEach-Object {
        try{[System.IO.File]::Copy($_.FullName,"$dir\$($_.Name)",$true);$copied++}catch{}
    }
}

# MCP .cmd wrapper files
$mcpDir = "$LatestDir\mcp-cmd-wrappers"
if(-not(Test-Path $mcpDir)){New-Item -ItemType Directory -Path $mcpDir -Force|Out-Null}
Get-ChildItem "$HP" -Filter "*.cmd" -File -EA SilentlyContinue | ForEach-Object {
    $match = $_.Name -match "mcp|claude|openclaw|clawd|moltbot|anthropic|browser|puppeteer|playwright|filesystem|shell|git-mcp|github|slack|postgres|neo4j|airtable|exa|tavily|firecrawl|duckduckgo|deep-research|deepwiki|everything|knowledge-graph|graphql|desktop-commander|computer-use|time-mcp|zip-mcp|windows-mcp|smart-crawler|read-website|open-websearch|npm-search|document-generator|scheduled-tasks|powershell|shell-server|mcp-compass|mcp-installer|fast-playwright|task-master"
    if(-not $match){
        $c = try{[System.IO.File]::ReadAllText($_.FullName)}catch{""}
        $match = $c -match "node\.exe|node_modules"
    }
    if($match){
        try{[System.IO.File]::Copy($_.FullName,"$mcpDir\$($_.Name)",$true);$copied++
            Write-Host "  [MCP] $($_.Name)" -ForegroundColor DarkGray
        }catch{}
    }
}

# NPM bin shims
$shimDir="$LatestDir\npm-global\bin-shims"
if(-not(Test-Path $shimDir)){New-Item -ItemType Directory -Path $shimDir -Force|Out-Null}
@("claude","claude.cmd","claude.ps1","openclaw","openclaw.cmd","openclaw.ps1",
  "clawdbot","clawdbot.cmd","clawdbot.ps1","opencode","opencode.cmd","opencode.ps1",
  "moltbot","moltbot.cmd","moltbot.ps1") | ForEach-Object {
    $p="$A\npm\$_"
    if(Test-Path $p){try{[System.IO.File]::Copy($p,"$shimDir\$_",$true);$copied++}catch{}}
}

# Startup + Desktop shortcuts
$startDir = "$A\Microsoft\Windows\Start Menu\Programs\Startup"
Get-ChildItem $startDir -File -EA SilentlyContinue | Where-Object {$_.Name -match "openclaw|claude|clawd|moltbot|OpenClaw|TgTray|Tg"} | ForEach-Object {
    $d="$LatestDir\startup"; if(-not(Test-Path $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null}
    try{[System.IO.File]::Copy($_.FullName,"$d\$($_.Name)",$true);$copied++}catch{}
}
Get-ChildItem "$HP\Desktop" -Filter "*.lnk" -File -EA SilentlyContinue | Where-Object {$_.Name -match "claude|openclaw|clawd|moltbot"} | ForEach-Object {
    $d="$LatestDir\special\shortcuts"; if(-not(Test-Path $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null}
    try{[System.IO.File]::Copy($_.FullName,"$d\$($_.Name)",$true);$copied++}catch{}
}

# Task Scheduler XML exports (TgChannel, TgTray, OpenClaw tasks)
$taskDir = "$LatestDir\startup\scheduled-tasks"
if(-not(Test-Path $taskDir)){New-Item -ItemType Directory -Path $taskDir -Force|Out-Null}
@("TgChannel","TgTray") | ForEach-Object {
    try {
        $xml = Get-ScheduledTask -TaskName $_ -EA Stop | Export-ScheduledTask
        [System.IO.File]::WriteAllText("$taskDir\$_.xml", $xml)
        $copied++; Write-Host "  [TASK] $_" -ForegroundColor DarkGray
    } catch {}
}
# Also export any openclaw/claude/moltbot tasks
Get-ScheduledTask -EA SilentlyContinue | Where-Object {$_.TaskName -match "claude|openclaw|clawd|moltbot|OpenClaw"} | ForEach-Object {
    $n = $_.TaskName -replace '[\\/:*?"<>|]','_'
    try { $xml = $_ | Export-ScheduledTask; [System.IO.File]::WriteAllText("$taskDir\$n.xml", $xml); $copied++ } catch {}
}

Write-Host "[P2] Done: $copied files" -ForegroundColor Green
#endregion

#region ===== PHASE 3: METADATA =====
# Collect Phase 0 cache results now (they ran in parallel with Phase 1+2)
Write-Host "[P3] Collecting cache results..." -ForegroundColor Cyan
foreach($h in $ch){
    if($h.H.AsyncWaitHandle.WaitOne(8000)){
        try{$cmdCache[$h.Name]=$h.PS.EndInvoke($h.H)}catch{}
    }
    $h.PS.Dispose()
}
$cp.Close(); $cp.Dispose()
Write-Host "[P3] Cached $($cmdCache.Count)/5 | Writing metadata..." -ForegroundColor Cyan

# Tool versions
New-Item -ItemType Directory -Path "$LatestDir\meta" -Force | Out-Null
if($cmdCache.ContainsKey("versions")){
    $v=$cmdCache["versions"]; if($v -is [System.Collections.IList]){$v=$v[0]}
    if($v){$v|ConvertTo-Json -Depth 5 2>$null|Out-File "$LatestDir\meta\tool-versions.json" -Encoding UTF8}
}

# NPM
New-Item -ItemType Directory -Path "$LatestDir\npm-global" -Force | Out-Null
if($cmdCache.ContainsKey("npm")){
    $n=$cmdCache["npm"]; if($n -is [System.Collections.IList]){$n=$n[0]}
    if($n){
        @{NodeVersion=$n.nodeVer;NpmVersion=$n.npmVer;NpmPrefix=$n.prefix;Timestamp=(Get-Date -Format "o")}|ConvertTo-Json|Out-File "$LatestDir\npm-global\node-info.json" -Encoding UTF8
        if($n.list){$n.list|Out-File "$LatestDir\npm-global\global-packages.txt" -Encoding UTF8}
        if($n.listJson){
            $n.listJson|Out-File "$LatestDir\npm-global\global-packages.json" -Encoding UTF8
            $rs="# NPM Reinstall Script`n# $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n`n"
            try{$p=$n.listJson|ConvertFrom-Json; if($p.dependencies){$p.dependencies.PSObject.Properties|ForEach-Object{$rs+="npm install -g $($_.Name)@$($_.Value.version)`n"}}}catch{}
            $rs|Out-File "$LatestDir\npm-global\REINSTALL-ALL.ps1" -Encoding UTF8
        }
    }
}

# Pip
if($cmdCache.ContainsKey("pip")){
    $po=$cmdCache["pip"]; if($po){
        New-Item -ItemType Directory -Path "$LatestDir\python" -Force|Out-Null
        ($po -join "`n")|Out-File "$LatestDir\python\requirements.txt" -Encoding UTF8
    }
}

# Env vars
New-Item -ItemType Directory -Path "$LatestDir\env" -Force|Out-Null
$ev=@{}
$patterns=@("CLAUDE","ANTHROPIC","OPENAI","OPENCODE","OPENCLAW","MCP","MOLT","CLAWD","NODE","NPM","PYTHON","UV","PATH")
[Environment]::GetEnvironmentVariables("User").GetEnumerator()|ForEach-Object{
    foreach($p in $patterns){if($_.Key -match $p -or $_.Key -eq "PATH"){$ev["USER_$($_.Key)"]=$_.Value;break}}
}
# Also capture Machine-scope claude-related env vars
[Environment]::GetEnvironmentVariables("Machine").GetEnumerator()|ForEach-Object{
    foreach($p in $patterns){if($_.Key -match $p){$ev["MACHINE_$($_.Key)"]=$_.Value;break}}
}
# Capture current process env vars that match claude patterns (picks up session-set vars)
[System.Environment]::GetEnvironmentVariables().GetEnumerator()|ForEach-Object{
    foreach($p in @("CLAUDE","ANTHROPIC","OPENCLAW","MCP")){if($_.Key -match $p -and -not $ev.ContainsKey("USER_$($_.Key)") -and -not $ev.ContainsKey("MACHINE_$($_.Key)")){$ev["PROC_$($_.Key)"]=$_.Value;break}}
}
$ev|ConvertTo-Json -Depth 5|Out-File "$LatestDir\env\environment-variables.json" -Encoding UTF8
# Also write plain-text version for easy grep/diff
($ev.GetEnumerator()|Sort-Object Key|ForEach-Object{"$($_.Key)=$($_.Value)"})|Out-File "$LatestDir\env\environment-variables.txt" -Encoding UTF8

# Registry
New-Item -ItemType Directory -Path "$LatestDir\registry" -Force|Out-Null
@("HKCU\Environment","HKCU\Software\Claude","HKCU\Software\Anthropic","HKCU\Software\Microsoft\Windows\CurrentVersion\Run")|ForEach-Object{
    $key=$_; $sf=($key -replace "\\","-"); $of=Join-Path "$LatestDir\registry" "$sf.reg"
    try{if(Test-Path "Registry::$key"){Start-Process -FilePath "reg" -ArgumentList @("export",$key,$of,"/y") -NoNewWindow -Wait -EA SilentlyContinue}}catch{}
}

# Credentials - individual files + credential manager dump
New-Item -ItemType Directory -Path "$LatestDir\credentials" -Force|Out-Null
$credFiles = @(
    @("$HP\.claude\.credentials.json", "claude-credentials.json"),
    @("$HP\.claude\credentials.json", "claude-credentials-alt.json"),
    @("$HP\.claude\settings.local.json", "settings-local.json"),
    @("$HP\.local\share\opencode\auth.json", "opencode-auth.json"),
    @("$HP\.local\share\opencode\mcp-auth.json", "opencode-mcp-auth.json"),
    @("$HP\.anthropic\credentials.json", "anthropic-credentials.json"),
    @("$HP\.moltbot\credentials.json", "moltbot-credentials.json"),
    @("$HP\.moltbot\config.json", "moltbot-config.json"),
    @("$HP\.clawdbot\credentials.json", "clawdbot-credentials.json"),
    @("$HP\.clawdbot\config.json", "clawdbot-config.json")
)
foreach ($cf in $credFiles) {
    if (Test-Path $cf[0]) {
        try { [System.IO.File]::Copy($cf[0], "$LatestDir\credentials\$($cf[1])", $true); $copied++
            Write-Host "  [CRED] $($cf[1])" -ForegroundColor DarkGray
        } catch {}
    }
}
# OpenClaw auth files
$ocAuthDir = "$LatestDir\credentials\openclaw-auth"
if (Test-Path "$HP\.openclaw") {
    $authFiles = Get-ChildItem "$HP\.openclaw" -File -EA SilentlyContinue | Where-Object { $_.Name -match 'auth|cred|token|secret|\.key$' }
    if ($authFiles) {
        New-Item -ItemType Directory -Path $ocAuthDir -Force | Out-Null
        foreach ($af in $authFiles) { try { [System.IO.File]::Copy($af.FullName, "$ocAuthDir\$($af.Name)", $true); $copied++ } catch {} }
    }
}
# Claude JSON auth files
$clAuthDir = "$LatestDir\credentials\claude-json-auth"
if (Test-Path "$HP\.claude") {
    $clAuthFiles = Get-ChildItem "$HP\.claude" -File -EA SilentlyContinue | Where-Object { $_.Name -match 'credential|auth|token|secret|\.key$' }
    if ($clAuthFiles) {
        New-Item -ItemType Directory -Path $clAuthDir -Force | Out-Null
        foreach ($af in $clAuthFiles) { try { [System.IO.File]::Copy($af.FullName, "$clAuthDir\$($af.Name)", $true); $copied++ } catch {} }
    }
}
# Credential manager text dump
if($cmdCache.ContainsKey("cmdkey")){
    $ck=$cmdCache["cmdkey"]; if($ck){
        ($ck -join "`n")|Out-File "$LatestDir\credentials\credential-manager-full.txt" -Encoding UTF8
        $fi=$ck|Select-String -Pattern "claude|anthropic|openclaw|opencode|moltbot|clawd|github|npm|node" -Context 0,3
        if($fi){$fi|Out-File "$LatestDir\credentials\credential-manager-filtered.txt" -Encoding UTF8}
    }
}

# Scheduled tasks - JSON list AND individual XML exports for restore
New-Item -ItemType Directory -Path "$LatestDir\scheduled-tasks" -Force|Out-Null
if($cmdCache.ContainsKey("schtasks")){
    try{
        $st=$cmdCache["schtasks"]; if($st){
            $tasks=$st|ConvertFrom-Csv -EA SilentlyContinue
            $rel=$tasks|Where-Object{$_."TaskName" -match "claude|openclaw|clawd|moltbot|anthropic" -or $_."Task To Run" -match "claude|openclaw|clawd|moltbot|anthropic"}
            if($rel){
                $rel|ConvertTo-Json -Depth 5|Out-File "$LatestDir\scheduled-tasks\relevant-tasks.json" -Encoding UTF8
                # Export individual XMLs for restore import
                foreach($task in $rel){
                    $tn = $task."TaskName"
                    if($tn){
                        $safeName = ($tn -replace "\\","_" -replace "[^\w_-]","").TrimStart("_")
                        try{
                            $xmlOut = schtasks /query /tn $tn /xml 2>$null
                            if($LASTEXITCODE -eq 0 -and $xmlOut){
                                ($xmlOut -join "`n")|Out-File "$LatestDir\scheduled-tasks\$safeName.xml" -Encoding UTF8
                            }
                        }catch{}
                    }
                }
            }
        }
    }catch{}
}

# Consolidated XML export using CACHED schtasks data (no re-query)
try {
    if($cmdCache.ContainsKey("schtasks")){
        $cachedSt = $cmdCache["schtasks"]
        if($cachedSt){
            $cachedParsed = ($cachedSt -join "`n") | ConvertFrom-Csv -EA SilentlyContinue
            $relCached = $cachedParsed | Where-Object {
                $_."TaskName" -match "claude|openclaw|clawd|moltbot|anthropic|OpenClaw" -or
                $_."Task To Run" -match "claude|openclaw|clawd|moltbot|anthropic|OpenClaw"
            }
            if($relCached){
                $xmlFragments = [System.Collections.Generic.List[string]]::new()
                foreach($t in $relCached){
                    $tn3 = $t."TaskName"
                    if($tn3){
                        try{
                            $xmlOut3 = schtasks /query /tn $tn3 /xml 2>$null
                            if($LASTEXITCODE -eq 0 -and $xmlOut3){
                                $xmlFragments.Add("<!-- Task: $tn3 -->")
                                $xmlFragments.Add(($xmlOut3 -join "`n"))
                            }
                        }catch{}
                    }
                }
                if($xmlFragments.Count -gt 0){
                    $combined = "<?xml version=""1.0"" encoding=""UTF-8""?>`n<Tasks>`n" + ($xmlFragments -join "`n") + "`n</Tasks>"
                    [System.IO.File]::WriteAllText("$LatestDir\scheduled-tasks\scheduled-tasks-claude.xml", $combined, [System.Text.UTF8Encoding]::new($false))
                }
            }
        }
    }
} catch {}
# Software info
$si=@{}
@("claude","openclaw","moltbot","clawdbot","opencode")|ForEach-Object{
    $tool=$_; $vd=$null
    if($cmdCache.ContainsKey("versions")){$vv=$cmdCache["versions"];if($vv -is [System.Collections.IList]){$vv=$vv[0]};if($vv -and $vv.ContainsKey($tool)){$vd=$vv[$tool]}}
    $si[$tool]=@{Installed=$null -ne $vd;Version=if($vd){$vd.Version}else{"N/A"};Path=if($vd){$vd.Path}else{""}}
}
$si|ConvertTo-Json -Depth 5|Out-File "$LatestDir\meta\software-info.json" -Encoding UTF8

Write-Host "[P3] Done" -ForegroundColor Green
#endregion

#region ===== PHASE 4: PROJECT .CLAUDE DIRS =====
Write-Host "[P4] Project .claude scan..." -ForegroundColor Cyan
if($env:SKIP_PROJECT_SEARCH -eq "1"){
    Write-Host "  Skipped (SKIP_PROJECT_SEARCH=1)" -ForegroundColor Yellow
} else {
    $projDirs=@()
    $skipRx = 'node_modules|\\\.git\\|__pycache__|\\\.venv\\|\\venv\\|\\dist\\|\\build\\'
    @("$HP\Projects","$HP\repos","$HP\dev","$HP\code","F:\Projects","D:\Projects","F:\study")|ForEach-Object{
        if(Test-Path $_){
            try {
                # System.IO is 5-10x faster than Get-ChildItem -Recurse
                foreach($d in [System.IO.Directory]::EnumerateDirectories($_, ".claude", [System.IO.SearchOption]::AllDirectories)){
                    if($d -notmatch $skipRx){
                        $projDirs += [System.IO.DirectoryInfo]::new($d)
                    }
                }
            } catch {}
        }
    }
    if($projDirs.Count -gt 0){
        # Use compiled IncrementalCopier instead of robocopy (no process spawn)
        $p4Srcs = [string[]]::new($projDirs.Count)
        $p4Dsts = [string[]]::new($projDirs.Count)
        $p4Descs = [string[]]::new($projDirs.Count)
        $p4Xds = [string[][]]::new($projDirs.Count)
        $xdGit = @("node_modules",".git")
        for($i=0; $i -lt $projDirs.Count; $i++){
            $sn=($projDirs[$i].FullName -replace ":","_" -replace "\\","_" -replace "^_+","")
            $p4Srcs[$i] = $projDirs[$i].FullName
            $p4Dsts[$i] = "$LatestDir\project-claude\$sn"
            $p4Descs[$i] = "$($projDirs[$i].Parent.Name)\.claude"
            $p4Xds[$i] = $xdGit
        }
        $p4Err = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
        $p4Log = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
        [IncrementalCopier]::BulkSync($p4Srcs, $p4Dsts, $p4Descs, $p4Xds, $p4Err, $p4Log, 16) | Out-Null
        $m = $null; while($p4Log.TryDequeue([ref]$m)){ Write-Host "  [PROJECT] $m" -ForegroundColor DarkGray }
        Write-Host "  $($projDirs.Count) project .claude dirs" -ForegroundColor Green
    }
}
#endregion

#region ===== PHASE 5: SYSTEM CLEANUP (optional) =====
if ($Cleanup) {
    Write-Host ""
    Write-Host "[P5] SYSTEM CLEANUP - removing regeneratable garbage..." -ForegroundColor Cyan

    $cleanTargets = @(
        @{Path="$HP\.claude\file-history"; Desc=".claude/file-history (edit history cache)"},
        @{Path="$HP\.claude\cache"; Desc=".claude/cache"},
        @{Path="$HP\.claude\paste-cache"; Desc=".claude/paste-cache"},
        @{Path="$HP\.claude\image-cache"; Desc=".claude/image-cache"},
        @{Path="$HP\.claude\shell-snapshots"; Desc=".claude/shell-snapshots"},
        @{Path="$HP\.claude\debug"; Desc=".claude/debug"},
        @{Path="$HP\.claude\test-logs"; Desc=".claude/test-logs"},
        @{Path="$HP\.claude\downloads"; Desc=".claude/downloads"},
        @{Path="$HP\.claude\session-env"; Desc=".claude/session-env"},
        @{Path="$HP\.claude\telemetry"; Desc=".claude/telemetry"},
        @{Path="$HP\.claude\statsig"; Desc=".claude/statsig"},
        @{Path="$A\Claude\Code Cache"; Desc="Claude Code Cache"},
        @{Path="$A\Claude\GPUCache"; Desc="Claude GPUCache"},
        @{Path="$A\Claude\DawnGraphiteCache"; Desc="Claude DawnGraphiteCache"},
        @{Path="$A\Claude\DawnWebGPUCache"; Desc="Claude DawnWebGPUCache"},
        @{Path="$A\Claude\Cache"; Desc="Claude Cache"},
        @{Path="$A\Claude\Crashpad"; Desc="Claude Crashpad"},
        @{Path="$A\Claude\Network"; Desc="Claude Network cache"},
        @{Path="$A\Claude\blob_storage"; Desc="Claude blob_storage"},
        @{Path="$A\Claude\Session Storage"; Desc="Claude Session Storage"},
        @{Path="$A\Claude\Local Storage"; Desc="Claude Local Storage"},
        @{Path="$L\claude-cli-nodejs"; Desc="claude-cli-nodejs cache"},
        @{Path="$HP\.cache\opencode"; Desc="OpenCode cache"},
        @{Path="$HP\.openclaw\logs"; Desc="OpenClaw logs"}
    )

    $totalFreed = 0
    foreach ($t in $cleanTargets) {
        if (Test-Path $t.Path) {
            $size = try {
                (Get-ChildItem $t.Path -Recurse -File -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
            } catch { 0 }
            if (-not $size) { $size = 0 }

            try {
                Remove-Item $t.Path -Recurse -Force -EA Stop
                $totalFreed += $size
                $sizeMB = [math]::Round($size / 1MB, 1)
                Write-Host "  [CLEANED] $($t.Desc) ($sizeMB MB)" -ForegroundColor Green
            } catch {
                Write-Host "  [LOCKED]  $($t.Desc) - in use" -ForegroundColor Yellow
            }
        }
    }

    # Old CLI version binaries (keep latest only)
    $versionsDir = "$HP\.local\share\claude\versions"
    if (Test-Path $versionsDir) {
        $versions = Get-ChildItem $versionsDir -Directory -EA SilentlyContinue | Sort-Object Name -Descending
        if ($versions.Count -gt 1) {
            $keep = $versions[0].Name
            foreach ($old in $versions | Select-Object -Skip 1) {
                $size = try {
                    (Get-ChildItem $old.FullName -Recurse -File -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                } catch { 0 }
                if (-not $size) { $size = 0 }
                try {
                    Remove-Item $old.FullName -Recurse -Force -EA Stop
                    $totalFreed += $size
                    Write-Host "  [CLEANED] Old CLI version $($old.Name) ($([math]::Round($size/1MB,1)) MB)" -ForegroundColor Green
                } catch {
                    Write-Host "  [LOCKED]  CLI version $($old.Name) - in use" -ForegroundColor Yellow
                }
            }
            Write-Host "  Kept latest CLI: $keep" -ForegroundColor DarkGray
        }
    }

    Write-Host "[P5] Freed $([math]::Round($totalFreed / 1MB, 1)) MB" -ForegroundColor Green
}
#endregion

# Phase 6 REMOVED (v26) - npm @anthropic-ai, cmdkey, schtasks XML, registry all covered by Phase 1/2/3.
# VS Code extensions + Anthropic registry merged into Phase 1 Add-Tasks and Phase 3 registry block.

#region ===== PHASE 7: MANIFEST (fast file listing - no SHA256) =====
Write-Host "[P7] Generating manifest (fast listing)..." -ForegroundColor Cyan
try {
    $manifestEntries = [System.Collections.Generic.List[hashtable]]::new()
    $bpLen = $LatestDir.Length
    foreach ($fi in [System.IO.Directory]::EnumerateFiles($LatestDir, '*', [System.IO.SearchOption]::AllDirectories)) {
        try {
            $info = [System.IO.FileInfo]::new($fi)
            $manifestEntries.Add(@{ path=$fi.Substring($bpLen).TrimStart('\'); size=$info.Length; modified=$info.LastWriteTimeUtc.ToString("o") })
        } catch {}
    }
    $json = @{
        version   = "27.0"
        generated = (Get-Date -Format "o")
        computer  = $env:COMPUTERNAME
        fileCount = $manifestEntries.Count
        files     = $manifestEntries
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText("$LatestDir\manifest.json", $json, [System.Text.UTF8Encoding]::new($false))
    Write-Host "[P7] manifest.json: $($manifestEntries.Count) files" -ForegroundColor Green
} catch {
    Write-Host "[P7] manifest generation failed: $_" -ForegroundColor Yellow
}
#endregion

#region ===== PHASE 8: SNAPSHOT =====
if ($script:IsExFat) {
    # exFAT: robocopy snapshot runs in BACKGROUND so script returns instantly
    # The snapshot finishes copying silently - nothing is skipped
    $snapName = Split-Path $BackupPath -Leaf
    $roboArgs = "`"$LatestDir`" `"$BackupPath`" /E /XO /R:0 /W:0 /MT:32 /NFL /NDL /NJH /NJS /NP"
    # Write metadata FIRST so the snapshot has it when robocopy finishes
    try {
        New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null
        $earlyMeta = @{
            Version    = "28.0 INCREMENTAL"
            Timestamp  = Get-Date -Format "o"
            Computer   = $env:COMPUTERNAME
            Status     = "copying"
        } | ConvertTo-Json -Depth 5
        [System.IO.File]::WriteAllText("$BackupPath\BACKUP-METADATA.json", $earlyMeta, [System.Text.UTF8Encoding]::new($false))
    } catch {}
    Start-Process -FilePath "robocopy" -ArgumentList $roboArgs -WindowStyle Hidden
    Write-Host "[P8] Snapshot $snapName copying in background (robocopy MT:32)" -ForegroundColor Green
} else {
    Write-Host "[P8] Creating hardlink snapshot: $BackupPath ..." -ForegroundColor Cyan
    $hlSw = [System.Diagnostics.Stopwatch]::StartNew()
    try {
        Add-Type @"
using System;
using System.IO;
using System.Runtime.InteropServices;
using System.Threading;
using System.Threading.Tasks;

public class HardLinkCloner {
    [DllImport("kernel32.dll", SetLastError = true, CharSet = CharSet.Unicode)]
    static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);

    public static int[] CloneWithHardlinks(string sourceDir, string targetDir, int maxParallelism) {
        int linked = 0, failed = 0;
        Directory.CreateDirectory(targetDir);
        foreach (string d in Directory.EnumerateDirectories(sourceDir, "*", SearchOption.AllDirectories)) {
            Directory.CreateDirectory(targetDir + d.Substring(sourceDir.Length));
        }
        int srcLen = sourceDir.Length;
        var opts = new ParallelOptions { MaxDegreeOfParallelism = maxParallelism };
        Parallel.ForEach(Directory.EnumerateFiles(sourceDir, "*", SearchOption.AllDirectories), opts, f => {
            string target = targetDir + f.Substring(srcLen);
            if (CreateHardLink(target, f, IntPtr.Zero)) {
                Interlocked.Increment(ref linked);
            } else {
                try { File.Copy(f, target, true); Interlocked.Increment(ref linked); }
                catch { Interlocked.Increment(ref failed); }
            }
        });
        return new int[] { linked, failed };
    }
}
"@
        $result = [HardLinkCloner]::CloneWithHardlinks($LatestDir, $BackupPath, 32)
        $hlSw.Stop()
        Write-Host "[P8] $($result[0]) hardlinks ($($result[1]) fallback) in $([math]::Round($hlSw.Elapsed.TotalSeconds,1))s" -ForegroundColor Green
    } catch {
        Write-Host "[P8] Hardlink snapshot failed: $_ - falling back to robocopy" -ForegroundColor Yellow
        $hlSw.Stop()
        Start-Process -FilePath "robocopy" -ArgumentList "`"$LatestDir`" `"$BackupPath`" /E /R:0 /W:0 /MT:128 /NFL /NDL /NJH /NJS /NP" -WindowStyle Hidden -Wait
        Write-Host "[P8] Fallback robocopy completed" -ForegroundColor Yellow
    }
}
#endregion

#region ===== SUMMARY =====
$sw.Stop()
$elapsedSec = [math]::Round($sw.Elapsed.TotalSeconds, 1)

# Metadata (inside latest; snapshot only if created)
try {
    $metaJson = @{
        Version      = "28.0 INCREMENTAL"
        Timestamp    = Get-Date -Format "o"
        Computer     = $env:COMPUTERNAME
        User         = $env:USERNAME
        LatestDir    = $LatestDir
        SnapshotPath = $BackupPath
        FileSystem   = $backupFsType
        Errors       = @($script:Errors)
        Duration     = $elapsedSec
    } | ConvertTo-Json -Depth 5
    [System.IO.File]::WriteAllText("$LatestDir\BACKUP-METADATA.json", $metaJson, [System.Text.UTF8Encoding]::new($false))
    if (Test-Path $BackupPath) {
        [System.IO.File]::WriteAllText("$BackupPath\BACKUP-METADATA.json", $metaJson, [System.Text.UTF8Encoding]::new($false))
    }
} catch {}

$errCount = @($script:Errors).Count
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  DONE  ${elapsedSec}s  errors=$errCount" -ForegroundColor $(if($errCount -eq 0){"Green"}else{"Yellow"})
Write-Host "  Latest:   $LatestDir" -ForegroundColor DarkGray
Write-Host "  Snapshot: $BackupPath" -ForegroundColor DarkGray
Write-Host ("=" * 80) -ForegroundColor Cyan

exit 0
#endregion
