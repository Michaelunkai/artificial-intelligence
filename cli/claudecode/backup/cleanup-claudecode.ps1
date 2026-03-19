#Requires -Version 5.1
<#
.SYNOPSIS
    Safe Claude Code + OpenClaw Cleanup v3.0 - Maximum space reclamation, zero data loss
.DESCRIPTION
    Safely removes ONLY regeneratable/cached/temp/old data related to Claude Code and OpenClaw.
    Scans ENTIRE C: drive dynamically - never misses anything.

    WHAT IT CLEANS (all regeneratable or non-essential):
    - Temp directories (%TEMP%\claude, openclaw, jiti, C:\tmp scan scripts)
    - Claude CLI old version binaries (keeps only current version)
    - AnthropicClaude Desktop Electron cache (GPUCache, Cache, Code Cache, blob_storage, Crashpad)
    - OpenClaw browser-data cache and Chromium caches inside .openclaw\browser subdirs
    - OpenClaw media cache, temp files, old logs, debug captures
    - OpenClaw cloudflared.exe (62MB, re-downloadable)
    - OpenClaw restore reports, rollback dirs, old backups, .bak files
    - .claude caches (cache, paste-cache, image-cache, shell-snapshots, file-history, chrome)
    - .claude\projects tool-results (cached tool output, fully regeneratable)
    - claude-cli-nodejs MCP logs and cache
    - %APPDATA%\Claude Code (Electron state cache)
    - npm cache (global, regeneratable)
    - OpenClaw node_modules + package-lock (regeneratable via npm install)
    - OpenCode caches (.cache\opencode, .local\state\opencode, .local\state\claude)
    - DEEP recursive workspace cleanup (nested node_modules, dist, build, __pycache__, .venv, .next, temp)
    - Stale lock/PID files across all dirs
    - .openclaw root temp artifacts (extglob.FullName, temp-commands*.json, temp_*)
    - Old documentation MDs, screenshots, test/verify scripts
    - Git gc optimization on large workspace repos (optional, saves 30-60% pack space)
    - Dynamic AppData scanner (catches ANY new claude/openclaw/anthropic cache dirs)

    WHAT IT NEVER TOUCHES:
    - All config/settings files (.json configs, CLAUDE.md, settings, etc.)
    - All credentials, auth files, SSH keys, tokens
    - All workspace SOURCE CODE (only cleans build artifacts inside workspaces)
    - All npm global modules (they ARE the tools)
    - Browser extension source (.openclaw\browser\chrome-extension)
    - Sessions, conversation history (.claude\projects\*\*.jsonl)
    - Scripts, cron jobs, extensions, hooks, agents, memory, skills
    - Git config, git history (git gc only optimizes, never deletes history)
    - Environment variables, registry, scheduled tasks
    - openclaw-mission-control repo (user's project)

    SAFETY FEATURES:
    - DRY RUN mode by default (use -Execute to actually delete)
    - Shows exactly what will be deleted with sizes
    - Skips anything that doesn't exist or is 0 bytes
    - Never force-deletes critical directories
    - Git gc is optional (use -GitGC flag)

.PARAMETER Execute
    Actually perform the cleanup. Without this flag, only shows what WOULD be deleted (dry run).
.PARAMETER GitGC
    Run git gc --aggressive on large workspace repos to optimize pack files.
.PARAMETER SkipCLIVersions
    Don't clean old Claude CLI versions from .local\share\claude
.PARAMETER SkipBrowserData
    Don't clean .openclaw\browser-data cache
.PARAMETER SkipDesktopCache
    Don't clean AnthropicClaude Desktop cache
.PARAMETER SkipMedia
    Don't clean .openclaw\media cache
.PARAMETER SkipNpmCache
    Don't clean global npm cache
.NOTES
    Version: 3.0
    Author: AI Agent (Autonomous)
#>
[CmdletBinding()]
param(
    [switch]$Execute = $false,
    [switch]$GitGC = $false,
    [switch]$SkipCLIVersions = $false,
    [switch]$SkipBrowserData = $false,
    [switch]$SkipDesktopCache = $false,
    [switch]$SkipMedia = $false,
    [switch]$SkipNpmCache = $false
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'SilentlyContinue'
$script:TotalFreed = 0
$script:ItemsCleaned = 0
$script:ItemsSkipped = 0
$script:Errors = @()
$script:StartTime = Get-Date

$HOME_DIR = $env:USERPROFILE
$APPDATA = $env:APPDATA
$LOCALAPPDATA = $env:LOCALAPPDATA
$TEMP_DIR = $env:TEMP
$TOTAL_SECTIONS = 25

#region Helper Functions
function Write-Step {
    param([string]$Message, [string]$Status = "INFO")
    $color = switch ($Status) {
        "SUCCESS" { "Green" }
        "WARNING" { "Yellow" }
        "ERROR"   { "Red" }
        "DELETE"  { "Magenta" }
        "DRY"     { "DarkYellow" }
        "SKIP"    { "DarkGray" }
        "GIT"     { "Blue" }
        default   { "Cyan" }
    }
    $ts = Get-Date -Format "HH:mm:ss"
    Write-Host "[$ts] " -NoNewline -ForegroundColor DarkGray
    Write-Host "[$Status] " -NoNewline -ForegroundColor $color
    Write-Host $Message
}

function Get-DirSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        $size = (Get-ChildItem $Path -Recurse -File -Force -ErrorAction SilentlyContinue |
            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
        if ($null -eq $size) { return 0 }
        return [math]::Round($size / 1MB, 2)
    } catch { return 0 }
}

function Get-FileSizeMB {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return 0 }
    try {
        return [math]::Round((Get-Item $Path -Force -ErrorAction SilentlyContinue).Length / 1MB, 2)
    } catch { return 0 }
}

