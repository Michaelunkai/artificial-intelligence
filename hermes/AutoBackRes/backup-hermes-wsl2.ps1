param(
  [string]$Distro = 'ubuntu',
  [string]$BackupRoot = (Join-Path $PSScriptRoot 'backups'),
  [switch]$NoRestartGateway,
  [switch]$RestartGateway
)

$ErrorActionPreference = 'Stop'

function Write-Log {
  param([string]$Message)
  $line = '[{0}] {1}' -f (Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'), $Message
  Write-Host $line
  if ($script:LogFile) { Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8 }
}

function ConvertTo-WslPath {
  param([Parameter(Mandatory = $true)][string]$WindowsPath)
  $full = [System.IO.Path]::GetFullPath($WindowsPath)
  if ($full -notmatch '^([A-Za-z]):\\(.*)$') {
    throw "Cannot convert path to WSL /mnt path: $WindowsPath"
  }
  $drive = $matches[1].ToLowerInvariant()
  $rest = $matches[2].Replace('\', '/')
  return "/mnt/$drive/$rest"
}

function Write-LinuxScript {
  param(
    [Parameter(Mandatory = $true)][string]$Path,
    [Parameter(Mandatory = $true)][string]$Body
  )
  $lf = $Body -replace "`r`n", "`n"
  $lf = $lf -replace "`r", "`n"
  [System.IO.File]::WriteAllText($Path, $lf, [System.Text.Encoding]::ASCII)
}

function Get-Sha256Hex {
  param([Parameter(Mandatory = $true)][string]$Path)
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

function Get-WindowsToolFileNames {
  return @(
    'a.sh',
    'backup-hermes-wsl2.ps1',
    'build-HermesTray.ps1',
    'enable-windows-startup.ps1',
    'hermes-command-guard.sh',
    'hermes-gateway-process-check.sh',
    'hermes-tray-health.sh',
    'HermesDashboard.html',
    'HermesTray.cs',
    'HermesTray.exe',
    'parse-and-validate-check.ps1',
    'purge-backups-fast.ps1',
    'README.md',
    'restore-hermes-wsl2.ps1',
    'resume.sh',
    'run-hermes-wsl2-gateway.ps1',
    'run-HermesTray.ps1'
  )
}

function Backup-WindowsToolFiles {
  $toolBackupDir = Join-Path $script:BackupDir 'windows-tool-files'
  New-Item -ItemType Directory -Path $toolBackupDir -Force | Out-Null
  $copied = @()
  foreach ($name in Get-WindowsToolFileNames) {
    $source = Join-Path $PSScriptRoot $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) { continue }
    Copy-Item -LiteralPath $source -Destination (Join-Path $toolBackupDir $name) -Force
    $copied += $name
  }
  $copied | Set-Content -LiteralPath (Join-Path $toolBackupDir 'windows-tool-files.txt') -Encoding UTF8
  Write-Log ("Backed up Windows-side AutoBackRes tool files: {0}" -f ($copied -join ', '))
  return $copied
}

function Add-NativeOutputToLog {
  param([Parameter(Mandatory = $true)][string]$Path)
  if (-not $script:LogFile) { return }
  if (-not (Test-Path -LiteralPath $Path)) { return }
  Get-Content -LiteralPath $Path | ForEach-Object {
    Add-Content -LiteralPath $script:LogFile -Value $_ -Encoding UTF8
  }
}

function Invoke-Native {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [string]$Label = $FilePath,
    [switch]$AllowNonZero
  )
  Write-Log ("+ {0} {1}" -f $FilePath, ($Arguments -join ' '))
  $stdout = [System.IO.Path]::GetTempFileName()
  $stderr = [System.IO.Path]::GetTempFileName()
  $oldEap = $ErrorActionPreference
  try {
    $script:ErrorActionPreference = 'Continue'
    $ErrorActionPreference = 'Continue'
    & $FilePath @Arguments > $stdout 2> $stderr
    $code = $LASTEXITCODE
  } finally {
    $script:ErrorActionPreference = $oldEap
    $ErrorActionPreference = $oldEap
  }
  try {
    Add-NativeOutputToLog -Path $stdout
    Add-NativeOutputToLog -Path $stderr
    if ($code -ne 0 -and -not $AllowNonZero) {
      throw "$Label exited with code $code"
    }
  } finally {
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
  }
  return $code
}

function Invoke-NativeWithStandardInput {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$StandardInputText,
    [string]$Label = $FilePath,
    [int]$TimeoutSeconds = 1800
  )
  Write-Log ("+ {0} {1} <stdin>" -f $FilePath, ($Arguments -join ' '))
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = $FilePath
  $psi.Arguments = (($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' ')
  $psi.WorkingDirectory = $env:SystemRoot
  $psi.UseShellExecute = $false
  $psi.RedirectStandardInput = $true
  $psi.RedirectStandardOutput = $false
  $psi.RedirectStandardError = $false
  $proc = New-Object System.Diagnostics.Process
  $proc.StartInfo = $psi
  if (-not $proc.Start()) { throw "Failed to start $Label" }
  $stdinText = $StandardInputText.Replace([string][char]0xFEFF, '')
  $stdinBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($stdinText)
  $proc.StandardInput.BaseStream.Write($stdinBytes, 0, $stdinBytes.Length)
  $proc.StandardInput.Close()
  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    throw "$Label timed out after $TimeoutSeconds seconds; native process was not force-stopped to avoid interrupting live Hermes work"
  }
  $code = [int]$proc.ExitCode
  if ($code -ne 0) { throw "$Label exited with code $code" }
  return $code
}

