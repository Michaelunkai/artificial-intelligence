<#
.SYNOPSIS
    claude27
#>
Set-ClaudeResource -Model "opus" -Thinking $true -ThinkingBudget 25000 -MaxOutputTokens 28672 -BashTimeout 260000 -BashMaxTimeout 520000 -McpTimeout 48000 -CompactThreshold 0.83 -CompactBudget 83000 -Label "CLAUDE27 [O7+T] (83% ~166k)" -Color "DarkCyan"
