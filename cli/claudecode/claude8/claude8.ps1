<#
.SYNOPSIS
    claude8
#>
Set-ClaudeResource -Model "haiku" -Thinking $false -MaxOutputTokens 3840 -BashTimeout 65000 -BashMaxTimeout 130000 -McpTimeout 6500 -CompactThreshold 0.26 -CompactBudget 26000 -Label "CLAUDE8 [H8] (26% ~52k)" -Color "Yellow"
