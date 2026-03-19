<#
.SYNOPSIS
    cccontext
#>
param([string]$t="0.1", [int]$b=2000, [int]$m=1500)
    $f="$env:USERPROFILE\.claude\settings.json"
    if (!(Test-Path $f)) {
        New-Item -ItemType Directory -Path (Split-Path $f) -Force -EA SilentlyContinue | Out-Null
        '{"autoCompact":{"enabled":true,"threshold":0.1,"budgetTokens":2000},"compact":{"model":"claude-haiku-4-5-20251001","maxTokens":1500,"temperature":0.3},"env":{"MCP_TIMEOUT":"3000","CLAUDE_CODE_DISABLE_NONESSENTIAL_TRAFFIC":"1","DISABLE_NON_ESSENTIAL_MODEL_CALLS":"1"},"alwaysThinkingEnabled":false,"thinking":{"enabled":false}}' | Set-Content $f
    }
    $c = (gc $f -Raw) -replace '"threshold":\s*[0-9.]+', "`"threshold`": $t" -replace '"budgetTokens":\s*\d+', "`"budgetTokens`": $b" -replace '"maxTokens":\s*\d+', "`"maxTokens`": $m"
    $c | Set-Content $f
    $level = $MyInvocation.MyCommand.Name -replace '\D',''
    $triggers = [int]($t * $b)
    Write-Host "Level $level | Threshold: $t | Budget: $b | CompactMax: $m | Triggers: $triggers tokens" -ForegroundColor Green
