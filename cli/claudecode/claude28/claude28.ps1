<#
.SYNOPSIS
    claude28
#>
Set-ClaudeResource -Model "opus" -Thinking $true -ThinkingBudget 30000 -MaxOutputTokens 30720 -BashTimeout 270000 -BashMaxTimeout 540000 -McpTimeout 52000 -CompactThreshold 0.86 -CompactBudget 86000 -Label "CLAUDE28 [O8+T] (86% ~172k)" -Color "White"
