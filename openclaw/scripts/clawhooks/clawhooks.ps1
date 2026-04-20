$ErrorActionPreference = 'SilentlyContinue'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$HARD_TIMEOUT = 170  # seconds

# ==================== STEP 1: Get installed hooks ====================
Write-Host "Getting installed hooks..." -ForegroundColor Yellow
$hooksDir = "C:\Users\micha\.openclaw\hooks"
$installed = @()
if (Test-Path $hooksDir) {
    $installed = @(Get-ChildItem $hooksDir -Directory | ForEach-Object { $_.Name.ToLower() })
    $installed += @(Get-ChildItem $hooksDir -File -Filter "*.js" | ForEach-Object { $_.BaseName.ToLower() })
    $installed += @(Get-ChildItem $hooksDir -File -Filter "*.ps1" | ForEach-Object { $_.BaseName.ToLower() })
}
Write-Host "Installed hooks ($($installed.Count)): $($installed -join ', ')" -ForegroundColor Green

# ==================== STEP 2: Search hook-related categories ====================
$categories = @(
    "hook", "hooks", "trigger", "event", "middleware", "interceptor",
    "guard", "validator", "monitor", "watcher", "listener", "handler",
    "pre-", "post-", "on-", "before", "after", "lifecycle",
    "auto", "prevention", "recovery", "retry", "fallback", "resilience",
    "health", "check", "gate", "filter", "pipeline", "chain"
)

Write-Host "Searching $($categories.Count) categories (15 parallel)..." -ForegroundColor Yellow
$searchPool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 15)
$searchPool.Open()
$searchJobs = @()

foreach ($cat in $categories) {
    $ps = [PowerShell]::Create().AddScript({
        param($c)
        $r = npx -y clawhub@latest search $c --limit 80 2>&1
        $names = @()
        foreach ($l in $r) {
            $s = "$l".Trim() -replace '\x1b\[[0-9;]*m', ''
            if ($s -ne '' -and $s -notmatch '^[\[\-]' -and $s -match '^\w') {
                $parts = $s -split '\s{2,}'
                if ($parts[0]) { $names += $parts[0].Trim().ToLower() }
            }
        }
        $names
    }).AddArgument($cat)
    $ps.RunspacePool = $searchPool
    $searchJobs += [PSCustomObject]@{ P = $ps; H = $ps.BeginInvoke() }
}

# Wait with timeout
$deadline = (Get-Date).AddSeconds(90)
while ($true) {
    $done = @($searchJobs | Where-Object { $_.H.IsCompleted }).Count
    Write-Host ("`r  Search: $done/$($searchJobs.Count)") -NoNewline -ForegroundColor DarkGray
    if ($done -ge $searchJobs.Count -or (Get-Date) -gt $deadline) { break }
    Start-Sleep -Milliseconds 500
}
Write-Host ""

$allNames = @()
foreach ($j in $searchJobs) {
    if ($j.H.IsCompleted) { try { $allNames += $j.P.EndInvoke($j.H) } catch {} }
    $j.P.Dispose()
}
$searchPool.Close(); $searchPool.Dispose()

# Dedupe & filter — prioritize hook-like names
$hitCount = @{}
foreach ($n in $allNames) {
    if ($n -and $n.Length -gt 1) {
        if (-not $hitCount.ContainsKey($n)) { $hitCount[$n] = 1 } else { $hitCount[$n]++ }
    }
}

# Boost score for hook-like names
$hookKeywords = @('hook', 'guard', 'monitor', 'watcher', 'prevention', 'recovery', 'retry', 'fallback', 'health', 'gate', 'trigger', 'event', 'middleware', 'interceptor', 'validator', 'listener', 'handler', 'resilience', 'auto')
$boosted = @{}
foreach ($entry in $hitCount.GetEnumerator()) {
    $score = $entry.Value
    foreach ($kw in $hookKeywords) {
        if ($entry.Name -match $kw) { $score += 3; break }
    }
    $boosted[$entry.Name] = $score
}

$candidates = @($boosted.GetEnumerator() | Where-Object {
    ($installed -notcontains $_.Name) -and
    $_.Name -notmatch '-\d+-\d+-\d+$' -and
    $_.Name -notmatch '^backup-' -and
    $_.Name -notmatch '^20\d{2,3}-' -and
    $_.Name -notmatch '-bak-'
} | Sort-Object -Property Value -Descending | Select-Object -First 150 | ForEach-Object { $_.Name })

Write-Host "Found $($hitCount.Count) unique, inspecting $($candidates.Count) (excl. $($installed.Count) installed hooks) [$([math]::Round($sw.Elapsed.TotalSeconds))s]" -ForegroundColor Yellow

# ==================== STEP 3: Inspect in parallel (25 workers) ====================
$inspectPool = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspacePool(1, 25)
$inspectPool.Open()
$inspectJobs = @()

