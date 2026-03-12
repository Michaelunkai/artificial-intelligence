<#
.SYNOPSIS
    claudemin
#>
Set-ClaudeResource -Model "haiku" -Thinking $false -MaxOutputTokens 2048 -BashTimeout 30000 -BashMaxTimeout 60000 -McpTimeout 3000 -CompactThreshold 0.05 -CompactBudget 5000 -Label "CLAUDEMIN [H1] (5% ~10k)" -Color "Green"
