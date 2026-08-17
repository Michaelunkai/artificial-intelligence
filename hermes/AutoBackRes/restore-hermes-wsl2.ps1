param(
  [string]$BackupId = 'latest',
  [string]$Distro = 'ubuntu',
  [string]$BackupRoot = (Join-Path $PSScriptRoot 'backups'),
  [switch]$NoTelegramProbe,
  [switch]$ValidateOnly,
  [switch]$SlashCommandsOnly
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

function Get-BackedUpWindowsToolFiles {
  $toolBackupDir = Join-Path $backupDir 'windows-tool-files'
  if (-not (Test-Path -LiteralPath $toolBackupDir -PathType Container)) {
    return @()
  }
  $listPath = Join-Path $toolBackupDir 'windows-tool-files.txt'
  if (Test-Path -LiteralPath $listPath -PathType Leaf) {
    return @(Get-Content -LiteralPath $listPath | Where-Object { $_ -and $_.Trim() })
  }
  return @(Get-ChildItem -LiteralPath $toolBackupDir -File | Where-Object { $_.Name -ne 'windows-tool-files.txt' } | Select-Object -ExpandProperty Name)
}

function Stop-RunningTrayForRestore {
  param([Parameter(Mandatory = $true)][string]$TargetExe)
  $running = @()
  Get-Process -Name 'HermesTray' -ErrorAction SilentlyContinue | ForEach-Object {
    $path = $null
    try { $path = $_.Path } catch { $path = $null }
    if ($path -and ([System.IO.Path]::GetFullPath($path) -ieq [System.IO.Path]::GetFullPath($TargetExe))) {
      $running += $_.Id
    }
  }
  if ($running.Count -gt 0) {
    Write-Log ("HermesTray.exe is running and will not be force-stopped during restore; keeping live executable. pids={0}" -f ($running -join ','))
  }
  return $false
}

function Restore-WindowsToolFiles {
  param([switch]$Validate)
  $toolBackupDir = Join-Path $backupDir 'windows-tool-files'
  if (-not (Test-Path -LiteralPath $toolBackupDir -PathType Container)) {
    Write-Log "No Windows-side AutoBackRes tool-file backup found in this backup; treating as legacy backup"
    return
  }

  $names = @(Get-BackedUpWindowsToolFiles)
  if ($names.Count -eq 0) {
    throw "Windows-side tool-file backup is present but empty: $toolBackupDir"
  }

  foreach ($name in $names) {
    if ($name -match '[\\/:]' -or $name -eq '.' -or $name -eq '..') {
      throw "Refusing unsafe Windows-side tool-file name from backup: $name"
    }
    $source = Join-Path $toolBackupDir $name
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
      throw "Missing Windows-side tool-file backup item: $source"
    }
  }

  if ($Validate) {
    Write-Log ("Windows-side AutoBackRes tool-file backup validated: {0}" -f ($names -join ', '))
    return
  }

  $relaunchTray = $false
  foreach ($name in $names) {
    $source = Join-Path $toolBackupDir $name
    $target = Join-Path $PSScriptRoot $name
    if ($name -ieq 'HermesTray.exe') {
      if (Stop-RunningTrayForRestore -TargetExe $target) { $relaunchTray = $true }
      if (Get-Process -Name 'HermesTray' -ErrorAction SilentlyContinue | Where-Object { try { $_.Path -and ([System.IO.Path]::GetFullPath($_.Path) -ieq [System.IO.Path]::GetFullPath($target)) } catch { $false } }) {
        Write-Log "Skipping restore of running HermesTray.exe; restore will not make the tray exit unless the user manually exits it."
        continue
      }
    }
    Copy-Item -LiteralPath $source -Destination $target -Force
  }

  Write-Log ("Windows-side AutoBackRes tool files restored: {0}" -f ($names -join ', '))
  if ($relaunchTray) {
    Start-Process -FilePath (Join-Path $PSScriptRoot 'HermesTray.exe') -WindowStyle Hidden
    Write-Log "HermesTray.exe relaunched after Windows-side tool restore"
  }
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
        throw "$Label timed out after $TimeoutSeconds seconds; native process was not force-stopped to avoid interrupting live Hermes work"
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
        Write-Log ("{0} completed via done file; leaving native process pid={1} to exit naturally instead of force-stopping it" -f $Label,$proc.Id)
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

  $scriptPath = Join-Path $script:RestoreWorkDir 'start-gateway.sh'
  Write-LinuxScript -Path $scriptPath -Body @'
set -euo pipefail
export PATH="/home/ubuntu/.local/bin:/home/ubuntu/.hermes/node/bin:/usr/local/bin:/usr/local/sbin:/usr/bin:/bin:/snap/bin"
if pgrep -u ubuntu -f "hermes gateway run" >/dev/null 2>&1; then
  sudo -H -u ubuntu env PATH="$PATH" hermes gateway status
  exit 0
fi
sudo -H -u ubuntu tmux new-session -d -s hermes-gateway "cd /home/ubuntu && export PATH='$PATH' && exec hermes gateway run >>/home/ubuntu/.hermes/logs/gateway-run.log 2>&1"
sleep 8
sudo -H -u ubuntu env PATH="$PATH" hermes gateway status
sudo -H -u ubuntu env PATH="$PATH" hermes --version | head -20
grep -E "Connected to Telegram|Gateway running with 1 platform" /home/ubuntu/.hermes/logs/gateway.log | tail -10 || true
'@
  Invoke-HermesWslScript -ScriptPath $scriptPath | Out-Null
}

