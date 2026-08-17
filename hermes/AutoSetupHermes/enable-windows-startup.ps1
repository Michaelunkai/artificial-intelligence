param(
  [switch]$RunNow
)

$ErrorActionPreference = 'Stop'

$TaskName = 'Hermes WSL2 Gateway'
$Root = Split-Path -Parent $PSCommandPath
$RunScript = Join-Path $Root 'run-hermes-wsl2-gateway.ps1'
if (-not (Test-Path -LiteralPath $RunScript -PathType Leaf)) {
  throw "Launcher script not found: $RunScript"
}

$PowerShell5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Action = New-ScheduledTaskAction -Execute $PowerShell5 -Argument "-NoLogo -NoProfile -ExecutionPolicy Bypass -File `"$RunScript`"" -WorkingDirectory $Root
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
