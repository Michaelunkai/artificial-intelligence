<#
.SYNOPSIS
    claude4
#>
Set-ClaudeResource -Model "haiku" -Thinking $false -MaxOutputTokens 2816 -BashTimeout 45000 -BashMaxTimeout 90000 -McpTimeout 4500 -CompactThreshold 0.14 -CompactBudget 14000 -Label "CLAUDE4 [H4] (14% ~28k)" -Color "DarkGreen"
