# cclatest - Update and launch latest Claude Code
Write-Host "Updating Claude Code to latest..." -ForegroundColor Cyan
npm update -g @anthropic-ai/claude-code 2>$null
claude @args