function Quote-NativeArgument {
  param([string]$Argument)
  if ($null -eq $Argument) { return '""' }
  if ($Argument -notmatch '[\s"]') { return $Argument }
  return '"' + ($Argument -replace '"', '\"') + '"'
}

function Invoke-NativeUntilDone {
  param(
    [Parameter(Mandatory = $true)][string]$FilePath,
    [Parameter(Mandatory = $true)][string[]]$Arguments,
    [Parameter(Mandatory = $true)][string]$DoneFile,
    [string]$Label = $FilePath,
    [int]$TimeoutSeconds = 1800
  )
  Write-Log ("+ {0} {1}" -f $FilePath, ($Arguments -join ' '))
  Remove-Item -LiteralPath $DoneFile -Force -ErrorAction SilentlyContinue
  $stdout = [System.IO.Path]::GetTempFileName()
  $stderr = [System.IO.Path]::GetTempFileName()
  $argLine = ($Arguments | ForEach-Object { Quote-NativeArgument $_ }) -join ' '
  try {
    $proc = Start-Process -FilePath $FilePath -ArgumentList $argLine -NoNewWindow -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
    $deadline = (Get-Date).AddSeconds($TimeoutSeconds)
    while ($true) {
      if (Test-Path -LiteralPath $DoneFile -PathType Leaf) { break }
      $proc.Refresh()
      if ($proc.HasExited) { break }
      if ((Get-Date) -gt $deadline) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
        throw "$Label timed out after $TimeoutSeconds seconds"
      }
      Start-Sleep -Seconds 1
    }
    if (Test-Path -LiteralPath $DoneFile -PathType Leaf) {
      $codeText = (Get-Content -LiteralPath $DoneFile -Raw).Trim()
      $code = [int]$codeText
      $proc.Refresh()
      if (-not $proc.HasExited) {
        Start-Sleep -Seconds 2
        $proc.Refresh()
      }
      if (-not $proc.HasExited) {
        Stop-Process -Id $proc.Id -Force -ErrorAction SilentlyContinue
      }
    } else {
      $proc.WaitForExit()
      $code = $proc.ExitCode
    }
    Add-NativeOutputToLog -Path $stdout
    Add-NativeOutputToLog -Path $stderr
    if ($code -ne 0) {
      throw "$Label exited with code $code"
    }
  } finally {
    Remove-Item -LiteralPath $stdout, $stderr -Force -ErrorAction SilentlyContinue
  }
}