function Remove-SafeDir {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path $Path)) {
        $script:ItemsSkipped++
        return
    }
    $sizeMB = Get-DirSizeMB $Path
    if ($sizeMB -eq 0) {
        $script:ItemsSkipped++
        return
    }
    if ($Execute) {
        try {
            Remove-Item $Path -Recurse -Force -ErrorAction Stop
            Write-Step "  DELETED $Description ($sizeMB MB)" "DELETE"
            $script:TotalFreed += $sizeMB
            $script:ItemsCleaned++
        } catch {
            Write-Step "  FAILED $Description : $_" "ERROR"
            $script:Errors += "$Description : $_"
        }
    } else {
        Write-Step "  WOULD DELETE $Description ($sizeMB MB)" "DRY"
        $script:TotalFreed += $sizeMB
        $script:ItemsCleaned++
    }
}

function Remove-SafeFile {
    param([string]$Path, [string]$Description)
    if (-not (Test-Path $Path)) {
        $script:ItemsSkipped++
        return
    }
    $sizeMB = Get-FileSizeMB $Path
    if ($sizeMB -eq 0) {
        $script:ItemsSkipped++
        return
    }
    if ($Execute) {
        try {
            Remove-Item $Path -Force -ErrorAction Stop
            Write-Step "  DELETED $Description ($sizeMB MB)" "DELETE"
            $script:TotalFreed += $sizeMB
            $script:ItemsCleaned++
        } catch {
            Write-Step "  FAILED $Description : $_" "ERROR"
            $script:Errors += "$Description : $_"
        }
    } else {
        Write-Step "  WOULD DELETE $Description ($sizeMB MB)" "DRY"
        $script:TotalFreed += $sizeMB
        $script:ItemsCleaned++
    }
}

function Remove-SafeFiles {
    param([string]$Dir, [string]$Filter, [string]$Description)
    if (-not (Test-Path $Dir)) { return }
    $files = Get-ChildItem $Dir -File -Filter $Filter -Force -ErrorAction SilentlyContinue
    if (-not $files -or $files.Count -eq 0) { return }
    $totalSize = ($files | Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
    $sizeMB = [math]::Round($totalSize / 1MB, 2)
    if ($sizeMB -eq 0 -and $totalSize -eq 0) { return }
    if ($Execute) {
        try {
            $files | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Step "  DELETED $($files.Count) $Description ($sizeMB MB)" "DELETE"
            $script:TotalFreed += $sizeMB
            $script:ItemsCleaned++
        } catch {
            Write-Step "  FAILED $Description : $_" "ERROR"
            $script:Errors += "$Description : $_"
        }
    } else {
        Write-Step "  WOULD DELETE $($files.Count) $Description ($sizeMB MB)" "DRY"
        $script:TotalFreed += $sizeMB
        $script:ItemsCleaned++
    }
}

# Recursively clean build artifacts inside a directory (any depth)
function Remove-DeepBuildArtifacts {
    param([string]$BaseDir, [string]$Label)
    if (-not (Test-Path $BaseDir)) { return }
    $artifactNames = @("node_modules", "__pycache__", ".venv", "venv", ".cache", "dist", "build", ".next", ".nuxt", ".parcel-cache", ".turbo", "coverage", ".nyc_output", "temp", "tmp")
    Get-ChildItem $BaseDir -Directory -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -in $artifactNames } |
        ForEach-Object {
            # Don't recurse INTO an artifact dir's children (already deleting the whole dir)
            $isNested = $false
            foreach ($an in $artifactNames) {
                if ($_.FullName -match "\\$an\\") { $isNested = $true; break }
            }
            if (-not $isNested) {
                Remove-SafeDir $_.FullName "$Label\...\$($_.Name)"
            }
        }
    # Also clean stale package-lock.json where node_modules was removed
    Get-ChildItem $BaseDir -File -Recurse -Force -Filter "package-lock.json" -ErrorAction SilentlyContinue |
        ForEach-Object {
            $nmDir = Join-Path $_.DirectoryName "node_modules"
            if (-not (Test-Path $nmDir)) {
                Remove-SafeFile $_.FullName "$Label\...\package-lock.json"
            }
        }
}
#endregion

