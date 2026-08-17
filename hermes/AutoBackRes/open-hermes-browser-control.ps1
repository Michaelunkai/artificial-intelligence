param(
  [string]$Distro = "Ubuntu",
  [string]$WslUser = "ubuntu",
  [string]$BrowserDocsUrl = "https://hermes-agent.nousresearch.com/docs/user-guide/features/browser",
  [string]$OpenUrlScript = "/home/ubuntu/.hermes/scripts/open_url_on_second_monitor.sh"
)

$ErrorActionPreference = 'Stop'

function Quote-Bash([string]$Value) {
  return "'" + ($Value -replace "'", "'`"'`"'") + "'"
}

$wsl = Join-Path $env:WINDIR 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $wsl -PathType Leaf)) { $wsl = 'wsl.exe' }

Write-Host "Hermes Browser Control launcher"
Write-Host "URL: $BrowserDocsUrl"
Write-Host "Policy: opens the latest Hermes Browser feature docs in real Windows Chrome Profile 2 on monitor 2, then prints the live installed browser-control surface. No cloned/sandbox --user-data-dir."

$script = @"
set -Eeuo pipefail
OPEN_URL_SCRIPT=$(Quote-Bash $OpenUrlScript)
BROWSER_DOCS_URL=$(Quote-Bash $BrowserDocsUrl)
[ -x "`$OPEN_URL_SCRIPT" ] || { echo "ERROR: opener missing/not executable: `$OPEN_URL_SCRIPT" >&2; exit 14; }
if command -v hermes >/dev/null 2>&1; then
  hermes version | sed -n '1,8p'
  echo "--- Browser tool/config surface ---"
  hermes tools list 2>/dev/null | grep -Ei 'browser|computer|mcp|windows' || true
  hermes config 2>/dev/null | grep -Ei 'browser|cdp|camofox|browserbase|mcp_servers|winremote|windows_mcp' | sed -n '1,80p' || true
fi
curl -fsSI --max-time 10 "`$BROWSER_DOCS_URL" | sed -n '1,8p'
"@
$script += "`n"
$script += "`"$OpenUrlScript`" `"$BrowserDocsUrl`"`n"

$tmp = Join-Path $PSScriptRoot (".open-hermes-browser-control.$PID.sh")
try {
  $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
  [System.IO.File]::WriteAllText($tmp, $script, $utf8NoBom)
  if ($tmp -notmatch '^([A-Za-z]):\\(.*)$') {
    throw "Cannot convert temp script path to WSL path: $tmp"
  }
  $drive = $Matches[1].ToLowerInvariant()
  $rest = '/' + ($Matches[2] -replace '\\', '/')
  $wslPath = "/mnt/$drive$rest"
  & $wsl -d $Distro -u $WslUser -- bash $wslPath
  if ($LASTEXITCODE -ne 0) {
    throw "WSL command failed with exit code $LASTEXITCODE"
  }
} finally {
  Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
}
