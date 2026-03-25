<#
.SYNOPSIS
    claude25
#>
Set-ClaudeResource -Model "opus" -Thinking $true -ThinkingBudget 15000 -MaxOutputTokens 24576 -BashTimeout 240000 -BashMaxTimeout 480000 -McpTimeout 40000 -CompactThreshold 0.77 -CompactBudget 77000 -Label "CLAUDE25 [O5+T] (77% ~154k)" -Color "DarkCyan"
