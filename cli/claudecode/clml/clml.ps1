# clml - Show current Claude model configuration
$s = 'C:\Users\micha\.claude\settings.json'
if (-not (Test-Path $s)) { Write-Host "settings.json not found" -ForegroundColor Red; return }
$j = Get-Content $s -Raw | ConvertFrom-Json
Write-Host "=== Claude Code Configuration ===" -ForegroundColor Cyan
Write-Host "  Model:     $($j.model)" -ForegroundColor White
if ($j.thinking) { Write-Host "  Thinking:  enabled=$($j.thinking.enabled) budget=$($j.thinking.budgetTokens)" -ForegroundColor White }
if ($j.env) {
    Write-Host "  Output:    $($j.env.CLAUDE_CODE_MAX_OUTPUT_TOKENS)" -ForegroundColor Gray
    Write-Host "  BashTO:    $($j.env.BASH_DEFAULT_TIMEOUT_MS)ms" -ForegroundColor Gray
    Write-Host "  McpTO:     $($j.env.MCP_TOOL_TIMEOUT)ms" -ForegroundColor Gray
}
if ($j.autoCompact) { Write-Host "  Compact:   threshold=$($j.autoCompact.threshold) budget=$($j.autoCompact.budgetTokens)" -ForegroundColor Gray }