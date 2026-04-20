<#
.SYNOPSIS
    claude19
#>
Set-ClaudeResource -Model "sonnet" -Thinking $true -ThinkingBudget 12000 -MaxOutputTokens 13312 -BashTimeout 180000 -BashMaxTimeout 360000 -McpTimeout 26000 -CompactThreshold 0.59 -CompactBudget 59000 -Label "CLAUDE19 [S9+T] (59% ~118k)" -Color "Blue"
