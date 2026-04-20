<#
.SYNOPSIS
    claude17
#>
Set-ClaudeResource -Model "sonnet" -Thinking $true -ThinkingBudget 8000 -MaxOutputTokens 11264 -BashTimeout 160000 -BashMaxTimeout 320000 -McpTimeout 22000 -CompactThreshold 0.53 -CompactBudget 53000 -Label "CLAUDE17 [S7+T] (53% ~106k)" -Color "DarkMagenta"
