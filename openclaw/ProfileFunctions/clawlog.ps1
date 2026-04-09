# clawlog - Show recent OpenClaw logs
param([int]$Lines = 20)
@(
    'C:\Users\micha\.openclaw\channels\channel.log',
    'C:\Users\micha\.openclaw\channels\tg-debug.log',
    'C:\Users\micha\.openclaw\channels\claude-debug.log'
) | Where-Object { Test-Path $_ } | ForEach-Object {
    Write-Host "=== $_ ===" -ForegroundColor Cyan
    Get-Content $_ -Tail $Lines
}
