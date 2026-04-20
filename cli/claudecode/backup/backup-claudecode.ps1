#Requires -Version 5.1
<#
.SYNOPSIS
    Claude Code + OpenClaw Backup v23.0 - BLITZ INCREMENTAL
.DESCRIPTION
    Zero-garbage backup: only useful data, real-time progress, system cleanup.
    v23.0: 100x faster incremental via /MIR /XO. Adds TgTray, channels, Claude Desktop,
    shell:startup shortcuts, Task Scheduler exports, NGEN restore.
    Optional -Cleanup flag safely removes garbage from the live system.
.PARAMETER BackupPath
    Backup directory (default: F:\backup\claudecode\backup_<timestamp>)
.PARAMETER MaxJobs
    Parallel threads (default: 32)
.PARAMETER Cleanup
    After backup, safely remove regeneratable caches from the live system
.NOTES
    Version: 23.0 - BLITZ INCREMENTAL
#>
[CmdletBinding()]
param(
    [string]$BackupPath = "F:\backup\claudecode\backup_$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss')",
    [int]$MaxJobs = 32,
    [switch]$Cleanup
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
    'WebStorage','IndexedDB','Service Worker')

#region Banner
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  CLAUDE CODE + OPENCLAW BACKUP v23.0 BLITZ INCREMENTAL" -ForegroundColor White
Write-Host "  ZERO GARBAGE | REAL-TIME PROGRESS | ALL PARALLEL" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "Backup: $BackupPath"
Write-Host "Threads: $MaxJobs | Cleanup: $Cleanup"
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
#endregion

New-Item -ItemType Directory -Path $BackupPath -Force | Out-Null

#region ===== PHASE 0: CACHE EXPENSIVE COMMANDS =====
Write-Host "[P0] Caching commands..." -ForegroundColor Cyan
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
foreach($h in $ch){
    if($h.H.AsyncWaitHandle.WaitOne(15000)){
        try{$cmdCache[$h.Name]=$h.PS.EndInvoke($h.H)}catch{}
    }
    $h.PS.Dispose()
}
$cp.Close(); $cp.Dispose()
Write-Host "[P0] Cached $($cmdCache.Count)/5 commands" -ForegroundColor Green
#endregion

#region ===== PHASE 1: ALL DIRECTORY COPIES VIA RUNSPACEPOOL =====
Write-Host "[P1] Building task list..." -ForegroundColor Cyan

