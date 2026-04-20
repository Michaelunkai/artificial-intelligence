#Requires -Version 5.1
# CLEANCLAU v4.0 - BLITZ C: DRIVE CLEANUP
# Nukes ALL regeneratable Claude Code + OpenClaw garbage from C: drive
# Target: under 20 seconds, maximum space + context reduction
# KEEPS: skills, memory, CLAUDE.md, MEMORY.md, settings, credentials,
#        keybindings, rules, commands, scripts, plugins, chrome, hooks,
#        config, platform-tools, extensions, completions, ClawdBot,
#        current binaries (claude-code, claude-code-vm, app-*),
#        claude_desktop_config.json, ChromeNativeHost

param([switch]$DryRun)

$sw = [System.Diagnostics.Stopwatch]::StartNew()
$h = $env:USERPROFILE
$a = $env:APPDATA
$la = $env:LOCALAPPDATA
$t = $env:TEMP
$freed = [long]0

function Nuke {
    param([string]$Path)
    if (Test-Path $Path) {
        if ($DryRun) { Write-Host "  [DRY] $Path" -ForegroundColor DarkYellow; return }
        try { Remove-Item $Path -Recurse -Force -EA Stop } catch {}
    }
}

function NukeFiles {
    param([string]$Dir, [string]$Filter)
    if (-not (Test-Path $Dir)) { return }
    Get-ChildItem $Dir -Force -File -Filter $Filter -EA 0 | ForEach-Object {
        if ($DryRun) { Write-Host "  [DRY] $($_.FullName)" -ForegroundColor DarkYellow; return }
        try { Remove-Item $_.FullName -Force -EA 0 } catch {}
    }
}

Write-Host ""
Write-Host "  CLEANCLAU v4.0 BLITZ - C: drive cleanup" -ForegroundColor Cyan
if ($DryRun) { Write-Host "  DRY RUN" -ForegroundColor Yellow }

# =================================================================
# 1. .claude garbage dirs (all regeneratable caches)
# =================================================================
Write-Host "  [1/12] .claude caches..." -ForegroundColor Gray
foreach ($d in @('file-history','cache','paste-cache','image-cache','shell-snapshots',
    'debug','test-logs','downloads','session-env','telemetry','statsig',
    'tasks','backups','plans','sessions')) {
    Nuke "$h\.claude\$d"
}

# =================================================================
# 2. .claude/projects old conversations (keep memory + MEMORY.md + CLAUDE.md)
# =================================================================
Write-Host "  [2/12] Old conversations..." -ForegroundColor Gray
$cutoff = (Get-Date).AddDays(-3)
Get-ChildItem "$h\.claude\projects" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Name -ne 'MEMORY.md' -and $_.Name -ne 'CLAUDE.md' -and
        $_.Directory.Name -ne 'memory' -and $_.LastWriteTime -lt $cutoff } |
    ForEach-Object {
        if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} }
    }
# Old UUID dirs
Get-ChildItem "$h\.claude\projects" -Recurse -Directory -Force -EA 0 |
    Where-Object { $_.Name -ne 'memory' -and $_.Name -match '^[0-9a-f]{8}-' -and $_.LastWriteTime -lt $cutoff } |
    ForEach-Object {
        if (-not $DryRun) { try { Remove-Item $_.FullName -Recurse -Force -EA 0 } catch {} }
    }

# =================================================================
# 3. Claude Desktop (AppData\Roaming\Claude) - nuke all caches
# =================================================================
Write-Host "  [3/12] Claude Desktop caches..." -ForegroundColor Gray
foreach ($d in @('Code Cache','GPUCache','DawnGraphiteCache','DawnWebGPUCache',
    'Cache','cache','Crashpad','Network','blob_storage','Session Storage',
    'Local Storage','WebStorage','IndexedDB','Service Worker','Dictionaries',
    'sentry','VideoDecodeStats','Shared Dictionary','shared_proto_db','logs')) {
    Nuke "$a\Claude\$d"
}
# Old agent sessions (keep last 24h)
$c1 = (Get-Date).AddDays(-1)
Get-ChildItem "$a\Claude\local-agent-mode-sessions" -Force -File -EA 0 |
    Where-Object { $_.LastWriteTime -lt $c1 } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