function Invoke-HermesWslScript {
  param(
    [Parameter(Mandatory = $true)][string]$ScriptPath,
    [object[]]$WslArgs = $null
  )
  $scriptBody = Get-Content -LiteralPath $ScriptPath -Raw
  $scriptBody = ($scriptBody -replace "`r`n", "`n" -replace "`r", "`n") + "`n"
  $stdinBashRunner = "import subprocess,sys; data=sys.stdin.buffer.read(); data=data[3:] if data.startswith(b'\xef\xbb\xbf') else data; raise SystemExit(subprocess.run(['bash','-s','--']+sys.argv[2:], input=data).returncode)"
  $allArgs = @('-d', $Distro, '-u', 'root', '--cd', '/', '--', 'python3', '-c', $stdinBashRunner, '--') | Where-Object { $_ -ne '' }
  if ($null -ne $WslArgs) { $allArgs += @($WslArgs | ForEach-Object { [string]$_ } | Where-Object { $_ -ne '' }) }
  Invoke-NativeWithStandardInput -FilePath $script:WslExe -Arguments $allArgs -StandardInputText $scriptBody -Label 'wsl script'
}

function Start-HermesGateway {
  $resumePeer = Join-Path $PSScriptRoot 'resume.sh'
  if (Test-Path -LiteralPath $resumePeer -PathType Leaf) {
    Invoke-HermesWslScript -ScriptPath $resumePeer | Out-Null
    return
  }

  $scriptPath = Join-Path $script:BackupDir 'start-gateway.sh'
  Write-LinuxScript -Path $scriptPath -Body @'
set -euo pipefail
export PATH="/home/ubuntu/.local/bin:/home/ubuntu/.hermes/node/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/snap/bin"
if sudo -H -u ubuntu env PATH="$PATH" hermes gateway status >/tmp/hermes-gateway-status.txt 2>&1; then
  cat /tmp/hermes-gateway-status.txt
  exit 0
fi
if pgrep -u ubuntu -f "hermes gateway run" >/dev/null 2>&1; then
  cat /tmp/hermes-gateway-status.txt
  echo "Hermes gateway process is alive; refusing restart during backup." >&2
  exit 21
fi
sudo -H -u ubuntu tmux new-session -d -s hermes-gateway "cd /home/ubuntu && export PATH='$PATH' && exec hermes gateway run >>/home/ubuntu/.hermes/logs/gateway-run.log 2>&1"
sleep 8
sudo -H -u ubuntu env PATH="$PATH" hermes gateway status
sudo -H -u ubuntu env PATH="$PATH" hermes --version | head -20
grep -E "Connected to Telegram|Gateway running with 1 platform" /home/ubuntu/.hermes/logs/gateway.log | tail -10 || true
'@
  Invoke-HermesWslScript -ScriptPath $scriptPath | Out-Null
}

$script:WslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $script:WslExe -PathType Leaf)) { $script:WslExe = 'wsl.exe' }

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$script:BackupDir = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Path $script:BackupDir -Force | Out-Null
$script:LogFile = Join-Path $script:BackupDir 'backup.log'
New-Item -ItemType File -Path $script:LogFile -Force | Out-Null

$archive = Join-Path $script:BackupDir 'hermes-wsl-data.tar.gz'
$pathList = Join-Path $script:BackupDir 'hermes-wsl-data.paths.txt'
$summary = Join-Path $script:BackupDir 'hermes-wsl-data.summary.txt'
$statusBefore = Join-Path $script:BackupDir 'hermes-status-before.txt'
$statusAfter = Join-Path $script:BackupDir 'hermes-status-after.txt'
$manifest = Join-Path $script:BackupDir 'manifest.json'

