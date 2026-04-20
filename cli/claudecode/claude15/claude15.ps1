<#
.SYNOPSIS
    claude15
#>
Set-ClaudeResource -Model "sonnet" -Thinking $false -MaxOutputTokens 9216 -BashTimeout 130000 -BashMaxTimeout 260000 -McpTimeout 18000 -CompactThreshold 0.47 -CompactBudget 47000 -Label "CLAUDE15 [S5] (47% ~94k)" -Color "Magenta"
