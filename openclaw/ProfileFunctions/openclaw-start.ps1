# openclaw-start - Start OpenClaw gateway and ClawdBot tray
$vbs = 'C:\Users\micha\.openclaw\ClawdBot\ClawdbotTray.vbs'
Write-Host 'Starting OpenClaw...' -ForegroundColor Cyan
if (Test-Path $vbs) { Start-Process wscript.exe -ArgumentList "`"$vbs`"" -WindowStyle Hidden }
$restart = 'C:\Users\micha\.openclaw\scripts\openclaw-restart.ps1'
if (Test-Path $restart) { & powershell -NoProfile -NonInteractive -File $restart }
Write-Host 'OpenClaw started' -ForegroundColor Green
