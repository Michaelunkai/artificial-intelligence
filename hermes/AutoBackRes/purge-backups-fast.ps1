param(
  [string]$BackupsPath = (Join-Path $PSScriptRoot 'backups'),
  [switch]$PlanOnly
)

$ErrorActionPreference = 'Stop'

function Write-Log {
  param([string]$Message)
  Write-Host ('[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'), $Message)
}

$expected = [System.IO.Path]::GetFullPath((Join-Path $PSScriptRoot 'backups')).TrimEnd('\')
$target = [System.IO.Path]::GetFullPath($BackupsPath).TrimEnd('\')

if ($target -ine $expected) {
  throw "Refusing to purge unexpected path. Expected '$expected' but got '$target'."
}

if ($target -notmatch '\\hermes\\AutoBackRes\\backups$') {
  throw "Refusing to purge path outside Hermes AutoBackRes backups: $target"
}

Write-Log "Validating purge target $target"
New-Item -ItemType Directory -Path $target -Force | Out-Null
$resolved = (Resolve-Path -LiteralPath $target).ProviderPath.TrimEnd('\')
if ($resolved -ine $target) {
  throw "Resolved path mismatch. Refusing purge. Resolved '$resolved', target '$target'."
}

$items = Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue
$count = @($items).Count
if ($PlanOnly) {
  Write-Log "PLANONLY would purge $count top-level item(s) under $target"
  Write-Host "PLANONLY_PURGE_BACKUPS_PATH=$target"
  Write-Host "PLANONLY_PURGE_TOP_LEVEL_ITEMS=$count"
  return
}

Write-Log "Purging all children under $target"
$sw = [System.Diagnostics.Stopwatch]::StartNew()

foreach ($item in $items) {
  Remove-Item -LiteralPath $item.FullName -Recurse -Force -ErrorAction Stop
}

$sw.Stop()
$remaining = @(Get-ChildItem -LiteralPath $target -Force -ErrorAction SilentlyContinue).Count
if ($remaining -ne 0) {
  throw "Purge incomplete: $remaining item(s) remain in $target"
}

Write-Log "Purge complete. Removed $count top-level item(s) in $([math]::Round($sw.Elapsed.TotalSeconds, 2)) seconds."
Write-Host "PURGED_BACKUPS_PATH=$target"
Write-Host "PURGED_TOP_LEVEL_ITEMS=$count"
