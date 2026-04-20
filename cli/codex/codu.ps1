#Requires -Version 5

param(
    [switch]$Json,
    [switch]$Quiet,
    [switch]$Refresh
)

function Write-Banner {
    if ($Quiet -or $Json) { return }

    Write-Host ""
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "   CODEX - REAL-TIME ACCOUNT USAGE" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

function Get-CodexCommandPath {
    $candidates = @(
        "C:\Users\micha\AppData\Local\npm-global\codex.cmd",
        "C:\Users\micha\AppData\Local\npm-global\codex.ps1"
    )

    foreach ($candidate in $candidates) {
        if (Test-Path $candidate) { return $candidate }
    }

    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd) { return $cmd.Source }

    return $null
}

function Get-RateLimitResponse {
    $codexPath = Get-CodexCommandPath
    if (-not $codexPath) {
        throw "Codex CLI not found in PATH or expected install locations."
    }

    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $codexPath
    $psi.Arguments = 'app-server --listen stdio://'
    $psi.RedirectStandardInput = $true
    $psi.RedirectStandardOutput = $true
    $psi.RedirectStandardError = $true
    $psi.UseShellExecute = $false
    $psi.CreateNoWindow = $true
    $psi.WorkingDirectory = (Get-Location).Path

    $process = [System.Diagnostics.Process]::Start($psi)
    if (-not $process) {
        throw "Failed to start Codex app-server."
    }

    try {
        $init = '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"clientInfo":{"name":"codu","version":"1.0"}}}'
        $read = '{"jsonrpc":"2.0","id":2,"method":"account/rateLimits/read","params":null}'

        $process.StandardInput.WriteLine($init)
        $process.StandardInput.WriteLine($read)

        $deadline = (Get-Date).AddSeconds(15)
        $rawLines = New-Object System.Collections.Generic.List[string]

        while ((Get-Date) -lt $deadline) {
            if (-not $process.StandardOutput.EndOfStream) {
                $line = $process.StandardOutput.ReadLine()
                if ($null -ne $line -and $line.Length -gt 0) {
                    $rawLines.Add($line)
                    if ($line -match '"id"\s*:\s*2') { break }
                }
            } elseif ($process.HasExited) {
                break
            } else {
                Start-Sleep -Milliseconds 100
            }
        }

        if ($rawLines.Count -eq 0) {
            $stderr = $process.StandardError.ReadToEnd()
            throw "No response from Codex app-server. $stderr"
        }

        $responseLine = $null
        foreach ($line in $rawLines) {
            if ($line -match '"id"\s*:\s*2') {
                $responseLine = $line
                break
            }
        }

        if (-not $responseLine) {
            throw "Codex app-server returned no rate-limit payload."
        }

        $response = $responseLine | ConvertFrom-Json
        if ($response.error) {
            $message = if ($response.error.message) { $response.error.message } else { "Unknown app-server error." }
            throw $message
        }

        return $response.result
    } finally {
        try {
            if (-not $process.HasExited) { $process.Kill() }
        } catch { }
        $process.Dispose()
    }
}

function Get-WindowLabel([object]$window, [string]$fallback) {
    if ($window.windowDurationMins) {
        $mins = [int64]$window.windowDurationMins
        if ($mins % 10080 -eq 0) {
            $weeks = [int]($mins / 10080)
            if ($weeks -eq 1) { return "7-Day Window" }
            return "${weeks}-Week Window"
        }
        if ($mins % 1440 -eq 0) {
            $days = [int]($mins / 1440)
            if ($days -eq 1) { return "1-Day Window" }
            return "${days}-Day Window"
        }
        if ($mins % 60 -eq 0) {
            $hours = [int]($mins / 60)
            if ($hours -eq 1) { return "1-Hour Window" }
            return "${hours}-Hour Window"
        }
        return "${mins}-Minute Window"
    }

    return $fallback
}

