# ============================================================================
# CLEANCLAU - OpenClaw + Claude Code Daily Cleanup Script
# Reduces disk space and Claude context without removing anything useful
# ============================================================================
# PROTECTED PATHS - these are NEVER deleted or modified by this script:
#   ~/.claude/skills/          - all Claude Code skills (68+ skills)
#   ~/.claude/settings*        - Claude Code settings files
#   ~/.claude/CLAUDE.md        - Claude Code project rules
#   ~/.claude/projects/*/CLAUDE.md - per-project rules
#   ~/.claude/projects/*/memory/   - memory files
#   ~/.claude/projects/*/MEMORY.md - memory index
#   ~/.openclaw/skills/        - OpenClaw skills (source copies)
#   ~/.openclaw/config/        - OpenClaw configuration
#   ~/.openclaw/hooks/         - OpenClaw hooks
# ============================================================================

param(
    [switch]$DryRun,
    [switch]$Verbose
)

$h = $env:USERPROFILE
$la = $env:LOCALAPPDATA
$t = $env:TEMP
$c3 = (Get-Date).AddDays(-3)
$c7 = (Get-Date).AddDays(-7)
$c14 = (Get-Date).AddDays(-14)

# -- PROTECTED PATHS: absolute paths that must NEVER be deleted --
$protectedPaths = @(
    "$h\.claude\skills",
    "$h\.claude\CLAUDE.md",
    "$h\.claude\settings.json",
    "$h\.claude\settings.local.json",
    "$h\.claude\keybindings.json",
    "$h\.claude\credentials.json",
    "$h\.claude\.credentials.json",
    "$h\.openclaw\skills",
    "$h\.openclaw\config",
    "$h\.openclaw\hooks"
)

# Protected directory names - items inside these dirs are never deleted
$protectedDirNames = @('skills', 'config', 'hooks')

# Protected file names - these are never deleted anywhere under .claude or .openclaw
$protectedFileNames = @('CLAUDE.md', 'MEMORY.md', 'SKILL.md', 'settings.json', 'settings.local.json', 'keybindings.json', 'credentials.json', '.credentials.json')

# -- Measure BEFORE --
$before = 0
foreach ($d in @("$h\.openclaw","$h\.claude","$la\AnthropicClaude\packages","$la\electron-builder\Cache","$t\node-compile-cache","$la\pip\cache")) {
    if (Test-Path $d) {
        $before += (Get-ChildItem $d -Recurse -Force -EA 0 | Measure-Object -Property Length -Sum).Sum
    }
}
$ctxBefore = (Get-ChildItem "$h\.claude\projects" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Name -ne 'MEMORY.md' -and $_.Directory.Name -ne 'memory' } |
    Measure-Object -Property Length -Sum).Sum

