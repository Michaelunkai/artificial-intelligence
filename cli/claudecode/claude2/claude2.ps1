<#
.SYNOPSIS
    claude2
#>
Set-ClaudeResource -Model "sonnet" -Thinking $false -MaxOutputTokens 2560 -BashTimeout 40000 -BashMaxTimeout 80000 -McpTimeout 4000 -CompactThreshold 0.11 -CompactBudget 11000 -Label "CLAUDE3 [H3] (11% ~22k)" -Color "Green"