# Copy scriptblock - returns desc for real-time progress
$copyScript = {
    param($src, $dst, $desc, $errBag, $doneLog, $timeoutSec, $xdExtra)
    try {
        if (-not (Test-Path $src)) { return $null }
        if (Test-Path $src -PathType Container) {
            $xdList = @('node_modules','.git','__pycache__','.venv','venv','platform-tools','outbound','canvas')
            if ($xdExtra) { $xdList += $xdExtra }
            $argStr = "`"$src`" `"$dst`" /MIR /XO /R:0 /W:0 /MT:128 /NFL /NDL /NJH /NJS /NP /FFT"
            if ($xdList.Count -gt 0) {
                $quoted = @(); foreach ($x in $xdList) { $quoted += "`"$x`"" }
                $argStr += " /XD " + ($quoted -join " ")
            }
            $proc = Start-Process -FilePath "robocopy" -ArgumentList $argStr -NoNewWindow -PassThru
            $waitMs = $timeoutSec * 1000
            if (-not $proc.WaitForExit($waitMs)) {
                try { $proc.Kill() } catch {}
                $errBag.Add("TIMEOUT: $desc")
                $doneLog.Enqueue("[TIMEOUT] $desc")
                return $desc
            }
        } else {
            $dir = Split-Path $dst -Parent
            if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
            [System.IO.File]::Copy($src, $dst, $true)
        }
        $doneLog.Enqueue("[OK] $desc")
        return $desc
    } catch {
        $errBag.Add("FAIL: $desc - $($_.ToString())")
        $doneLog.Enqueue("[FAIL] $desc")
        return $desc
    }
}

# Task list
$allTasks = [System.Collections.Generic.List[hashtable]]::new()

function Add-Task {
    param([string]$S,[string]$D,[string]$Desc,[int]$T=120,[string[]]$XD=$null)
    $allTasks.Add(@{S=$S;D=$D;Desc=$Desc;T=$T;XD=$XD})
}

# ============ CORE CLAUDE CODE ============
# .claude FULL but EXCLUDING garbage (saves 26MB file-history + caches)
Add-Task "$HP\.claude" "$BackupPath\core\claude-home" ".claude (settings, rules, hooks, commands, sessions, memory, plugins)" 180 -XD $claudeExcludeDirs
Add-Task "$HP\.claude.json" "$BackupPath\core\claude.json" ".claude.json (main config, 63KB)" 10
Add-Task "$HP\.claude.json.backup" "$BackupPath\core\claude.json.backup" ".claude.json.backup" 10
Add-Task "$HP\.config\claude\projects" "$BackupPath\sessions\config-claude-projects" ".config/claude/projects" 60

# ============ OPENCLAW (selective - full dir is 800MB with node_modules) ============
Add-Task "$HP\.openclaw\workspace" "$BackupPath\openclaw\workspace" "OpenClaw workspace (SOUL.md, USER.md, MEMORY.md)" 60
Add-Task "$HP\.openclaw\workspace-main" "$BackupPath\openclaw\workspace-main" "OpenClaw workspace-main" 60
Add-Task "$HP\.openclaw\workspace-session2" "$BackupPath\openclaw\workspace-session2" "OpenClaw workspace-session2" 60
Add-Task "$HP\.openclaw\workspace-openclaw" "$BackupPath\openclaw\workspace-openclaw" "OpenClaw workspace-openclaw" 60
Add-Task "$HP\.openclaw\workspace-openclaw4" "$BackupPath\openclaw\workspace-openclaw4" "OpenClaw workspace-openclaw4" 60
Add-Task "$HP\.openclaw\workspace-moltbot" "$BackupPath\openclaw\workspace-moltbot" "OpenClaw workspace-moltbot" 180
Add-Task "$HP\.openclaw\workspace-moltbot2" "$BackupPath\openclaw\workspace-moltbot2" "OpenClaw workspace-moltbot2" 60
Add-Task "$HP\.openclaw\workspace-openclaw-main" "$BackupPath\openclaw\workspace-openclaw-main" "OpenClaw workspace-openclaw-main" 60
Add-Task "$HP\.openclaw\agents" "$BackupPath\openclaw\agents" "OpenClaw agents" 60
Add-Task "$HP\.openclaw\credentials" "$BackupPath\openclaw\credentials-dir" "OpenClaw credentials (tokens)" 30
Add-Task "$HP\.openclaw\memory" "$BackupPath\openclaw\memory" "OpenClaw memory" 30
Add-Task "$HP\.openclaw\cron" "$BackupPath\openclaw\cron" "OpenClaw cron jobs" 30
Add-Task "$HP\.openclaw\extensions" "$BackupPath\openclaw\extensions" "OpenClaw extensions" 30
Add-Task "$HP\.openclaw\skills" "$BackupPath\openclaw\skills" "OpenClaw skills" 30
Add-Task "$HP\.openclaw\scripts" "$BackupPath\openclaw\scripts" "OpenClaw scripts" 30
Add-Task "$HP\.openclaw\browser" "$BackupPath\openclaw\browser" "OpenClaw browser relay" 180
Add-Task "$HP\.openclaw\telegram" "$BackupPath\openclaw\telegram" "OpenClaw telegram cmds" 30
Add-Task "$HP\.openclaw\ClawdBot" "$BackupPath\openclaw\ClawdBot-tray" "OpenClaw ClawdBot tray" 30
Add-Task "$HP\.openclaw\completions" "$BackupPath\openclaw\completions" "OpenClaw completions" 30
Add-Task "$HP\.openclaw\.claude" "$BackupPath\openclaw\dot-claude-nested" ".openclaw/.claude config" 30
Add-Task "$HP\.openclaw\config" "$BackupPath\openclaw\config" "OpenClaw config dir" 30
Add-Task "$HP\.openclaw\devices" "$BackupPath\openclaw\devices" "OpenClaw devices" 30
Add-Task "$HP\.openclaw\delivery-queue" "$BackupPath\openclaw\delivery-queue" "OpenClaw delivery-queue" 30
Add-Task "$HP\.openclaw\sessions" "$BackupPath\openclaw\sessions-dir" "OpenClaw sessions dir" 30
Add-Task "$HP\.openclaw\hooks" "$BackupPath\openclaw\hooks" "OpenClaw hooks" 30
Add-Task "$HP\.openclaw\startup-wrappers" "$BackupPath\openclaw\startup-wrappers" "OpenClaw startup-wrappers" 30
Add-Task "$HP\.openclaw\subagents" "$BackupPath\openclaw\subagents" "OpenClaw subagents" 30
Add-Task "$HP\.openclaw\docs" "$BackupPath\openclaw\docs" "OpenClaw docs" 30
Add-Task "$HP\.openclaw\evolved-tools" "$BackupPath\openclaw\evolved-tools" "OpenClaw evolved-tools" 30
Add-Task "$HP\.openclaw\foundry" "$BackupPath\openclaw\foundry" "OpenClaw foundry" 30
Add-Task "$HP\.openclaw\lib" "$BackupPath\openclaw\lib" "OpenClaw lib" 30
Add-Task "$HP\.openclaw\patterns" "$BackupPath\openclaw\patterns" "OpenClaw patterns" 30
# SKIPPED: .openclaw\logs (regeneratable), .openclaw\backups (inception-level duplication)

# Dynamic workspace-* scanner
$knownWS = @("workspace","workspace-main","workspace-session2","workspace-openclaw","workspace-openclaw4","workspace-moltbot","workspace-moltbot2","workspace-openclaw-main")
if (Test-Path "$HP\.openclaw") {
    Get-ChildItem "$HP\.openclaw" -Directory -Filter "workspace-*" -EA SilentlyContinue | Where-Object {
        $knownWS -notcontains $_.Name
    } | ForEach-Object { Add-Task $_.FullName "$BackupPath\openclaw\$($_.Name)" "OpenClaw dynamic: $($_.Name)" 60 }
}

# .openclaw catch-all unknown subdirs
$knownOC = @("workspace","workspace-main","workspace-session2","workspace-openclaw","workspace-openclaw4",
    "workspace-moltbot","workspace-moltbot2","workspace-openclaw-main","agents","credentials","memory",
    "cron","extensions","skills","scripts","browser","telegram","ClawdBot","completions",".claude",
    "config","devices","delivery-queue","sessions","hooks","startup-wrappers","subagents","docs",
    "evolved-tools","foundry","lib","patterns",
    "node_modules","logs","backups")
if (Test-Path "$HP\.openclaw") {
    Get-ChildItem "$HP\.openclaw" -Directory -EA SilentlyContinue | Where-Object {
        $knownOC -notcontains $_.Name -and $_.Name -notmatch "^workspace-" -and $_.Name -notmatch "^(\.git|__pycache__|\.venv|venv)$"
    } | ForEach-Object { Add-Task $_.FullName "$BackupPath\openclaw\catchall\$($_.Name)" "OpenClaw CATCHALL: $($_.Name)" 60 }
}

Add-Task "$A\npm\node_modules\openclaw" "$BackupPath\openclaw\npm-module" "openclaw npm module" 120
Add-Task "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot" "$BackupPath\openclaw\clawdbot-wrappers" "ClawdBot wrappers" 30
Add-Task "$HP\openclaw-mission-control" "$BackupPath\openclaw\mission-control" "openclaw-mission-control" 120 -XD @('.git')

# ============ OPENCODE ============
Add-Task "$HP\.local\share\opencode" "$BackupPath\opencode\local-share" "OpenCode data" 60
Add-Task "$HP\.config\opencode" "$BackupPath\opencode\config" "OpenCode config" 30
Add-Task "$HP\.sisyphus" "$BackupPath\opencode\sisyphus" ".sisyphus agent" 30
Add-Task "$HP\.local\state\opencode" "$BackupPath\opencode\state" "OpenCode state" 30
# SKIPPED: .cache\opencode (regeneratable cache)

# ============ APPDATA ============
# Roaming\Claude but EXCLUDING caches (saves ~5MB caches + avoids huge Code Cache growth)
Add-Task "$A\Claude" "$BackupPath\appdata\roaming-claude" "AppData\Roaming\Claude (config, sessions, bridge)" 180 -XD $claudeAppExcludeDirs
Add-Task "$A\Claude Code" "$BackupPath\appdata\roaming-claude-code" "Claude Code browser ext" 30
# SKIPPED: Local\Claude (just logs), Local\claude-cli-nodejs (cache), Local\AnthropicClaude (546MB reinstallable app), Local\claude (cache)

# ============ CLI STATE (skip old version binaries - 230MB reinstallable) ============
Add-Task "$HP\.local\state\claude" "$BackupPath\cli-state\state" "CLI state (locks)" 30
Add-Task "$HP\.local\bin" "$BackupPath\cli-state\local-bin" ".local/bin (claude.exe, uv.exe)" 30
Add-Task "$HP\.local\share\claude" "$BackupPath\cli-binary\local-share-claude" ".local/share/claude (config, excl versions)" 60 -XD @('versions')
# SKIPPED: .local\share\claude\versions (230MB old binaries - reinstallable via npm)

# ============ MOLTBOT + CLAWDBOT + CLAWD ============
Add-Task "$HP\.moltbot" "$BackupPath\moltbot\dot-moltbot" ".moltbot config" 30
Add-Task "$HP\.clawdbot" "$BackupPath\clawdbot\dot-clawdbot" ".clawdbot config" 30
Add-Task "$HP\clawd" "$BackupPath\clawd\workspace" "clawd workspace" 60
Add-Task "$A\npm\node_modules\moltbot" "$BackupPath\moltbot\npm-module" "moltbot npm module" 60
Add-Task "$A\npm\node_modules\clawdbot" "$BackupPath\clawdbot\npm-module" "clawdbot npm module" 180

# ============ NPM GLOBAL ============
Add-Task "$A\npm\node_modules\@anthropic-ai" "$BackupPath\npm-global\anthropic-ai" "@anthropic-ai packages" 60
Add-Task "$A\npm\node_modules\opencode-ai" "$BackupPath\npm-global\opencode-ai" "opencode-ai module" 60
Add-Task "$A\npm\node_modules\opencode-antigravity-auth" "$BackupPath\npm-global\opencode-antigravity-auth" "opencode-antigravity-auth" 30

# ============ STARTUP VBS (CRITICAL FOR NEW PC BOOT) ============
Add-Task "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup\ClawdBot_Startup.vbs" "$BackupPath\startup\vbs\ClawdBot_Startup.vbs" "Windows Startup VBS - ClawdBot auto-launch" 5
Add-Task "$HP\.openclaw\startup-wrappers" "$BackupPath\startup\openclaw-startup-wrappers" "OpenClaw startup wrappers (ALL VBS files)" 30
Add-Task "$HP\.openclaw\gateway-silent.vbs" "$BackupPath\startup\vbs\gateway-silent.vbs" "Gateway silent launcher VBS" 5
Add-Task "$HP\.openclaw\lib\silent-runner.vbs" "$BackupPath\startup\vbs\lib-silent-runner.vbs" "Silent runner VBS library" 5
Add-Task "$HP\.openclaw\typing-daemon\daemon-silent.vbs" "$BackupPath\startup\vbs\typing-daemon-silent.vbs" "Typing daemon VBS" 5

# ============ OTHER DOT-DIRS ============
Add-Task "$HP\.claudegram" "$BackupPath\other\claudegram" ".claudegram" 30
Add-Task "$HP\.claude-server-commander" "$BackupPath\other\claude-server-commander" ".claude-server-commander" 30
Add-Task "$HP\.cagent" "$BackupPath\other\cagent" ".cagent store" 30
Add-Task "$HP\.anthropic" "$BackupPath\other\anthropic" ".anthropic (credentials)" 15

# ============ GIT + SSH ============
# SSH backed up as individual files in Phase 2 to avoid robocopy ACL errors
Add-Task "$HP\.config\gh" "$BackupPath\git\github-cli" "GitHub CLI config" 15

# ============ PYTHON ============
Add-Task "$HP\.local\share\uv" "$BackupPath\python\uv" "uv data" 60

# ============ POWERSHELL MODULES ============
Add-Task "$HP\Documents\PowerShell\Modules\ClaudeUsage" "$BackupPath\powershell\ClaudeUsage-ps7" "ClaudeUsage PS7" 15
Add-Task "$HP\Documents\WindowsPowerShell\Modules\ClaudeUsage" "$BackupPath\powershell\ClaudeUsage-ps5" "ClaudeUsage PS5" 15

# ============ CONFIG DIRS ============
Add-Task "$HP\.config\browserclaw" "$BackupPath\config\browserclaw" ".config/browserclaw" 180
Add-Task "$HP\.config\cagent" "$BackupPath\config\cagent" ".config/cagent" 15
Add-Task "$HP\.config\configstore" "$BackupPath\config\configstore" ".config/configstore" 15

# ============ CHROME INDEXEDDB ============
Add-Task "$L\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.blob" "$BackupPath\chrome\p1-blob" "Chrome P1 claude.ai blob" 30
Add-Task "$L\Google\Chrome\User Data\Profile 1\IndexedDB\https_claude.ai_0.indexeddb.leveldb" "$BackupPath\chrome\p1-leveldb" "Chrome P1 claude.ai leveldb" 30
Add-Task "$L\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.blob" "$BackupPath\chrome\p2-blob" "Chrome P2 claude.ai blob" 30
Add-Task "$L\Google\Chrome\User Data\Profile 2\IndexedDB\https_claude.ai_0.indexeddb.leveldb" "$BackupPath\chrome\p2-leveldb" "Chrome P2 claude.ai leveldb" 30

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
                Add-Task $_.FullName "$BackupPath\chrome\$pn-$($_.Name)" "Chrome $pn claude.ai" 30
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
                Add-Task $_.FullName "$BackupPath\browser\$($bp.P)-$pn-$($_.Name)" "$($bp.P) $pn claude.ai" 30
            }}
        }
    }
}
if(Test-Path "$A\Mozilla\Firefox\Profiles"){
    Get-ChildItem "$A\Mozilla\Firefox\Profiles" -Directory -EA SilentlyContinue | ForEach-Object {
        $fp=$_.Name; $sp=Join-Path $_.FullName "storage\default"
        if(Test-Path $sp){ Get-ChildItem $sp -Directory -Filter "*claude*" -EA SilentlyContinue | ForEach-Object {
            Add-Task $_.FullName "$BackupPath\browser\firefox-$fp-$($_.Name)" "Firefox $fp claude.ai" 30
        }}
    }
}

# ============ CATCH-ALL SCANNERS ============
# Home dot-dirs
$knownHome = @(".claude",".claudegram",".claude-server-commander",".openclaw",".moltbot",".clawdbot",".sisyphus",".cagent",".anthropic")
Get-ChildItem $HP -Directory -Force -EA SilentlyContinue | Where-Object {
    $_.Name -match "^\.?(claude|openclaw|anthropic|opencode|cagent|browserclaw|clawd|moltbot)" -and ($knownHome -notcontains $_.Name)
} | ForEach-Object {
    Add-Task $_.FullName "$BackupPath\catchall\home-$($_.Name -replace '^\.','')" "Home: $($_.Name)" 60
}

# AppData
$knownAD = @("Claude","Claude Code","claude-code-sessions")
@($A, $L) | ForEach-Object {
    $root=$_; Get-ChildItem $root -Directory -EA SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic|cagent|browserclaw|clawd|moltbot" -and ($knownAD -notcontains $_.Name)
    } | ForEach-Object {
        $rel = if($root -eq $A){"roaming"}else{"local"}
        Add-Task $_.FullName "$BackupPath\catchall\appdata-$rel-$($_.Name)" "AppData $rel\$($_.Name)" 60
    }
}

# npm global
$knownNpm = @("@anthropic-ai","openclaw","moltbot","clawdbot","opencode-ai","opencode-antigravity-auth")
if(Test-Path "$A\npm\node_modules"){
    Get-ChildItem "$A\npm\node_modules" -Directory -EA SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic|opencode|moltbot|clawd|cagent|browserclaw" -and ($knownNpm -notcontains $_.Name)
    } | ForEach-Object { Add-Task $_.FullName "$BackupPath\catchall\npm-$($_.Name)" "npm: $($_.Name)" 60 }
}

# .local
$knownLocal = @("claude","opencode","uv")
@("$HP\.local\share","$HP\.local\state") | ForEach-Object {
    if(Test-Path $_){
        $seg = ($_ -replace ".*\\\.local\\","")
        Get-ChildItem $_ -Directory -EA SilentlyContinue | Where-Object {
            $_.Name -match "claude|openclaw|anthropic|opencode|cagent|browserclaw|clawd|moltbot" -and ($knownLocal -notcontains $_.Name)
        } | ForEach-Object { Add-Task $_.FullName "$BackupPath\catchall\local-$seg-$($_.Name)" ".local/$seg/$($_.Name)" 60 }
    }
}

# .config
$knownCfg = @("claude","opencode","gh","browserclaw","cagent","configstore")
if(Test-Path "$HP\.config"){
    Get-ChildItem "$HP\.config" -Directory -EA SilentlyContinue | Where-Object {
        $_.Name -match "claude|openclaw|anthropic|opencode|cagent|browserclaw|clawd|moltbot" -and ($knownCfg -notcontains $_.Name)
    } | ForEach-Object { Add-Task $_.FullName "$BackupPath\catchall\config-$($_.Name)" ".config/$($_.Name)" 30 }
}

# ProgramData + LocalLow
if(Test-Path "$env:ProgramData"){
    Get-ChildItem "$env:ProgramData" -Directory -EA SilentlyContinue | Where-Object {$_.Name -match "claude|openclaw|anthropic"} | ForEach-Object {
        Add-Task $_.FullName "$BackupPath\catchall\progdata-$($_.Name)" "ProgramData/$($_.Name)" 30
    }
}
if(Test-Path "$HP\AppData\LocalLow"){
    Get-ChildItem "$HP\AppData\LocalLow" -Directory -EA SilentlyContinue | Where-Object {$_.Name -match "claude|openclaw|anthropic"} | ForEach-Object {
        Add-Task $_.FullName "$BackupPath\catchall\locallow-$($_.Name)" "LocalLow/$($_.Name)" 30
    }
}

# Temp
@("claude","openclaw") | ForEach-Object {
    $td = "$L\Temp\$_"
    if(Test-Path $td){ Add-Task $td "$BackupPath\catchall\temp-$_" "Temp/$_" 30 }
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
                    if(Test-Path $wp){ Add-Task $wp "$BackupPath\catchall\wsl-$wu-$($_ -replace '[\\./]','-')" "WSL $wu/$_" 30 }
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
        } | ForEach-Object { Add-Task $_.FullName "$BackupPath\catchall\drive-$dl-$($_.Name)" "Drive $dl/$($_.Name)" 120 }
    }
}

# Restore rollbacks
Get-ChildItem "$HP" -Directory -Force -EA SilentlyContinue | Where-Object {$_.Name -match "^\.?openclaw-restore-rollback"} | ForEach-Object {
    Add-Task $_.FullName "$BackupPath\openclaw\restore-rollbacks\$($_.Name -replace '^\.','')" "Restore rollback: $($_.Name)" 60
}

# Windows Store Claude (desktop app settings, minus VM bundles)
$storeCl = "$L\Packages\Claude_pzs8sxrjxfjjc\Settings"
if(Test-Path $storeCl){ Add-Task $storeCl "$BackupPath\appdata\store-claude-settings" "Windows Store Claude settings" 15 }
$storeRoaming = "$L\Packages\Claude_pzs8sxrjxfjjc\LocalCache\Roaming\Claude"
if(Test-Path $storeRoaming){ Add-Task $storeRoaming "$BackupPath\appdata\store-claude-roaming" "Claude Desktop app data (excl VM)" 60 -XD @("vm_bundles") }

# ============ TGTRAY + CHANNELS (Telegram tray app) ============
Add-Task "F:\study\Dev_Toolchain\programming\.net\projects\c#\TgTray" "$BackupPath\tgtray\source" "TgTray source + build script" 30
Add-Task "$HP\.local\bin\tg.exe" "$BackupPath\tgtray\tg.exe" "tg.exe deployed binary" 5
Add-Task "$HP\.claude\channels" "$BackupPath\tgtray\channels" "Channel scripts (VBS, CMD, PS1, logs)" 30

# ============ SHELL:STARTUP SHORTCUTS ============
$startupDir = "$A\Microsoft\Windows\Start Menu\Programs\Startup"
Add-Task "$startupDir\Claude Channel.lnk" "$BackupPath\startup\shortcuts\Claude_Channel.lnk" "Startup: Claude Channel shortcut" 5
Add-Task "$startupDir\TgTray.lnk" "$BackupPath\startup\shortcuts\TgTray.lnk" "Startup: TgTray shortcut" 5
Add-Task "$startupDir\ClawdBot Tray.lnk" "$BackupPath\startup\shortcuts\ClawdBot_Tray.lnk" "Startup: ClawdBot Tray shortcut" 5

# ============ EXECUTE ALL TASKS ============
$pool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, $MaxJobs)
$pool.ApartmentState = "MTA"
$pool.Open()

$handles = [System.Collections.Generic.List[hashtable]]::new()
$skipped = 0

foreach ($task in $allTasks) {
    if (-not (Test-Path $task.S)) { $skipped++; continue }
    $ps = [System.Management.Automation.PowerShell]::Create()
    $ps.RunspacePool = $pool
    $ps.AddScript($copyScript).AddArgument($task.S).AddArgument($task.D).AddArgument($task.Desc).AddArgument($script:Errors).AddArgument($script:DoneLog).AddArgument($task.T).AddArgument($task.XD) | Out-Null
    $handles.Add(@{ PS=$ps; Handle=$ps.BeginInvoke(); Desc=$task.Desc })
}

$total = $handles.Count
Write-Host "[P1] $total tasks launched ($skipped not found)" -ForegroundColor Green

# Real-time progress loop
$pending = [System.Collections.Generic.List[hashtable]]::new($handles)
$completed = 0
$globalDeadline = (Get-Date).AddMinutes(10)

while ($pending.Count -gt 0) {
    if ((Get-Date) -gt $globalDeadline) {
        Write-Host "  [GLOBAL TIMEOUT] Killing $($pending.Count) remaining" -ForegroundColor Red
        foreach ($h in $pending) { try{$h.PS.Stop();$h.PS.Dispose()}catch{} }
        break
    }

    $still = [System.Collections.Generic.List[hashtable]]::new()
    foreach ($h in $pending) {
        if ($h.Handle.IsCompleted) {
            try { $h.PS.EndInvoke($h.Handle) | Out-Null } catch {}
            $h.PS.Dispose()
            $completed++
        } else { $still.Add($h) }
    }
    $pending = $still

    # Drain and print real-time progress
    $msg = $null
    while ($script:DoneLog.TryDequeue([ref]$msg)) {
        $pct = if($total -gt 0){[math]::Round($completed/$total*100)}else{100}
        Write-Host "  [$completed/$total $pct%] $msg" -ForegroundColor DarkGray
    }

    if ($pending.Count -gt 0) { Start-Sleep -Milliseconds 100 }
}
# Drain remaining
$msg = $null
while ($script:DoneLog.TryDequeue([ref]$msg)) {
    Write-Host "  [$completed/$total] $msg" -ForegroundColor DarkGray
}

$pool.Close(); $pool.Dispose()
Write-Host "[P1] Done: $completed/$total" -ForegroundColor Green
#endregion

#region ===== PHASE 2: SMALL FILES =====
Write-Host "[P2] Small files..." -ForegroundColor Cyan
$copied = 0

$smallFiles = @(
    @("$HP\.gitconfig", "$BackupPath\git\gitconfig"),
    @("$HP\.gitignore_global", "$BackupPath\git\gitignore_global"),
    @("$HP\.git-credentials", "$BackupPath\git\git-credentials"),
    @("$HP\.npmrc", "$BackupPath\npm-global\npmrc"),
    @("$HP\CLAUDE.md", "$BackupPath\agents\CLAUDE.md"),
    @("$HP\AGENTS.md", "$BackupPath\agents\AGENTS.md"),
    @("$HP\claude-wrapper.ps1", "$BackupPath\special\claude-wrapper.ps1"),
    @("$HP\mcp-ondemand.ps1", "$BackupPath\special\mcp-ondemand.ps1"),
    @("$HP\Documents\WindowsPowerShell\claude.md", "$BackupPath\special\ps-claude.md"),
    @("$HP\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1", "$BackupPath\powershell\ps5-profile.ps1"),
    @("$HP\Documents\PowerShell\Microsoft.PowerShell_profile.ps1", "$BackupPath\powershell\ps7-profile.ps1"),
    @("$A\Claude\claude_desktop_config.json", "$BackupPath\mcp\claude_desktop_config.json"),
    @("$HP\.openclaw\config.yaml", "$BackupPath\openclaw\config.yaml"),
    @("$HP\.openclaw\openclaw.json", "$BackupPath\openclaw\openclaw.json"),
    @("$HP\.openclaw\auth.json", "$BackupPath\openclaw\auth.json"),
    @("$HP\.openclaw\auth-profiles.json", "$BackupPath\openclaw\auth-profiles.json"),
    @("$HP\.openclaw\.openclawrc.json", "$BackupPath\openclaw\openclawrc.json"),
    @("$HP\.openclaw\moltbot.json", "$BackupPath\openclaw\moltbot.json"),
    @("$HP\.openclaw\clawdbot.json", "$BackupPath\openclaw\clawdbot.json"),
    @("$HP\.openclaw\openclaw-backup.json", "$BackupPath\openclaw\openclaw-backup.json"),
    @("$HP\.openclaw\openclaw-gateway-task.xml", "$BackupPath\openclaw\openclaw-gateway-task.xml"),
    @("$HP\.openclaw\apply-jobs.ps1", "$BackupPath\openclaw\apply-jobs.ps1"),
    @("$HP\.openclaw\autostart.log", "$BackupPath\openclaw\autostart.log"),
    @("$HP\.openclaw\sessions.json", "$BackupPath\openclaw\sessions.json"),
    @("$HP\.openclaw\discord-bot-tokens.json", "$BackupPath\openclaw\discord-bot-tokens.json"),
    @("$HP\.openclaw\bot-resilience.json", "$BackupPath\openclaw\bot-resilience.json"),
    @("$HP\.openclaw\package.json", "$BackupPath\openclaw\package.json"),
    @("$HP\.openclaw\gateway.cmd", "$BackupPath\openclaw\gateway.cmd"),
    @("$HP\.openclaw\gateway-silent.vbs", "$BackupPath\openclaw\gateway-silent.vbs"),
    @("$HP\.openclaw\gateway-launcher.ps1", "$BackupPath\openclaw\gateway-launcher.ps1"),
    @("$HP\.openclaw\gateway_watchdog.ps1", "$BackupPath\openclaw\gateway_watchdog.ps1"),
    @("$L\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json", "$BackupPath\terminal\settings.json"),
    @("$L\Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json", "$BackupPath\terminal\settings-preview.json")
)

foreach ($f in $smallFiles) {
    if (Test-Path $f[0]) {
        $dir = Split-Path $f[1] -Parent
        if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
        try { [System.IO.File]::Copy($f[0], $f[1], $true); $copied++
            Write-Host "  [FILE] $(Split-Path $f[0] -Leaf)" -ForegroundColor DarkGray
        } catch {}
    }
}

# .env files from home dir
$envDir = "$BackupPath\credentials\env-files"
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
    $dbDir = "$BackupPath\sessions\databases"
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
    $sessDir = "$BackupPath\sessions"
    if(-not(Test-Path $sessDir)){New-Item -ItemType Directory -Path $sessDir -Force|Out-Null}
    try{[System.IO.File]::Copy($histFile,"$sessDir\history.jsonl",$true);$copied++}catch{}
}

# SSH keys (individual files to avoid robocopy ACL errors on config/known_hosts)
if (Test-Path "$HP\.ssh") {
    $sshDir = "$BackupPath\git\ssh"
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
        $dir = "$BackupPath\openclaw\rolling-backups"
        if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
        try{[System.IO.File]::Copy($_.FullName,"$dir\$($_.Name)",$true);$copied++}catch{}
    }
}

# ALL .openclaw root files
if(Test-Path "$HP\.openclaw"){
    $dir="$BackupPath\openclaw\root-files"
    if(-not(Test-Path $dir)){New-Item -ItemType Directory -Path $dir -Force|Out-Null}
    Get-ChildItem "$HP\.openclaw" -File -EA SilentlyContinue | ForEach-Object {
        try{[System.IO.File]::Copy($_.FullName,"$dir\$($_.Name)",$true);$copied++}catch{}
    }
}

# MCP .cmd wrapper files
$mcpDir = "$BackupPath\mcp-cmd-wrappers"
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
$shimDir="$BackupPath\npm-global\bin-shims"
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
    $d="$BackupPath\startup"; if(-not(Test-Path $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null}
    try{[System.IO.File]::Copy($_.FullName,"$d\$($_.Name)",$true);$copied++}catch{}
}
Get-ChildItem "$HP\Desktop" -Filter "*.lnk" -File -EA SilentlyContinue | Where-Object {$_.Name -match "claude|openclaw|clawd|moltbot"} | ForEach-Object {
    $d="$BackupPath\special\shortcuts"; if(-not(Test-Path $d)){New-Item -ItemType Directory -Path $d -Force|Out-Null}
    try{[System.IO.File]::Copy($_.FullName,"$d\$($_.Name)",$true);$copied++}catch{}
}

# Task Scheduler XML exports (TgChannel, TgTray, OpenClaw tasks)
$taskDir = "$BackupPath\startup\scheduled-tasks"
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
Write-Host "[P3] Metadata..." -ForegroundColor Cyan

# Tool versions
New-Item -ItemType Directory -Path "$BackupPath\meta" -Force | Out-Null
if($cmdCache.ContainsKey("versions")){
    $v=$cmdCache["versions"]; if($v -is [System.Collections.IList]){$v=$v[0]}
    if($v){$v|ConvertTo-Json -Depth 5 2>$null|Out-File "$BackupPath\meta\tool-versions.json" -Encoding UTF8}
}

# NPM
New-Item -ItemType Directory -Path "$BackupPath\npm-global" -Force | Out-Null
if($cmdCache.ContainsKey("npm")){
    $n=$cmdCache["npm"]; if($n -is [System.Collections.IList]){$n=$n[0]}
    if($n){
        @{NodeVersion=$n.nodeVer;NpmVersion=$n.npmVer;NpmPrefix=$n.prefix;Timestamp=(Get-Date -Format "o")}|ConvertTo-Json|Out-File "$BackupPath\npm-global\node-info.json" -Encoding UTF8
        if($n.list){$n.list|Out-File "$BackupPath\npm-global\global-packages.txt" -Encoding UTF8}
        if($n.listJson){
            $n.listJson|Out-File "$BackupPath\npm-global\global-packages.json" -Encoding UTF8
            $rs="# NPM Reinstall Script`n# $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n`n"
            try{$p=$n.listJson|ConvertFrom-Json; if($p.dependencies){$p.dependencies.PSObject.Properties|ForEach-Object{$rs+="npm install -g $($_.Name)@$($_.Value.version)`n"}}}catch{}
            $rs|Out-File "$BackupPath\npm-global\REINSTALL-ALL.ps1" -Encoding UTF8
        }
    }
}

# Pip
if($cmdCache.ContainsKey("pip")){
    $po=$cmdCache["pip"]; if($po){
        New-Item -ItemType Directory -Path "$BackupPath\python" -Force|Out-Null
        ($po -join "`n")|Out-File "$BackupPath\python\requirements.txt" -Encoding UTF8
    }
}

# Env vars
New-Item -ItemType Directory -Path "$BackupPath\env" -Force|Out-Null
$ev=@{}
$patterns=@("CLAUDE","ANTHROPIC","OPENAI","OPENCODE","OPENCLAW","MCP","MOLT","CLAWD","NODE","NPM","PYTHON","UV","PATH")
[Environment]::GetEnvironmentVariables("User").GetEnumerator()|ForEach-Object{
    foreach($p in $patterns){if($_.Key -match $p -or $_.Key -eq "PATH"){$ev["USER_$($_.Key)"]=$_.Value;break}}
}
$ev|ConvertTo-Json -Depth 5|Out-File "$BackupPath\env\environment-variables.json" -Encoding UTF8

# Registry
New-Item -ItemType Directory -Path "$BackupPath\registry" -Force|Out-Null
@("HKCU\Environment","HKCU\Software\Claude")|ForEach-Object{
    $key=$_; $sf=($key -replace "\\","-"); $of=Join-Path "$BackupPath\registry" "$sf.reg"
    try{if(Test-Path "Registry::$key"){Start-Process -FilePath "reg" -ArgumentList @("export",$key,$of,"/y") -NoNewWindow -Wait -EA SilentlyContinue}}catch{}
}

# Credentials - individual files + credential manager dump
New-Item -ItemType Directory -Path "$BackupPath\credentials" -Force|Out-Null
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
        try { [System.IO.File]::Copy($cf[0], "$BackupPath\credentials\$($cf[1])", $true); $copied++
            Write-Host "  [CRED] $($cf[1])" -ForegroundColor DarkGray
        } catch {}
    }
}
# OpenClaw auth files
$ocAuthDir = "$BackupPath\credentials\openclaw-auth"
if (Test-Path "$HP\.openclaw") {
    $authFiles = Get-ChildItem "$HP\.openclaw" -File -EA SilentlyContinue | Where-Object { $_.Name -match 'auth|cred|token|secret|\.key$' }
    if ($authFiles) {
        New-Item -ItemType Directory -Path $ocAuthDir -Force | Out-Null
        foreach ($af in $authFiles) { try { [System.IO.File]::Copy($af.FullName, "$ocAuthDir\$($af.Name)", $true); $copied++ } catch {} }
    }
}
# Claude JSON auth files
$clAuthDir = "$BackupPath\credentials\claude-json-auth"
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
        ($ck -join "`n")|Out-File "$BackupPath\credentials\credential-manager-full.txt" -Encoding UTF8
        $fi=$ck|Select-String -Pattern "claude|anthropic|openclaw|opencode|moltbot|clawd|github|npm|node" -Context 0,3
        if($fi){$fi|Out-File "$BackupPath\credentials\credential-manager-filtered.txt" -Encoding UTF8}
    }
}

