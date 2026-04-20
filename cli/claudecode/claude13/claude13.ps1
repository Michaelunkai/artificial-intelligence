<#
.SYNOPSIS
    claude13
#>
Set-ClaudeResource -Model "sonnet" -Thinking $false -MaxOutputTokens 7168 -BashTimeout 110000 -BashMaxTimeout 220000 -McpTimeout 14000 -CompactThreshold 0.41 -CompactBudget 41000 -Label "CLAUDE13 [S3] (41% ~82k)" -Color "Magenta"