function Invoke-TelegramProbe {
  if ($NoTelegramProbe) { return }
  $scriptPath = Join-Path $script:RestoreWorkDir 'telegram-probe.sh'
  Write-LinuxScript -Path $scriptPath -Body @'
set -euo pipefail
secret="/home/ubuntu/.config/hermes-setup/telegram.env"
if [ ! -f "$secret" ]; then
  echo "Telegram secret file missing; skipping probe"
  exit 30
fi
set -a
. "$secret"
set +a
if [ -z "${TELEGRAM_BOT_TOKEN:-}" ]; then
  echo "TELEGRAM_BOT_TOKEN missing; skipping probe"
  exit 31
fi
curl -fsS "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/getMe" >/tmp/hermes-telegram-getme.json
python3 - <<'PY'
import json
data=json.load(open('/tmp/hermes-telegram-getme.json'))
if not data.get('ok'):
    raise SystemExit('Telegram getMe returned not ok')
user=data.get('result',{})
print('Telegram bot OK: id=%s username=@%s' % (user.get('id'), user.get('username')))
PY
chat="${TELEGRAM_TEST_CHAT_ID:-}"
if [ -z "$chat" ] && [ -n "${TELEGRAM_ALLOWED_USERS:-}" ]; then
  chat="${TELEGRAM_ALLOWED_USERS%%,*}"
fi
if [ -z "$chat" ]; then
  echo "No Telegram chat id available for sendMessage"
  exit 32
fi
curl -fsS -X POST "https://api.telegram.org/bot${TELEGRAM_BOT_TOKEN}/sendMessage" \
  -d chat_id="$chat" \
  --data-urlencode text="Hermes WSL2 Hermes-data restore verified and ready: $(date -Iseconds)" >/tmp/hermes-telegram-send.json
python3 - <<'PY'
import json
data=json.load(open('/tmp/hermes-telegram-send.json'))
if not data.get('ok'):
    raise SystemExit('Telegram sendMessage returned not ok')
print('Telegram restore probe sent')
PY
'@
  Invoke-HermesWslScript -ScriptPath $scriptPath | Out-Null
}

function Assert-NoActiveTelegramWork {
  $scriptPath = Join-Path $script:RestoreWorkDir 'assert-no-active-telegram-work.sh'
  Write-LinuxScript -Path $scriptPath -Body @'
set -euo pipefail
python3 - <<'PY'
import json
from pathlib import Path

homes = [
    Path('/home/ubuntu/.hermes'),
    Path('/home/ubuntu/.hermes-michahermes5bot'),
    Path('/home/ubuntu/.hermes-michaopenclawbot'),
    Path('/home/ubuntu/.hermes-mmichael_moltbot_bot'),
    Path('/home/ubuntu/.hermes-mmmoltbot_bot'),
]
active = []
for home in homes:
    state = home / 'gateway_state.json'
    try:
        data = json.loads(state.read_text(encoding='utf-8'))
    except Exception:
        continue
    try:
        agents = int(data.get('active_agents') or 0)
    except Exception:
        agents = 0
    if agents > 0:
        active.append(f'{home}:active_agents={agents}')
if active:
    print('RESTORE_REFUSED_ACTIVE_TELEGRAM_WORK=' + ','.join(active))
    raise SystemExit(44)
print('RESTORE_ACTIVE_TELEGRAM_WORK=none')
PY
'@
  Invoke-HermesWslScript -ScriptPath $scriptPath | Out-Null
}