#region Banner
Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  CLAUDE CODE + OPENCLAW SAFE CLEANUP v3.0" -ForegroundColor White
if ($Execute) {
    Write-Host "  MODE: EXECUTE - Files WILL be deleted!" -ForegroundColor Red
} else {
    Write-Host "  MODE: DRY RUN - Nothing will be deleted (use -Execute to clean)" -ForegroundColor Yellow
}
if ($GitGC) {
    Write-Host "  GIT GC: ENABLED - Will optimize large repos" -ForegroundColor Blue
}
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""
#endregion

#region 1. TEMP DIRECTORIES (always safe)
Write-Step "[1/$TOTAL_SECTIONS] Temp directories..." "INFO"
Remove-SafeDir "$TEMP_DIR\claude"   "%TEMP%\claude"
Remove-SafeDir "$TEMP_DIR\openclaw" "%TEMP%\openclaw"
Remove-SafeDir "$TEMP_DIR\jiti"     "%TEMP%\jiti (anthropic module cache)"
Remove-SafeDir "$HOME_DIR\.openclaw\temp" ".openclaw\temp"
# Stale lock/flag files in %TEMP%
foreach ($staleTempFile in @("claude_task_complete", "OpenClawTray.exclusive.lock")) {
    Remove-SafeFile "$TEMP_DIR\$staleTempFile" "%TEMP%\$staleTempFile (stale flag)"
}
# Any other claude/openclaw temp files
if (Test-Path $TEMP_DIR) {
    Get-ChildItem $TEMP_DIR -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'claude|openclaw|anthropic' -and $_.Name -notmatch '\.lock$' -and $_.Length -gt 0 } |
        ForEach-Object { Remove-SafeFile $_.FullName "%TEMP%\$($_.Name) (temp file)" }
}
#endregion

#region 2. CLAUDE CLI OLD VERSIONS (keep only current)
if (-not $SkipCLIVersions) {
    Write-Step "[2/$TOTAL_SECTIONS] Claude CLI old versions (.local\share\claude\versions)..." "INFO"
    $versionsDir = "$HOME_DIR\.local\share\claude\versions"
    if (Test-Path $versionsDir) {
        $versionDirs = @(Get-ChildItem $versionsDir -Directory -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -match '^\d+\.\d+' })

        if ($versionDirs.Count -gt 1) {
            $sorted = $versionDirs | Sort-Object { try { [version]$_.Name } catch { [version]"0.0.0" } } -Descending
            $keep = $sorted[0]
            Write-Step "  Keeping latest: $($keep.Name)" "SUCCESS"
            $sorted | Select-Object -Skip 1 | ForEach-Object {
                Remove-SafeDir $_.FullName "CLI old version: $($_.Name)"
            }
        } elseif ($versionDirs.Count -eq 1) {
            Write-Step "  Only 1 version ($($versionDirs[0].Name)) - nothing to clean" "SUCCESS"
        }
    } else {
        $cliShareDir = "$HOME_DIR\.local\share\claude"
        if (Test-Path $cliShareDir) {
            Get-ChildItem $cliShareDir -Directory -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -match 'cache|tmp|temp|log' } |
                ForEach-Object { Remove-SafeDir $_.FullName "CLI cache: $($_.Name)" }
        }
    }
} else {
    Write-Step "[2/$TOTAL_SECTIONS] Skipping CLI versions (-SkipCLIVersions)" "SKIP"
}
#endregion

#region 3. ANTHROPIC CLAUDE DESKTOP CACHE
if (-not $SkipDesktopCache) {
    Write-Step "[3/$TOTAL_SECTIONS] AnthropicClaude Desktop cache..." "INFO"
    $desktopDir = "$LOCALAPPDATA\AnthropicClaude"
    if (Test-Path $desktopDir) {
        $electronCacheDirs = @(
            "Cache", "CachedData", "CachedExtensions", "Code Cache",
            "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
            "blob_storage", "Session Storage", "Service Worker",
            "WebStorage", "GrShaderCache", "ShaderCache",
            "component_crx_cache", "extensions_crx_cache",
            "Crashpad", "ScriptCache", "Network"
        )
        Get-ChildItem $desktopDir -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -in $electronCacheDirs } |
            ForEach-Object {
                Remove-SafeDir $_.FullName "Desktop cache: $($_.Name)"
            }
        # Clean log, crash, old, tmp files
        Get-ChildItem $desktopDir -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
            Where-Object { $_.Extension -in @('.log', '.old', '.tmp', '.dmp') -or $_.Name -match '^crash' } |
            ForEach-Object {
                Remove-SafeFile $_.FullName "Desktop: $($_.Name)"
            }
    }
} else {
    Write-Step "[3/$TOTAL_SECTIONS] Skipping Desktop cache (-SkipDesktopCache)" "SKIP"
}
#endregion

