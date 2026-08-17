[CmdletBinding()]
param(
    [string] $BackupId = 'latest',
    [string] $Distro = 'ubuntu',
    [string] $BackupRoot = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backups',
    [switch] $ValidateOnly,
    [switch] $PlanOnly,
    [switch] $NoTelegramProbe,
    [switch] $SlashCommandsOnly,
    [switch] $Legacy,
    [Parameter(ValueFromRemainingArguments = $true)][string[]] $ResherArgs
)
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$legacyScript = Join-Path $scriptRoot 'restore-hermes-wsl2.ps1'
if ($Legacy -or $SlashCommandsOnly -or ($ResherArgs -and $ResherArgs.Count -gt 0)) {
    if (-not (Test-Path -LiteralPath $legacyScript -PathType Leaf)) { throw "Legacy restore script not found: $legacyScript" }
    if ($SlashCommandsOnly) { & $legacyScript -BackupId $BackupId -Distro $Distro -BackupRoot $BackupRoot -ValidateOnly:$ValidateOnly -NoTelegramProbe:$NoTelegramProbe -SlashCommandsOnly; exit $LASTEXITCODE }
    & $legacyScript @ResherArgs
    exit $LASTEXITCODE
}
function ConvertTo-WslPath([string]$WindowsPath) {
    $full = [System.IO.Path]::GetFullPath($WindowsPath)
    $drive = $full.Substring(0,1).ToLowerInvariant()
    $rest = $full.Substring(3).Replace('\','/')
    return "/mnt/$drive/$rest"
}
function ConvertFrom-WslNativePathToUnc([string]$DistroName, [string]$WslPath) {
    $relative = $WslPath.TrimStart('/').Replace('/','\')
    $primary = "\\wsl.localhost\$DistroName\$relative"
    if (Test-Path -LiteralPath $primary) { return $primary }
    return "\\wsl$\$DistroName\$relative"
}
function Assert-ChildPath([string]$Root, [string]$Child, [string]$Label) {
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $childFull = [System.IO.Path]::GetFullPath($Child).TrimEnd('\','/')
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not ($childFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label is outside expected root: $childFull"
    }
}
function Write-NewProcessLines([string]$Path, [ref]$LineCount, [switch]$AsError) {
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return }
    $lines = @(Get-Content -LiteralPath $Path -ErrorAction SilentlyContinue)
    for ($i = $LineCount.Value; $i -lt $lines.Count; $i++) {
        if ($AsError) { Write-Warning $lines[$i] } else { Write-Host $lines[$i] }
    }
    $LineCount.Value = $lines.Count
}
function ConvertTo-NativeArgument([string]$Argument) {
    if ($null -eq $Argument) { return '""' }
    if ($Argument -notmatch '[\s"]') { return $Argument }
    return ('"{0}"' -f ($Argument.Replace('"','\"')))
}
function Assert-TarContains([string]$ArchivePath, [string[]]$RequiredEntries, [string]$Label) {
    $listing = @(& $windowsTarExe -tf $ArchivePath 2>$null)
    if ($LASTEXITCODE -ne 0) { throw "Could not list $Label archive: $ArchivePath" }
    foreach ($listed in $listing) {
        $entry = [string]$listed
        if ([string]::IsNullOrWhiteSpace($entry)) { continue }
        if ($entry.StartsWith('/') -or $entry.StartsWith('\') -or $entry -match '^[A-Za-z]:' -or $entry -match '(^|[\\/])\.\.([\\/]|$)') {
            throw "$Label archive contains unsafe restore entry '$entry': $ArchivePath"
        }
    }
    if ($RequiredEntries.Count -eq 0) { return }
    foreach ($entry in $RequiredEntries) {
        $entryPrefix = $entry.TrimEnd('/') + '/'
        $found = ($listing -contains $entry) -or (@($listing | Where-Object { $_.StartsWith($entryPrefix, [System.StringComparison]::OrdinalIgnoreCase) }).Count -gt 0)
        if (-not $found) { throw "$Label archive is missing required entry '$entry': $ArchivePath" }
    }
}
function Invoke-WithLiveProgress([string]$FilePath, [string[]]$ArgumentList, [string]$Label, [string]$WorkingDirectory, [string]$StatusPath, [string]$StandardInputText = '') {
    Write-Host ("PROGRESS {0}: starting" -f $Label)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardInput = -not [string]::IsNullOrEmpty($StandardInputText)
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw "Failed to start $Label" }
    if ($psi.RedirectStandardInput) {
        $stdinText = $StandardInputText.Replace([string][char]0xFEFF, '')
        $stdinBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($stdinText)
        $proc.StandardInput.BaseStream.Write($stdinBytes, 0, $stdinBytes.Length)
        $proc.StandardInput.Close()
    }
    $lastProgressMs = -100
    $lastStatusMs = -1000
    $lastDetail = ''
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 250
        $elapsedMs = [int64]$sw.Elapsed.TotalMilliseconds
        $seconds = [int][Math]::Floor($sw.Elapsed.TotalSeconds)
        if (($elapsedMs - $lastProgressMs) -ge 250) {
            $lastProgressMs = $elapsedMs
            $detail = $lastDetail
            if ($StatusPath -and (($elapsedMs - $lastStatusMs) -ge 1000) -and (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
                $lastStatusMs = $elapsedMs
                $bytes = (Get-Item -LiteralPath $StatusPath).Length
                $detail = (' archive={0:n1} MB' -f ($bytes / 1MB))
                $lastDetail = $detail
            }
            Write-Progress -Activity $Label -Status ("running for {0:n1}s{1}" -f $sw.Elapsed.TotalSeconds,$detail) -PercentComplete -1
            Write-Host ("PROGRESS {0}: elapsed_ms={1:n0}{2}" -f $Label,$sw.Elapsed.TotalMilliseconds,$detail)
        }
    }
    $proc.WaitForExit()
    $exitCode = [int]$proc.ExitCode
    Write-Progress -Activity $Label -Completed
    Write-Host ("PROGRESS {0}: finished elapsed={1:n1}s exit={2}" -f $Label,$sw.Elapsed.TotalSeconds,$exitCode)
    return $exitCode
}
$wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $wslExe -PathType Leaf)) { $wslExe = 'wsl.exe' }
$windowsTarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
if (-not (Test-Path -LiteralPath $windowsTarExe -PathType Leaf)) { $windowsTarExe = 'tar.exe' }
$BackupRoot = [System.IO.Path]::GetFullPath($BackupRoot)
if ($BackupId -eq 'latest') {
    $latest = Join-Path $BackupRoot 'LATEST.txt'
    if (-not (Test-Path -LiteralPath $latest -PathType Leaf)) { throw "LATEST.txt not found under $BackupRoot" }
    $BackupId = (Get-Content -LiteralPath $latest -Raw).Trim()
}
if ($BackupId -notmatch '^\d{8}-\d{6}$') {
    throw "Refusing unsafe Hermes backup id: $BackupId"
}
$backupDir = Join-Path $BackupRoot $BackupId
Assert-ChildPath -Root $BackupRoot -Child $backupDir -Label 'Hermes restore backup directory'
if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) { throw "Backup directory not found: $backupDir" }
$archive = Join-Path $backupDir 'hermes-wsl-data.tar.zst'
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { $archive = Join-Path $backupDir 'hermes-wsl-data.tar.gz' }
$pathList = Join-Path $backupDir 'hermes-wsl-data.paths.txt'
$manifestPath = Join-Path $backupDir 'manifest.json'
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Missing Hermes data archive: $archive" }
if ((Get-Item -LiteralPath $archive).Length -le 0) { throw "Hermes data archive is empty: $archive" }
if (-not (Test-Path -LiteralPath $pathList -PathType Leaf)) { throw "Missing Hermes data path list: $pathList" }
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.archive -and ((Split-Path -Leaf $archive) -ne [string]$manifest.archive)) { throw 'Hermes data archive name does not match manifest' }
    if ($manifest.archive_bytes) {
        $actualBytes = (Get-Item -LiteralPath $archive).Length
        if ([int64]$manifest.archive_bytes -ne [int64]$actualBytes) { throw "Hermes data archive byte size mismatch: manifest=$($manifest.archive_bytes) actual=$actualBytes" }
    }
    if ((-not $PlanOnly) -and $manifest.archive_sha256) {
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actual -ine $manifest.archive_sha256) { throw 'Hermes data archive hash mismatch' }
    }
}
$pathEntries = @(Get-Content -LiteralPath $pathList | ForEach-Object { $_.ToString().Trim() } | Where-Object { $_ })
$requiredHermesPaths = @(
    'home/ubuntu/.hermes',
    'home/ubuntu/.hermes-mmmoltbot_bot',
    'home/ubuntu/.hermes-mmichael_moltbot_bot',
    'home/ubuntu/.hermes-michaopenclawbot',
    'home/ubuntu/.hermes-michahermes5bot',
    'home/ubuntu/.codex',
    'home/ubuntu/.local/state/hermes'
)
foreach ($requiredPath in $requiredHermesPaths) {
    if ($pathEntries -notcontains $requiredPath) { throw "Backup path list is missing required Hermes restore path: $requiredPath" }
}
$optionalOffloadTargets = @(
    'mnt/c/local-uncensored-llm/wsl-offload/hermes-homes/.hermes-michaopenclawbot',
    'mnt/c/local-uncensored-llm/wsl-offload/hermes-homes/.hermes-michahermes5bot'
)
foreach ($optionalPath in $optionalOffloadTargets) {
    $windowsOptionalPath = Join-Path 'C:\' ($optionalPath.Substring(6).Replace('/','\'))
    if ((Test-Path -LiteralPath $windowsOptionalPath) -and ($pathEntries -notcontains $optionalPath)) {
        throw "Backup path list is missing existing symlink target restore path: $optionalPath"
    }
}
if ($PlanOnly) {
    Write-Host 'PROGRESS resher-wsl-restore: starting'
    Write-Progress -Activity 'resher-wsl-restore' -Status 'reading saved restore path list' -PercentComplete 50
    Write-Host '== full restore path list =='
    $pathEntries | ForEach-Object { Write-Host $_ }
    Write-Progress -Activity 'resher-wsl-restore' -Completed
    Write-Host 'PROGRESS resher-wsl-restore: finished elapsed=0.0s exit=0'
    return
}
$windowsRelatedManifestPath = Join-Path $backupDir 'windows-related-files.json'
$windowsRelatedDir = Join-Path $backupDir 'windows-related-files'
$windowsRelatedItems = @()
function Get-SafeWindowsRelatedArchiveRestoreRoot([string]$RestoreRoot, [string]$ArchiveName) {
    $allowedRoots = @(
        'C:\Users\micha\Documents\WindowsPowerShell',
        'C:\Users\micha\.codex',
        'C:\Users\micha\.agents',
        'C:\Users\micha\.claude'
    )
    foreach ($allowedRoot in $allowedRoots) {
        if ([System.IO.Path]::GetFullPath($RestoreRoot).TrimEnd('\','/') -ieq [System.IO.Path]::GetFullPath($allowedRoot).TrimEnd('\','/')) {
            return $allowedRoot
        }
    }
    throw "Refusing unknown Windows-related Hermes archive restore root for $ArchiveName`: $RestoreRoot"
}
function Assert-WindowsRelatedArchive([string]$ArchivePath, [string]$ArchiveName) {
    if ([string]::IsNullOrWhiteSpace($ArchiveName) -or $ArchiveName -match '[\\/:]' -or $ArchiveName -match '(^|[\\/])\.\.([\\/]|$)') {
        throw "Refusing unsafe Windows-related archive name: $ArchiveName"
    }
    Assert-ChildPath -Root $windowsRelatedDir -Child $ArchivePath -Label 'Windows-related archive'
    if (-not (Test-Path -LiteralPath $ArchivePath -PathType Leaf)) { throw "Windows-related Hermes archive missing: $ArchivePath" }
    if ((Get-Item -LiteralPath $ArchivePath).Length -le 0) { throw "Windows-related Hermes archive is empty: $ArchivePath" }
    Assert-TarContains -ArchivePath $ArchivePath -RequiredEntries @() -Label "Windows-related $ArchiveName"
}
if (Test-Path -LiteralPath $windowsRelatedManifestPath -PathType Leaf) {
    if (-not (Test-Path -LiteralPath $windowsRelatedDir -PathType Container)) { throw "Missing Windows-related Hermes restore directory: $windowsRelatedDir" }
    $windowsRelatedRaw = Get-Content -LiteralPath $windowsRelatedManifestPath -Raw | ConvertFrom-Json
    if ($null -eq $windowsRelatedRaw) {
        $windowsRelatedItems = @()
    } elseif ($windowsRelatedRaw -is [System.Array]) {
        $windowsRelatedItems = @($windowsRelatedRaw)
    } else {
        $windowsRelatedItems = @($windowsRelatedRaw)
    }
    if (@($windowsRelatedItems | Where-Object { $_.type -eq 'archive' }).Count -gt 0) {
        foreach ($requiredArchive in @('powershell-profile.tar','codex-hermes-support.tar')) {
            $found = @($windowsRelatedItems | Where-Object { $_.archive -eq $requiredArchive }).Count -gt 0
            if (-not $found) { throw "Backup is missing required Hermes/Codex Windows archive: $requiredArchive" }
            $candidate = Join-Path $windowsRelatedDir $requiredArchive
            Assert-WindowsRelatedArchive -ArchivePath $candidate -ArchiveName $requiredArchive
        }
        Assert-TarContains -ArchivePath (Join-Path $windowsRelatedDir 'powershell-profile.tar') -RequiredEntries @('Microsoft.PowerShell_profile.ps1') -Label 'PowerShell profile'
        Assert-TarContains -ArchivePath (Join-Path $windowsRelatedDir 'codex-hermes-support.tar') -RequiredEntries @('config.toml','skills') -Label 'Codex Hermes support'
    } else {
        $requiredWindowsTargets = @(
            'WindowsPowerShell\Microsoft.PowerShell_profile.ps1',
            'codex\config.toml',
            'codex\hooks.json',
            'codex\skills',
            'codex\prompts',
            'codex\hooks'
        )
        foreach ($target in $requiredWindowsTargets) {
            $found = @($windowsRelatedItems | Where-Object { $_.target -eq $target }).Count -gt 0
            if (-not $found) { throw "Backup is missing required Hermes/Codex Windows restore target: $target" }
            $candidate = Join-Path $windowsRelatedDir $target
            if (-not (Test-Path -LiteralPath $candidate)) { throw "Windows-related Hermes backup payload missing: $candidate" }
        }
    }
} else {
    Write-Warning "Backup has no windows-related-files.json; WSL Hermes data can be validated/restored, but PS5/Codex skill restore coverage is older/incomplete."
}
$backupDirWsl = ConvertTo-WslPath $backupDir
$wslWorkDir = "/tmp/resher-fast-$BackupId-$([guid]::NewGuid().ToString('N'))"
& $wslExe -d $Distro -u root --cd / -- mkdir -p -- $wslWorkDir
if ($LASTEXITCODE -ne 0) { throw "Could not create native WSL restore workspace: $wslWorkDir" }
$wslWorkUnc = ConvertFrom-WslNativePathToUnc -DistroName $Distro -WslPath $wslWorkDir
Copy-Item -LiteralPath $archive -Destination (Join-Path $wslWorkUnc (Split-Path -Leaf $archive)) -Force
Copy-Item -LiteralPath $pathList -Destination (Join-Path $wslWorkUnc 'hermes-wsl-data.paths.txt') -Force
$bash = @'
set -euo pipefail
backup_dir="$1"
mode="$2"
if [ -f "$backup_dir/hermes-wsl-data.tar.zst" ]; then
  archive="$backup_dir/hermes-wsl-data.tar.zst"
  tar_list=(tar --use-compress-program=zstd -tf "$archive")
  tar_verbose=(tar --use-compress-program=zstd -tvf "$archive")
  tar_extract=(tar --xattrs --acls --numeric-owner --overwrite --delay-directory-restore --use-compress-program=zstd -C / -xpf "$archive")
else
  archive="$backup_dir/hermes-wsl-data.tar.gz"
  tar_list=(tar -tzf "$archive")
  tar_verbose=(tar -tzvf "$archive")
  tar_extract=(tar --xattrs --acls --numeric-owner --overwrite --delay-directory-restore -C / -xzpf "$archive")
fi
path_list="$backup_dir/hermes-wsl-data.paths.txt"
while IFS= read -r p; do
  p="${p%$'\r'}"
  [ -n "$p" ] || continue
  case "$p" in
    mnt/c/local-uncensored-llm/wsl-offload/hermes-homes/.hermes-*|mnt/c/local-uncensored-llm/wsl-offload/hermes-homes/.hermes-*/*) ;;
    home/*/.hermes|home/*/.hermes/*|home/*/.hermes-*|home/*/.hermes-*/*|root/.hermes|root/.hermes/*|root/.hermes-*|root/.hermes-*/*|opt/hermes|opt/hermes/*|opt/hermes-*|opt/hermes-*/*|srv/hermes|srv/hermes/*|srv/hermes-*|srv/hermes-*/*|home/*/.codex|home/*/.codex/*|home/*/.config/hermes|home/*/.config/hermes/*|home/*/.config/hermes-*|home/*/.config/hermes-*/*|home/*/.config/uv|home/*/.config/uv/*|home/*/.local/bin/hermes|home/*/.local/bin/node|home/*/.local/bin/npm|home/*/.local/bin/npx|home/*/.local/bin/corepack|home/*/.local/bin/uv|home/*/.local/bin/uvx|home/*/.local/state/hermes|home/*/.local/state/hermes/*|home/*/.local/state/hermes-*|home/*/.local/state/hermes-*/*|home/*/.local/share/hermes|home/*/.local/share/hermes/*|home/*/.local/share/hermes-*|home/*/.local/share/hermes-*/*|home/*/.local/share/uv|home/*/.local/share/uv/*|home/*/.cache/ms-playwright|home/*/.cache/ms-playwright/*|home/*/.cache/uv|home/*/.cache/uv/*|home/*/.bashrc|home/*/.profile|home/*/.bash_profile) ;;
    *) echo "Refusing unsafe restore path from list: $p" >&2; exit 40 ;;
  esac
