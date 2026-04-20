<#
.SYNOPSIS
    claude21
#>
Set-ClaudeResource -Model "opus" -Thinking $false -MaxOutputTokens 16384 -BashTimeout 200000 -BashMaxTimeout 400000 -McpTimeout 30000 -CompactThreshold 0.65 -CompactBudget 65000 -Label "CLAUDE21 [O1] (65% ~130k)" -Color "Blue"
