#Requires -Version 5
# CLU - Claude Code Subscription Usage (Cached, Shared)
# Caches rate limit data for 5 min - all bots share one cache = minimal token usage

param(
    [switch]$Json,      # Output raw JSON (for bots)
    [switch]$Quiet,     # Skip header/footer (for embedding)
    [switch]$Refresh    # Force refresh from API (skip cache)
)

$cachePath = Join-Path $env:USERPROFILE ".claude\usage-cache.json"

if (-not $Quiet -and -not $Json) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   CLAUDE CODE - SUBSCRIPTION USAGE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

# --- Get OAuth token ---
$token = $env:CLAUDE_CODE_OAUTH_TOKEN
if (-not $token) { $token = $env:ANTHROPIC_OAUTH_TOKEN }

# Fallback: read from credentials file
if (-not $token) {
    $credPath = Join-Path $env:USERPROFILE ".claude\.credentials.json"
    if (Test-Path $credPath) {
        try {
            $cred = Get-Content $credPath -Raw | ConvertFrom-Json
            if ($cred.claudeAiOauth.accessToken) {
                $token = $cred.claudeAiOauth.accessToken
            }
        } catch { }
    }
}

if (-not $token) {
    if ($Json) {
        Write-Output '{"error":"No OAuth token found"}'
    } else {
        Write-Host "  (!) No OAuth token found." -ForegroundColor Red
        Write-Host "      Run clu from inside a Claude Code session," -ForegroundColor Yellow
        Write-Host "      or ensure CLAUDE_CODE_OAUTH_TOKEN is set." -ForegroundColor Yellow
        Write-Host ""
    }
    exit 1
}

# --- Check cache first (shared across all bots, avoids redundant API calls) ---
$cacheValid = $false
if (-not $Refresh -and (Test-Path $cachePath)) {
    $cacheAge = ((Get-Date) - (Get-Item $cachePath).LastWriteTime).TotalSeconds
    if ($cacheAge -lt 300) {  # 5 min cache
        $cacheValid = $true
    }
}

if ($cacheValid -and -not $Json) {
    # Display from cache - zero API calls
    $data = Get-Content $cachePath -Raw | ConvertFrom-Json
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    foreach ($win in $data.windows) {
        $pct = [Math]::Round($win.utilization * 100)
        $barLen = 30
        $filled = [Math]::Floor(($pct / 100) * $barLen)
        $bar = ('#' * $filled) + ('-' * ($barLen - $filled))
        $diff = $win.reset_ts - $now
        $resetInfo = ""
        if ($diff -gt 0) {
            $days = [Math]::Floor($diff / 86400)
            $hrs  = [Math]::Floor(($diff % 86400) / 3600)
            $mins = [Math]::Floor(($diff % 3600) / 60)
            if ($days -gt 0) { $resetInfo = "  resets in ${days}d ${hrs}h" }
            elseif ($hrs -gt 0) { $resetInfo = "  resets in ${hrs}h ${mins}m" }
            else { $resetInfo = "  resets in ${mins}m" }
        } elseif ($win.reset_ts -gt 0) { $resetInfo = "  resets now" }
        $line = "  {0,-18} [{1}] {2,3}%{3}" -f $win.name, $bar, $pct, $resetInfo
        if ($pct -ge 90) { Write-Host $line -ForegroundColor Red }
        elseif ($pct -ge 70) { Write-Host $line -ForegroundColor Yellow }
        elseif ($pct -ge 40) { Write-Host $line -ForegroundColor DarkYellow }
        else { Write-Host $line -ForegroundColor Green }
    }
    Write-Host ""
    if ($data.status -eq 'rejected') { Write-Host "  STATUS: RATE LIMITED" -ForegroundColor Red }
    elseif ($data.status -and $data.status -ne 'unknown') { Write-Host "  STATUS: $($data.status)" -ForegroundColor Green }
    if ($data.overage_status -eq 'rejected' -and $data.overage_reason) {
        $reason = $data.overage_reason -replace '_', ' '
        Write-Host "  Extra Usage: disabled ($reason)" -ForegroundColor DarkGray
    } elseif ($data.overage_status -eq 'allowed') { Write-Host "  Extra Usage: enabled" -ForegroundColor Cyan }
    if ($data.fallback_pct -gt 0) {
        Write-Host "  Fallback: $($data.fallback_pct)% of requests may use fallback model" -ForegroundColor DarkGray
    }
    $cacheAgeSec = [Math]::Round(((Get-Date) - (Get-Item $cachePath).LastWriteTime).TotalSeconds)
    Write-Host "  (cached ${cacheAgeSec}s ago)" -ForegroundColor DarkGray
    if (-not $Quiet) { Write-Host ""; Write-Host "========================================" -ForegroundColor Cyan; Write-Host "" }
    exit 0
} elseif ($cacheValid -and $Json) {
    Get-Content $cachePath -Raw
    exit 0
}

