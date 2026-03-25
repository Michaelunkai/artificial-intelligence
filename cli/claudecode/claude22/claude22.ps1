<#
.SYNOPSIS
    claude22
#>
Set-ClaudeResource -Model "opus" -Thinking $false -MaxOutputTokens 18432 -BashTimeout 210000 -BashMaxTimeout 420000 -McpTimeout 32000 -CompactThreshold 0.68 -CompactBudget 68000 -Label "CLAUDE22 [O2] (68% ~136k)" -Color "DarkBlue"
