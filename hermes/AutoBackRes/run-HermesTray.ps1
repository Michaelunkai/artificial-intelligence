param(
  [string]$Root = $PSScriptRoot,
  [switch]$WithSupervisor
)

$ErrorActionPreference = 'Stop'
$exe = Join-Path $Root 'HermesTray.exe'
$supervisor = Join-Path $Root 'HermesTraySupervisor.ps1'
if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
  throw "HermesTray.exe not found: $exe"
}

if ($WithSupervisor -and (Test-Path -LiteralPath $supervisor -PathType Leaf)) {
  Start-Process -FilePath (Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe') `
    -WindowStyle Hidden `
    -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $supervisor, '-EnableRelaunch')
}

$existing = Get-Process -Name HermesTray -ErrorAction SilentlyContinue |
  Where-Object { $_.Path -eq $exe } |
  Select-Object -First 1

if ($existing) {
  "HermesTray already running: PID=$($existing.Id)"
  return
}

$process = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
"HermesTray started: PID=$($process.Id)"
