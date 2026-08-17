[CmdletBinding()]
param(
    [string] $BackupRoot = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backups',
    [string] $BackupId = 'latest',
    [string] $Distro = 'ubuntu',
    [string] $AutoBackResPath = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes',
    [switch] $ValidateOnly,
    [switch] $PlanOnly,
    [switch] $NoResume
)
$ErrorActionPreference = 'Stop'
function Assert-File([string]$Path, [string]$Label) { if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { throw "Missing $Label`: $Path" } }
function Assert-Dir([string]$Path, [string]$Label) { if (-not (Test-Path -LiteralPath $Path -PathType Container)) { throw "Missing $Label`: $Path" } }
function ConvertTo-WslPath([string]$WindowsPath) {
    $full = [System.IO.Path]::GetFullPath($WindowsPath)
    $drive = $full.Substring(0,1).ToLowerInvariant()
    $rest = $full.Substring(3).Replace('\','/')
    return "/mnt/$drive/$rest"
}
if ($BackupId -eq 'latest') {
    $latest = Join-Path $BackupRoot 'LATEST.txt'
    Assert-File $latest 'LATEST marker'
    $BackupId = (Get-Content -LiteralPath $latest -Raw).Trim()
    if ([string]::IsNullOrWhiteSpace($BackupId)) { throw "LATEST.txt is empty: $latest" }
}
$backupDir = Join-Path $BackupRoot $BackupId
$toolDir = Join-Path $backupDir 'windows-tool-files'
Assert-Dir $backupDir 'backup directory'
Assert-Dir $toolDir 'Windows tool backup directory'
$archive = Join-Path $backupDir 'hermes-wsl-data.tar.gz'
$pathList = Join-Path $backupDir 'hermes-wsl-data.paths.txt'
$manifestPath = Join-Path $backupDir 'manifest.json'
Assert-File $archive 'Hermes WSL archive'
Assert-File $pathList 'Hermes WSL path list'
Assert-File $manifestPath 'manifest'
$requiredToolFiles = @('Microsoft.PowerShell_profile.ps1','HermesTray.exe','run-HermesTray.ps1','run-hermes-wsl2-gateway.ps1','resume.sh','resher-fast.ps1','backher-fast.ps1')
foreach ($name in $requiredToolFiles) { Assert-File (Join-Path $toolDir $name) "Windows tool file $name" }
$manifest = Get-Content -LiteralPath $manifestPath -Raw | ConvertFrom-Json
if (-not $manifest.archive_sha256) { throw "Manifest missing archive_sha256: $manifestPath" }
$actualHash = (Get-FileHash -LiteralPath $archive -Algorithm SHA256).Hash
if ($actualHash -ine $manifest.archive_sha256) { throw "Archive hash mismatch for $archive" }
$wslExe = Join-Path $env:SystemRoot 'System32\wsl.exe'
if (-not (Test-Path -LiteralPath $wslExe -PathType Leaf)) { $wslExe = 'wsl.exe' }
& $wslExe -d $Distro -u root -- bash -lc 'printf WSL_OK'
if ($LASTEXITCODE -ne 0) { throw "WSL distro '$Distro' is not ready. Install/import Ubuntu before restoring." }
New-Item -ItemType Directory -Path $AutoBackResPath -Force | Out-Null
$copyErrors = @()
Get-ChildItem -LiteralPath $toolDir -File | Where-Object { $_.Name -ne 'windows-tool-files.txt' } | ForEach-Object {
    $dest = Join-Path $AutoBackResPath $_.Name
    try { Copy-Item -LiteralPath $_.FullName -Destination $dest -Force -ErrorAction Stop }
    catch {
        if (Test-Path -LiteralPath $dest -PathType Leaf) { Write-Warning "Could not overwrite $dest (probably running/locked); kept existing file for this validation/run: $($_.Exception.Message)" }
        else { $copyErrors += "Failed to restore required file $($_.Name): $($_.Exception.Message)" }
    }
}
if ($copyErrors.Count) { throw ($copyErrors -join '; ') }
$profileTarget = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$profileDir = Split-Path -Parent $profileTarget
New-Item -ItemType Directory -Path $profileDir -Force | Out-Null
Copy-Item -LiteralPath (Join-Path $toolDir 'Microsoft.PowerShell_profile.ps1') -Destination $profileTarget -Force
Write-Host "BOOTSTRAP_PROFILE_READY=$profileTarget"
Write-Host "BOOTSTRAP_AUTOBACKRES_READY=$AutoBackResPath"
$resher = Join-Path $AutoBackResPath 'resher-fast.ps1'
Assert-File $resher 'canonical resher-fast.ps1'
$oldTarOptions = $env:TAR_OPTIONS
$oldWslEnv = $env:WSLENV
try {
    & $resher -BackupRoot $BackupRoot -BackupId $BackupId -Distro $Distro -ValidateOnly:$ValidateOnly -PlanOnly:$PlanOnly -NoTelegramProbe
    if ($LASTEXITCODE -ne $null -and $LASTEXITCODE -ne 0) { throw "resher-fast exited with $LASTEXITCODE" }
} finally {
    if ($null -eq $oldTarOptions) { Remove-Item Env:\TAR_OPTIONS -ErrorAction SilentlyContinue } else { $env:TAR_OPTIONS = $oldTarOptions }
    if ($null -eq $oldWslEnv) { Remove-Item Env:\WSLENV -ErrorAction SilentlyContinue } else { $env:WSLENV = $oldWslEnv }
}
if (-not $ValidateOnly -and -not $PlanOnly -and -not $NoResume) {
    $resume = Join-Path $AutoBackResPath 'resume.sh'
    if (Test-Path -LiteralPath $resume -PathType Leaf) { & $wslExe -d $Distro -u root -- bash (ConvertTo-WslPath $resume) }
}
Write-Host "FRESH_WINDOWS_RESTORE_READY backup=$BackupId mode=$(if ($ValidateOnly) { 'validate' } elseif ($PlanOnly) { 'plan' } else { 'restore' })"