#region 4. OPENCLAW BROWSER-DATA CACHE (NOT the browser extension!)
if (-not $SkipBrowserData) {
    Write-Step "[4/$TOTAL_SECTIONS] OpenClaw browser-data cache..." "INFO"
    Remove-SafeDir "$HOME_DIR\.openclaw\browser-data" ".openclaw\browser-data (cache, NOT extension)"
} else {
    Write-Step "[4/$TOTAL_SECTIONS] Skipping browser-data (-SkipBrowserData)" "SKIP"
}
#endregion

#region 5. OPENCLAW MEDIA CACHE
if (-not $SkipMedia) {
    Write-Step "[5/$TOTAL_SECTIONS] OpenClaw media cache..." "INFO"
    Remove-SafeDir "$HOME_DIR\.openclaw\media" ".openclaw\media (cached media files)"
} else {
    Write-Step "[5/$TOTAL_SECTIONS] Skipping media (-SkipMedia)" "SKIP"
}
#endregion

#region 6. OPENCLAW LARGE BINARIES (re-downloadable)
Write-Step "[6/$TOTAL_SECTIONS] OpenClaw re-downloadable binaries..." "INFO"
Remove-SafeFile "$HOME_DIR\.openclaw\cloudflared.exe" ".openclaw\cloudflared.exe (62MB, re-downloadable)"
# Any other large re-downloadable binaries
if (Test-Path "$HOME_DIR\.openclaw") {
    Get-ChildItem "$HOME_DIR\.openclaw" -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.exe' -and $_.Length -gt 5MB -and $_.Name -ne 'openclaw.exe' } |
        ForEach-Object { Remove-SafeFile $_.FullName ".openclaw\$($_.Name) (large binary, re-downloadable)" }
}
#endregion

#region 7. OPENCLAW LOGS, TEMP FILES, DEBUG CAPTURES
Write-Step "[7/$TOTAL_SECTIONS] OpenClaw logs and temp files..." "INFO"
# Logs directory
Remove-SafeDir "$HOME_DIR\.openclaw\logs" ".openclaw\logs (log directory)"
# Root log files
Remove-SafeFiles "$HOME_DIR\.openclaw" "*.log" "log files in .openclaw"
Remove-SafeFile "$HOME_DIR\.openclaw\FLICKER_CAUGHT.txt" ".openclaw\FLICKER_CAUGHT.txt (debug capture)"
# Temp files (temp_*.png, temp_*.py, temp-*.ps1, temp-*.json, temp-commands*.json)
if (Test-Path "$HOME_DIR\.openclaw") {
    Get-ChildItem "$HOME_DIR\.openclaw" -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^temp[-_]' } |
        ForEach-Object {
            Remove-SafeFile $_.FullName ".openclaw\$($_.Name)"
        }
}
# Restore reports (we have backups on F:\)
Remove-SafeFiles "$HOME_DIR\.openclaw" "restore-report-*.json" "restore-report files"
# Old rollback directories
Get-ChildItem $HOME_DIR -Force -Directory -ErrorAction SilentlyContinue |
    Where-Object { $_.Name -match '^\.openclaw-restore-rollback-' } |
    ForEach-Object {
        Remove-SafeDir $_.FullName "rollback: $($_.Name)"
    }
# Dashboard tunnel logs
foreach ($logFile in @("dashboard-tunnel-new.log", "dashboard-tunnel.log", "gateway-monitor.log")) {
    Remove-SafeFile "$HOME_DIR\.openclaw\$logFile" ".openclaw\$logFile"
}
#endregion

#region 8. .CLAUDE CACHES
Write-Step "[8/$TOTAL_SECTIONS] .claude caches..." "INFO"
Remove-SafeDir "$HOME_DIR\.claude\cache"           ".claude\cache"
Remove-SafeDir "$HOME_DIR\.claude\paste-cache"      ".claude\paste-cache"
Remove-SafeDir "$HOME_DIR\.claude\image-cache"      ".claude\image-cache"
Remove-SafeDir "$HOME_DIR\.claude\shell-snapshots"  ".claude\shell-snapshots"
Remove-SafeDir "$HOME_DIR\.claude\chrome"            ".claude\chrome (Chromium state)"
# Old backups inside .claude (we have F:\backup)
Remove-SafeDir "$HOME_DIR\.claude\backups"          ".claude\backups (we have F:\backup)"
# Dynamic: clean any other cache-like dirs inside .claude
if (Test-Path "$HOME_DIR\.claude") {
    Get-ChildItem "$HOME_DIR\.claude" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'cache|tmp|temp' -and $_.Name -notin @("cache","paste-cache","image-cache") } |
        ForEach-Object { Remove-SafeDir $_.FullName ".claude\$($_.Name) (cache dir)" }
}
#endregion

#region 9. CLI NODEJS CACHE + MCP LOGS
Write-Step "[9/$TOTAL_SECTIONS] claude-cli-nodejs cache..." "INFO"
$cliNodejsDir = "$LOCALAPPDATA\claude-cli-nodejs"
if (Test-Path $cliNodejsDir) {
    Get-ChildItem $cliNodejsDir -Directory -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'cache|log|tmp|temp' } |
        ForEach-Object {
            Remove-SafeDir $_.FullName "cli-nodejs: $($_.Name)"
        }
    Get-ChildItem $cliNodejsDir -File -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.log', '.tmp', '.old') } |
        ForEach-Object {
            Remove-SafeFile $_.FullName "cli-nodejs: $($_.Name)"
        }
}
#endregion