Write-Log "Starting Hermes-only WSL2 backup into $script:BackupDir"
Write-Log "This backup contains Hermes secrets/auth data; keep it private."
Copy-Item -LiteralPath $PSCommandPath -Destination (Join-Path $script:BackupDir 'backup-hermes-wsl2.ps1') -Force
$restorePeer = Join-Path $PSScriptRoot 'restore-hermes-wsl2.ps1'
if (Test-Path -LiteralPath $restorePeer -PathType Leaf) {
  Copy-Item -LiteralPath $restorePeer -Destination (Join-Path $script:BackupDir 'restore-hermes-wsl2.ps1') -Force
}
$windowsToolFiles = Backup-WindowsToolFiles
Invoke-Native -FilePath $script:WslExe -Arguments @('-l', '-v') -Label 'wsl list' | Out-Null

$statusScript = Join-Path $script:BackupDir 'status-before.sh'
Write-LinuxScript -Path $statusScript -Body @'
set +e
export PATH="/home/ubuntu/.local/bin:/home/ubuntu/.hermes/node/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/snap/bin"
echo "== uname =="
uname -a
echo "== hermes version =="
sudo -H -u ubuntu env PATH="$PATH" hermes --version
echo "== gateway status =="
sudo -H -u ubuntu env PATH="$PATH" hermes gateway status
echo "== telegram log tail =="
tail -120 /home/ubuntu/.hermes/logs/gateway.log 2>/dev/null | grep -E "Connected to Telegram|Gateway running with" | tail -10
exit 0
'@
Invoke-HermesWslScript -ScriptPath $statusScript | Out-Null
Copy-Item -LiteralPath $script:LogFile -Destination $statusBefore -Force

$collectScript = Join-Path $script:BackupDir 'collect-hermes-data.sh'
Write-LinuxScript -Path $collectScript -Body @'
set -euo pipefail
archive="$1"
path_list="$2"
summary="$3"
sync
: > "$path_list"
for p in \
  home/ubuntu/.hermes \
  home/ubuntu/.codex \
  home/ubuntu/.config/hermes-setup \
  home/ubuntu/.config/uv \
  home/ubuntu/.local/bin/hermes \
  home/ubuntu/.local/bin/node \
  home/ubuntu/.local/bin/npm \
  home/ubuntu/.local/bin/npx \
  home/ubuntu/.local/bin/corepack \
  home/ubuntu/.local/bin/uv \
  home/ubuntu/.local/bin/uvx \
  home/ubuntu/.local/state/hermes \
  home/ubuntu/.local/share/uv \
  home/ubuntu/.cache/ms-playwright \
  home/ubuntu/.cache/uv \
  home/ubuntu/.bashrc \
  home/ubuntu/.profile \
  home/ubuntu/.bash_profile
do
  if [ -e "/$p" ]; then
    echo "$p" >> "$path_list"
  fi
done
if [ ! -s "$path_list" ]; then
  echo "No Hermes WSL data paths found" >&2
  exit 20
fi
{
  echo "== hermes-only archive path list =="
  cat "$path_list"
  echo "== selected sizes =="
  du -sh \
    /home/ubuntu/.hermes \
    /home/ubuntu/.codex \
    /home/ubuntu/.config/hermes-setup \
    /home/ubuntu/.config/uv \
    /home/ubuntu/.local/bin/hermes \
    /home/ubuntu/.local/bin/node \
    /home/ubuntu/.local/bin/npm \
    /home/ubuntu/.local/bin/npx \
    /home/ubuntu/.local/bin/corepack \
    /home/ubuntu/.local/bin/uv \
    /home/ubuntu/.local/bin/uvx \
    /home/ubuntu/.local/state/hermes \
    /home/ubuntu/.local/share/uv \
    /home/ubuntu/.cache/ms-playwright \
    /home/ubuntu/.cache/uv \
    /home/ubuntu/.bashrc \
    /home/ubuntu/.profile \
    /home/ubuntu/.bash_profile 2>/dev/null || true
} > "$summary"
tar_code=0
tar --xattrs --acls --numeric-owner --hard-dereference --ignore-failed-read --warning=no-file-changed \
  --exclude='home/ubuntu/.hermes/gateway.lock' \
  --exclude='home/ubuntu/.hermes/gateway.pid' \
  -C / -czpf "$archive" -T "$path_list" || tar_code=$?