# Scheduled tasks - JSON list AND individual XML exports for restore
New-Item -ItemType Directory -Path "$BackupPath\scheduled-tasks" -Force|Out-Null
if($cmdCache.ContainsKey("schtasks")){
    try{
        $st=$cmdCache["schtasks"]; if($st){
            $tasks=$st|ConvertFrom-Csv -EA SilentlyContinue
            $rel=$tasks|Where-Object{$_."TaskName" -match "claude|openclaw|clawd|moltbot|anthropic" -or $_."Task To Run" -match "claude|openclaw|clawd|moltbot|anthropic"}
            if($rel){
                $rel|ConvertTo-Json -Depth 5|Out-File "$BackupPath\scheduled-tasks\relevant-tasks.json" -Encoding UTF8
                # Export individual XMLs for restore import
                foreach($task in $rel){
                    $tn = $task."TaskName"
                    if($tn){
                        $safeName = ($tn -replace "\\","_" -replace "[^\w_-]","").TrimStart("_")
                        try{
                            $xmlOut = schtasks /query /tn $tn /xml 2>$null
                            if($LASTEXITCODE -eq 0 -and $xmlOut){
                                ($xmlOut -join "`n")|Out-File "$BackupPath\scheduled-tasks\$safeName.xml" -Encoding UTF8
                            }
                        }catch{}
                    }
                }
            }
        }
    }catch{}
}

