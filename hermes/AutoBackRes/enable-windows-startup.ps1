param(
  [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

$TaskName = 'CustomStartup_HermesTray_064be82f'
$Root = Split-Path -Parent $PSCommandPath
$TrayExe = Join-Path $Root 'HermesTray.exe'
if (-not (Test-Path -LiteralPath $TrayExe -PathType Leaf)) {
  throw "Tray executable not found: $TrayExe"
}
$QuietLauncher = 'C:\Users\micha\.claude\scripts\trayquiet-start.vbs'
if (-not (Test-Path -LiteralPath $QuietLauncher -PathType Leaf)) {
  throw "Quiet tray launcher not found: $QuietLauncher"
}

$DelaySeconds = 30
$WindowStyle = 0
$RetrySeconds = 25

$WScript = Join-Path $env:SystemRoot 'System32\wscript.exe'
$Action = New-ScheduledTaskAction -Execute $WScript -Argument "//B //Nologo `"$QuietLauncher`" `"$TrayExe`" $DelaySeconds $WindowStyle $RetrySeconds" -WorkingDirectory $Root
$Trigger = New-ScheduledTaskTrigger -AtLogOn
$Settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew
$Identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
$Principal = New-ScheduledTaskPrincipal -UserId $Identity -LogonType Interactive -RunLevel Limited

Register-ScheduledTask -TaskName $TaskName -Action $Action -Trigger $Trigger -Settings $Settings -Principal $Principal -Force | Out-Null
Write-Host "Registered scheduled task '$TaskName' for $Identity"

if ($RunNow) {
  Start-ScheduledTask -TaskName $TaskName
  Write-Host "Started scheduled task '$TaskName'"
}