done < "$path_list"
if [ "$mode" = "plan" ]; then echo '== full restore path list =='; cat "$path_list"; exit 0; fi
"${tar_list[@]}" >/tmp/resher-listing.$$
entries=$(wc -l </tmp/resher-listing.$$)
rm -f /tmp/resher-listing.$$
echo "Restore input verified: $entries archive entries"
if [ "$mode" = "validate" ]; then exit 0; fi
python3 - <<'PY'
import json, os, pathlib, sys
homes = [
    pathlib.Path('/home/ubuntu/.hermes'),
    pathlib.Path('/home/ubuntu/.hermes-michahermes5bot'),
    pathlib.Path('/home/ubuntu/.hermes-michaopenclawbot'),
    pathlib.Path('/home/ubuntu/.hermes-mmichael_moltbot_bot'),
    pathlib.Path('/home/ubuntu/.hermes-mmmoltbot_bot'),
]
active = []
for home in homes:
    state_path = home / 'state' / 'gateway_state.json'
    if not state_path.exists():
        state_path = home / 'gateway_state.json'
    try:
        data = json.loads(state_path.read_text(encoding='utf-8'))
    except Exception:
        continue
    try:
        agents = int(data.get('active_agents') or 0)
    except Exception:
        agents = 0
    if agents > 0:
        active.append(f'{home}:active_agents={agents}')
