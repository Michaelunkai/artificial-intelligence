$ErrorActionPreference = 'SilentlyContinue'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$HARD_TIMEOUT = 170  # seconds - hard cap under 3 min

# ==================== STEP 1: Get installed skills ====================
Write-Host "Getting installed skills..." -ForegroundColor Yellow
$installedRaw = npx -y clawhub@latest list 2>&1
$installed = @()
foreach ($line in $installedRaw) {
    $s = "$line".Trim() -replace '\x1b\[[0-9;]*m', ''
    if ($s -ne '' -and $s -notmatch '^[\[\-]' -and $s -match '^\w') {
        $parts = $s -split '\s+'
        if ($parts[0]) { $installed += $parts[0].ToLower() }
    }
}
Write-Host "Installed ($($installed.Count)): $($installed -join ', ')" -ForegroundColor Green

# ==================== STEP 2: Search 30 high-yield categories ====================
$categories = @(
    "agent", "automation", "workflow", "ai", "tool", "productivity",
    "code", "cli", "web", "api", "database", "deploy", "security",
    "monitor", "chat", "search", "git", "debug", "generate", "cloud",
    "devops", "scrape", "browser", "summarize", "memory", "prompt",
    "docker", "backup", "optimize", "data"
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

# Dedupe & filter
$hitCount = @{}
foreach ($n in $allNames) {
    if ($n -and $n.Length -gt 1) {
        if (-not $hitCount.ContainsKey($n)) { $hitCount[$n] = 1 } else { $hitCount[$n]++ }
    }
}

$candidates = @($hitCount.GetEnumerator() | Where-Object {
    ($installed -notcontains $_.Name) -and
    $_.Name -notmatch '-\d+-\d+-\d+$' -and
    $_.Name -notmatch '^backup-' -and
    $_.Name -notmatch '^20\d{2,3}-' -and
    $_.Name -notmatch '-bak-'
} | Sort-Object -Property Value -Descending | Select-Object -First 150 | ForEach-Object { $_.Name })

Write-Host "Found $($hitCount.Count) unique, inspecting $($candidates.Count) (excl. $($installed.Count) installed) [$([math]::Round($sw.Elapsed.TotalSeconds))s]" -ForegroundColor Yellow

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
                [PSCustomObject]@{
                    Name = $n
                    Downloads = if ($s.downloads) { [int]$s.downloads } else { 0 }
                    Installs = if ($s.installsAllTime) { [int]$s.installsAllTime } else { 0 }
                    Stars = if ($s.stars) { [int]$s.stars } else { 0 }
                    Summary = if ($obj.skill.summary) { $obj.skill.summary } else { '(no description)' }
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
$top150 = $skillData | Sort-Object -Property Downloads -Descending | Select-Object -First 150
$elapsed = [math]::Round($sw.Elapsed.TotalSeconds, 1)

Write-Host ""
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host "  TOP $($top150.Count) SKILLS (NOT INSTALLED) sorted by downloads  |  ${elapsed}s" -ForegroundColor Cyan
Write-Host "============================================================================" -ForegroundColor Cyan
Write-Host ""

$rank = 0
foreach ($skill in $top150) {
    $rank++
    $desc = "$($skill.Summary)"
    if ($desc.Length -gt 110) { $desc = $desc.Substring(0, 107) + "..." }
    Write-Host ("{0,3}. " -f $rank) -NoNewline -ForegroundColor White
    Write-Host "$($skill.Name)" -NoNewline -ForegroundColor Green
    Write-Host " (DL:$($skill.Downloads) inst:$($skill.Installs) *$($skill.Stars))" -ForegroundColor DarkGray
    Write-Host "     $desc" -ForegroundColor Gray
}

Write-Host ""
Write-Host "  Searched: $($hitCount.Count) unique | Got details: $($skillData.Count) | Showing: $($top150.Count) | ${elapsed}s" -ForegroundColor White
Write-Host "============================================================================" -ForegroundColor Cyan