# --- Minimal API call: haiku max_tokens=1 (~11 tokens, cached 5min for all bots) ---
$body = @{
    model      = 'claude-haiku-4-5-20251001'
    max_tokens = 1
    messages   = @(@{ role = 'user'; content = '.' })
} | ConvertTo-Json -Depth 3

$headers = @{
    'Authorization'   = "Bearer $token"
    'anthropic-version' = '2023-06-01'
    'content-type'    = 'application/json'
    'anthropic-beta'  = 'oauth-2025-04-20'
}

$respHeaders = $null
$apiError = $null

try {
    $resp = Invoke-WebRequest -Uri 'https://api.anthropic.com/v1/messages' `
        -Method Post -Headers $headers -Body $body -UseBasicParsing -TimeoutSec 15
    $respHeaders = $resp.Headers
} catch {
    $ex = $_.Exception
    if ($ex.Response) {
        # 400 validation error still returns rate limit headers - this is expected!
        $respHeaders = @{}
        foreach ($key in $ex.Response.Headers.AllKeys) {
            $respHeaders[$key] = $ex.Response.Headers[$key]
        }
        $statusCode = [int]$ex.Response.StatusCode
        if ($statusCode -eq 401) {
            $apiError = "Authentication failed. Token may be expired."
        }
        # 400 is expected (empty messages) - NOT an error for our purposes
    } else {
        $apiError = "Request failed: $($ex.Message)"
    }
}

if ($apiError -and -not $respHeaders) {
    if ($Json) {
        Write-Output "{`"error`":`"$apiError`"}"
    } else {
        Write-Host "  (!) $apiError" -ForegroundColor Red
        Write-Host ""
    }
    exit 1
}

# --- Parse rate limit headers ---
# Build case-insensitive lookup
$h = @{}
if ($respHeaders) {
    foreach ($key in $respHeaders.Keys) {
        $val = $respHeaders[$key]
        # Headers return String[] on some PS versions — always extract first element
        $h[$key.ToLower()] = if ($val -is [System.Array]) { $val[0] } else { "$val" }
    }
}

$now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

$limits = @(
    @{ key = '5h';  name = '5-Hour Window' }
    @{ key = '7d';  name = '7-Day Window' }
)

$hasData = $false

