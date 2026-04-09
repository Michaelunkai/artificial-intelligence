# gclauded - Launch Claude Code with debug logging
$env:CLAUDE_CODE_DEBUG = "true"
$env:DEBUG = "claude:*"
Write-Host "Claude Code DEBUG mode" -ForegroundColor Yellow
claude @args
$env:CLAUDE_CODE_DEBUG = $null
$env:DEBUG = $null