if [ "$tar_code" -gt 1 ]; then
  echo "tar failed with fatal exit code: $tar_code" >&2
  exit "$tar_code"
fi
if [ ! -s "$archive" ]; then
  echo "tar produced an empty or missing archive" >&2
  exit 60
fi
sync
'@
Invoke-HermesWslScript -ScriptPath $collectScript -WslArgs @((ConvertTo-WslPath $archive), (ConvertTo-WslPath $pathList), (ConvertTo-WslPath $summary)) | Out-Null

$validateScript = Join-Path $script:BackupDir 'validate-hermes-archive.sh'
Write-LinuxScript -Path $validateScript -Body @'
set -euo pipefail
archive="$1"
path_list="$2"
listing="$(mktemp)"
trap 'rm -f "$listing"' EXIT
tar -tzf "$archive" > "$listing"
missing=0
while IFS= read -r p; do
  [ -n "$p" ] || continue
  if ! grep -Fx -- "$p" "$listing" >/dev/null \
    && ! grep -Fx -- "$p/" "$listing" >/dev/null \
    && ! grep -F -- "$p/" "$listing" >/dev/null; then
    echo "Archive missing expected path: $p" >&2
    missing=1
  fi
done < "$path_list"
if [ "$missing" -ne 0 ]; then
  exit 50
fi
echo "Archive integrity and path coverage verified: $(wc -l < "$listing") entries"
'@
Invoke-HermesWslScript -ScriptPath $validateScript -WslArgs @((ConvertTo-WslPath $archive), (ConvertTo-WslPath $pathList)) | Out-Null

if ($RestartGateway -and -not $NoRestartGateway) {
  Write-Log "Restarting/resuming Hermes gateway after Hermes-only backup because -RestartGateway was set"
  Start-HermesGateway
  Copy-Item -LiteralPath $script:LogFile -Destination $statusAfter -Force
} else {
  Write-Log "Leaving Hermes gateway untouched after backup"
}

$archiveHash = Get-Sha256Hex -Path $archive
$manifestObj = [ordered]@{
  created_at = (Get-Date).ToString('o')
  distro = $Distro
  backup_dir = $script:BackupDir
  backup_kind = 'hermes-wsl-data-only'
  archive = (Split-Path -Leaf $archive)
  archive_sha256 = $archiveHash
  archive_bytes = (Get-Item -LiteralPath $archive).Length
  restore_script = 'restore-hermes-wsl2.ps1'
  includes = @(
    '/home/ubuntu/.hermes',
    '/home/ubuntu/.codex',
    '/home/ubuntu/.config/hermes-setup',
    '/home/ubuntu/.config/uv',
    '/home/ubuntu/.local/bin/hermes',
    '/home/ubuntu/.local/bin/node',
    '/home/ubuntu/.local/bin/npm',
    '/home/ubuntu/.local/bin/npx',
    '/home/ubuntu/.local/bin/corepack',
    '/home/ubuntu/.local/bin/uv',
    '/home/ubuntu/.local/bin/uvx',
    '/home/ubuntu/.local/state/hermes',
    '/home/ubuntu/.local/share/uv',
    '/home/ubuntu/.cache/ms-playwright',
    '/home/ubuntu/.cache/uv',
    '/home/ubuntu/.bashrc',
    '/home/ubuntu/.profile',
    '/home/ubuntu/.bash_profile'
  )
  windows_side_files = @($windowsToolFiles)
  excludes = @('full Ubuntu WSL distro export', 'Windows-side WSL import directory', 'Windows profile functions', 'Hermes setup installer script')
}
$manifestObj | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $manifest -Encoding UTF8
$stamp | Set-Content -LiteralPath (Join-Path $BackupRoot 'LATEST.txt') -Encoding ASCII

Write-Log "Hermes-only backup complete"
Write-Host "BACKUP_ID=$stamp"
Write-Host "BACKUP_DIR=$script:BackupDir"
Write-Host "HERMES_ARCHIVE=$archive"
Write-Host "MANIFEST=$manifest"
