<#
.SYNOPSIS
    thinkoff
#>
[Environment]::SetEnvironmentVariable('MAX_THINKING_TOKENS','0','User'); $env:MAX_THINKING_TOKENS='0'; Write-Host 'Thinking DISABLED (MAX_THINKING_TOKENS=0) - Restart Claude Code' -ForegroundColor Yellow
