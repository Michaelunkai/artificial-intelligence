<#
.SYNOPSIS
    claude20
#>
Set-ClaudeResource -Model "sonnet" -Thinking $true -ThinkingBudget 15000 -MaxOutputTokens 14336 -BashTimeout 190000 -BashMaxTimeout 380000 -McpTimeout 28000 -CompactThreshold 0.62 -CompactBudget 62000 -Label "CLAUDE20 [S10+T] (62% ~124k)" -Color "Blue"
