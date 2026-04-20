<#
.SYNOPSIS
    cclu - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
$killed=0; Get-Process -Name 'claude','anthropic*','AnthropicClaude' -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; $killed++ }; Get-Process | Where-Object { $_.Path -match 'claude|anthropic' } -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue; $killed++ }; if($killed -gt 0){ Write-Host "Killed $killed Claude Code process(es)" -ForegroundColor Green }else{ Write-Host "No Claude Code processes found" -ForegroundColor Yellow }; & "$env:USERPROFILE\.claude\Start-Claude-Unrestricted.ps1" @args
