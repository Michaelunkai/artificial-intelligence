#Requires -Version 5

param(
    [string]$Session,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$PromptParts
)

function Get-CodexSessionFile {
    param([string]$SessionId)

    $sessionsDir = Join-Path $env:USERPROFILE '.codex\sessions'
    if (-not (Test-Path $sessionsDir)) { return $null }

    Get-ChildItem -Path $sessionsDir -Recurse -Filter "*$SessionId*.jsonl" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Get-CodexSessionCwd {
    param([string]$JsonlPath)

    $head = Get-Content -Path $JsonlPath -TotalCount 10 -ErrorAction SilentlyContinue
    foreach ($line in $head) {
        try {
            $obj = $line | ConvertFrom-Json -ErrorAction Stop
            if ($obj.type -eq 'session_meta' -and $obj.payload.cwd) {
                return [string]$obj.payload.cwd
            }
        } catch { }
    }

    return $null
}

function Resolve-CodexSession {
    param([string]$NameOrId)

    if ([string]::IsNullOrWhiteSpace($NameOrId)) {
        return @{ SessionId = $null; Cwd = $null }
    }

    $candidate = $NameOrId.Trim()
    $isUuid = $candidate -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    $resolvedId = $null

    if ($isUuid) {
        $resolvedId = $candidate
    } else {
        $indexPath = Join-Path $env:USERPROFILE '.codex\session_index.jsonl'
        if (Test-Path $indexPath) {
            $match = Get-Content -Path $indexPath -ErrorAction SilentlyContinue |
                ForEach-Object {
                    try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
                } |
                Where-Object { $_ -and $_.thread_name -eq $candidate } |
                Sort-Object { [datetime]$_.updated_at } -Descending |
                Select-Object -First 1

            if ($match) {
                $resolvedId = [string]$match.id
            }
        }
    }

    if (-not $resolvedId) {
        return @{ SessionId = $null; Cwd = $null }
    }

    $sessionFile = Get-CodexSessionFile $resolvedId
    $cwd = if ($sessionFile) { Get-CodexSessionCwd $sessionFile.FullName } else { $null }

    return @{ SessionId = $resolvedId; Cwd = $cwd }
}

function Get-LatestCodexSession {
    $indexPath = Join-Path $env:USERPROFILE '.codex\session_index.jsonl'
    if (-not (Test-Path $indexPath)) {
        return @{ SessionId = $null; Cwd = $null }
    }

    $latest = Get-Content -Path $indexPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        } |
        Where-Object { $_ -and $_.id } |
        Sort-Object { [datetime]$_.updated_at } -Descending |
        Select-Object -First 1

    if (-not $latest) {
        return @{ SessionId = $null; Cwd = $null }
    }

    $sessionFile = Get-CodexSessionFile ([string]$latest.id)
    $cwd = if ($sessionFile) { Get-CodexSessionCwd $sessionFile.FullName } else { $null }

    return @{
        SessionId  = [string]$latest.id
        Cwd        = $cwd
        ThreadName = [string]$latest.thread_name
    }
}

if ($Session) {
    $resolved = Resolve-CodexSession $Session
    $resolvedId = $resolved.SessionId
    $resolvedCwd = $resolved.Cwd

    if ($resolvedId -and $resolvedId -ne $Session) {
        Write-Host "Resolved '$Session' -> $resolvedId" -ForegroundColor Cyan
        if ($resolvedCwd) { Write-Host "  cwd: $resolvedCwd" -ForegroundColor DarkCyan }
    }
} else {
    $latest = Get-LatestCodexSession
    $resolvedId = $latest.SessionId
    $resolvedCwd = $latest.Cwd

    if ($resolvedId) {
        $label = if ($latest.ThreadName) { $latest.ThreadName } else { $resolvedId }
        Write-Host "Continuing latest Codex session: $label" -ForegroundColor Cyan
        Write-Host "  id: $resolvedId" -ForegroundColor DarkCyan
        if ($resolvedCwd) { Write-Host "  cwd: $resolvedCwd" -ForegroundColor DarkCyan }
    }
}

$origLocation = Get-Location
if ($resolvedCwd -and (Test-Path $resolvedCwd)) {
    Set-Location $resolvedCwd
}

$cmdArgs = @('--yolo', 'resume')
if ($resolvedId) {
    $cmdArgs += $resolvedId
} elseif ($Session) {
    $cmdArgs += $Session
} else {
    $cmdArgs += '--last'
    $cmdArgs += '--all'
}

if ($PromptParts.Count -gt 0) {
    $cmdArgs += ($PromptParts -join ' ')
}

try {
    & codex @cmdArgs
} finally {
    Set-Location $origLocation
}
