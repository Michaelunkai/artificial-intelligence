# Register-ClawdBotStartup - Register ClawdBot to start on logon via Task Scheduler
param([switch]$Unregister)
$taskName = 'ClawdBotTray'
$vbs = 'C:\Users\micha\.openclaw\ClawdBot\ClawdbotTray.vbs'
if ($Unregister) {
    schtasks /delete /tn $taskName /f 2>$null
    Write-Host "Unregistered task: $taskName" -ForegroundColor Yellow
    return
}
schtasks /create /tn $taskName /tr "wscript.exe `"$vbs`"" /sc onlogon /ru $env:USERNAME /f 2>&1 | Out-Null
Write-Host "Registered ClawdBot startup task: $taskName" -ForegroundColor Green
