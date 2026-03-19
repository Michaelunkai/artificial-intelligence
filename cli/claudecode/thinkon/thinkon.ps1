<#
.SYNOPSIS
    thinkon
#>
[Environment]::SetEnvironmentVariable('MAX_THINKING_TOKENS',$null,'User'); Remove-Item Env:MAX_THINKING_TOKENS -ErrorAction SilentlyContinue; Write-Host 'Thinking ENABLED (MAX_THINKING_TOKENS removed) - Restart Claude Code' -ForegroundColor Green
