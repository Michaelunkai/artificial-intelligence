<#
.SYNOPSIS
    claude29
#>
Set-ClaudeResource -Model "opus" -Thinking $true -ThinkingBudget 40000 -MaxOutputTokens 31744 -BashTimeout 280000 -BashMaxTimeout 560000 -McpTimeout 56000 -CompactThreshold 0.90 -CompactBudget 90000 -Label "CLAUDE29 [O9+T] (90% ~180k)" -Color "White"