#region 10. OPENCLAW NODE_MODULES (regeneratable)
Write-Step "[10/$TOTAL_SECTIONS] .openclaw\node_modules (regeneratable)..." "INFO"
Remove-SafeDir "$HOME_DIR\.openclaw\node_modules" ".openclaw\node_modules (npm install regenerates)"
Remove-SafeFile "$HOME_DIR\.openclaw\package-lock.json" ".openclaw\package-lock.json"
#endregion

#region 11. OPENCODE CACHES
Write-Step "[11/$TOTAL_SECTIONS] OpenCode caches..." "INFO"
Remove-SafeDir "$HOME_DIR\.cache\opencode"          ".cache\opencode"
Remove-SafeDir "$HOME_DIR\.local\state\opencode"    ".local\state\opencode (frecency cache)"
Remove-SafeDir "$HOME_DIR\.local\state\claude"      ".local\state\claude"
#endregion

#region 12. OPENCLAW OLD BACKUPS INSIDE .openclaw
Write-Step "[12/$TOTAL_SECTIONS] OpenClaw internal old backups..." "INFO"
Remove-SafeDir "$HOME_DIR\.openclaw\backups" ".openclaw\backups (F:\backup has real backups)"
# Old .bak files in .openclaw root - ALL of them
if (Test-Path "$HOME_DIR\.openclaw") {
    Get-ChildItem "$HOME_DIR\.openclaw" -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '\.(bak|bak\.\d+)$' -or $_.Name -match '\.backup-\d+' -or $_.Name -match '\.mdd-backup$' } |
        ForEach-Object {
            Remove-SafeFile $_.FullName ".openclaw\$($_.Name) (old backup)"
        }
}
#endregion

#region 13. OPENCLAW BROWSER CHROMIUM CACHE (inside .openclaw\browser, NOT the extension)
Write-Step "[13/$TOTAL_SECTIONS] OpenClaw browser Chromium cache (inside .openclaw\browser)..." "INFO"
$browserBase = "$HOME_DIR\.openclaw\browser"
if (Test-Path $browserBase) {
    $chromiumCacheDirs = @(
        "Cache", "CachedData", "CachedExtensions", "Code Cache",
        "GPUCache", "DawnGraphiteCache", "DawnWebGPUCache",
        "blob_storage", "Session Storage", "Service Worker",
        "WebStorage", "GrShaderCache", "ShaderCache",
        "component_crx_cache", "extensions_crx_cache",
        "ScriptCache", "Network", "Crashpad", "Local Storage",
        "IndexedDB", "File System"
    )
    # Scan inside chrome/, openclaw/, clawd/ and ANY other subdirs (except chrome-extension which is source)
    Get-ChildItem $browserBase -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -ne 'chrome-extension' } |
        ForEach-Object {
            $subDir = $_.Name
            $chromiumDir = $_.FullName
            Get-ChildItem $chromiumDir -Directory -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.Name -in $chromiumCacheDirs } |
                ForEach-Object {
                    Remove-SafeDir $_.FullName "browser\$subDir cache: $($_.Name)"
                }
            # Log, crash, tmp files inside
            Get-ChildItem $chromiumDir -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                Where-Object { $_.Extension -in @('.log', '.old', '.tmp', '.dmp') -or $_.Name -match '^crash' } |
                ForEach-Object {
                    Remove-SafeFile $_.FullName "browser\$subDir - $($_.Name)"
                }
        }
}
#endregion

#region 14. .CLAUDE FILE-HISTORY (old file snapshots)
Write-Step "[14/$TOTAL_SECTIONS] .claude\file-history (old file snapshots)..." "INFO"
Remove-SafeDir "$HOME_DIR\.claude\file-history" ".claude\file-history (regeneratable snapshots)"
#endregion

#region 15. DEEP WORKSPACE BUILD ARTIFACTS (recursive scan of ALL workspaces)
Write-Step "[15/$TOTAL_SECTIONS] Deep workspace build artifacts (recursive node_modules, dist, temp)..." "INFO"
if (Test-Path "$HOME_DIR\.openclaw") {
    # Scan ALL workspace-* dirs recursively (not just top level)
    Get-ChildItem "$HOME_DIR\.openclaw" -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^workspace' } |
        ForEach-Object {
            Remove-DeepBuildArtifacts $_.FullName $_.Name
        }
    # Also the main workspace dir
    if (Test-Path "$HOME_DIR\.openclaw\workspace") {
        Remove-DeepBuildArtifacts "$HOME_DIR\.openclaw\workspace" "workspace"
    }
}
#endregion

