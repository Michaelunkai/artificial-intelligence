<#
.SYNOPSIS
    claude6
#>
Set-ClaudeResource -Model "haiku" -Thinking $false -MaxOutputTokens 3328 -BashTimeout 55000 -BashMaxTimeout 110000 -McpTimeout 5500 -CompactThreshold 0.20 -CompactBudget 20000 -Label "CLAUDE6 [H6] (20% ~40k)" -Color "DarkGreen"
