<#
.SYNOPSIS
    ultrathink
#>
[Environment]::SetEnvironmentVariable('MAX_THINKING_TOKENS','100000','User'); $env:MAX_THINKING_TOKENS='100000'; Write-Host 'ULTRA THINKING ENABLED (MAX_THINKING_TOKENS=100000) - Restart Claude Code' -ForegroundColor Cyan
