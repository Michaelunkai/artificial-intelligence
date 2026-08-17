[CmdletBinding()]
param(
    [string] $Distro = 'ubuntu',
    [string] $BackupRoot = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backups',
    [switch] $PlanOnly,
    [switch] $RestartGateway,
    [switch] $NoRestartGateway,
    [switch] $KeepPreviousBackup,
    [switch] $SkipPostValidate,
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
function ConvertFrom-WslNativePathToUnc([string]$DistroName, [string]$WslPath) {
    $relative = $WslPath.TrimStart('/').Replace('/','\')
    $primary = "\\wsl.localhost\$DistroName\$relative"
    if (Test-Path -LiteralPath $primary) { return $primary }
    return "\\wsl$\$DistroName\$relative"
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
function Get-HermesTrayProcess([string]$ExePath) {
    $resolved = [System.IO.Path]::GetFullPath($ExePath)
    @(Get-CimInstance Win32_Process -Filter "Name = 'HermesTray.exe'" -ErrorAction SilentlyContinue | Where-Object {
        $_.ExecutablePath -and ([System.IO.Path]::GetFullPath($_.ExecutablePath) -ieq $resolved)
    })
}
function Stop-HermesTrayForBackup([string]$ExePath) {
    $processes = @(Get-HermesTrayProcess -ExePath $ExePath)
    if ($processes.Count -eq 0) {
        Write-Host 'HERMES_TRAY_PRE_BACKUP=not-running'
        return $false
    }
    Write-Host ("HERMES_TRAY_BACKUP_KEEP_RUNNING=1 pids={0}" -f (($processes | ForEach-Object { $_.ProcessId }) -join ','))
    return $false
}
function Start-HermesTrayAfterBackup([string]$ExePath) {
    if (-not (Test-Path -LiteralPath $ExePath -PathType Leaf)) { return }
    $processes = @(Get-HermesTrayProcess -ExePath $ExePath)
    if ($processes.Count -eq 0) {
        $started = Start-Process -FilePath $ExePath -WindowStyle Hidden -PassThru
        Write-Host "HERMES_TRAY_RELAUNCHED_AFTER_BACKUP_PID=$($started.Id)"
    } else {
        Write-Host "HERMES_TRAY_ALREADY_RUNNING_AFTER_BACKUP_PID=$($processes[0].ProcessId)"
    }
}
function Assert-ChildPath([string]$Root, [string]$Child, [string]$Label) {
    $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\','/')
    $childFull = [System.IO.Path]::GetFullPath($Child).TrimEnd('\','/')
    $prefix = $rootFull + [System.IO.Path]::DirectorySeparatorChar
    if (-not ($childFull.StartsWith($prefix, [System.StringComparison]::OrdinalIgnoreCase))) {
        throw "$Label is outside backup root: $childFull"
    }
}
function Remove-PreviousHermesBackups([string]$Root, [string]$PreserveBackupId = '') {
    if (-not (Test-Path -LiteralPath $Root -PathType Container)) { return }
    $rootFull = [System.IO.Path]::GetFullPath($Root)
    $oldBackups = @(Get-ChildItem -LiteralPath $Root -Directory -ErrorAction SilentlyContinue | Where-Object {
        $_.Name -match '^\d{8}-\d{6}$' -and ([string]::IsNullOrWhiteSpace($PreserveBackupId) -or $_.Name -ne $PreserveBackupId)
    } | Sort-Object Name)
    if ($oldBackups.Count -eq 0) {
        Write-Host 'PROGRESS backher-prune: no previous Hermes backup directories found'
        return
    }
    if (-not [string]::IsNullOrWhiteSpace($PreserveBackupId)) {
        Write-Host ("PROGRESS backher-prune: preserving_current_backup={0}" -f $PreserveBackupId)
    }
    Write-Host ("PROGRESS backher-prune: deleting_previous_count={0}" -f $oldBackups.Count)
    foreach ($dir in $oldBackups) {
        Assert-ChildPath -Root $rootFull -Child $dir.FullName -Label 'Hermes backup prune target'
        Write-Host ("PROGRESS backher-prune: deleting={0}" -f $dir.FullName)
        $deleted = $false
        for ($attempt = 1; $attempt -le 10 -and -not $deleted; $attempt++) {
            try {
                Remove-Item -LiteralPath $dir.FullName -Recurse -Force -ErrorAction Stop
                $deleted = $true
            } catch {
                if ($attempt -eq 10) {
                    $pendingName = "{0}.delete-pending-{1}" -f $dir.FullName,(Get-Date -Format 'yyyyMMdd-HHmmss')
                    Write-Host ("PROGRESS backher-prune: lock_persisted_no_wsl_terminate path={0}" -f $dir.FullName)
                    try {
                        Move-Item -LiteralPath $dir.FullName -Destination $pendingName -Force -ErrorAction Stop
                        Write-Host ("PROGRESS backher-prune: deferred_locked_backup_delete renamed_to={0}" -f $pendingName)
                        $deleted = $true
                        break
                    } catch {
                        Write-Host ("PROGRESS backher-prune: deferred_locked_backup_delete_failed path={0} error={1}" -f $dir.FullName,$_.Exception.Message)
                        Write-Host 'PROGRESS backher-prune: continuing_without_wsl_termination'
                        break
                    }
                }
                Write-Host ("PROGRESS backher-prune: waiting_for_lock_release retry={0} path={1}" -f $attempt,$dir.FullName)
                Start-Sleep -Milliseconds (250 * $attempt)
            }
        }
    }
    $latestPath = Join-Path $Root 'LATEST.txt'
    if (Test-Path -LiteralPath $latestPath -PathType Leaf) { Remove-Item -LiteralPath $latestPath -Force -ErrorAction Stop }
    Write-Host 'PROGRESS backher-prune: finished'
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
$script:BackherWslExe = $wslExe
$script:BackherDistro = $Distro
if ($PlanOnly) {
    Write-Host "PLANONLY_BACKHER_BACKUP_ROOT=$BackupRoot"
} else {
    New-Item -ItemType Directory -Path $BackupRoot -Force | Out-Null
}
$hermesTrayExe = Join-Path $scriptRoot 'HermesTray.exe'
$script:BackherTrayStopped = $false
$script:BackherPlanWorkspace = $null
trap {
    if ($PlanOnly -and $script:BackherPlanWorkspace -and (Test-Path -LiteralPath $script:BackherPlanWorkspace -PathType Container)) {
        Write-Host "PROGRESS backher-plan-cleanup: removing $script:BackherPlanWorkspace"
        Remove-Item -LiteralPath $script:BackherPlanWorkspace -Recurse -Force -ErrorAction SilentlyContinue
        $script:BackherPlanWorkspace = $null
    }
    if ($script:BackherTrayStopped) { Start-HermesTrayAfterBackup -ExePath $hermesTrayExe }
    throw
}
if (-not $PlanOnly) {
    $script:BackherTrayStopped = Stop-HermesTrayForBackup -ExePath $hermesTrayExe
}
$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backupDir = if ($PlanOnly) {
    Join-Path ([System.IO.Path]::GetTempPath()) ("backher-plan-$stamp")
} else {
    Join-Path $BackupRoot $stamp
}
New-Item -ItemType Directory -Path $backupDir -Force | Out-Null
if ($PlanOnly) {
    $script:BackherPlanWorkspace = $backupDir
    Write-Host "PLANONLY_BACKHER_TEMP_WORKSPACE=$backupDir"
}
$backupDirWsl = ConvertTo-WslPath $backupDir
$toolDir = Join-Path $backupDir 'windows-tool-files'
New-Item -ItemType Directory -Path $toolDir -Force | Out-Null
if ($PlanOnly) {
    Write-Host 'PLANONLY_BACKHER_SKIP_WINDOWS_TOOL_COPY=1'
    'plan-only-no-tool-copy' | Set-Content -LiteralPath (Join-Path $toolDir 'windows-tool-files.txt') -Encoding UTF8
} else {
    Get-ChildItem -LiteralPath $scriptRoot -File -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Extension -in @('.ps1','.sh','.cs','.exe','.html','.md','.txt') -and
            $_.Name -notmatch '(\.log$|\.pid\.txt$|\.out\.log$|\.err\.log$|\.bak-|^windows-tool-files\.txt$)'
        } |
        ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $toolDir $_.Name) -Force }
    $profileBackupSource = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
    if (Test-Path -LiteralPath $profileBackupSource -PathType Leaf) {
        Copy-Item -LiteralPath $profileBackupSource -Destination (Join-Path $toolDir 'Microsoft.PowerShell_profile.ps1') -Force
    }
    Get-ChildItem -LiteralPath $toolDir -File -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name | Set-Content -LiteralPath (Join-Path $toolDir 'windows-tool-files.txt') -Encoding UTF8
}
$windowsRelatedDir = Join-Path $backupDir 'windows-related-files'
New-Item -ItemType Directory -Path $windowsRelatedDir -Force | Out-Null
$windowsRelatedManifest = @()
if ($PlanOnly) {
    Write-Host 'PLANONLY_BACKHER_SKIP_WINDOWS_RELATED_ARCHIVES=1'
} else {
    $windowsTarExe = Join-Path $env:SystemRoot 'System32\tar.exe'
    if (-not (Test-Path -LiteralPath $windowsTarExe -PathType Leaf)) { $windowsTarExe = 'tar.exe' }
    function New-HermesWindowsArchive([string]$SourceRoot, [string]$RestoreRoot, [string]$ArchiveName, [string[]]$Entries) {
        if (-not (Test-Path -LiteralPath $SourceRoot -PathType Container)) { return }
        $existingEntries = @($Entries | Where-Object { Test-Path -LiteralPath (Join-Path $SourceRoot $_) })
        if ($existingEntries.Count -eq 0) { return }
        $archivePath = Join-Path $windowsRelatedDir $ArchiveName
        $manifestPath = Join-Path $backupDir ($ArchiveName + '.manifest.txt')
        $excludeNames = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
        foreach ($name in @('.git','node_modules','.cache','cache','.pytest_cache','__pycache__','.mypy_cache','.ruff_cache','.tox','tmp','.tmp','logs','log','downloads','file-history','sessions','archived_sessions')) {
            [void]$excludeNames.Add($name)
        }
        $excludeRelativePrefixes = @('plugins/cache')
        $archiveEntries = New-Object 'System.Collections.Generic.List[string]'
        foreach ($entry in $existingEntries) {
            $entryPath = Join-Path $SourceRoot $entry
            $entryItem = Get-Item -LiteralPath $entryPath -Force -ErrorAction SilentlyContinue
            if ($null -eq $entryItem) { continue }
            if (-not $entryItem.PSIsContainer) {
                $archiveEntries.Add($entry.Replace('\','/'))
                continue
            }
            if ($excludeNames.Contains($entryItem.Name)) { continue }
            $pending = New-Object System.Collections.Generic.Stack[object]
            $pending.Push($entryItem)
            while ($pending.Count -gt 0) {
                $current = $pending.Pop()
                if ($excludeNames.Contains($current.Name)) { continue }
                $relativeCurrent = $current.FullName.Substring($SourceRoot.Length).TrimStart('\').Replace('\','/')
                $skipPrefix = $false
                foreach ($prefix in $excludeRelativePrefixes) {
                    if ($relativeCurrent.Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or $relativeCurrent.StartsWith($prefix + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                        $skipPrefix = $true
                        break
                    }
                }
                if ($skipPrefix) { continue }
                try {
                    $children = @(Get-ChildItem -LiteralPath $current.FullName -Force -ErrorAction Stop)
                } catch {
                    Write-Host ("WARN backher-windows-archive: skipped unreadable dir: {0}" -f $current.FullName)
                    continue
                }
                foreach ($child in $children) {
                    if ($excludeNames.Contains($child.Name)) { continue }
                    $relativeChild = $child.FullName.Substring($SourceRoot.Length).TrimStart('\').Replace('\','/')
                    $skipChildPrefix = $false
                    foreach ($prefix in $excludeRelativePrefixes) {
                        if ($relativeChild.Equals($prefix, [System.StringComparison]::OrdinalIgnoreCase) -or $relativeChild.StartsWith($prefix + '/', [System.StringComparison]::OrdinalIgnoreCase)) {
                            $skipChildPrefix = $true
                            break
                        }
                    }
                    if ($skipChildPrefix) { continue }
                    if ($child.PSIsContainer) {
                        $pending.Push($child)
                        continue
                    }
                    if ($child.Name -match '\.(log|tmp|pid)$' -or $child.Name -match '\.sqlite-(shm|wal)$') { continue }
                    $archiveEntries.Add($relativeChild)
                }
            }
        }
        if ($archiveEntries.Count -eq 0) { return }
        [System.IO.File]::WriteAllLines($manifestPath, [string[]]$archiveEntries, [System.Text.UTF8Encoding]::new($false))
        $tarArgs = @('-cf', $archivePath, '-C', $SourceRoot, '-T', $manifestPath)
        & $windowsTarExe @tarArgs
        if ($LASTEXITCODE -ne 0) { throw "tar.exe failed while backing up Hermes-related Windows files from $SourceRoot to $archivePath (exit $LASTEXITCODE)" }
        $script:windowsRelatedManifest += [ordered]@{ source_root = $SourceRoot; restore_root = $RestoreRoot; archive = $ArchiveName; type = 'archive'; entries = $existingEntries }
    }
    New-HermesWindowsArchive 'C:\Users\micha\Documents\WindowsPowerShell' 'C:\Users\micha\Documents\WindowsPowerShell' 'powershell-profile.tar' @('Microsoft.PowerShell_profile.ps1')
    New-HermesWindowsArchive 'C:\Users\micha\.codex' 'C:\Users\micha\.codex' 'codex-hermes-support.tar' @('AGENTS.md','config.toml','settings.json','hooks.json','set-tg-commands.ps1','skills','prompts','hooks','scripts','rules')
    New-HermesWindowsArchive 'C:\Users\micha\.agents' 'C:\Users\micha\.agents' 'agents-hermes-support.tar' @('skills','plugins')
    New-HermesWindowsArchive 'C:\Users\micha\.claude' 'C:\Users\micha\.claude' 'claude-hermes-support.tar' @('commands','hooks','skills','scripts','settings.json','set-tg-commands.ps1')
}
$windowsRelatedManifest | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath (Join-Path $backupDir 'windows-related-files.json') -Encoding UTF8
$bash = @'
set -euo pipefail
backup_dir="$1"
plan_only="$2"
resume_script="${3:-}"
mkdir -p "$backup_dir"
path_list="$backup_dir/hermes-wsl-data.paths.txt"
summary="$backup_dir/hermes-wsl-data.summary.txt"
archive="$backup_dir/hermes-wsl-data.tar.gz"
resume_started=0
resume_gateways() {
  if [ "$plan_only" = "1" ] || [ "$resume_started" = "1" ]; then return 0; fi
  resume_started=1
  if [ -n "$resume_script" ] && [ -f "$resume_script" ]; then
    echo "PROGRESS backher-wsl-gateway: resuming"
    resume_log="$backup_dir/backher-resume.log"
    nohup bash "$resume_script" >"$resume_log" 2>&1 &
    echo "PROGRESS backher-wsl-gateway: resume_started log=$resume_log"
    return 0
  fi
}
stop_gateways() {
  [ "$plan_only" = "1" ] && return 0
  echo "PROGRESS backher-wsl-gateway: keep_running_no_interrupt"
  return 0
}
trap resume_gateways EXIT
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
for p in /home/*/.hermes /home/*/.hermes-* /root/.hermes /root/.hermes-*; do
  [ -L "$p" ] || continue
  target="$(readlink -f "$p" 2>/dev/null || true)"
  add_path "$target"
done
for env in /proc/[0-9]*/environ; do
  [ -r "$env" ] || continue
  { tr '\0' '\n' < "$env" 2>/dev/null || true; } | sed -n 's/^HERMES_HOME=//p'
done | sort -u | while IFS= read -r p; do
  add_path "$p"
  if [ -L "$p" ]; then
    target="$(readlink -f "$p" 2>/dev/null || true)"
    add_path "$target"
  fi
done
sort -u -o "$path_list" "$path_list"
if [ ! -s "$path_list" ]; then echo 'No Hermes-related WSL paths found' >&2; exit 20; fi
{
  echo '== full Hermes/all-bot archive path list =='
  cat "$path_list"
  echo '== selected sizes =='
  echo 'Skipped in fast mode so backup/restore readiness is not delayed by recursive pre-scan.'
} > "$summary"
if [ "$plan_only" = "1" ]; then cat "$summary"; exit 0; fi
stop_gateways
if command -v sqlite3 >/dev/null 2>&1; then
  echo "PROGRESS backher-wsl-sqlite: checkpointing"
  while IFS= read -r -d '' db; do
    sqlite3 "$db" 'PRAGMA wal_checkpoint(TRUNCATE);' >/dev/null 2>&1 || true
  done < <(find /home/ubuntu -maxdepth 3 -path '/home/ubuntu/.hermes*/*.db' -print0 2>/dev/null)
fi
if command -v zstd >/dev/null 2>&1; then
  archive="$backup_dir/hermes-wsl-data.tar.zst"
  compressor='zstd -1 -T0'
elif command -v pigz >/dev/null 2>&1; then
  compressor='pigz -1 -p 8'
else
  compressor='gzip -1'
fi
tar_code=0
tar_err="$backup_dir/hermes-wsl-data.tar.stderr.txt"
tar --xattrs --acls --numeric-owner --use-compress-program="$compressor" \
  --warning=no-file-changed --ignore-failed-read \
  --exclude='home/*/.hermes/gateway.lock' --exclude='home/*/.hermes/gateway.pid' \
  --exclude='home/*/.hermes-*/gateway.lock' --exclude='home/*/.hermes-*/gateway.pid' \
  --exclude='root/.hermes/gateway.lock' --exclude='root/.hermes/gateway.pid' \
  --exclude='root/.hermes-*/gateway.lock' --exclude='root/.hermes-*/gateway.pid' \
  --exclude='home/*/.hermes*/*-shm' --exclude='home/*/.hermes*/*-wal' \
  --exclude='home/*/.hermes*/**/*-shm' --exclude='home/*/.hermes*/**/*-wal' \
  --exclude='home/*/.hermes*/**/node_modules' --exclude='home/*/.hermes*/lsp' \
  --exclude='home/*/.hermes*/hermes-agent/.venv' --exclude='home/*/.hermes*/hermes-agent/venv' --exclude='home/*/.hermes*/hermes-agent/node_modules' \
  --exclude='home/*/.hermes/node' --exclude='home/*/.hermes/tv-control-venv' \
  --exclude='home/*/.hermes*/cache' --exclude='home/*/.hermes*/audio_cache' --exclude='home/*/.hermes*/logs' --exclude='home/*/.hermes*/cron/output' \
  --exclude='home/*/.cache/uv' --exclude='home/*/.cache/ms-playwright' --exclude='home/*/.local/share/uv' --exclude='home/*/.local/bin/uv' \
  --exclude='root/.hermes*/logs' --exclude='root/.hermes*/cache' \
  -C / -cpf "$archive" -T "$path_list" 2>"$tar_err" || tar_code=$?
if [ "$tar_code" -ne 0 ]; then cat "$tar_err" >&2; exit "$tar_code"; fi
if [ ! -s "$archive" ]; then
  echo "Archive file was not created or is empty: $archive" >&2
  ls -la "$backup_dir" >&2 || true
  exit 34
fi
printf 'ARCHIVE_PATH=%s\n' "$archive"
printf 'Archive created: %s bytes (tar_exit=%s). Run resher -ValidateOnly for full archive listing validation.\n' "$(wc -c < "$archive")" "$tar_code"
resume_gateways
'@
$archive = Join-Path $backupDir 'hermes-wsl-data.tar.zst'
$resume = Join-Path $scriptRoot 'resume.sh'
$resumeWsl = ''
if (Test-Path -LiteralPath $resume -PathType Leaf) { $resumeWsl = ConvertTo-WslPath $resume }
$wslWorkDir = "/tmp/backher-fast-$stamp-$([guid]::NewGuid().ToString('N'))"
$stdinBashRunner = "import subprocess,sys; data=sys.stdin.buffer.read(); data=data[3:] if data.startswith(b'\xef\xbb\xbf') else data; raise SystemExit(subprocess.run(['bash','-s','--']+sys.argv[2:], input=data).returncode)"
$wslArgs = @('-d', $Distro, '-u', 'root', '--cd', '/', '--', 'python3', '-c', $stdinBashRunner, '--', $wslWorkDir, ($(if ($PlanOnly) { '1' } else { '0' })), $resumeWsl)
$wslExitCode = Invoke-WithLiveProgress -FilePath $wslExe -ArgumentList $wslArgs -Label 'backher-wsl-archive' -WorkingDirectory $env:SystemRoot -StatusPath $archive -StandardInputText (($bash -replace "`r`n", "`n" -replace "`r", "`n") + "`n")
if ($wslExitCode -ne 0) { throw "backher WSL archive step failed with exit code $wslExitCode" }
if ($PlanOnly) {
    Remove-Item -LiteralPath $backupDir -Recurse -Force -ErrorAction SilentlyContinue
    $script:BackherPlanWorkspace = $null
    & $wslExe -d $Distro -u root --cd / -- rm -rf -- $wslWorkDir 2>$null
    Write-Host "PLANONLY_BACKHER_NO_BACKUP_WRITTEN=$BackupRoot"
    return
}
$wslWorkUnc = ConvertFrom-WslNativePathToUnc -DistroName $Distro -WslPath $wslWorkDir
foreach ($name in @('hermes-wsl-data.paths.txt','hermes-wsl-data.summary.txt','hermes-wsl-data.tar.zst','hermes-wsl-data.tar.gz','hermes-wsl-data.tar.stderr.txt','backher-resume.log')) {
    $source = Join-Path $wslWorkUnc $name
    if (Test-Path -LiteralPath $source -PathType Leaf) {
        Copy-Item -LiteralPath $source -Destination (Join-Path $backupDir $name) -Force
    }
}
& $wslExe -d $Distro -u root --cd / -- rm -rf -- $wslWorkDir 2>$null
$archive = Join-Path $backupDir 'hermes-wsl-data.tar.zst'
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { $archive = Join-Path $backupDir 'hermes-wsl-data.tar.gz' }
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) {
    Get-ChildItem -LiteralPath $backupDir -Force -ErrorAction SilentlyContinue | Format-Table -AutoSize | Out-String | Write-Host
    throw "Hermes archive missing after WSL backup step: expected $archive"
}
$pathList = Join-Path $backupDir 'hermes-wsl-data.paths.txt'
$manifest = [ordered]@{
    created_at = (Get-Date).ToString('o')
    distro = $Distro
    backup_dir = $backupDir
    backup_kind = 'hermes-wsl-all-bots-fast-canonical'
    optimized_excludes = @(
        'rebuildable dependency trees only: venv/node_modules/lsp/node/uv/playwright caches',
        'runtime logs/cache/cron output/gateway locks only',
        'sessions, configs, state snapshots, Telegram bot homes, slash-command skills, hooks, and profiles are intentionally included'
    )
    archive = (Split-Path -Leaf $archive)
    archive_sha256 = $null
    archive_hash_status = 'skipped in hot backup path to avoid rereading the full archive; backher runs resher-fast -ValidateOnly unless -SkipPostValidate is supplied'
    archive_bytes = (Get-Item -LiteralPath $archive).Length
    restore_command = 'resher'
    includes = @(Get-Content -LiteralPath $pathList | ForEach-Object { $_.ToString() })
    compression = $(if ((Split-Path -Leaf $archive) -eq 'hermes-wsl-data.tar.zst') { 'zstd-level-1-multithreaded' } else { 'pigz-or-gzip-level-1' })
    windows_side_files = @(Get-ChildItem -LiteralPath $toolDir -File | Where-Object { $_.Name -ne 'windows-tool-files.txt' } | Select-Object -ExpandProperty Name)
    windows_related_manifest = 'windows-related-files.json'
    windows_related_items = $windowsRelatedManifest
}
$manifest | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath (Join-Path $backupDir 'manifest.json') -Encoding UTF8
if (-not $SkipPostValidate) {
    $resherFast = Join-Path $scriptRoot 'resher-fast.ps1'
    if (-not (Test-Path -LiteralPath $resherFast -PathType Leaf)) { throw "Post-backup validation script not found: $resherFast" }
    Write-Host ("PROGRESS backher-post-validate: backup={0} starting" -f $stamp)
    & $resherFast -BackupId $stamp -Distro $Distro -BackupRoot $BackupRoot -ValidateOnly -NoTelegramProbe
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { throw "Post-backup resher validation failed with exit code $LASTEXITCODE for $stamp" }
    Write-Host ("PROGRESS backher-post-validate: backup={0} finished" -f $stamp)
}
if (-not $KeepPreviousBackup) {
    Remove-PreviousHermesBackups -Root $BackupRoot -PreserveBackupId $stamp
}
$stamp | Set-Content -LiteralPath (Join-Path $BackupRoot 'LATEST.txt') -Encoding ASCII
if ($RestartGateway -and -not $NoRestartGateway) {
    $resume = Join-Path $scriptRoot 'resume.sh'
    if (Test-Path -LiteralPath $resume -PathType Leaf) { & $wslExe -d $Distro -u root -- bash (ConvertTo-WslPath $resume) }
}
Write-Host "BACKUP_ID=$stamp"
Write-Host "BACKUP_DIR=$backupDir"
Write-Host "HERMES_ARCHIVE=$archive"
Write-Host ("COVERAGE=all discovered /home/*/.hermes* bot homes plus live HERMES_HOME paths and Hermes CLI/session/cache/state/tooling paths; {0} root paths" -f $manifest.includes.Count)
if ($script:BackherTrayStopped) {
    Start-HermesTrayAfterBackup -ExePath $hermesTrayExe
    $script:BackherTrayStopped = $false
}
