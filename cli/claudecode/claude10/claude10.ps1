<#
.SYNOPSIS
    claude10
#>
Set-ClaudeResource -Model "haiku" -Thinking $false -MaxOutputTokens 4352 -BashTimeout 75000 -BashMaxTimeout 150000 -McpTimeout 7500 -CompactThreshold 0.32 -CompactBudget 32000 -Label "CLAUDE10 [H10] (32% ~64k)" -Color "DarkYellow"
