<#
.SYNOPSIS
    claude26
#>
Set-ClaudeResource -Model "opus" -Thinking $true -ThinkingBudget 20000 -MaxOutputTokens 26624 -BashTimeout 250000 -BashMaxTimeout 500000 -McpTimeout 44000 -CompactThreshold 0.80 -CompactBudget 80000 -Label "CLAUDE26 [O6+T] (80% ~160k)" -Color "DarkCyan"
