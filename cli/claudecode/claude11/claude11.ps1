<#
.SYNOPSIS
    claude11
#>
Set-ClaudeResource -Model "sonnet" -Thinking $false -MaxOutputTokens 5120 -BashTimeout 90000 -BashMaxTimeout 180000 -McpTimeout 10000 -CompactThreshold 0.35 -CompactBudget 35000 -Label "CLAUDE11 [S1] (35% ~70k)" -Color "DarkYellow"
