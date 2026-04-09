# clau2 - Claude Code with auto-restart on crash
param([string]$Prompt)
$maxRetries = 5
for ($i = 1; $i -le $maxRetries; $i++) {
    Write-Host "Claude Code attempt $i/$maxRetries" -ForegroundColor Cyan
    try {
        if ($Prompt) { claude $Prompt } else { claude }
        break
    } catch {
        Write-Host "Claude crashed: $($_.Exception.Message)" -ForegroundColor Red
        if ($i -lt $maxRetries) {
            Write-Host "Restarting in 3s..." -ForegroundColor Yellow
            Start-Sleep -Seconds 3
        }
    }
}