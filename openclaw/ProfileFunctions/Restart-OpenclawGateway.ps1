# Restart-OpenclawGateway - Full OpenClaw gateway restart
$restart = 'C:\Users\micha\.openclaw\scripts\openclaw-restart.ps1'
if (Test-Path $restart) {
    Write-Host 'Restarting OpenClaw gateway...' -ForegroundColor Cyan
    & $restart
    Write-Host 'Gateway restarted' -ForegroundColor Green
} else { Write-Warning "openclaw-restart.ps1 not found at $restart" }
