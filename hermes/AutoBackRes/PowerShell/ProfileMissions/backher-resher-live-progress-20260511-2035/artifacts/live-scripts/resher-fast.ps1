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
if ($BackupId -eq 'latest') {
    $latest = Join-Path $BackupRoot 'LATEST.txt'
    if (-not (Test-Path -LiteralPath $latest -PathType Leaf)) { throw "LATEST.txt not found under $BackupRoot" }
    $BackupId = (Get-Content -LiteralPath $latest -Raw).Trim()
}
$backupDir = Join-Path $BackupRoot $BackupId
if (-not (Test-Path -LiteralPath $backupDir -PathType Container)) { throw "Backup directory not found: $backupDir" }
$archive = Join-Path $backupDir 'hermes-wsl-data.tar.gz'
$pathList = Join-Path $backupDir 'hermes-wsl-data.paths.txt'
$manifestPath = Join-Path $backupDir 'manifest.json'
if (-not (Test-Path -LiteralPath $archive -PathType Leaf)) { throw "Missing Hermes data archive: $archive" }
if (-not (Test-Path -LiteralPath $pathList -PathType Leaf)) { throw "Missing Hermes data path list: $pathList" }
if (Test-Path -LiteralPath $manifestPath -PathType Leaf) {
    $manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
    if ($manifest.archive_sha256) {
        $actual = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
        if ($actual -ine $manifest.archive_sha256) { throw 'Hermes data archive hash mismatch' }
    }
}
$backupDirWsl = ConvertTo-WslPath $backupDir
$bash = @'
set -euo pipefail
backup_dir="$1"
mode="$2"
archive="$backup_dir/hermes-wsl-data.tar.gz"
path_list="$backup_dir/hermes-wsl-data.paths.txt"
while IFS= read -r p; do
  p="${p%$'\r'}"
  [ -n "$p" ] || continue
  case "$p" in
    home/*/.hermes|home/*/.hermes/*|home/*/.hermes-*|home/*/.hermes-*/*|root/.hermes|root/.hermes/*|root/.hermes-*|root/.hermes-*/*|opt/hermes|opt/hermes/*|opt/hermes-*|opt/hermes-*/*|srv/hermes|srv/hermes/*|srv/hermes-*|srv/hermes-*/*|home/*/.codex|home/*/.codex/*|home/*/.config/hermes|home/*/.config/hermes/*|home/*/.config/hermes-*|home/*/.config/hermes-*/*|home/*/.config/uv|home/*/.config/uv/*|home/*/.local/bin/hermes|home/*/.local/bin/node|home/*/.local/bin/npm|home/*/.local/bin/npx|home/*/.local/bin/corepack|home/*/.local/bin/uv|home/*/.local/bin/uvx|home/*/.local/state/hermes|home/*/.local/state/hermes/*|home/*/.local/state/hermes-*|home/*/.local/state/hermes-*/*|home/*/.local/share/hermes|home/*/.local/share/hermes/*|home/*/.local/share/hermes-*|home/*/.local/share/hermes-*/*|home/*/.local/share/uv|home/*/.local/share/uv/*|home/*/.cache/ms-playwright|home/*/.cache/ms-playwright/*|home/*/.cache/uv|home/*/.cache/uv/*|home/*/.bashrc|home/*/.profile|home/*/.bash_profile) ;;
    *) echo "Refusing unsafe restore path from list: $p" >&2; exit 40 ;;
  esac
done < "$path_list"
if [ "$mode" = "plan" ]; then echo '== full restore path list =='; cat "$path_list"; exit 0; fi
tar -tzf "$archive" >/tmp/resher-listing.$$
entries=$(wc -l </tmp/resher-listing.$$)
rm -f /tmp/resher-listing.$$
echo "Restore input verified: $entries archive entries"
if [ "$mode" = "validate" ]; then exit 0; fi
tar --xattrs --acls --numeric-owner --overwrite --delay-directory-restore -C / -xzpf "$archive"
sync
'@
$mode = 'restore'
if ($PlanOnly) { $mode = 'plan' }
if ($ValidateOnly) { $mode = 'validate' }
$runScript = Join-Path $backupDir 'resher-fast.sh'
[System.IO.File]::WriteAllText($runScript, ($bash -replace "`r`n", "`n" -replace "`r", "`n"), [System.Text.Encoding]::ASCII)
$wslArgs = @('-d', $Distro, '-u', 'root', '--', 'bash', (ConvertTo-WslPath $runScript), $backupDirWsl, $mode)
$wslExitCode = Invoke-WithLiveProgress -FilePath $wslExe -ArgumentList $wslArgs -Label 'resher-wsl-restore' -WorkingDirectory $backupDir -StatusPath $archive
if ($wslExitCode -ne 0) { throw "resher WSL restore step failed with exit code $wslExitCode" }
if ($PlanOnly -or $ValidateOnly) { return }
$toolBackupDir = Join-Path $backupDir 'windows-tool-files'
if (Test-Path -LiteralPath $toolBackupDir -PathType Container) {
    Get-ChildItem -LiteralPath $toolBackupDir -File | Where-Object { $_.Name -ne 'windows-tool-files.txt' } | ForEach-Object {
        Copy-Item -LiteralPath $_.FullName -Destination (Join-Path $scriptRoot $_.Name) -Force
    }
}
$resume = Join-Path $scriptRoot 'resume.sh'
if (Test-Path -LiteralPath $resume -PathType Leaf) { & $wslExe -d $Distro -u root -- bash (ConvertTo-WslPath $resume) }
Write-Host "RESTORED_BACKUP_ID=$BackupId"
Write-Host 'RESTORE_MODE=full overlay restore of all archived Hermes bot homes/sessions/chats/workspaces; use -SlashCommandsOnly only when explicitly wanted'