foreach ($name in $candidates) {
    $ps = [PowerShell]::Create().AddScript({
        param($n)
        $raw = npx -y clawhub@latest inspect $n --json 2>&1 | Out-String
        $raw = $raw -replace '\x1b\[[0-9;]*m', ''
        $start = $raw.IndexOf('{')
        if ($start -ge 0) {
            try {
                $obj = ($raw.Substring($start)) | ConvertFrom-Json
                $s = $obj.skill.stats
                $type = if ($obj.skill.type) { $obj.skill.type } else { 'unknown' }
                [PSCustomObject]@{
                    Name = $n
                    Type = $type
                    Downloads = if ($s.downloads) { [int]$s.downloads } else { 0 }
                    Installs = if ($s.installsAllTime) { [int]$s.installsAllTime } else { 0 }
                    Stars = if ($s.stars) { [int]$s.stars } else { 0 }
                    Summary = if ($obj.skill.summary) { $obj.skill.summary } else { '(no description)' }
                    IsHook = ($type -eq 'hook' -or $n -match 'hook|guard|monitor|prevention|recovery|retry|fallback|health|gate|trigger|event|middleware|interceptor|watcher|listener')
                }
            } catch {}
        }
    }).AddArgument($name)
    $ps.RunspacePool = $inspectPool
    $inspectJobs += [PSCustomObject]@{ P = $ps; H = $ps.BeginInvoke() }
}

# Wait with hard timeout
$deadline = (Get-Date).AddSeconds([math]::Max(30, $HARD_TIMEOUT - $sw.Elapsed.TotalSeconds))
while ($true) {
    $done = @($inspectJobs | Where-Object { $_.H.IsCompleted }).Count
    Write-Host ("`r  Inspect: $done/$($inspectJobs.Count)") -NoNewline -ForegroundColor DarkGray
    if ($done -ge $inspectJobs.Count -or (Get-Date) -gt $deadline) { break }
    Start-Sleep -Milliseconds 500
}
Write-Host ""

$skillData = @()
foreach ($j in $inspectJobs) {
    if ($j.H.IsCompleted) { try { $r = $j.P.EndInvoke($j.H); if ($r) { $skillData += $r } } catch {} }
    $j.P.Dispose()
}
$inspectPool.Close(); $inspectPool.Dispose()

# ==================== STEP 4: Output ====================
# Sort: actual hooks first, then hook-like names, then by downloads
$hooksFirst = $skillData | Sort-Object -Property @{Expression={$_.IsHook}; Descending=$true}, @{Expression={$_.Downloads}; Descending=$true} | Select-Object -First 150
$elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

$actualHooks = @($hooksFirst | Where-Object { $_.IsHook })
$otherTools = @($hooksFirst | Where-Object { -not $_.IsHook })

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ("  CLAWHOOKS - TOP " + $hooksFirst.Count + " HOOK-LIKE PACKAGES (NOT INSTALLED)  -  " + $elapsed + "s") -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan

if ($actualHooks.Count -gt 0) {
    Write-Host ""
    Write-Host ("  --- HOOKS AND GUARDS (" + $actualHooks.Count + ") ---") -ForegroundColor Yellow
    $rank = 0
    foreach ($skill in $actualHooks) {
        $rank++
        $desc = "$($skill.Summary)"
        if ($desc.Length -gt 100) { $desc = $desc.Substring(0, 97) + "..." }
        $typeTag = if ($skill.Type -ne 'unknown') { " [$($skill.Type)]" } else { "" }
        Write-Host ("{0,3}. " -f $rank) -NoNewline -ForegroundColor White
        Write-Host "$($skill.Name)" -NoNewline -ForegroundColor Green
        Write-Host "$typeTag (DL:$($skill.Downloads) inst:$($skill.Installs) *$($skill.Stars))" -ForegroundColor DarkGray
        Write-Host "     $desc" -ForegroundColor Gray
    }
}

if ($otherTools.Count -gt 0) {
    Write-Host ""
    Write-Host ("  --- RELATED TOOLS (" + $otherTools.Count + ") ---") -ForegroundColor Yellow
    $rank = 0
    foreach ($skill in $otherTools) {
        $rank++
        $desc = "$($skill.Summary)"
        if ($desc.Length -gt 100) { $desc = $desc.Substring(0, 97) + "..." }
        $typeTag = if ($skill.Type -ne 'unknown') { " [$($skill.Type)]" } else { "" }
        Write-Host ("{0,3}. " -f $rank) -NoNewline -ForegroundColor White
        Write-Host "$($skill.Name)" -NoNewline -ForegroundColor DarkGray
        Write-Host "$typeTag (DL:$($skill.Downloads) inst:$($skill.Installs) *$($skill.Stars))" -ForegroundColor DarkGray
        Write-Host "     $desc" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host ("  Searched: " + $hitCount.Count + " unique - Got details: " + $skillData.Count + " - Hooks: " + $actualHooks.Count + " - Related: " + $otherTools.Count + " - " + $elapsed + "s") -ForegroundColor White
Write-Host "============================================================================" -ForegroundColor Cyan