if active:
    print('RESTORE_REFUSED_ACTIVE_TELEGRAM_WORK=' + ','.join(active), file=sys.stderr)
    print('Run /stop or finish the active bot work before full WSL restore; resher will not kill working sessions automatically.', file=sys.stderr)
    raise SystemExit(44)
PY
live_gateway_pids="$(python3 - <<'PY'
import os
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    try:
        env = {}
        for item in open(f'/proc/{name}/environ', 'rb').read().split(b'\0'):
            if b'=' in item:
                k, v = item.split(b'=', 1)
                env[k.decode('utf-8', 'ignore')] = v.decode('utf-8', 'ignore')
        cmd = open(f'/proc/{name}/cmdline', 'rb').read().decode('utf-8', 'ignore')
    except Exception:
        continue
    home = env.get('HERMES_HOME') or ''
    if home.startswith('/home/ubuntu/.hermes') and 'gateway' in cmd and 'run' in cmd:
        print(name)
PY
)"
if [ -n "$live_gateway_pids" ]; then
  if [ "${HERMES_ALLOW_RESTORE_GATEWAY_STOP:-0}" = "1" ]; then
    echo "Stopping live Hermes WSL gateway processes before archive extraction due to explicit HERMES_ALLOW_RESTORE_GATEWAY_STOP=1"
  else
    echo "Stopping idle live Hermes WSL gateway processes automatically before archive extraction"
  fi
  for s in hermes-gateway hermes-michahermes5bot hermes-michaopenclawbot hermes-mmichael_moltbot_bot hermes-mmmoltbot_bot hermes-fleet-companion-watchdog; do
    tmux kill-session -t "=$s" 2>/dev/null || true
    sudo -H -u ubuntu tmux kill-session -t "=$s" 2>/dev/null || true
  done
  printf '%s\n' "$live_gateway_pids" | while read -r pid; do
    [ -n "$pid" ] || continue
    kill "$pid" 2>/dev/null || true
    echo "Stopped live Hermes gateway pid=$pid"
  done
  sleep 2
  remaining_gateway_pids="$(python3 - <<'PY'
