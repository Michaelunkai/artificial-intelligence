<#
.SYNOPSIS
    claude7
#>
Set-ClaudeResource -Model "haiku" -Thinking $false -MaxOutputTokens 3584 -BashTimeout 60000 -BashMaxTimeout 120000 -McpTimeout 6000 -CompactThreshold 0.23 -CompactBudget 23000 -Label "CLAUDE7 [H7] (23% ~46k)" -Color "Yellow"