# Old claude-code / claude-code-vm versions (keep latest)
foreach ($sub in @('claude-code','claude-code-vm')) {
    $vd = "$a\Claude\$sub"
    if (Test-Path $vd) {
        $vers = Get-ChildItem $vd -Directory -Force -EA 0 | Sort-Object Name -Descending
        if ($vers.Count -gt 1) {
            $vers | Select-Object -Skip 1 | ForEach-Object { Nuke $_.FullName }
        }
    }
}
# Stale root files
Get-ChildItem "$a\Claude" -Force -File -EA 0 |
    Where-Object { $_.Name -match '^(DIPS|fcache|SharedStorage|extensions-blocklist|git-worktrees)' -or $_.Name -match '-wal$' } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }

# =================================================================
# 4. AnthropicClaude (AppData\Local) - packages + caches + old app
# =================================================================
Write-Host "  [4/12] AnthropicClaude caches..." -ForegroundColor Gray
NukeFiles "$la\AnthropicClaude\packages" "*.nupkg"
foreach ($d in @('Code Cache','GPUCache','Cache','Crashpad','blob_storage',
    'DawnGraphiteCache','DawnWebGPUCache','Network','Session Storage','Local Storage')) {
    Nuke "$la\AnthropicClaude\$d"
}
# Old app versions
$appVers = Get-ChildItem "$la\AnthropicClaude" -Directory -Force -EA 0 |
    Where-Object { $_.Name -match '^app-' } | Sort-Object Name -Descending
if ($appVers.Count -gt 1) {
    $appVers | Select-Object -Skip 1 | ForEach-Object { Nuke $_.FullName }
}

# =================================================================
# 5. Old CLI versions + tool caches
# =================================================================
Write-Host "  [5/12] CLI versions + tool caches..." -ForegroundColor Gray
# Old CLI versions (keep latest)
$vDir = "$h\.local\share\claude\versions"
if (Test-Path $vDir) {
    $vers = Get-ChildItem $vDir -Directory -EA 0 | Sort-Object Name -Descending
    if ($vers.Count -gt 1) {
        $vers | Select-Object -Skip 1 | ForEach-Object { Nuke $_.FullName }
    }
}
Nuke "$la\claude-cli-nodejs"
Nuke "$h\.cache\opencode"
Nuke "$la\electron-builder\Cache"
Nuke "$t\node-compile-cache"

# =================================================================
# 6. OpenClaw browser caches
# =================================================================
Write-Host "  [6/12] OpenClaw browser caches..." -ForegroundColor Gray
$browserGarbage = @('optimization_guide_model_store','BrowserMetrics','GraphiteDawnCache',
    'blob_storage','GrShaderCache','ShaderCache','GPUCache','Code Cache','DawnCache',
    'DawnWebGPUCache','Crashpad','Cache','Network','Session Storage','Local Storage',
    'Service Worker','IndexedDB','WebStorage','VideoDecodeStats')
Get-ChildItem "$h\.openclaw\browser" -Recurse -Directory -Force -EA 0 |
    Where-Object { $_.Name -in $browserGarbage } |
    ForEach-Object { Nuke $_.FullName }
Get-ChildItem "$h\.openclaw\browser" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Extension -eq '.pma' } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }

# =================================================================
# 7. OpenClaw node_modules (ALL - regeneratable)
# =================================================================
Write-Host "  [7/12] OpenClaw node_modules..." -ForegroundColor Gray
Get-ChildItem "$h\.openclaw" -Directory -Force -Recurse -EA 0 |
    Where-Object { $_.Name -eq 'node_modules' } |
    ForEach-Object { Nuke $_.FullName }

