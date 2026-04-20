<#
.SYNOPSIS
    claude18
#>
Set-ClaudeResource -Model "sonnet" -Thinking $true -ThinkingBudget 10000 -MaxOutputTokens 12288 -BashTimeout 170000 -BashMaxTimeout 340000 -McpTimeout 24000 -CompactThreshold 0.56 -CompactBudget 56000 -Label "CLAUDE18 [S8+T] (56% ~112k)" -Color "DarkMagenta"