function Test-IsProtected {
    param([string]$Path)
    $normalized = $Path.Replace('/', '\').TrimEnd('\')

    # Check exact protected paths
    foreach ($pp in $protectedPaths) {
        $pn = $pp.Replace('/', '\').TrimEnd('\')
        if ($normalized -eq $pn -or $normalized.StartsWith("$pn\")) { return $true }
    }

    # Check if item is inside a protected directory name under .claude or .openclaw
    foreach ($dirName in $protectedDirNames) {
        if ($normalized -match "\\\.claude\\$dirName\\" -or $normalized -match "\\\.claude\\$dirName$") { return $true }
        if ($normalized -match "\\\.openclaw\\$dirName\\" -or $normalized -match "\\\.openclaw\\$dirName$") { return $true }
    }

    # Check protected file names
    $fileName = [System.IO.Path]::GetFileName($normalized)
    if ($fileName -in $protectedFileNames) {
        if ($normalized -match '\\\.claude\\' -or $normalized -match '\\\.openclaw\\') { return $true }
    }

    # Check memory directories
    $parent = [System.IO.Path]::GetDirectoryName($normalized)
    if ($parent) {
        $parentName = [System.IO.Path]::GetFileName($parent)
        if ($parentName -eq 'memory' -and ($normalized -match '\\\.claude\\')) { return $true }
    }

    return $false
}

function Remove-Safely {
    param([Parameter(ValueFromPipeline)]$Item, [switch]$Recurse)
    process {
        if ($Item) {
            if (Test-IsProtected $Item.FullName) {
                if ($Verbose -or $DryRun) {
                    Write-Host "  [PROTECTED] Skipping: $($Item.FullName)" -ForegroundColor Magenta
                }
                return
            }
            if ($DryRun) {
                Write-Host "  [DRY] Would remove: $($Item.FullName)" -ForegroundColor DarkYellow
            } else {
                if ($Recurse) { Remove-Item $Item.FullName -Recurse -Force -EA 0 }
                else { Remove-Item $Item.FullName -Force -EA 0 }
            }
        }
    }
}

Write-Host ""
Write-Host "[CLEANCLAU] Starting OpenClaw + Claude Code cleanup..." -ForegroundColor Cyan
if ($DryRun) { Write-Host "[CLEANCLAU] DRY RUN - nothing will be deleted" -ForegroundColor Yellow; Write-Host "" }

# -- 1. Browser caches (~122 MB) --
Write-Host "  [1/20] Browser caches (ML models, metrics, GPU, crashpad)..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw\browser" -Recurse -Directory -Force -EA 0 |
    Where-Object { $_.Name -in @('optimization_guide_model_store','BrowserMetrics','GraphiteDawnCache','blob_storage','GrShaderCache','ShaderCache','GPUCache','Code Cache','DawnCache','DawnWebGPUCache','Crashpad') } |
    Remove-Safely -Recurse

# -- 2. BrowserMetrics .pma blobs (~16 MB) --
Write-Host "  [2/20] BrowserMetrics .pma telemetry..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw\browser" -Recurse -Force -Include '*.pma' -EA 0 |
    Remove-Safely

# -- 3. AnthropicClaude old update .nupkg (~151 MB) --
Write-Host "  [3/20] Claude Desktop old update packages..." -ForegroundColor Gray
Get-ChildItem "$la\AnthropicClaude\packages" -Force -EA 0 |
    Where-Object { $_.Extension -eq '.nupkg' } |
    Remove-Safely

# -- 4. Electron-builder download cache (~33 MB) --
Write-Host "  [4/20] Electron-builder cache..." -ForegroundColor Gray
if (Test-Path "$la\electron-builder\Cache") {
    if ($DryRun) { Write-Host "  [DRY] Would remove: $la\electron-builder\Cache" -ForegroundColor DarkYellow }
    else { Remove-Item "$la\electron-builder\Cache" -Recurse -Force -EA 0 }
}

# -- 5. Node compile cache (~21 MB) --
Write-Host "  [5/20] Node.js compile cache..." -ForegroundColor Gray
if (Test-Path "$t\node-compile-cache") {
    if ($DryRun) { Write-Host "  [DRY] Would remove: $t\node-compile-cache" -ForegroundColor DarkYellow }
    else { Remove-Item "$t\node-compile-cache" -Recurse -Force -EA 0 }
}

# -- 6. pip cache (~23 MB) --
Write-Host "  [6/20] pip package cache..." -ForegroundColor Gray
if (-not $DryRun) { pip cache purge 2>$null | Out-Null }
else { Write-Host "  [DRY] Would run: pip cache purge" -ForegroundColor DarkYellow }

# -- 7. Old Claude conversation files older than 7d --
Write-Host "  [7/20] Old Claude conversations older than 7d (preserving memory)..." -ForegroundColor Gray
Get-ChildItem "$h\.claude\projects" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Name -ne 'MEMORY.md' -and $_.Directory.Name -ne 'memory' -and $_.LastWriteTime -lt $c7 } |
    Remove-Safely

# -- 8. Old conversation UUID cache dirs older than 7d --
Write-Host "  [8/20] Old conversation UUID dirs older than 7d..." -ForegroundColor Gray
Get-ChildItem "$h\.claude\projects" -Recurse -Directory -Force -EA 0 |
    Where-Object { $_.Name -ne 'memory' -and $_.Name -match '^[0-9a-f]{8}-' -and $_.LastWriteTime -lt $c7 } |
    Remove-Safely -Recurse

# -- 9. Old .claude tasks/file-history/image-cache/backups older than 7d --
Write-Host "  [9/20] Old .claude tasks/file-history/image-cache/backups..." -ForegroundColor Gray
@('tasks','file-history','image-cache','backups') | ForEach-Object {
    Get-ChildItem "$h\.claude\$_" -Recurse -Force -File -EA 0 |
        Where-Object { $_.LastWriteTime -lt $c7 } |
        Remove-Safely
}

# -- 10. .openclaw log/bak/tmp/old files --
Write-Host "  [10/20] OpenClaw stale log/bak/tmp/old files..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw" -Recurse -Force -File -Include '*.log','*.log.*','*.bak','*.bak.*','*.tmp','*.old' -EA 0 |
    Remove-Safely

# -- 11. Old cron run logs older than 14d --
Write-Host "  [11/20] Old cron run logs older than 14d..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw\cron\runs" -Force -File -EA 0 |
    Where-Object { $_.LastWriteTime -lt $c14 } |
    Remove-Safely

# -- 12. Agent orphaned .deleted/.reset files --
Write-Host "  [12/20] Agent orphaned .deleted/.reset files..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw\agents" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Name -match '\.(deleted|reset)\.' } |
    Remove-Safely

# -- 13. Agent old session .jsonl older than 14d --
Write-Host "  [13/20] Agent old session logs older than 14d..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw\agents" -Recurse -Force -File -Include '*.jsonl' -EA 0 |
    Where-Object { $_.LastWriteTime -lt $c14 } |
    Remove-Safely

# -- 14. Debug/error screenshots older than 3d --
Write-Host "  [14/20] Debug/error screenshots older than 3d..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Name -match '^(error-|debug-|screenshot|screen_)' -and $_.Extension -in @('.png','.jpg','.jpeg') -and $_.LastWriteTime -lt $c3 } |
    Remove-Safely

# -- 15. Test images (moon_check, etc.) older than 3d --
Write-Host "  [15/20] Stale test images older than 3d..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw\workspace-openclaw-main" -Force -File -EA 0 |
    Where-Object { $_.Name -match '(moon_check|red_moon_test|red_moon_final)' -and $_.LastWriteTime -lt $c3 } |
    Remove-Safely

# -- 16. Old TEMP claude session files older than 7d --
Write-Host "  [16/20] Old TEMP claude/openclaw files..." -ForegroundColor Gray
Get-ChildItem "$t\claude" -Recurse -Force -File -EA 0 |
    Where-Object { $_.LastWriteTime -lt $c7 } |
    Remove-Safely
Get-ChildItem "$t\openclaw" -Force -File -EA 0 |
    Where-Object { $_.Name -match '\.log$' -and $_.LastWriteTime -lt $c3 } |
    Remove-Safely

# -- 17. Git GC on game-library-manager-web (~80 MB savings) --
Write-Host "  [17/20] Git GC on game-library-manager-web..." -ForegroundColor Gray
$glm = "$h\.openclaw\workspace-moltbot\game-library-manager-web"
if (Test-Path "$glm\.git") {
    if (-not $DryRun) {
        Push-Location $glm
        git gc --quiet --prune=now 2>$null
        Pop-Location
    } else {
        Write-Host "  [DRY] Would run: git gc --prune=now in $glm" -ForegroundColor DarkYellow
    }
}

# -- 18. SQLite VACUUM on memory DBs (~4 MB savings) --
Write-Host "  [18/20] SQLite VACUUM on memory databases..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw\memory" -Force -Filter '*.sqlite' -EA 0 | ForEach-Object {
    if (-not $DryRun) {
        try { sqlite3 $_.FullName 'VACUUM;' 2>$null } catch {}
    } else {
        Write-Host "  [DRY] Would VACUUM: $($_.FullName)" -ForegroundColor DarkYellow
    }
}

# -- 19. Failed delivery queue items --
Write-Host "  [19/20] Failed delivery queue items..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw\delivery-queue\failed" -Force -File -EA 0 |
    Remove-Safely

# -- 20. Stale output files older than 7d --
Write-Host "  [20/20] Stale output files older than 7d..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw" -Force -File -EA 0 |
    Where-Object { $_.Name -in @('status-out.txt','channels-out.txt','ch-status.txt','dashboard-url.txt','claude-session.txt') -and $_.LastWriteTime -lt $c7 } |
    Remove-Safely

# -- Measure AFTER --
$after = 0
foreach ($d in @("$h\.openclaw","$h\.claude","$la\AnthropicClaude\packages","$la\electron-builder\Cache","$t\node-compile-cache","$la\pip\cache")) {
    if (Test-Path $d) {
        $after += (Get-ChildItem $d -Recurse -Force -EA 0 | Measure-Object -Property Length -Sum).Sum
    }
}
$ctxAfter = (Get-ChildItem "$h\.claude\projects" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Name -ne 'MEMORY.md' -and $_.Directory.Name -ne 'memory' } |
    Measure-Object -Property Length -Sum).Sum

$saved = [math]::Round(($before - $after) / 1MB, 1)
$ctxSaved = [math]::Round(($ctxBefore - $ctxAfter) / 1MB, 1)

[GC]::Collect()

$ts = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
Write-Host ""
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  OpenClaw + Claude Code Daily Cleanup - COMPLETE" -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  C: Drive space reduced:   $saved MB" -ForegroundColor Green
Write-Host "  Claude context reduced:   $ctxSaved MB" -ForegroundColor Yellow
Write-Host "  Completed:                $ts" -ForegroundColor Gray
Write-Host "============================================================" -ForegroundColor Cyan
Write-Host ""