# =================================================================
# 8. OpenClaw logs + temp + old agents + docs + backups
# =================================================================
Write-Host "  [8/12] OpenClaw logs/agents/docs/backups..." -ForegroundColor Gray
Nuke "$h\.openclaw\logs"
Nuke "$h\.openclaw\backups"
Nuke "$h\.openclaw\docs"
# All .log .bak .tmp .old files recursively
Get-ChildItem "$h\.openclaw" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Extension -in @('.log','.bak','.tmp','.old') -or $_.Name -match '\.(log|bak)\.' } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
# Old agent data (>1 day)
Get-ChildItem "$h\.openclaw\agents" -Recurse -Force -File -EA 0 |
    Where-Object { $_.LastWriteTime -lt $c1 -or $_.Name -match '\.(deleted|reset)\.' } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
# Old cron runs
Get-ChildItem "$h\.openclaw\cron\runs" -Force -File -EA 0 |
    Where-Object { $_.LastWriteTime -lt $cutoff } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
# Failed delivery queue
Get-ChildItem "$h\.openclaw\delivery-queue\failed" -Force -File -EA 0 |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
# Debug screenshots + test images
Get-ChildItem "$h\.openclaw" -Recurse -Force -File -EA 0 |
    Where-Object { ($_.Name -match '^(error-|debug-|screenshot|screen_)' -and
        $_.Extension -in @('.png','.jpg','.jpeg')) -or
        $_.Name -match '(moon_check|red_moon_test|red_moon_final)' } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
# Stale output files
Get-ChildItem "$h\.openclaw" -Force -File -EA 0 |
    Where-Object { $_.Name -in @('status-out.txt','channels-out.txt','ch-status.txt',
        'dashboard-url.txt','claude-session.txt') } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
# Old media
Get-ChildItem "$h\.openclaw\media" -Force -File -EA 0 |
    Where-Object { $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
# Old foundry
Get-ChildItem "$h\.openclaw\foundry" -Recurse -Force -File -EA 0 |
    Where-Object { $_.Extension -in @('.cache','.tmp','.log') -or $_.LastWriteTime -lt (Get-Date).AddDays(-3) } |
    ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }

# =================================================================
# 9. TEMP dirs
# =================================================================
Write-Host "  [9/12] TEMP cleanup..." -ForegroundColor Gray
foreach ($td in @("$t\claude","$t\openclaw","$env:WINDIR\TEMP\claude","$env:WINDIR\TEMP\openclaw")) {
    if (Test-Path $td) {
        Get-ChildItem $td -Recurse -Force -File -EA 0 |
            ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
    }
}

# =================================================================
# 10. Windows Store + ProgramData Claude
# =================================================================
Write-Host "  [10/12] WinStore + ProgramData..." -ForegroundColor Gray
Get-ChildItem "$la\Packages" -Directory -Force -EA 0 |
    Where-Object { $_.Name -match 'Claude|Anthropic' } |
    ForEach-Object {
        foreach ($sub in @('AC\INetCache','AC\INetCookies','TempState','LocalCache\cache')) {
            Nuke "$($_.FullName)\$sub"
        }
    }
if (Test-Path "$env:ProgramData\Claude") {
    Get-ChildItem "$env:ProgramData\Claude" -Recurse -Force -File -EA 0 |
        Where-Object { $_.Extension -in @('.log','.tmp','.cache') } |
        ForEach-Object { if (-not $DryRun) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} } }
}

# =================================================================
# 11. Empty dirs cleanup
# =================================================================
Write-Host "  [11/12] Empty dirs..." -ForegroundColor Gray
if (-not $DryRun) {
    foreach ($root in @("$h\.claude","$h\.openclaw")) {
        if (-not (Test-Path $root)) { continue }
        Get-ChildItem $root -Directory -Recurse -Force -EA 0 |
            Sort-Object { $_.FullName.Length } -Descending |
            ForEach-Object {
                $c = (Get-ChildItem $_.FullName -Force -EA 0).Count
                if ($c -eq 0) { try { Remove-Item $_.FullName -Force -EA 0 } catch {} }
            }
    }
}

# =================================================================
# 12. Done
# =================================================================
$sw.Stop()
[GC]::Collect()
Write-Host ""
Write-Host "  CLEANCLAU v4.0 done in $([math]::Round($sw.Elapsed.TotalSeconds,1))s" -ForegroundColor Green
Write-Host ""
