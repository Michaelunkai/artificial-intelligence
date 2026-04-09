# cleanclau.ps1 - Comprehensive Claude Code cleanup (safe targets only)
# Usage: .\cleanclau.ps1 [-DryRun] [-Force]
param(
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'SilentlyContinue'

# Protected paths - NEVER delete these
$PROTECTED_NAMES = @('settings.json','CLAUDE.md','keybindings.json')
$PROTECTED_DIRS  = @('memory','commands','scripts','workspace')

function IsProtected($path) {
    foreach ($n in $PROTECTED_NAMES) {
        if ($path -like "*\$n") { return $true }
    }
    foreach ($d in $PROTECTED_DIRS) {
        if ($path -like "*\$d\*" -or $path -like "*\$d") { return $true }
    }
    if ($path -match '\.ps1$') { return $true }
    return $false
}

function Get-SizeMB($items) {
    if (-not $items -or $items.Count -eq 0) { return 0.0 }
    $bytes = ($items | Measure-Object -Property Length -Sum).Sum
    if (-not $bytes) { return 0.0 }
    return [math]::Round($bytes / 1MB, 2)
}

function Invoke-CleanCategory($name, $items) {
    if (-not $items) { $items = @() }
    $safeItems = @($items | Where-Object { -not (IsProtected $_.FullName) })
    $mb = Get-SizeMB $safeItems
    $count = $safeItems.Count
    if ($DryRun) {
        $color = if ($count -gt 0) { 'Yellow' } else { 'DarkGray' }
        Write-Host ("  [DryRun] {0,-42} {1,5} items  {2,8} MB" -f $name, $count, $mb) -ForegroundColor $color
    } else {
        foreach ($i in $safeItems) {
            Remove-Item $i.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        $color = if ($count -gt 0) { 'Green' } else { 'DarkGray' }
        Write-Host ("  {0,-42} {1,5} items  {2,8} MB" -f $name, $count, $mb) -ForegroundColor $color
    }
    return @{ Count = $count; MB = $mb }
}

Write-Host ""
Write-Host "=== cleanclau - Claude Code Cleanup ===" -ForegroundColor Cyan
if ($DryRun) { Write-Host "  [DRY RUN - no files will be deleted]" -ForegroundColor Magenta }
Write-Host ""

$totalCount = 0
$totalMB    = 0.0
$claudeDir  = "$env:USERPROFILE\.claude"
$appData    = "$env:APPDATA\Claude"
$cutoff     = (Get-Date).AddDays(-7)

# Category 1: .jsonl files older than 7 days
$items = @()
if (Test-Path "$claudeDir\projects") {
    $items = @(Get-ChildItem "$claudeDir\projects" -Recurse -Filter "*.jsonl" -ErrorAction SilentlyContinue |
               Where-Object { $_.LastWriteTime -lt $cutoff })
}
$r = Invoke-CleanCategory ".claude\projects .jsonl >7 days" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 2: file-history
$items = @()
if (Test-Path "$claudeDir\file-history") {
    $items = @(Get-ChildItem "$claudeDir\file-history" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory ".claude\file-history" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 3: paste-cache
$items = @()
if (Test-Path "$claudeDir\paste-cache") {
    $items = @(Get-ChildItem "$claudeDir\paste-cache" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory ".claude\paste-cache" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 4: image-cache
$items = @()
if (Test-Path "$claudeDir\image-cache") {
    $items = @(Get-ChildItem "$claudeDir\image-cache" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory ".claude\image-cache" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 5: shell-snapshots
$items = @()
if (Test-Path "$claudeDir\shell-snapshots") {
    $items = @(Get-ChildItem "$claudeDir\shell-snapshots" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory ".claude\shell-snapshots" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 6: telemetry
$items = @()
if (Test-Path "$claudeDir\telemetry") {
    $items = @(Get-ChildItem "$claudeDir\telemetry" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory ".claude\telemetry" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 7: statsig
$items = @()
if (Test-Path "$claudeDir\statsig") {
    $items = @(Get-ChildItem "$claudeDir\statsig" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory ".claude\statsig" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 8: debug
$items = @()
if (Test-Path "$claudeDir\debug") {
    $items = @(Get-ChildItem "$claudeDir\debug" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory ".claude\debug" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 9: AppData Code Cache
$items = @()
if (Test-Path "$appData\Code Cache") {
    $items = @(Get-ChildItem "$appData\Code Cache" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory "AppData\Claude\Code Cache" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 10: AppData GPUCache
$items = @()
if (Test-Path "$appData\GPUCache") {
    $items = @(Get-ChildItem "$appData\GPUCache" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory "AppData\Claude\GPUCache" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 11: AppData DawnGraphiteCache
$items = @()
if (Test-Path "$appData\DawnGraphiteCache") {
    $items = @(Get-ChildItem "$appData\DawnGraphiteCache" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory "AppData\Claude\DawnGraphiteCache" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 12: AppData Cache
$items = @()
if (Test-Path "$appData\Cache") {
    $items = @(Get-ChildItem "$appData\Cache" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory "AppData\Claude\Cache" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 13: AppData Crashpad
$items = @()
if (Test-Path "$appData\Crashpad") {
    $items = @(Get-ChildItem "$appData\Crashpad" -Recurse -File -ErrorAction SilentlyContinue)
}
$r = Invoke-CleanCategory "AppData\Claude\Crashpad" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 14: TEMP claude_*.tmp
$items = @(Get-ChildItem $env:TEMP -Filter "claude_*.tmp" -File -ErrorAction SilentlyContinue)
$r = Invoke-CleanCategory "TEMP claude_*.tmp" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Category 15: TEMP claude-code-*.log
$items = @(Get-ChildItem $env:TEMP -Filter "claude-code-*.log" -File -ErrorAction SilentlyContinue)
$r = Invoke-CleanCategory "TEMP claude-code-*.log" $items
$totalCount += $r.Count ; $totalMB += $r.MB

# Summary
Write-Host ""
$totalMBRound = [math]::Round($totalMB, 2)
$action = if ($DryRun) { "Would free" } else { "Freed" }
Write-Host "  $action $totalCount items  ($totalMBRound MB total)" -ForegroundColor Cyan
Write-Host ""
