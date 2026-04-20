<#
.SYNOPSIS
    claude5
#>
Set-ClaudeResource -Model "haiku" -Thinking $false -MaxOutputTokens 3072 -BashTimeout 50000 -BashMaxTimeout 100000 -McpTimeout 5000 -CompactThreshold 0.17 -CompactBudget 17000 -Label "CLAUDE5 [H5] (17% ~34k)" -Color "DarkGreen"