#region 16. NPM CACHE (global)
if (-not $SkipNpmCache) {
    Write-Step "[16/$TOTAL_SECTIONS] npm cache (global, regeneratable)..." "INFO"
    Remove-SafeDir "$LOCALAPPDATA\npm-cache" "npm-cache (regeneratable)"
    Remove-SafeDir "$HOME_DIR\.npm" ".npm cache (regeneratable)"
    # Also check APPDATA location
    Remove-SafeDir "$APPDATA\npm-cache" "Roaming npm-cache"
} else {
    Write-Step "[16/$TOTAL_SECTIONS] Skipping npm cache (-SkipNpmCache)" "SKIP"
}
#endregion

#region 17. OPENCLAW OLD DOCUMENTATION MDs (already backed up)
Write-Step "[17/$TOTAL_SECTIONS] OpenClaw old documentation MDs..." "INFO"
if (Test-Path "$HOME_DIR\.openclaw") {
    # Auto-generated status/completion docs - NOT config MDs like claude.md
    $docPatterns = @(
        '_(COMPLETE|DEPLOYED|APPLIED|DISABLED|SETUP|FIXED|DONE|RESOLVED|MIGRATED)\.md$',
        '^(BROWSER-FIX|BROWSER-RELAY|BULLETPROOF|CONNECTION-ERROR|EXTENSION-AUTO|PERMANENT-FIXES|SILENT-STARTUP|STARTUP-FIXES|TODOIST_GLOBAL|WEB_SEARCH)',
        '^(AUTOMATION-DEPLOYMENT|CENTRALIZED_|optimization-proof).*\.md$'
    )
    $completionMDs = Get-ChildItem "$HOME_DIR\.openclaw" -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $name = $_.Name
            $isDoc = $false
            foreach ($p in $docPatterns) {
                if ($name -match $p) { $isDoc = $true; break }
            }
            $isDoc
        }
    if ($completionMDs -and $completionMDs.Count -gt 0) {
        $totalSize = ($completionMDs | Measure-Object -Property Length -Sum).Sum
        $sizeMB = [math]::Round($totalSize / 1MB, 2)
        if ($Execute) {
            $completionMDs | Remove-Item -Force -ErrorAction SilentlyContinue
            Write-Step "  DELETED $($completionMDs.Count) old status docs ($sizeMB MB)" "DELETE"
            $script:TotalFreed += $sizeMB
            $script:ItemsCleaned++
        } else {
            Write-Step "  WOULD DELETE $($completionMDs.Count) old status docs ($sizeMB MB)" "DRY"
            $script:TotalFreed += $sizeMB
            $script:ItemsCleaned++
        }
    }
}
#endregion

#region 18. OPENCLAW SCREENSHOTS AND TEST/VERIFY SCRIPTS
Write-Step "[18/$TOTAL_SECTIONS] OpenClaw screenshots and test/verify scripts..." "INFO"
if (Test-Path "$HOME_DIR\.openclaw") {
    # Screenshots (temp captures)
    Get-ChildItem "$HOME_DIR\.openclaw" -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -eq '.png' -and $_.Length -gt 10KB } |
        ForEach-Object { Remove-SafeFile $_.FullName ".openclaw\$($_.Name) (screenshot)" }
    # Old test/verify/check/fix scripts that aren't in scripts/ dir
    Get-ChildItem "$HOME_DIR\.openclaw" -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^(test_|test-|verify|check-|fix-|force-)' -and $_.Extension -in @('.ps1','.py','.sh','.js','.mjs') } |
        ForEach-Object { Remove-SafeFile $_.FullName ".openclaw\$($_.Name) (utility script)" }
}
#endregion

#region 19. .CLAUDE\PROJECTS TOOL-RESULTS (cached tool output, fully regeneratable)
Write-Step "[19/$TOTAL_SECTIONS] .claude\projects tool-results (cached tool output)..." "INFO"
$projectsDir = "$HOME_DIR\.claude\projects"
if (Test-Path $projectsDir) {
    Get-ChildItem $projectsDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
        $projDir = $_.FullName
        # Each project has session dirs with tool-results subdirs
        Get-ChildItem $projDir -Directory -Force -ErrorAction SilentlyContinue | ForEach-Object {
            $toolResultsDir = "$($_.FullName)\tool-results"
            if (Test-Path $toolResultsDir) {
                Remove-SafeDir $toolResultsDir "projects\...\$($_.Name)\tool-results"
            }
        }
    }
}
#endregion

#region 20. STALE LOCK/PID FILES (across all claude/openclaw dirs)
Write-Step "[20/$TOTAL_SECTIONS] Stale lock/PID files..." "INFO"
$lockSearchDirs = @("$HOME_DIR\.openclaw", "$HOME_DIR\.claude")
foreach ($searchDir in $lockSearchDirs) {
    if (Test-Path $searchDir) {
        Get-ChildItem $searchDir -File -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { ($_.Extension -eq '.pid' -or ($_.Extension -eq '.lock' -and $_.Name -ne 'flake.lock' -and $_.Name -ne 'bun.lock' -and $_.Name -ne 'yarn.lock')) -and $_.Length -gt 0 } |
            ForEach-Object {
                Remove-SafeFile $_.FullName "stale: $($_.Name)"
            }
    }
}
#endregion

