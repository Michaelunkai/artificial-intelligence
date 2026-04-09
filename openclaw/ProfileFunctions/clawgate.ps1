# clawgate - Restart OpenClaw gateway
$restart = 'C:\Users\micha\.openclaw\scripts\openclaw-restart.ps1'
if (Test-Path $restart) {
    Write-Host 'Restarting OpenClaw gateway...' -ForegroundColor Cyan
    . $restart
} else { Write-Warning "openclaw-restart.ps1 not found at $restart" }