import os
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    try:
        env = {}
        for item in open(f'/proc/{name}/environ', 'rb').read().split(b'\0'):
            if b'=' in item:
                k, v = item.split(b'=', 1)
                env[k.decode('utf-8', 'ignore')] = v.decode('utf-8', 'ignore')
        cmd = open(f'/proc/{name}/cmdline', 'rb').read().decode('utf-8', 'ignore')
    except Exception:
        continue
    home = env.get('HERMES_HOME') or ''
    if home.startswith('/home/ubuntu/.hermes') and 'gateway' in cmd and 'run' in cmd:
        print(name)
PY
)"
  if [ -n "$remaining_gateway_pids" ]; then
    printf '%s\n' "$remaining_gateway_pids" | while read -r pid; do
      [ -n "$pid" ] || continue
      kill -9 "$pid" 2>/dev/null || true
      echo "Force-stopped live Hermes gateway pid=$pid"
    done
    sleep 1
  fi
  final_gateway_pids="$(python3 - <<'PY'
import os
for name in os.listdir('/proc'):
    if not name.isdigit():
        continue
    try:
        env = {}
        for item in open(f'/proc/{name}/environ', 'rb').read().split(b'\0'):
            if b'=' in item:
                k, v = item.split(b'=', 1)
                env[k.decode('utf-8', 'ignore')] = v.decode('utf-8', 'ignore')
        cmd = open(f'/proc/{name}/cmdline', 'rb').read().decode('utf-8', 'ignore')
    except Exception:
        continue
    home = env.get('HERMES_HOME') or ''
    if home.startswith('/home/ubuntu/.hermes') and 'gateway' in cmd and 'run' in cmd:
        print(name)