function Restore-SlashCommandsOnly {
  $scriptPath = Join-Path $script:RestoreWorkDir 'restore-slash-commands-only.sh'
  Write-LinuxScript -Path $scriptPath -Body @'
set -euo pipefail
archive="$1"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
cd "$tmp"
tar -xzf "$archive" \
  home/ubuntu/.hermes/config.yaml \
  home/ubuntu/.hermes/backups/config.yaml.20260505-170712.bak \
  home/ubuntu/.hermes/scripts \
  home/ubuntu/.hermes/hermes-agent/ui-tui/src/app/slash \
  home/ubuntu/.hermes/hermes-agent/gateway/run.py \
  home/ubuntu/.hermes/hermes-agent/hermes_cli/commands.py \
  home/ubuntu/.hermes/hermes-agent/tui_gateway/slash_worker.py \
  home/ubuntu/.hermes/hermes-agent/web/src/lib/slashExec.ts
install -d -o ubuntu -g ubuntu -m 0700 /home/ubuntu/.hermes/scripts
cp -a home/ubuntu/.hermes/scripts/. /home/ubuntu/.hermes/scripts/
chown -R ubuntu:ubuntu /home/ubuntu/.hermes/scripts
chmod 700 /home/ubuntu/.hermes/scripts
find /home/ubuntu/.hermes/scripts -type f -name '*.sh' -exec chmod 711 {} +
install -d -o ubuntu -g ubuntu /home/ubuntu/.hermes/hermes-agent/ui-tui/src/app/slash
cp -a home/ubuntu/.hermes/hermes-agent/ui-tui/src/app/slash/. /home/ubuntu/.hermes/hermes-agent/ui-tui/src/app/slash/
install -D -o ubuntu -g ubuntu -m 0644 home/ubuntu/.hermes/hermes-agent/gateway/run.py /home/ubuntu/.hermes/hermes-agent/gateway/run.py
install -D -o ubuntu -g ubuntu -m 0644 home/ubuntu/.hermes/hermes-agent/hermes_cli/commands.py /home/ubuntu/.hermes/hermes-agent/hermes_cli/commands.py
install -D -o ubuntu -g ubuntu -m 0644 home/ubuntu/.hermes/hermes-agent/tui_gateway/slash_worker.py /home/ubuntu/.hermes/hermes-agent/tui_gateway/slash_worker.py
install -D -o ubuntu -g ubuntu -m 0644 home/ubuntu/.hermes/hermes-agent/web/src/lib/slashExec.ts /home/ubuntu/.hermes/hermes-agent/web/src/lib/slashExec.ts
python3 - <<'PY'
from pathlib import Path
import time
import yaml

live = Path("/home/ubuntu/.hermes/config.yaml")
sources = [
    Path("home/ubuntu/.hermes/config.yaml"),
    Path("home/ubuntu/.hermes/backups/config.yaml.20260505-170712.bak"),
]
data = yaml.safe_load(live.read_text()) if live.exists() else {}
if not isinstance(data, dict):
    data = {}
quick_commands = data.get("quick_commands")
if not isinstance(quick_commands, dict):
    quick_commands = {}
allowlist = data.get("command_allowlist")
if not isinstance(allowlist, list):
    allowlist = []

for source in sources:
    if not source.exists():
        continue
    loaded = yaml.safe_load(source.read_text()) or {}
    if not isinstance(loaded, dict):
        continue
    source_quick = loaded.get("quick_commands")
    if isinstance(source_quick, dict):
        quick_commands.update(source_quick)
    source_allow = loaded.get("command_allowlist")
    if isinstance(source_allow, list):
        for item in source_allow:
            if item not in allowlist:
                allowlist.append(item)

data["quick_commands"] = quick_commands
data["command_allowlist"] = allowlist
if live.exists():
    backup = live.with_name(f"config.yaml.pre-slash-restore-{time.strftime('%Y%m%d-%H%M%S')}.bak")
    backup.write_text(live.read_text())
live.write_text(yaml.safe_dump(data, sort_keys=False, allow_unicode=True))
PY
chown ubuntu:ubuntu /home/ubuntu/.hermes/config.yaml
chmod 600 /home/ubuntu/.hermes/config.yaml
chown -R ubuntu:ubuntu /home/ubuntu/.hermes/hermes-agent/ui-tui/src/app/slash
chown ubuntu:ubuntu /home/ubuntu/.hermes/hermes-agent/gateway/run.py /home/ubuntu/.hermes/hermes-agent/hermes_cli/commands.py
echo "Slash command files, gateway handlers, scripts, and quick-command config restored"
if [ -x /home/ubuntu/.hermes/scripts/snap_all_monitors.sh ]; then
  python3 - <<'PY'
from pathlib import Path
path = Path("/home/ubuntu/.hermes/scripts/snap_all_monitors.sh")
text = path.read_text()
needle = "$resized.Save($OutPath, $codec, $params)\n"
if "foreach ($quality in 85, 75, 65, 55, 45, 35)" not in text and needle in text:
    text = text.replace(
        "$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 85L\n$resized.Save($OutPath, $codec, $params)\n",
        "$params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), 85L\nforeach ($quality in 85, 75, 65, 55, 45, 35) {\n    $params.Param[0] = New-Object System.Drawing.Imaging.EncoderParameter ([System.Drawing.Imaging.Encoder]::Quality), ([int64]$quality)\n    $resized.Save($OutPath, $codec, $params)\n    if ((Get-Item -LiteralPath $OutPath).Length -lt 9000000) { break }\n}\n",
    )
    path.write_text(text)
PY
fi
'@
  Invoke-HermesWslScript -ScriptPath $scriptPath -WslArgs @((ConvertTo-WslPath $archive)) | Out-Null
}

