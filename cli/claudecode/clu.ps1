#Requires -Version 5
# CLU - Claude Code Real-Time Subscription Usage

Write-Host ""
Write-Host "========================================"
Write-Host "   CLAUDE CODE - SUBSCRIPTION USAGE"
Write-Host "========================================"
Write-Host ""

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pyScript = Join-Path $scriptDir "clu-engine.py"

if (-not (Test-Path $pyScript)) {
    Write-Host "ERROR: clu-engine.py not found at $pyScript"
    exit 1
}

$result = python $pyScript 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "ERROR: $result"
    exit 1
}

try {
    $data = $result | ConvertFrom-Json
} catch {
    Write-Host "ERROR: Failed to parse output"
    Write-Host $result
    exit 1
}

if ($data.rate_limit_error) {
    Write-Host "  (!) $($data.rate_limit_error)" -ForegroundColor Red
    Write-Host ""
    exit 1
}

if (-not $data.rate_limits) {
    Write-Host "  No rate limit data available" -ForegroundColor DarkGray
    Write-Host ""
    exit 0
}

$limitNames = @{
    "five_hour"        = "5-Hour (Session)"
    "seven_day"        = "7-Day (All Models)"
    "seven_day_sonnet" = "7-Day (Sonnet)"
    "seven_day_opus"   = "7-Day (Opus)"
}
$limitOrder = @("five_hour", "seven_day", "seven_day_sonnet", "seven_day_opus")

foreach ($key in $limitOrder) {
    $limit = $data.rate_limits.PSObject.Properties | Where-Object { $_.Name -eq $key }
    if (-not $limit) { continue }
    $l = $limit.Value

    $displayName = $limitNames[$key]
    if (-not $displayName) { $displayName = $key }

    $pct = 0
    if ($l.utilization -ne $null) {
        $pct = [Math]::Round([double]$l.utilization * 100)
    }

    $barLen = 30
    $filled = [Math]::Floor(($pct / 100) * $barLen)
    $bar = ""
    for ($i = 0; $i -lt $barLen; $i++) {
        if ($i -lt $filled) { $bar += "#" } else { $bar += "-" }
    }

    $resetInfo = ""
    if ($l.resets_in) {
        $resetInfo = "  resets in $($l.resets_in)"
    }

    $line = "  {0,-22} [{1}] {2,3}%{3}" -f $displayName, $bar, $pct, $resetInfo

    if ($pct -ge 90) {
        Write-Host $line -ForegroundColor Red
    } elseif ($pct -ge 70) {
        Write-Host $line -ForegroundColor Yellow
    } elseif ($pct -ge 40) {
        Write-Host $line -ForegroundColor DarkYellow
    } else {
        Write-Host $line -ForegroundColor Green
    }
}

# Overall status
Write-Host ""
if ($data.rate_limit_status -eq "rejected") {
    Write-Host "  STATUS: RATE LIMITED" -ForegroundColor Red
} else {
    Write-Host "  STATUS: $($data.rate_limit_status)" -ForegroundColor Green
}

# Extra usage
$overageProp = $data.rate_limits.PSObject.Properties | Where-Object { $_.Name -eq "overage" }
if ($overageProp) {
    $ov = $overageProp.Value
    if ($ov.status -eq "rejected" -and $data.overage_disabled_reason) {
        $reason = $data.overage_disabled_reason -replace '_', ' '
        Write-Host "  Extra Usage: disabled ($reason)" -ForegroundColor DarkGray
    } elseif ($ov.status -eq "allowed") {
        Write-Host "  Extra Usage: enabled" -ForegroundColor Cyan
    }
}

# Fallback
if ($data.fallback_percentage) {
    $fbPct = [Math]::Round([double]$data.fallback_percentage * 100)
    Write-Host "  Fallback: ${fbPct}% of requests may use fallback model" -ForegroundColor DarkGray
}

# Token totals (just the total, no model breakdown)
if ($data.session_stats) {
    $s = $data.session_stats
    Write-Host ""
    Write-Host "  Sessions: $($s.sessions)  |  API calls: $($s.api_calls)  |  Tokens: $($s.tokens.total.ToString('N0'))"
}

Write-Host ""
Write-Host "========================================"
Write-Host ""