PY
)"
  if [ -n "$final_gateway_pids" ]; then
    echo "RESTORE_REFUSED_LIVE_GATEWAYS=$final_gateway_pids" >&2
    echo "Hermes gateway processes remained alive after automatic shutdown; restore refused to avoid overlaying live state." >&2
    exit 45
  fi
fi
symlink_conflicts="$backup_dir/resher-symlink-conflicts.txt"
if [ "${archive##*.}" = "gz" ]; then
  python3 - "$archive" > "$symlink_conflicts" <<'PY'
import sys
import tarfile

with tarfile.open(sys.argv[1], 'r:gz') as tf:
    for member in tf:
        if member.issym():
            print(member.name)
PY
else
  "${tar_verbose[@]}" 2>/dev/null | awk '$1 ~ /^l/ {
    line=$0
    sub(/^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]+/, "", line)
    sub(/[[:space:]]+->[[:space:]].*$/, "", line)
    print line
  }' > "$symlink_conflicts"
fi
while IFS= read -r p; do
  p="${p%$'\r'}"
  [ -n "$p" ] || continue
  case "$p" in
    mnt/c/local-uncensored-llm/wsl-offload/hermes-homes/.hermes-*|mnt/c/local-uncensored-llm/wsl-offload/hermes-homes/.hermes-*/*) ;;
    home/*/.hermes|home/*/.hermes/*|home/*/.hermes-*|home/*/.hermes-*/*|root/.hermes|root/.hermes/*|root/.hermes-*|root/.hermes-*/*|opt/hermes|opt/hermes/*|opt/hermes-*|opt/hermes-*/*|srv/hermes|srv/hermes/*|srv/hermes-*|srv/hermes-*/*|home/*/.codex|home/*/.codex/*|home/*/.config/hermes|home/*/.config/hermes/*|home/*/.config/hermes-*|home/*/.config/hermes-*/*|home/*/.config/uv|home/*/.config/uv/*|home/*/.local/bin/hermes|home/*/.local/bin/node|home/*/.local/bin/npm|home/*/.local/bin/npx|home/*/.local/bin/corepack|home/*/.local/bin/uv|home/*/.local/bin/uvx|home/*/.local/state/hermes|home/*/.local/state/hermes/*|home/*/.local/state/hermes-*|home/*/.local/state/hermes-*/*|home/*/.local/share/hermes|home/*/.local/share/hermes/*|home/*/.local/share/hermes-*|home/*/.local/share/hermes-*/*|home/*/.local/share/uv|home/*/.local/share/uv/*|home/*/.cache/ms-playwright|home/*/.cache/ms-playwright/*|home/*/.cache/uv|home/*/.cache/uv/*|home/*/.bashrc|home/*/.profile|home/*/.bash_profile) ;;
    *) echo "Refusing unsafe symlink cleanup path from archive: $p" >&2; exit 41 ;;
  esac
  target="/$p"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    rm -rf --one-file-system "$target"
    if [ -e "$target" ] || [ -L "$target" ]; then
      echo "Failed to prepare symlink restore path: $p" >&2
      exit 42
    fi
    echo "Prepared symlink restore path: $p"
  fi
