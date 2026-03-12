<#
.SYNOPSIS
    claudesize
#>
Write-Host "`n=== CLAUDE CODE RESOURCE SETTINGS ===" -ForegroundColor Cyan
    $settingsPath = "C:\Users\micha\.claude\settings.json"
    if (Test-Path $settingsPath) {
        try {
            $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
            $model = if ($settings.model) { $settings.model } else { "default" }
            $thinking = if ($settings.thinking.enabled) { "ON" } else { "OFF" }
            $thinkBudget = if ($settings.thinking.budgetTokens) { $settings.thinking.budgetTokens } else { "N/A" }
            $outTokens = if ($settings.env.CLAUDE_CODE_MAX_OUTPUT_TOKENS) { $settings.env.CLAUDE_CODE_MAX_OUTPUT_TOKENS } else { "default" }
            $bashTO = if ($settings.env.BASH_DEFAULT_TIMEOUT_MS) { [math]::Round([int]$settings.env.BASH_DEFAULT_TIMEOUT_MS / 1000) } else { "default" }
            $mcpTO = if ($settings.env.MCP_TOOL_TIMEOUT) { [math]::Round([int]$settings.env.MCP_TOOL_TIMEOUT / 1000) } else { "default" }
            $compactThr = if ($settings.autoCompact.threshold) { $settings.autoCompact.threshold } else { "default" }
            $compactBudget = if ($settings.autoCompact.budgetTokens) { $settings.autoCompact.budgetTokens } else { "default" }
            $maxCtx = 200000
            $ctxPct = if ($compactThr -ne "default") { [math]::Round($compactThr * 100) } else { "?" }
            $ctxTokens = if ($compactThr -ne "default") { [math]::Round($compactThr * $maxCtx / 1000) } else { "?" }
            Write-Host "[MODEL] $model" -ForegroundColor $(switch($model){"haiku"{"Green"}"sonnet"{"Yellow"}"opus"{"Cyan"}default{"Gray"}})
            Write-Host "[THINKING] $thinking$(if($thinking -eq 'ON'){" (budget: $thinkBudget)"})" -ForegroundColor $(if($thinking -eq 'ON'){"Magenta"}else{"Gray"})
            Write-Host "[OUTPUT] $outTokens tokens max" -ForegroundColor Yellow
            Write-Host "[TIMEOUTS] Bash: ${bashTO}s | MCP: ${mcpTO}s" -ForegroundColor DarkGray
            Write-Host "[CONTEXT] ${ctxPct}% threshold (~${ctxTokens}k tokens) | budget: $compactBudget" -ForegroundColor Cyan
        } catch {
            Write-Host "ERROR reading settings: $($_.Exception.Message)" -ForegroundColor Red
        }
    } else {
        Write-Host "settings.json not found" -ForegroundColor Red
    }
    Write-Host "[TIERS] 30 levels: min/1-10=haiku | 11-20=sonnet | 21-30/max=opus" -ForegroundColor DarkCyan
    Write-Host "[THINK] sonnet(16-20) | opus(25-30)" -ForegroundColor DarkGray
    Write-Host ""
