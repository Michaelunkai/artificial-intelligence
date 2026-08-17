
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new()
chcp 65001 > $null
$ErrorActionPreference = 'Stop'
function Get-Sha256HexCompat {
  param([Parameter(Mandatory=$true)][string]$Path)
  $sha = [System.Security.Cryptography.SHA256]::Create()
  $stream = [System.IO.File]::OpenRead($Path)
  try {
    $bytes = $sha.ComputeHash($stream)
    return (($bytes | ForEach-Object { $_.ToString('x2') }) -join '').ToUpperInvariant()
  } finally {
    $stream.Dispose()
    $sha.Dispose()
  }
}
$base = Split-Path -Parent $MyInvocation.MyCommand.Path
$files = @('backup-hermes-wsl2.ps1','restore-hermes-wsl2.ps1')
foreach ($name in $files) {
  $path = Join-Path $base $name
  $tokens = $null
  $errors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors) | Out-Null
  if ($errors.Count -gt 0) {
    Write-Output "PARSE_FAIL $path"
    $errors | ForEach-Object { Write-Output $_.ToString() }
    exit 10
  }
  $hash = Get-Sha256HexCompat -Path $path
  $len = (Get-Item -LiteralPath $path).Length
  Write-Output "PARSE_OK $name bytes=$len sha256=$hash"
}
Write-Output 'RUN_VALIDATE_ONLY_BEGIN'
& (Join-Path $base 'restore-hermes-wsl2.ps1') -ValidateOnly -NoTelegramProbe
$code = $LASTEXITCODE
Write-Output "RUN_VALIDATE_ONLY_EXIT=$code"
