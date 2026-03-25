<#
.SYNOPSIS
    claude16
#>
Set-ClaudeResource -Model "sonnet" -Thinking $true -ThinkingBudget 5000 -MaxOutputTokens 10240 -BashTimeout 150000 -BashMaxTimeout 300000 -McpTimeout 20000 -CompactThreshold 0.50 -CompactBudget 50000 -Label "CLAUDE16 [S6+T] (50% ~100k)" -Color "DarkMagenta"
