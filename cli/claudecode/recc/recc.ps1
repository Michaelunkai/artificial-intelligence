<#
.SYNOPSIS
    recc - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
cccclau; closecc; claude update; rmccc; Get-Process -Name node -ErrorAction SilentlyContinue | Where-Object { $_.Path -match 'openclaw|moltbot|clawdbot' } | Stop-Process -Force -ErrorAction SilentlyContinue; npm uninstall -g moltbot clawdbot; npm install -g openclaw@latest; npm list -g openclaw | Select-String 'openclaw@'; Write-Host 'OpenClaw updated successfully' -ForegroundColor Green; openclaw doctor --fix;  openclaw --version; claude --version
