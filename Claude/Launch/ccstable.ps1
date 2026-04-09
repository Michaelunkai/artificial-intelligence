# ccstable - Launch stable Claude Code version
$stable = (npm list -g @anthropic-ai/claude-code 2>$null | Select-String 'claude-code@' | ForEach-Object { $_ -replace '.*@','@anthropic-ai/claude-code@' })
if ($stable) { Write-Host "Stable: $stable" -ForegroundColor Green }
claude @args