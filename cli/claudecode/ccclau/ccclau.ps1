<#
.SYNOPSIS
    ccclau - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
Get-Process | Where-Object {$_.ProcessName -like "*claude*"} | Stop-Process -Force -ErrorAction SilentlyContinue; @("$env:USERPROFILE\.claude", "$env:USERPROFILE\.claude-code", "$env:USERPROFILE\.anthropic", "$env:LOCALAPPDATA\Claude", "$env:LOCALAPPDATA\claude-code", "$env:LOCALAPPDATA\Anthropic", "$env:APPDATA\Claude", "$env:APPDATA\claude-code", "$env:APPDATA\Anthropic", "$env:TEMP\claude*", "$env:LOCALAPPDATA\Temp\claude*", "$env:USERPROFILE\.config\claude", "$env:USERPROFILE\.config\anthropic", "$env:USERPROFILE\.cache\claude", "$env:USERPROFILE\.cache\anthropic", "$env:USERPROFILE\.npm\_npx", "$env:APPDATA\npm-cache") | ForEach-Object { if (Test-Path $_) { Remove-Item -Path $_ -Recurse -Force -ErrorAction SilentlyContinue } }; npm cache clean --force 2>$null; pip cache purge 2>$null; npm uninstall -g @anthropic-ai/claude-code 2>$null; pip uninstall -y claude-code anthropic 2>$null; npm cache verify 2>$null; npm install -g @anthropic-ai/claude-code 2>$null; Write-Host "Complete cache purge and reinstall finished!" -ForegroundColor Green