done < "$symlink_conflicts"
"${tar_extract[@]}"
sync
'@
$mode = 'restore'
if ($PlanOnly) { $mode = 'plan' }
if ($ValidateOnly) { $mode = 'validate' }
$stdinBashRunner = "import subprocess,sys; data=sys.stdin.buffer.read(); data=data[3:] if data.startswith(b'\xef\xbb\xbf') else data; raise SystemExit(subprocess.run(['bash','-s','--']+sys.argv[2:], input=data).returncode)"
$wslArgs = @('-d', $Distro, '-u', 'root', '--cd', '/', '--', 'python3', '-c', $stdinBashRunner, '--', $wslWorkDir, $mode)
function Get-HermesTrayProcess([string]$ExePath) {
    $resolved = [System.IO.Path]::GetFullPath($ExePath)
    @(Get-CimInstance Win32_Process -Filter "Name = 'HermesTray.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and ([System.IO.Path]::GetFullPath($_.ExecutablePath) -ieq $resolved)
    })
}
function Stop-HermesTrayForRestore([string]$ExePath) {
    $processes = @(Get-HermesTrayProcess -ExePath $ExePath)
    if ($processes.Count -eq 0) {
        Write-Host "HERMES_TRAY_PRE_RESTORE=not-running"
        return $false
    }
    Write-Host ("HERMES_TRAY_RESTORE_KEEP_RUNNING=1 pids={0}" -f (($processes | ForEach-Object { $_.ProcessId }) -join ','))
    return $false
}
function Start-HermesTrayAfterRestore([string]$ExePath) {
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) { throw "HermesTray.exe not found after restore: $ExePath" }
    $processes = @(Get-HermesTrayProcess -ExePath $ExePath)
    if ($processes.Count -eq 0) {
        $started = Start-Process -FilePath $ExePath -WindowStyle Hidden -PassThru
        Write-Host "HERMES_TRAY_RELAUNCHED_PID=$($started.Id)"
        Start-Sleep -Seconds 2
        $processes = @(Get-HermesTrayProcess -ExePath $ExePath)
    } else {
        Write-Host "HERMES_TRAY_ALREADY_RUNNING_AFTER_RESTORE_PID=$($processes[0].ProcessId)"
    }
    if ($processes.Count -eq 0) { throw "HermesTray.exe was not running after restore launch: $ExePath" }
    Write-Host "HERMES_TRAY_RUNNING_FROM=$ExePath"
}
function Invoke-HermesRestoreReadinessProbe {
    if ($NoTelegramProbe) {
        Write-Host 'HERMES_RESTORE_READINESS_PROBE=skipped'
        return
    }
    $healthScript = Join-Path $scriptRoot 'hermes-tray-health.sh'
    if (-not (Test-Path -LiteralPath $healthScript -PathType Leaf)) {
        Write-Warning "Hermes restore readiness probe script missing: $healthScript"
        return
    }
    Write-Host 'PROGRESS resher-health: starting'
    $healthWslPath = ConvertTo-WslPath $healthScript
    & $wslExe -d $Distro -- bash -lc "HERMES_TRAY_STARTUP_GRACE_SECONDS=240 bash '$healthWslPath'"
    if ($LASTEXITCODE -ne 0) { throw "Hermes restore readiness probe failed with exit code $LASTEXITCODE" }
    Write-Host 'PROGRESS resher-health: finished'
}
$hermesTrayExe = Join-Path $scriptRoot 'HermesTray.exe'
$script:ResherTrayStopped = $false
trap {
    if ($script:ResherTrayStopped) {
        try { Start-HermesTrayAfterRestore -ExePath $hermesTrayExe } catch { Write-Warning $_.Exception.Message }
    }
    throw $_
}
if (-not ($PlanOnly -or $ValidateOnly)) { $script:ResherTrayStopped = Stop-HermesTrayForRestore -ExePath $hermesTrayExe }
$wslExitCode = Invoke-WithLiveProgress -FilePath $wslExe -ArgumentList $wslArgs -Label 'resher-wsl-restore' -WorkingDirectory $env:SystemRoot -StatusPath $archive -StandardInputText (($bash -replace "`r`n", "`n" -replace "`r", "`n") + "`n")
& $wslExe -d $Distro -u root --cd / -- rm -rf -- $wslWorkDir 2>$null
if ($wslExitCode -ne 0) { throw "resher WSL restore step failed with exit code $wslExitCode" }
if ($PlanOnly -or $ValidateOnly) { return }
$toolBackupDir = Join-Path $backupDir 'windows-tool-files'
if (Test-Path -LiteralPath $toolBackupDir -PathType Container) {
    Get-ChildItem -LiteralPath $toolBackupDir -File | Where-Object { $_.Name -ne 'windows-tool-files.txt' } | ForEach-Object {
        $dest = Join-Path $scriptRoot $_.Name
        if ($_.Name -ieq 'HermesTray.exe') {
            Write-Host "RESTORE_SKIPPED_RUNNING_TOOL_FILE=HermesTray.exe reason=tray_never_force_exits"
            return
        }
        if ($_.Name -in @('resher-fast.ps1','backher-fast.ps1','resume.sh','hermes-tray-health.sh')) {
            Write-Host ("RESTORE_SKIPPED_TOOL_FILE={0} reason=current_authoritative_restore_orchestrator_preserved" -f $_.Name)
            return
        }
        try { Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop }
        catch {
            if (Test-Path -LiteralPath $dest -PathType Leaf) { Write-Warning "Could not overwrite $dest (probably running/locked); kept existing file: $($_.Exception.Message)" }
            else { throw }
        }
    }
}
function Get-WindowsRelatedRestoreTarget([string]$RelativeTarget) {
    if ($RelativeTarget -eq 'WindowsPowerShell\Microsoft.PowerShell_profile.ps1') { return 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1' }
    if ($RelativeTarget -like 'codex\*') { return (Join-Path 'C:\Users\micha\.codex' $RelativeTarget.Substring(6)) }
    if ($RelativeTarget -like 'agents\*') { return (Join-Path 'C:\Users\micha\.agents' $RelativeTarget.Substring(7)) }
    if ($RelativeTarget -like 'claude\*') { return (Join-Path 'C:\Users\micha\.claude' $RelativeTarget.Substring(7)) }
    throw "Refusing unknown Windows-related Hermes restore target: $RelativeTarget"
}
foreach ($item in $windowsRelatedItems) {
    if ([string]$item.type -eq 'archive') {
        $archiveName = [string]$item.archive
        $source = Join-Path $windowsRelatedDir $archiveName
        $dest = Get-SafeWindowsRelatedArchiveRestoreRoot -RestoreRoot ([string]$item.restore_root) -ArchiveName $archiveName
        Assert-WindowsRelatedArchive -ArchivePath $source -ArchiveName $archiveName
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        & $windowsTarExe -xf $source -C $dest
        if ($LASTEXITCODE -ne 0) { throw "tar.exe failed while restoring $source -> $dest (exit $LASTEXITCODE)" }
    } elseif ([string]$item.type -eq 'directory') {
        $source = Join-Path $windowsRelatedDir ([string]$item.target)
        $dest = Get-WindowsRelatedRestoreTarget ([string]$item.target)
        if (-not (Test-Path -LiteralPath $source)) { throw "Windows-related restore source missing: $source" }
        New-Item -ItemType Directory -Path $dest -Force | Out-Null
        $robocopyArgs = @($source, $dest, '/E', '/R:1', '/W:1', '/MT:8', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
        & robocopy @robocopyArgs | Out-Null
        if ($LASTEXITCODE -ge 8) { throw "robocopy failed while restoring $source -> $dest (exit $LASTEXITCODE)" }
    } else {
        $source = Join-Path $windowsRelatedDir ([string]$item.target)
        $dest = Get-WindowsRelatedRestoreTarget ([string]$item.target)
        if (-not (Test-Path -LiteralPath $source)) { throw "Windows-related restore source missing: $source" }
        $parent = Split-Path -Parent $dest
        if ($parent) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
        Copy-Item -LiteralPath $source -Destination $dest -Force
    }
}
$restoredWinPsProfile = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$restoredPsProfile = 'C:\Users\micha\Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
if (Test-Path -LiteralPath $restoredWinPsProfile -PathType Leaf) {
    $restoredPsProfileDir = Split-Path -Parent $restoredPsProfile
    if (-not (Test-Path -LiteralPath $restoredPsProfileDir -PathType Container)) {
        New-Item -ItemType Directory -Path $restoredPsProfileDir -Force | Out-Null
    }
    Copy-Item -LiteralPath $restoredWinPsProfile -Destination $restoredPsProfile -Force
    Write-Host "RESTORED_PS_PROFILE_MIRROR=$restoredPsProfile"
}
$resume = Join-Path $scriptRoot 'resume.sh'
Start-HermesTrayAfterRestore -ExePath $hermesTrayExe
if (Test-Path -LiteralPath $resume -PathType Leaf) {
    Write-Host 'PROGRESS resher-resume: starting'
    $resumeOverlapDeadline = (Get-Date).AddSeconds(120)
    $resumeFinished = $false
    while (-not $resumeFinished) {
        & $wslExe -d $Distro -u root -- bash (ConvertTo-WslPath $resume)
        $resumeExitCode = $LASTEXITCODE
        if ($resumeExitCode -eq 0) {
            $resumeFinished = $true
            break
        }
        if ($resumeExitCode -ne 75) {
            throw "Hermes resume after restore failed with exit code $resumeExitCode"
        }
        Write-Warning 'Hermes resume overlap detected; another fleet resume is already running. Waiting for the in-flight resume or lock release.'
        Start-Sleep -Seconds 10
        try {
            Invoke-HermesRestoreReadinessProbe
            Write-Host 'PROGRESS resher-resume: reused existing in-flight fleet resume'
            $resumeFinished = $true
            break
        } catch {
            if ((Get-Date) -ge $resumeOverlapDeadline) {
                throw "Hermes resume overlap did not clear within 120 seconds; latest exit code 75"
            }
        }
    }
    Write-Host 'PROGRESS resher-resume: finished'
}
Invoke-HermesRestoreReadinessProbe
Start-HermesTrayAfterRestore -ExePath $hermesTrayExe
Write-Host "RESTORED_BACKUP_ID=$BackupId"
Write-Host 'RESTORE_MODE=full overlay restore of all archived Hermes bot homes/sessions/chats/workspaces; use -SlashCommandsOnly only when explicitly wanted'