function New-DisplayWindow([string]$limitId, [string]$limitName, [string]$planType, [object]$window, [string]$slotName) {
    if (-not $window) { return $null }

    $label = Get-WindowLabel $window $slotName
    $displayLimit = if ($limitName) { $limitName } elseif ($limitId) { $limitId } else { "codex" }
    $usedPercent = [Math]::Max(0, [Math]::Min(100, [int]$window.usedPercent))
    $leftPercent = [Math]::Max(0, 100 - $usedPercent)
    $title = "$displayLimit / $label"

    return [pscustomobject]@{
        limit_id      = $limitId
        limit_name    = $limitName
        display_limit = $displayLimit
        plan_type     = $planType
        slot          = $slotName
        title         = $title
        used_percent  = $usedPercent
        left_percent  = $leftPercent
        reset_ts      = if ($null -ne $window.resetsAt) { [int64]$window.resetsAt } else { $null }
        duration_mins = if ($null -ne $window.windowDurationMins) { [int64]$window.windowDurationMins } else { $null }
    }
}

function Test-SameWindow([object]$a, [object]$b) {
    if (-not $a -and -not $b) { return $true }
    if (-not $a -or -not $b) { return $false }

    return (
        $a.used_percent -eq $b.used_percent -and
        $a.left_percent -eq $b.left_percent -and
        $a.reset_ts -eq $b.reset_ts -and
        $a.duration_mins -eq $b.duration_mins
    )
}

function Convert-ToCachePayload([object]$result) {
    $snapshots = @()

    if ($result.rateLimitsByLimitId) {
        foreach ($prop in $result.rateLimitsByLimitId.PSObject.Properties) {
            if ($prop.Value) { $snapshots += $prop.Value }
        }
    } elseif ($result.rateLimits) {
        $snapshots += $result.rateLimits
    }

    $snapshotWindows = @{}
    foreach ($snapshot in $snapshots) {
        $limitId = if ($snapshot.limitId) { [string]$snapshot.limitId } else { "codex" }
        $limitName = if ($snapshot.limitName) { [string]$snapshot.limitName } else { $null }
        $planType = if ($snapshot.planType) { [string]$snapshot.planType } else { "unknown" }

        $primaryWindow = New-DisplayWindow $limitId $limitName $planType $snapshot.primary "Primary"
        $secondaryWindow = New-DisplayWindow $limitId $limitName $planType $snapshot.secondary "Secondary"

        $snapshotWindows[$limitId] = [pscustomobject]@{
            limit_id   = $limitId
            limit_name = $limitName
            plan_type  = $planType
            primary    = $primaryWindow
            secondary  = $secondaryWindow
        }
    }

    $baseSnapshot = $null
    if ($snapshotWindows.ContainsKey("codex")) {
        $baseSnapshot = $snapshotWindows["codex"]
    }

    $windows = @()
    foreach ($entry in $snapshotWindows.GetEnumerator()) {
        $snapshotEntry = $entry.Value
        $isModelSpecific = $snapshotEntry.limit_id -ne "codex" -and [string]::IsNullOrWhiteSpace($snapshotEntry.limit_name) -eq $false
        $isDistinctFromBase = $true

        if ($baseSnapshot -and $snapshotEntry.limit_id -ne "codex") {
            $samePrimary = Test-SameWindow $snapshotEntry.primary $baseSnapshot.primary
            $sameSecondary = Test-SameWindow $snapshotEntry.secondary $baseSnapshot.secondary
            $isDistinctFromBase = -not ($samePrimary -and $sameSecondary)
        }

        if ($snapshotEntry.limit_id -eq "codex" -or -not $isModelSpecific -or $isDistinctFromBase) {
            if ($snapshotEntry.primary) { $windows += $snapshotEntry.primary }
            if ($snapshotEntry.secondary) { $windows += $snapshotEntry.secondary }
        }
    }

    $windows = @(
        $windows |
            Sort-Object `
                @{ Expression = { if ($_.limit_id -eq 'codex') { 0 } else { 1 } } }, `
                @{ Expression = { $_.limit_name } }, `
                @{ Expression = { $_.limit_id } }, `
                @{ Expression = { if ($_.slot -eq 'Primary') { 0 } else { 1 } } }
    )

    return [pscustomobject]@{
        fetched_at       = (Get-Date -Format 'o')
        unix_ts          = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        windows          = $windows
        raw              = $result
    }
}

