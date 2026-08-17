[CmdletBinding()]
param(
    [string] $Distro = 'ubuntu',
    [string] $BackupRoot = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backups',
    [switch] $PlanOnly,
    [switch] $RestartGateway,
    [switch] $NoRestartGateway,
    [switch] $Legacy,
    [Parameter(ValueFromRemainingArguments = $true)][string[]] $BackherArgs
)
$ErrorActionPreference = 'Stop'
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$legacyScript = Join-Path $scriptRoot 'backup-hermes-wsl2.ps1'
if ($Legacy -or ($BackherArgs -and $BackherArgs.Count -gt 0)) {
    if (-not (Test-Path -LiteralPath $legacyScript -PathType Leaf)) { throw "Legacy backup script not found: $legacyScript" }
    & $legacyScript @BackherArgs
    exit $LASTEXITCODE
}
function ConvertTo-WslPath([string]$WindowsPath) {
    $full = [System.IO.Path]::GetFullPath($WindowsPath)
    $drive = $full.Substring(0,1).ToLowerInvariant()
    $rest = $full.Substring(3).Replace('\','/')
    return "/mnt/$drive/$rest"
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
function Invoke-WithLiveProgress([string]$FilePath, [string[]]$ArgumentList, [string]$Label, [string]$WorkingDirectory, [string]$StatusPath) {
    Write-Host ("PROGRESS {0}: starting" -f $Label)
    $psi = New-Object System.Diagnostics.ProcessStartInfo
    $psi.FileName = $FilePath
    $psi.Arguments = (($ArgumentList | ForEach-Object { ConvertTo-NativeArgument $_ }) -join ' ')
    $psi.WorkingDirectory = $WorkingDirectory
    $psi.UseShellExecute = $false
    $psi.RedirectStandardOutput = $false
    $psi.RedirectStandardError = $false
    $proc = New-Object System.Diagnostics.Process
    $proc.StartInfo = $psi
    if (-not $proc.Start()) { throw "Failed to start $Label" }
    $lastSecond = -1
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    while (-not $proc.HasExited) {
        Start-Sleep -Milliseconds 500
        $seconds = [int][Math]::Floor($sw.Elapsed.TotalSeconds)
        if ($seconds -ge 2 -and $seconds -ne $lastSecond) {
            $lastSecond = $seconds
            $detail = ''
            if ($StatusPath -and (Test-Path -LiteralPath $StatusPath -PathType Leaf)) {
                $bytes = (Get-Item -LiteralPath $StatusPath).Length
                $detail = (' archive={0:n1} MB' -f ($bytes / 1MB))
            }
            Write-Progress -Activity $Label -Status ("running for {0}s{1}" -f $seconds,$detail) -PercentComplete -1
            Write-Host ("PROGRESS {0}: elapsed={1}s{2}" -f $Label,$seconds,$detail)
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
New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = Join-Path $BackupRoot $stamp
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
$backupDirWsl = ConvertTo-WslPath $backupDir
$toolDir = Join-Path $backupDir 'windows-tool-files'
New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
$toolNames = @(
    'a.sh','backup-hermes-wsl2.ps1','backher-fast.ps1','build-HermesTray.ps1','enable-windows-startup.ps1',
    'hermes-command-guard.sh','hermes-tray-health.sh','HermesDashboard.html','HermesTray.cs','HermesTray.exe',
    'parse-and-validate-check.ps1','purge-backups-fast.ps1','README.md','restore-hermes-wsl2.ps1','resher-fast.ps1',
    'resume.sh','run-hermes-wsl2-gateway.ps1','run-HermesTray.ps1','sandbox-diagnose.ps1','sandbox-log-diagnose.ps1'
)
foreach ($name in $toolNames) {
    $source = Join-Path $scriptRoot $name
    if (Test-Path -LiteralPath $source -PathType Leaf) { Copy-Item -LiteralPath $source -Destination (Join-Path $toolDir $name) -Force }
}
Get-ChildItem -LiteralPath $toolDir -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Set-Content -LiteralPath (Join-Path $toolDir 'windows-tool-files.txt') -Encoding UTF8
$bash = @'
set -euo pipefail
backup_dir="$1"
plan_only="$2"
mkdir -p "$backup_dir"
path_list="$backup_dir/hermes-wsl-data.paths.txt"
summary="$backup_dir/hermes-wsl-data.summary.txt"
archive="$backup_dir/hermes-wsl-data.tar.gz"
: > "$path_list"
add_path() {
  local p="$1"
  [ -n "$p" ] || return 0
  [ -e "$p" ] || return 0
  printf '%s\n' "${p#/}" >> "$path_list"
}
for p in \
  /home/*/.hermes /home/*/.hermes-* \
  /root/.hermes /root/.hermes-* \
  /opt/hermes /opt/hermes-* /srv/hermes /srv/hermes-* \
  /home/*/.config/hermes /home/*/.config/hermes-* /home/*/.config/hermes-setup \
  /home/*/.local/state/hermes /home/*/.local/state/hermes-* \
  /home/*/.local/share/hermes /home/*/.local/share/hermes-* \
  /home/*/.codex /home/*/.config/uv /home/*/.local/bin/hermes /home/*/.local/bin/node \
  /home/*/.local/bin/npm /home/*/.local/bin/npx /home/*/.local/bin/corepack \
  /home/*/.local/bin/uv /home/*/.local/bin/uvx /home/*/.local/share/uv \
  /home/*/.cache/ms-playwright /home/*/.cache/uv \
  /home/*/.bashrc /home/*/.profile /home/*/.bash_profile; do
  add_path "$p"
done
for env in /proc/[0-9]*/environ; do
  [ -r "$env" ] || continue
  tr '\0' '\n' < "$env" 2>/dev/null | sed -n 's/^HERMES_HOME=//p'
done | sort -u | while IFS= read -r p; do add_path "$p"; done
sort -u -o "$path_list" "$path_list"
if [ ! -s "$path_list" ]; then echo 'No Hermes-related WSL paths found' >&2; exit 20; fi
{
  echo '== full Hermes/all-bot archive path list =='
  cat "$path_list"
  echo '== selected sizes =='
  while IFS= read -r p; do du -sh "/$p" 2>/dev/null || true; done < "$path_list"
} > "$summary"
if [ "$plan_only" = "1" ]; then cat "$summary"; exit 0; fi
if command -v pigz >/dev/null 2>&1; then compressor='pigz -1'; else compressor='gzip -1'; fi
tar_code=0
tar_err="$backup_dir/hermes-wsl-data.tar.stderr.txt"
tar --xattrs --acls --numeric-owner --use-compress-program="$compressor" \
  --exclude='home/*/.hermes/gateway.lock' --exclude='home/*/.hermes/gateway.pid' \
  --exclude='home/*/.hermes-*/gateway.lock' --exclude='home/*/.hermes-*/gateway.pid' \
  --exclude='root/.hermes/gateway.lock' --exclude='root/.hermes/gateway.pid' \
  --exclude='root/.hermes-*/gateway.lock' --exclude='root/.hermes-*/gateway.pid' \
  -C / -cpf "$archive" -T "$path_list" 2>"$tar_err" || tar_code=$?
if [ "$tar_code" -gt 1 ]; then cat "$tar_err" >&2; exit "$tar_code"; fi
tar -tzf "$archive" >/tmp/backher-listing.$$
entries=$(wc -l </tmp/backher-listing.$$)
rm -f /tmp/backher-listing.$$
printf 'Archive integrity verified: %s entries (tar_exit=%s)\n' "$entries" "$tar_code"
if [ "$tar_code" -eq 1 ]; then echo 'WARNING: tar reported live-file changes during backup; archive integrity still verified. Details:'; cat "$tar_err"; fi
'@
$runScript = Join-Path $backupDir 'backher-fast.sh'
[System.IO.File]::WriteAllText($runScript, ($bash -replace "`r`n", "`n" -replace "`r", "`n"), [System.Text.Encoding]::ASCII)
$archive = Join-Path $backupDir 'hermes-wsl-data.tar.gz'
$wslArgs = @('-d', $Distro, '-u', 'root', '--', 'bash', (ConvertTo-WslPath $runScript), $backupDirWsl, ($(if ($PlanOnly) { '1' } else { '0' })))
$wslExitCode = Invoke-WithLiveProgress -FilePath $wslExe -ArgumentList $wslArgs -Label 'backher-wsl-archive' -WorkingDirectory $backupDir -StatusPath $archive
if ($wslExitCode -ne 0) { throw "backher WSL archive step failed with exit code $wslExitCode" }
if ($PlanOnly) { return }
$archive = Join-Path $backupDir 'hermes-wsl-data.tar.gz'
$pathList = Join-Path $backupDir 'hermes-wsl-data.paths.txt'
$manifest = [ordered]@{
    created_at = (Get-Date).ToString('o')
    distro = $Distro
    backup_dir = $backupDir
    backup_kind = 'hermes-wsl-all-bots-fast-standalone'
    archive = 'hermes-wsl-data.tar.gz'
    archive_sha256 = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
    archive_bytes = (Get-Item -LiteralPath $archive).Length
    restore_command = 'resher'
    includes = @(Get-Content -LiteralPath $pathList | ForEach-Object { $_.ToString() })
    compression = 'pigz-or-gzip-level-1'
    windows_side_files = @(Get-ChildItem -LiteralPath $toolDir -File | Where-Object { $_.Name -ne 'windows-tool-files.txt' } | Select-Object -ExpandProperty Name)
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backupDir 'manifest.json') -Encoding UTF8
$stamp | Set-Content -LiteralPath (Join-Path $BackupRoot 'LATEST.txt') -Encoding ASCII
if ($RestartGateway -and -not $NoRestartGateway) {
    $resume = Join-Path $scriptRoot 'resume.sh'
    if (Test-Path -LiteralPath $resume -PathType Leaf) { & $wslExe -d $Distro -u root -- bash (ConvertTo-WslPath $resume) }
}
Write-Host "BACKUP_ID=$stamp"
Write-Host "BACKUP_DIR=$backupDir"
Write-Host "HERMES_ARCHIVE=$archive"
Write-Host ("COVERAGE=all discovered /home/*/.hermes* bot homes plus live HERMES_HOME paths and Hermes CLI/session/cache/state/tooling paths; {0} root paths" -f $manifest.includes.Count)
