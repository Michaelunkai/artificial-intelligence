<#
.SYNOPSIS
    claur - Claude Code resume session by name from anywhere, survives reboots
.NOTES
    Original function: claur
    Extracted: 2026-02-19 20:20
    Fixed: 2026-03-27 - use project root cwd from JSONL, not rename event cwd
#>
param([string]$session, [Parameter(ValueFromRemainingArguments=$true)][string[]]$args_)

function Get-ClaudeProjectCwd {
    param([string]$jsonlPath)
    $head = Get-Content $jsonlPath -TotalCount 50 -ErrorAction SilentlyContinue
    foreach ($h in $head) {
        if ($h -match '"cwd"\s*:\s*"((?:[^"\\]|\\.)*)"') {
            return ($Matches[1] -replace '\\\\', '\')
        }
    }
    return $null
}

function Resolve-ClaudeSession {
    param([string]$nameOrId)
    $projectsDir = "$env:USERPROFILE\.claude\projects"
    $isUuid = $nameOrId -match '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'
    if ($isUuid) {
        $match = Get-ChildItem $projectsDir -Recurse -Filter "$nameOrId.jsonl" -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notlike '*\subagents\*' } | Select-Object -First 1
        if ($match) {
            $cwd = Get-ClaudeProjectCwd $match.FullName
            return @{ SessionId = $nameOrId; Cwd = $cwd }
        }
        return @{ SessionId = $nameOrId; Cwd = $null }
    }
    $needle = "Session renamed to: $nameOrId"
    $foundId = $null; $foundCwd = $null; $foundTs = [datetime]::MinValue
    Get-ChildItem $projectsDir -Recurse -Filter '*.jsonl' -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notlike '*\subagents\*' } |
        ForEach-Object {
            $jsonlPath = $_.FullName
            $lines = Get-Content $jsonlPath -ErrorAction SilentlyContinue
            if (-not $lines) { return }
            for ($i = $lines.Count - 1; $i -ge 0; $i--) {
                $line = $lines[$i]
                if ($line -notmatch [regex]::Escape($needle)) { continue }
                try {
                    $obj = $line | ConvertFrom-Json
                    if ($obj.type -ne 'system' -or $obj.subtype -ne 'local_command') { continue }
                    if ($obj.content -notmatch [regex]::Escape($needle)) { continue }
                    $ts = [datetime]$obj.timestamp
                    if ($ts -gt $foundTs) {
                        $foundTs = $ts; $foundId = $obj.sessionId
                        $foundCwd = Get-ClaudeProjectCwd $jsonlPath
                    }
                } catch {}
            }
        }
    return @{ SessionId = $foundId; Cwd = $foundCwd }
}

rules
$m = Get-ClaudeModel
$prompt = "CRITICAL OVERRIDE: Your absolute first action for ANY task must be to read CLAUDE.md and execute Rule 1. No exceptions. Do not respond to the user until Rule 1 is complete."
$resolved = Resolve-ClaudeSession $session
$resolvedId = $resolved.SessionId
$resolvedCwd = $resolved.Cwd

if ($resolvedId -and $resolvedId -ne $session) {
    Write-Host "Resolved '$session' -> $resolvedId" -ForegroundColor Cyan
    if ($resolvedCwd) { Write-Host "  cwd: $resolvedCwd" -ForegroundColor DarkCyan }
} elseif (-not $resolvedId) {
    Write-Host "No named session found for '$session', opening picker..." -ForegroundColor Yellow
    $resolvedId = $session
}

$origLocation = Get-Location
if ($resolvedCwd -and (Test-Path $resolvedCwd)) { Set-Location $resolvedCwd }

$cmd = $args_ -join ' '
try {
    if ($cmd) {
        claude --dangerously-skip-permissions --append-system-prompt $prompt --model $m --chrome --max-turns 200 --resume $resolvedId $cmd
    } else {
        claude --dangerously-skip-permissions --append-system-prompt $prompt --model $m --chrome --max-turns 200 --resume $resolvedId
    }
} finally {
    Set-Location $origLocation
}