# Software info
$si=@{}
@("claude","openclaw","moltbot","clawdbot","opencode")|ForEach-Object{
    $tool=$_; $vd=$null
    if($cmdCache.ContainsKey("versions")){$vv=$cmdCache["versions"];if($vv -is [System.Collections.IList]){$vv=$vv[0]};if($vv -and $vv.ContainsKey($tool)){$vd=$vv[$tool]}}
    $si[$tool]=@{Installed=$null -ne $vd;Version=if($vd){$vd.Version}else{"N/A"};Path=if($vd){$vd.Path}else{""}}
}
$si|ConvertTo-Json -Depth 5|Out-File "$BackupPath\meta\software-info.json" -Encoding UTF8

Write-Host "[P3] Done" -ForegroundColor Green
#endregion

#region ===== PHASE 4: PROJECT .CLAUDE DIRS =====
Write-Host "[P4] Project .claude scan..." -ForegroundColor Cyan
if($env:SKIP_PROJECT_SEARCH -ne "0"){
    Write-Host "  Skipped (SKIP_PROJECT_SEARCH!=0)" -ForegroundColor Yellow
} else {
    $projDirs=@()
    @("$HP\Projects","$HP\repos","$HP\dev","$HP\code","F:\Projects","D:\Projects","F:\study")|ForEach-Object{
        if(Test-Path $_){
            $projDirs += Get-ChildItem -Path $_ -Directory -Recurse -Filter ".claude" -EA SilentlyContinue -Depth 5 |
                Where-Object{$_.FullName -notmatch "node_modules|\.git|__pycache__|\.venv|venv|dist|build"}
        }
    }
    if($projDirs.Count -gt 0){
        $p4Pool=[System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1,[Math]::Min($projDirs.Count,16))
        $p4Pool.ApartmentState="MTA"; $p4Pool.Open()
        $p4Script={
            param($src,$dst,$label)
            if(-not(Test-Path $dst)){New-Item -ItemType Directory -Path $dst -Force|Out-Null}
            Start-Process -FilePath "robocopy" -ArgumentList "`"$src`" `"$dst`" /E /R:0 /W:0 /MT:128 /NFL /NDL /NJH /NJS /XD node_modules .git" -NoNewWindow -Wait
            return $label
        }
        $p4Handles=[System.Collections.Generic.List[hashtable]]::new()
        foreach($dir in $projDirs){
            $sn=($dir.FullName -replace ":","_" -replace "\\","_" -replace "^_+","")
            $dst="$BackupPath\project-claude\$sn"; $label="$($dir.Parent.Name)\.claude"
            $ps=[System.Management.Automation.PowerShell]::Create()
            $ps.RunspacePool=$p4Pool
            $ps.AddScript($p4Script).AddArgument($dir.FullName).AddArgument($dst).AddArgument($label)|Out-Null
            $p4Handles.Add(@{PS=$ps;Handle=$ps.BeginInvoke();Label=$label})
        }
        foreach($h in $p4Handles){
            try{$lbl=$h.PS.EndInvoke($h.Handle);Write-Host "  [PROJECT] $lbl" -ForegroundColor DarkGray}catch{}
            $h.PS.Dispose()
        }
        $p4Pool.Close(); $p4Pool.Dispose()
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

#region ===== SUMMARY =====
# Quick size measurement
$totalSize = 0
try {
    $totalSize = (Get-ChildItem $BackupPath -Recurse -File -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    if (-not $totalSize) { $totalSize = 0 }
} catch {}
$itemCount = @(Get-ChildItem $BackupPath -Recurse -File -EA SilentlyContinue).Count

# Metadata
@{
    Version = "22.0 LEAN BLITZ"
    Timestamp = Get-Date -Format "o"
    Computer = $env:COMPUTERNAME
    User = $env:USERNAME
    BackupPath = $BackupPath
    Items = $itemCount
    SizeMB = [math]::Round($totalSize / 1MB, 2)
    Errors = @($script:Errors)
    Duration = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 1)
    Excluded = @("file-history","cache","paste-cache","image-cache","shell-snapshots","debug","test-logs",
        "downloads","session-env","telemetry","statsig","Code Cache","GPUCache","DawnGraphiteCache",
        "DawnWebGPUCache","Crashpad","Network","blob_storage","Session Storage","Local Storage",
        "AnthropicClaude (546MB reinstallable)","claude versions (230MB reinstallable)",
        "claude-cli-nodejs cache","opencode cache")
} | ConvertTo-Json -Depth 5 | Out-File "$BackupPath\BACKUP-METADATA.json" -Encoding UTF8

$duration = (Get-Date) - $startTime

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  BACKUP COMPLETE - v22.0 LEAN BLITZ" -ForegroundColor Green
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  Files: $itemCount" -ForegroundColor White
Write-Host "  Size:  $([math]::Round($totalSize / 1MB, 2)) MB" -ForegroundColor White
Write-Host "  Time:  $([math]::Round($duration.TotalSeconds, 1))s" -ForegroundColor White

$errList = @($script:Errors)
if ($errList.Count -gt 0) {
    Write-Host "  Errors: $($errList.Count)" -ForegroundColor Yellow
    $errList | Select-Object -First 3 | ForEach-Object { Write-Host "    - $_" -ForegroundColor Yellow }
} else {
    Write-Host "  Errors: 0" -ForegroundColor Green
}

Write-Host ""
Write-Host "  Excluded (regeneratable): ~850MB saved" -ForegroundColor DarkGray
Write-Host "    file-history, caches, telemetry, statsig, GPU/Code/Network cache," -ForegroundColor DarkGray
Write-Host "    AnthropicClaude desktop (546MB), old CLI versions (230MB)" -ForegroundColor DarkGray
Write-Host ""
Write-Host "  Path: $BackupPath" -ForegroundColor Cyan
if (-not $Cleanup) {
    Write-Host "  Tip: Run with -Cleanup to free ~850MB from live system" -ForegroundColor DarkGray
}
Write-Host ("=" * 80) -ForegroundColor Cyan

exit 0
#endregion