$script:WslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $script:WslExe -PathType Leaf)) { $script:WslExe = 'wsl.exe' }

if ($BackupId -eq 'latest') {
  $latestFile = Join-Path $BackupRoot 'LATEST.txt'
  if (-not (Test-Path -LiteralPath $latestFile -PathType Leaf)) {
    throw "LATEST.txt not found under $BackupRoot"
  }
  $BackupId = (Get-Content -LiteralPath $latestFile -Raw).Trim()
}

$backupDir = Join-Path $BackupRoot $BackupId
if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) {
  throw "Backup directory not found: $backupDir"
}

$script:RestoreWorkDir = Join-Path $backupDir ('restore-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
New-Item -ItemType Directory -Path $script:RestoreWorkDir -Force | Out-Null
$script:LogFile = Join-Path $script:RestoreWorkDir 'restore.log'
New-Item -ItemType File -Path $script:LogFile -Force | Out-Null

$manifestPath = Join-Path $backupDir 'manifest.json'
if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw "Missing manifest: $manifestPath" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if ($manifest.backup_kind -ne 'hermes-wsl-data-only') {
  throw "Refusing non-Hermes-only backup kind: $($manifest.backup_kind)"
}

$archive = Join-Path $backupDir $manifest.archive
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Missing Hermes data archive: $archive" }
$pathList = Join-Path $backupDir 'hermes-wsl-data.paths.txt'
if (-not (Test-Path -LiteralPath $pathList -PathType Leaf)) { throw "Missing Hermes data path list: $pathList" }
if ($manifest.archive_sha256) {
  $actualHash = Get-Sha256Hex -Path $archive
  if ($actualHash -ine $manifest.archive_sha256) { throw "Hermes data archive hash mismatch" }
}
Restore-WindowsToolFiles -Validate:$ValidateOnly

Write-Log "Starting Hermes-only restore from $backupDir"
Invoke-Native -FilePath $script:WslExe -Arguments @('-l', '-v') -Label 'wsl list' | Out-Null

$validateScript = Join-Path $script:RestoreWorkDir 'validate-restore-input.sh'
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
  case "$p" in
    home/ubuntu/.hermes|home/ubuntu/.hermes/*|home/ubuntu/.codex|home/ubuntu/.codex/*|home/ubuntu/.config/hermes-setup|home/ubuntu/.config/hermes-setup/*|home/ubuntu/.config/uv|home/ubuntu/.config/uv/*|home/ubuntu/.local/bin/hermes|home/ubuntu/.local/bin/node|home/ubuntu/.local/bin/npm|home/ubuntu/.local/bin/npx|home/ubuntu/.local/bin/corepack|home/ubuntu/.local/bin/uv|home/ubuntu/.local/bin/uvx|home/ubuntu/.local/state/hermes|home/ubuntu/.local/state/hermes/*|home/ubuntu/.local/share/uv|home/ubuntu/.local/share/uv/*|home/ubuntu/.cache/ms-playwright|home/ubuntu/.cache/ms-playwright/*|home/ubuntu/.cache/uv|home/ubuntu/.cache/uv/*|home/ubuntu/.bashrc|home/ubuntu/.profile|home/ubuntu/.bash_profile) ;;
    *) echo "Refusing unsafe restore path from list: $p" >&2; exit 40 ;;
  esac
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
echo "Restore input verified: $(wc -l < "$listing") archive entries"
'@
Invoke-HermesWslScript -ScriptPath $validateScript -WslArgs @((ConvertTo-WslPath $archive), (ConvertTo-WslPath $pathList)) | Out-Null

if ($ValidateOnly) {
  Write-Log "Restore validation complete; ValidateOnly was set, so no files were changed"
  Write-Host "VALIDATED_BACKUP_ID=$BackupId"
  Write-Host "RESTORE_LOG=$script:LogFile"
  return
}

if ($SlashCommandsOnly) {
  Assert-NoActiveTelegramWork
  Restore-SlashCommandsOnly
  Start-HermesGateway
  Invoke-TelegramProbe
  Write-Log "Hermes slash-command restore complete"
  Write-Host "RESTORED_SLASH_COMMANDS_BACKUP_ID=$BackupId"
  Write-Host "RESTORE_LOG=$script:LogFile"
  return
}

Assert-NoActiveTelegramWork
$overlayScript = Join-Path $script:RestoreWorkDir 'restore-hermes-data.sh'
Write-LinuxScript -Path $overlayScript -Body @'
set -euo pipefail
archive="$1"
path_list="$2"
while IFS= read -r p; do
  [ -n "$p" ] || continue
  case "$p" in
    home/ubuntu/.hermes|home/ubuntu/.hermes/*|home/ubuntu/.codex|home/ubuntu/.codex/*|home/ubuntu/.config/hermes-setup|home/ubuntu/.config/hermes-setup/*|home/ubuntu/.config/uv|home/ubuntu/.config/uv/*|home/ubuntu/.local/bin/hermes|home/ubuntu/.local/bin/node|home/ubuntu/.local/bin/npm|home/ubuntu/.local/bin/npx|home/ubuntu/.local/bin/corepack|home/ubuntu/.local/bin/uv|home/ubuntu/.local/bin/uvx|home/ubuntu/.local/state/hermes|home/ubuntu/.local/state/hermes/*|home/ubuntu/.local/share/uv|home/ubuntu/.local/share/uv/*|home/ubuntu/.cache/ms-playwright|home/ubuntu/.cache/ms-playwright/*|home/ubuntu/.cache/uv|home/ubuntu/.cache/uv/*|home/ubuntu/.bashrc|home/ubuntu/.profile|home/ubuntu/.bash_profile)
      ;;
    *)
      echo "Refusing unsafe restore path from list: $p" >&2
      exit 40
      ;;
  esac
done < "$path_list"
tar --xattrs --acls --numeric-owner --overwrite --delay-directory-restore -C / -xzpf "$archive"
sync
'@
Invoke-HermesWslScript -ScriptPath $overlayScript -WslArgs @((ConvertTo-WslPath $archive), (ConvertTo-WslPath $pathList)) | Out-Null

Start-HermesGateway
Invoke-TelegramProbe

Write-Log "Hermes-only restore complete"
Write-Host "RESTORED_BACKUP_ID=$BackupId"
Write-Host "RESTORE_LOG=$script:LogFile"
