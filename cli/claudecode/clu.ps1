#Requires -Version 5
# CLU - Claude Usage (Real-Time)
# Auto-extracts session key from Claude Desktop cookies using DPAPI
# NEVER needs manual login - works as long as Claude Desktop is logged in
# Decryption uses your Windows user credentials (automatic)

Write-Host ""
Write-Host "========================================"
Write-Host "     CLAUDE REAL-TIME USAGE REPORT"
Write-Host "========================================"
Write-Host ""

# Run Python extraction + API call
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$pyScript = Join-Path $scriptDir "clu-engine.py"

if (-not (Test-Path $pyScript)) {
    Write-Host "ERROR: clu-engine.py not found at $pyScript"
    exit 1
}

$result = python $pyScript 2>&1
$exitCode = $LASTEXITCODE

if ($exitCode -ne 0) {
    Write-Host "ERROR: Usage check failed"
    Write-Host $result
    exit 1
}

# Parse JSON output from Python
try {
    $data = $result | ConvertFrom-Json
} catch {
    # If not JSON, it's an error message
    Write-Host $result
    exit 1
}

# Display usage
if ($data.error) {
    Write-Host "ERROR: $($data.error)"
    exit 1
}

Write-Host "[REAL-TIME RATE LIMITS]"
Write-Host ""

# 5-hour limit
if ($data.five_hour) {
    $pct = $data.five_hour.utilization
    $bar = ""
    $filled = [Math]::Floor($pct / 5)
    for ($i = 0; $i -lt 20; $i++) {
        if ($i -lt $filled) { $bar += "#" } else { $bar += "-" }
    }
    $resetTime = ""
    if ($data.five_hour.resets_at) {
        $reset = [DateTime]::Parse($data.five_hour.resets_at).ToLocalTime()
        $diff = $reset - (Get-Date)
        if ($diff.TotalMinutes -gt 0) {
            $resetTime = " (resets in {0}h {1}m)" -f [int]$diff.TotalHours, $diff.Minutes
        } else {
            $resetTime = " (resets now!)"
        }
    }
    Write-Host ("  5-Hour:  [{0}] {1}%{2}" -f $bar, $pct, $resetTime)
}

# Weekly limit  
if ($data.seven_day) {
    $pct = $data.seven_day.utilization
    $bar = ""
    $filled = [Math]::Floor($pct / 5)
    for ($i = 0; $i -lt 20; $i++) {
        if ($i -lt $filled) { $bar += "#" } else { $bar += "-" }
    }
    $resetTime = ""
    if ($data.seven_day.resets_at) {
        $reset = [DateTime]::Parse($data.seven_day.resets_at).ToLocalTime()
        $diff = $reset - (Get-Date)
        if ($diff.TotalDays -gt 0) {
            $resetTime = " (resets in {0}d {1}h)" -f [int]$diff.TotalDays, $diff.Hours
        } elseif ($diff.TotalHours -gt 0) {
            $resetTime = " (resets in {0}h {1}m)" -f [int]$diff.TotalHours, $diff.Minutes
        }
    }
    Write-Host ("  Weekly:  [{0}] {1}%{2}" -f $bar, $pct, $resetTime)
}

# Model-specific limits
if ($data.seven_day_sonnet) {
    $pct = $data.seven_day_sonnet.utilization
    $bar = ""
    $filled = [Math]::Floor($pct / 5)
    for ($i = 0; $i -lt 20; $i++) {
        if ($i -lt $filled) { $bar += "#" } else { $bar += "-" }
    }
    Write-Host ("  Sonnet:  [{0}] {1}%" -f $bar, $pct)
}

if ($data.seven_day_opus) {
    $pct = $data.seven_day_opus.utilization
    $bar = ""
    $filled = [Math]::Floor($pct / 5)
    for ($i = 0; $i -lt 20; $i++) {
        if ($i -lt $filled) { $bar += "#" } else { $bar += "-" }
    }
    Write-Host ("  Opus:    [{0}] {1}%" -f $bar, $pct)
}

Write-Host ""
Write-Host "========================================"
Write-Host "Auto-extracted from Claude Desktop (DPAPI)"
Write-Host "No manual login needed - ever."
Write-Host "========================================"
Write-Host ""
