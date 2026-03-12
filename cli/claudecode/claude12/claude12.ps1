<#
.SYNOPSIS
    claude12
#>
Set-ClaudeResource -Model "sonnet" -Thinking $false -MaxOutputTokens 6144 -BashTimeout 100000 -BashMaxTimeout 200000 -McpTimeout 12000 -CompactThreshold 0.38 -CompactBudget 38000 -Label "CLAUDE12 [S2] (38% ~76k)" -Color "DarkYellow"