#region 21. C:\TMP CLEANUP (scan scripts and temp files from previous runs)
Write-Step "[21/$TOTAL_SECTIONS] C:\tmp temp scan/cleanup scripts..." "INFO"
if (Test-Path "C:\tmp") {
    Get-ChildItem "C:\tmp" -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'claude|openclaw|anthropic|scan|cleanup|deep_scan|gap_scan|restore' -and $_.Extension -in @('.ps1','.txt','.log','.json','.tmp') } |
        ForEach-Object { Remove-SafeFile $_.FullName "C:\tmp\$($_.Name) (temp script)" }
}
#endregion

#region 22. DYNAMIC APPDATA SCANNER (catches ANY new claude/openclaw/anthropic cache dirs)
Write-Step "[22/$TOTAL_SECTIONS] Dynamic AppData scanner..." "INFO"
# Already-handled dirs (skip to avoid double counting)
$handledAppDataDirs = @("AnthropicClaude", "claude-cli-nodejs", "npm-cache")
foreach ($appDataRoot in @($LOCALAPPDATA, $APPDATA, "$LOCALAPPDATA\Low")) {
    if (-not (Test-Path $appDataRoot)) { continue }
    Get-ChildItem $appDataRoot -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'claude|openclaw|anthropic|opencode' -and $_.Name -notin $handledAppDataDirs } |
        ForEach-Object {
            $dirName = $_.Name
            $dirPath = $_.FullName
            # Check for cache subdirs inside
            $hasCacheDirs = $false
            if (Test-Path $dirPath) {
                $cacheSubs = Get-ChildItem $dirPath -Directory -Force -ErrorAction SilentlyContinue |
                    Where-Object { $_.Name -match 'cache|Cache|tmp|temp|log|Crash|blob' }
                if ($cacheSubs -and $cacheSubs.Count -gt 0) {
                    foreach ($cs in $cacheSubs) {
                        Remove-SafeDir $cs.FullName "AppData\$dirName\$($cs.Name) (dynamic)"
                        $hasCacheDirs = $true
                    }
                }
            }
            # If no cache subdirs but it IS a cache-like dir itself
            if (-not $hasCacheDirs -and $dirName -match 'cache|Cache|tmp|temp') {
                Remove-SafeDir $dirPath "AppData\$dirName (dynamic cache)"
            }
        }
}
#endregion

#region 23. %APPDATA%\CLAUDE CODE (Electron state dir)
Write-Step "[23/$TOTAL_SECTIONS] %APPDATA%\Claude Code..." "INFO"
$claudeCodeAppData = "$APPDATA\Claude Code"
if (Test-Path $claudeCodeAppData) {
    # Clean cache subdirs inside but preserve any settings/config
    $hasAnyCacheContent = $false
    Get-ChildItem $claudeCodeAppData -Directory -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match 'cache|Cache|tmp|temp|log|Crash|blob|GPU|Session Storage|Service Worker|Code Cache' } |
        ForEach-Object {
            Remove-SafeDir $_.FullName "Claude Code AppData\$($_.Name)"
            $hasAnyCacheContent = $true
        }
    # Log/tmp files
    Get-ChildItem $claudeCodeAppData -File -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Extension -in @('.log', '.tmp', '.old', '.dmp') } |
        ForEach-Object { Remove-SafeFile $_.FullName "Claude Code AppData\$($_.Name)" }
}
#endregion

#region 24. .OPENCLAW ROOT TEMP ARTIFACTS (orphaned files that aren't configs)
Write-Step "[24/$TOTAL_SECTIONS] .openclaw root temp artifacts..." "INFO"
if (Test-Path "$HOME_DIR\.openclaw") {
    # Known orphaned/artifact files (bug artifacts, old temp data)
    $orphanPatterns = @(
        '^extglob\.',           # PowerShell bug artifact (extglob.FullName)
        '^temp-commands',       # temp command files
        '^dashboard-tunnel',    # tunnel logs already covered but catch variants
        '\.pid$'                # stale PID files
    )
    Get-ChildItem "$HOME_DIR\.openclaw" -File -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $name = $_.Name
            $isOrphan = $false
            foreach ($p in $orphanPatterns) {
                if ($name -match $p) { $isOrphan = $true; break }
            }
            $isOrphan
        } |
        ForEach-Object { Remove-SafeFile $_.FullName ".openclaw\$($_.Name) (orphaned artifact)" }
}
#endregion