function Write-Usage([object]$payload) {
    $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()

    foreach ($window in $payload.windows) {
        $pct = [Math]::Max(0, [Math]::Min(100, [int]$window.used_percent))
        $leftPct = [Math]::Max(0, [Math]::Min(100, [int]$window.left_percent))
        $barLen = 30
        $filled = [Math]::Floor(($leftPct / 100) * $barLen)
        $bar = ('#' * $filled) + ('-' * ($barLen - $filled))

        $resetInfo = ""
        if ($null -ne $window.reset_ts) {
            $diff = [int64]$window.reset_ts - $now
            if ($diff -gt 0) {
                $days = [Math]::Floor($diff / 86400)
                $hrs = [Math]::Floor(($diff % 86400) / 3600)
                $mins = [Math]::Floor(($diff % 3600) / 60)
                if ($days -gt 0) { $resetInfo = "  resets in ${days}d ${hrs}h" }
                elseif ($hrs -gt 0) { $resetInfo = "  resets in ${hrs}h ${mins}m" }
                else { $resetInfo = "  resets in ${mins}m" }
            } else {
                $resetInfo = "  resets now"
            }
        }

        $line = "  {0,-36} [{1}] left {2,3}%  used {3,3}%{4}" -f $window.title, $bar, $leftPct, $pct, $resetInfo
        if ($leftPct -le 10) {
            Write-Host $line -ForegroundColor Red
        } elseif ($leftPct -le 30) {
            Write-Host $line -ForegroundColor Yellow
        } elseif ($leftPct -le 60) {
            Write-Host $line -ForegroundColor DarkYellow
        } else {
            Write-Host $line -ForegroundColor Green
        }
    }

    $plans = @($payload.windows | ForEach-Object { $_.plan_type } | Where-Object { $_ } | Select-Object -Unique)
    $limits = @($payload.windows | ForEach-Object { $_.limit_id } | Where-Object { $_ } | Select-Object -Unique)

    Write-Host ""
    if ($plans.Count -gt 0) {
        Write-Host ("  Plan: " + ($plans -join ", ")) -ForegroundColor Cyan
    }
    if ($limits.Count -gt 0) {
        Write-Host ("  Limit IDs: " + ($limits -join ", ")) -ForegroundColor DarkGray
    }

    if ($payload.raw.rateLimits -and $payload.raw.rateLimits.credits) {
        $credits = $payload.raw.rateLimits.credits
        if ($credits.unlimited) {
            Write-Host "  Credits: unlimited" -ForegroundColor Cyan
        } elseif ($credits.hasCredits -and $credits.balance) {
            Write-Host "  Credits balance: $($credits.balance)" -ForegroundColor Cyan
        } elseif (-not $credits.hasCredits) {
            Write-Host "  Credits: none" -ForegroundColor DarkGray
        }
    }

    if (-not $Quiet) {
        Write-Host ""
        Write-Host "========================================" -ForegroundColor Cyan
        Write-Host ""
    }
}

Write-Banner

try {
    $result = Get-RateLimitResponse
    $payload = Convert-ToCachePayload $result

    if ($Json) {
        $payload | ConvertTo-Json -Depth 6
        exit 0
    }

    if (-not $payload.windows -or $payload.windows.Count -eq 0) {
        Write-Host "  No Codex rate-limit data available." -ForegroundColor DarkGray
        if (-not $Quiet) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
        }
        exit 0
    }

    Write-Usage $payload
    exit 0
} catch {
    $message = $_.Exception.Message
    if ($Json) {
        [pscustomobject]@{ error = $message } | ConvertTo-Json -Depth 4
    } else {
        Write-Host "  (!) $message" -ForegroundColor Red
        if (-not $Quiet) {
            Write-Host ""
            Write-Host "========================================" -ForegroundColor Cyan
            Write-Host ""
        }
    }
    exit 1
}