foreach ($lim in $limits) {
    $prefix = "anthropic-ratelimit-unified-$($lim.key)"
    $utilRaw = $h["${prefix}-utilization"]
    $resetRaw = $h["${prefix}-reset"]
    $statusRaw = $h["${prefix}-status"]

    if ($null -eq $utilRaw -and $null -eq $resetRaw) { continue }
    $hasData = $true

    $pct = 0
    if ($utilRaw) { $pct = [Math]::Round([double]$utilRaw * 100) }

    # Build progress bar
    $barLen = 30
    $filled = [Math]::Floor(($pct / 100) * $barLen)
    $bar = ""
    for ($i = 0; $i -lt $barLen; $i++) {
        if ($i -lt $filled) { $bar += "#" } else { $bar += "-" }
    }

    # Calculate reset time
    $resetInfo = ""
    if ($resetRaw) {
        $resetTs = [double]$resetRaw
        $diff = $resetTs - $now
        if ($diff -gt 0) {
            $days = [Math]::Floor($diff / 86400)
            $hrs  = [Math]::Floor(($diff % 86400) / 3600)
            $mins = [Math]::Floor(($diff % 3600) / 60)
            if ($days -gt 0) {
                $resetInfo = "  resets in ${days}d ${hrs}h"
            } elseif ($hrs -gt 0) {
                $resetInfo = "  resets in ${hrs}h ${mins}m"
            } else {
                $resetInfo = "  resets in ${mins}m"
            }
        } else {
            $resetInfo = "  resets now"
        }
    }

    $line = "  {0,-18} [{1}] {2,3}%{3}" -f $lim.name, $bar, $pct, $resetInfo

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

if (-not $hasData -and -not $Json) {
    Write-Host "  No rate limit data available" -ForegroundColor DarkGray
}

# Overall status
$overallStatus = $h['anthropic-ratelimit-unified-status']
$overageStatus = $h['anthropic-ratelimit-unified-overage-status']
$overageReason = $h['anthropic-ratelimit-unified-overage-disabled-reason']
$fallback = $h['anthropic-ratelimit-unified-fallback-percentage']

# --- Save to cache for OpenClaw bots (zero-token shared access) ---
$cacheData = @{
    timestamp       = (Get-Date -Format 'o')
    unix_ts         = $now
    status          = if ($overallStatus) { $overallStatus } else { 'unknown' }
    overage_status  = if ($overageStatus) { $overageStatus } else { 'unknown' }
    overage_reason  = if ($overageReason) { $overageReason } else { '' }
    fallback_pct    = if ($fallback) { [Math]::Round([double]$fallback * 100) } else { 0 }
    windows         = @()
}

foreach ($lim in $limits) {
    $prefix = "anthropic-ratelimit-unified-$($lim.key)"
    $utilRaw = $h["${prefix}-utilization"]
    $resetRaw = $h["${prefix}-reset"]
    if ($null -ne $utilRaw -or $null -ne $resetRaw) {
        $cacheData.windows += @{
            key         = $lim.key
            name        = $lim.name
            utilization = if ($utilRaw) { [double]$utilRaw } else { 0 }
            reset_ts    = if ($resetRaw) { [double]$resetRaw } else { 0 }
        }
    }
}

$cacheDir = Split-Path $cachePath -Parent
if (-not (Test-Path $cacheDir)) { New-Item -ItemType Directory -Path $cacheDir -Force | Out-Null }
[System.IO.File]::WriteAllText($cachePath, ($cacheData | ConvertTo-Json -Depth 4), (New-Object System.Text.UTF8Encoding $false))

# --- JSON output mode (for bots) ---
if ($Json) {
    $cacheData | ConvertTo-Json -Depth 4
    exit 0
}

# --- Display status ---
Write-Host ""
if ($overallStatus -eq 'rejected') {
    Write-Host "  STATUS: RATE LIMITED" -ForegroundColor Red
} elseif ($overallStatus) {
    Write-Host "  STATUS: $overallStatus" -ForegroundColor Green
}

if ($overageStatus -eq 'rejected' -and $overageReason) {
    $reason = $overageReason -replace '_', ' '
    Write-Host "  Extra Usage: disabled ($reason)" -ForegroundColor DarkGray
} elseif ($overageStatus -eq 'allowed') {
    Write-Host "  Extra Usage: enabled" -ForegroundColor Cyan
}

if ($fallback) {
    $fbPct = [Math]::Round([double]$fallback * 100)
    Write-Host "  Fallback: ${fbPct}% of requests may use fallback model" -ForegroundColor DarkGray
}

if (-not $Quiet) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}