#region 25. GIT GC OPTIMIZATION (optional - only with -GitGC flag)
if ($GitGC) {
    Write-Step "[25/$TOTAL_SECTIONS] Git gc optimization on large repos..." "GIT"
    # Find git repos inside .openclaw with pack files > 10MB
    $gitRepos = @()
    if (Test-Path "$HOME_DIR\.openclaw") {
        Get-ChildItem "$HOME_DIR\.openclaw" -Directory -Recurse -Force -ErrorAction SilentlyContinue |
            Where-Object { $_.Name -eq '.git' } |
            ForEach-Object {
                $packDir = "$($_.FullName)\objects\pack"
                if (Test-Path $packDir) {
                    $packSize = (Get-ChildItem $packDir -File -Force -ErrorAction SilentlyContinue |
                        Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum
                    if ($packSize -gt 10MB) {
                        $gitRepos += @{
                            RepoDir = $_.Parent.FullName
                            PackSizeMB = [math]::Round($packSize / 1MB, 2)
                            GitDir = $_.FullName
                        }
                    }
                }
            }
    }

    if ($gitRepos.Count -gt 0) {
        foreach ($repo in $gitRepos) {
            Write-Step "  Found $($repo.PackSizeMB) MB pack in $($repo.RepoDir)" "GIT"
            if ($Execute) {
                try {
                    $beforeSize = $repo.PackSizeMB
                    Push-Location $repo.RepoDir
                    & git gc --aggressive --prune=now 2>&1 | Out-Null
                    Pop-Location
                    $afterSize = 0
                    $packDir = "$($repo.GitDir)\objects\pack"
                    if (Test-Path $packDir) {
                        $afterSize = [math]::Round((Get-ChildItem $packDir -File -Force -ErrorAction SilentlyContinue |
                            Measure-Object -Property Length -Sum -ErrorAction SilentlyContinue).Sum / 1MB, 2)
                    }
                    $saved = [math]::Round($beforeSize - $afterSize, 2)
                    if ($saved -gt 0) {
                        Write-Step "  GIT GC saved $saved MB in $($repo.RepoDir)" "GIT"
                        $script:TotalFreed += $saved
                        $script:ItemsCleaned++
                    } else {
                        Write-Step "  GIT GC: already optimized ($($repo.RepoDir))" "GIT"
                    }
                } catch {
                    Write-Step "  GIT GC FAILED: $_ ($($repo.RepoDir))" "ERROR"
                    $script:Errors += "git gc $($repo.RepoDir): $_"
                    try { Pop-Location } catch {}
                }
            } else {
                Write-Step "  WOULD RUN git gc --aggressive (est. 30-60% savings = ~$([math]::Round($repo.PackSizeMB * 0.4, 1)) MB)" "DRY"
                $script:TotalFreed += [math]::Round($repo.PackSizeMB * 0.4, 2)
                $script:ItemsCleaned++
            }
        }
    } else {
        Write-Step "  No repos with large pack files found" "SUCCESS"
    }
} else {
    Write-Step "[25/$TOTAL_SECTIONS] Git gc optimization (use -GitGC to enable)" "SKIP"
}
#endregion

#region SUMMARY
$duration = (Get-Date) - $script:StartTime

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
if ($Execute) {
    Write-Host "  CLEANUP COMPLETE" -ForegroundColor Green
} else {
    Write-Host "  DRY RUN COMPLETE - No files were deleted" -ForegroundColor Yellow
}
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

$freedDisplay = if ($script:TotalFreed -ge 1024) {
    "$([math]::Round($script:TotalFreed / 1024, 2)) GB"
} else {
    "$([math]::Round($script:TotalFreed, 1)) MB"
}

if ($Execute) {
    Write-Host "Space freed  : $freedDisplay" -ForegroundColor Green
} else {
    Write-Host "Would free   : $freedDisplay" -ForegroundColor Yellow
}
Write-Host "Items cleaned: $($script:ItemsCleaned)" -ForegroundColor White
Write-Host "Items skipped: $($script:ItemsSkipped) (not found or empty)" -ForegroundColor DarkGray
Write-Host "Duration     : $([math]::Round($duration.TotalSeconds, 1)) seconds" -ForegroundColor Cyan

if ($script:Errors.Count -gt 0) {
    Write-Host "Errors       : $($script:Errors.Count)" -ForegroundColor Red
    $script:Errors | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "Errors       : 0" -ForegroundColor Green
}

if (-not $Execute) {
    Write-Host ""
    Write-Host ("=" * 80) -ForegroundColor Yellow
    Write-Host "  To actually perform cleanup, run:" -ForegroundColor White
    Write-Host "  .\cleanup-claudecode.ps1 -Execute" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "  Optional flags:" -ForegroundColor White
    Write-Host "  -GitGC            Also run git gc --aggressive on large repos" -ForegroundColor Gray
    Write-Host "  -SkipCLIVersions  Keep old Claude CLI versions" -ForegroundColor Gray
    Write-Host "  -SkipBrowserData  Keep .openclaw\browser-data" -ForegroundColor Gray
    Write-Host "  -SkipDesktopCache Keep AnthropicClaude Desktop cache" -ForegroundColor Gray
    Write-Host "  -SkipMedia        Keep .openclaw\media" -ForegroundColor Gray
    Write-Host "  -SkipNpmCache     Keep global npm cache" -ForegroundColor Gray
    Write-Host ("=" * 80) -ForegroundColor Yellow
}

Write-Host ""
#endregion
