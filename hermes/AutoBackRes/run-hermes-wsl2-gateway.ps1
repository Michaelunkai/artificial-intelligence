$ErrorActionPreference = 'Stop'

$Root = Split-Path -Parent $PSCommandPath
$LogDir = Join-Path $Root 'logs'
New-Item -ItemType Directory -Path $LogDir -Force | Out-Null

$Stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$OutLog = Join-Path $LogDir "hermes-wsl2-gateway-$Stamp.out.log"
$ErrLog = Join-Path $LogDir "hermes-wsl2-gateway-$Stamp.err.log"
$CmdLog = Join-Path $LogDir "hermes-wsl2-gateway-$Stamp.command.txt"
$PidLog = Join-Path $LogDir "hermes-wsl2-gateway-$Stamp.pid.txt"

function ConvertTo-WslPath {
  param([Parameter(Mandatory = $true)][string]$WindowsPath)
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  $root = [System.IO.Path]::GetPathRoot($full)
  if ([string]::IsNullOrWhiteSpace($root) -or $root.Length -lt 2 -or $root[1] -ne ':') {
    throw "Cannot convert to WSL path: $WindowsPath"
  }
  $drive = [char]::ToLowerInvariant($root[0])
  $relative = $full.Substring($root.Length).Replace('\', '/')
  "/mnt/$drive/$relative"
}

$WslScript = ConvertTo-WslPath (Join-Path $Root 'a.sh')
$SetupCommand = ". `$PROFILE; rws; wsl -d ubuntu -- bash $WslScript"
$SetupCommand | Set-Content -LiteralPath $CmdLog -Encoding UTF8

$PowerShell5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
$Process = Start-Process -FilePath $PowerShell5 -ArgumentList @(
  '-NoLogo',
  '-NoProfile',
  '-ExecutionPolicy',
  'Bypass',
  '-Command',
  $SetupCommand
) -WorkingDirectory $Root -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog -WindowStyle Hidden -PassThru

"PID=$($Process.Id)" | Set-Content -LiteralPath $PidLog -Encoding ASCII
Write-Host "Started Hermes WSL2 setup as PID $($Process.Id)"
Write-Host "stdout=$OutLog"
Write-Host "stderr=$ErrLog"
exit 0
