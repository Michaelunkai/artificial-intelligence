<#
.SYNOPSIS
    claude30
#>
Set-ClaudeResource -Model "opus" -Thinking $true -ThinkingBudget 50000 -MaxOutputTokens 32768 -BashTimeout 300000 -BashMaxTimeout 600000 -McpTimeout 60000 -CompactThreshold 0.95 -CompactBudget 95000 -Label "CLAUDE30 [O10+T] (95% ~190k)" -Color "Cyan"
