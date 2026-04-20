<#
.SYNOPSIS
    claude14
#>
Set-ClaudeResource -Model "sonnet" -Thinking $false -MaxOutputTokens 8192 -BashTimeout 120000 -BashMaxTimeout 240000 -McpTimeout 16000 -CompactThreshold 0.44 -CompactBudget 44000 -Label "CLAUDE14 [S4] (44% ~88k)" -Color "Magenta"
