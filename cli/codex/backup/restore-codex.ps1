#Requires -Version 5.1
<#
.SYNOPSIS
    Restore Codex from the latest backup with incremental skip semantics.
.DESCRIPTION
    Restores Codex/OpenAI-related data from F:\backup\claudecode. Identical files are
    skipped so rerunning shortly after a backup should finish very quickly. The script
    prefers a RESTORE-MAP.json for exact path reconstruction and falls back to the
    well-known Codex backup layout when the map is missing.
.PARAMETER BackupPath
    Optional backup path. Defaults to F:\backup\claudecode\latest, or the newest
    timestamped backup if latest is unavailable.
.PARAMETER RepairLatestBackupMap
    Reconstruct and write RESTORE-MAP.json into the latest backup and newest snapshot
    using the current machine's path layout, then exit.
.PARAMETER Force
    Reserved for future use.
.PARAMETER SkipPrerequisites
    Skip WinGet bootstrap and package installation.
.PARAMETER DryRun
    Print planned restore tasks without copying data.
#>
[CmdletBinding()]
param(
    [string]$BackupPath,
    [switch]$RepairLatestBackupMap,
    [switch]$Force,
    [switch]$SkipPrerequisites,
    [switch]$DryRun
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'Continue'

$script:Errors = New-Object System.Collections.Generic.List[string]
$script:Restored = 0
$script:Skipped = 0
$script:Missing = 0
$script:Failed = 0
$script:Installed = 0

$HP = $env:USERPROFILE
$A = $env:APPDATA
$L = $env:LOCALAPPDATA
$BackupRoot = 'F:\backup\claudecode'
$MatchRx = 'codex|openai|chatgpt'

function Write-Stage {
    param([string]$Message,[string]$Level='INFO')
    $color = switch ($Level) {
        'OK' { 'Green' }
        'WARN' { 'Yellow' }
        'ERR' { 'Red' }
        'STEP' { 'Cyan' }
        default { 'Gray' }
    }
    Write-Host "$(Get-Date -Format 'HH:mm:ss') [$Level] $Message" -ForegroundColor $color
}

function Update-OverallProgress {
    param([string]$Status,[int]$Percent)
    Write-Progress -Id 0 -Activity 'Codex restore' -Status $Status -PercentComplete $Percent
}

function Get-LatestTimestampedBackup {
    if (-not (Test-Path $BackupRoot)) { return $null }
    Get-ChildItem $BackupRoot -Directory -EA SilentlyContinue |
        Where-Object { $_.Name -match '^backup_\d{4}_\d{2}_\d{2}' } |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}

function Resolve-BackupPath {
    param([string]$InputPath)
    if ($InputPath) { return $InputPath }
    $snap = Get-LatestTimestampedBackup
    if ($snap) { return $snap.FullName }
    $latest = Join-Path $BackupRoot 'latest'
    if ((Test-Path $latest) -and (Get-ChildItem $latest -Force -EA SilentlyContinue | Measure-Object).Count -gt 0) {
        return $latest
    }
    throw "No backup found under $BackupRoot"
}

function Resolve-PointerSnapshot {
    param([string]$Path)
    $pointerFile = Join-Path $Path 'BACKUP-POINTER.json'
    if (-not (Test-Path $pointerFile)) { return $Path }
    try {
        $pointer = Get-Content $pointerFile -Raw | ConvertFrom-Json
        if ($pointer.ResolvedPath -and (Test-Path $pointer.ResolvedPath)) { return [string]$pointer.ResolvedPath }
        if ($pointer.TargetRelative) {
            $candidate = [System.IO.Path]::GetFullPath((Join-Path $Path ([string]$pointer.TargetRelative)))
            if (Test-Path $candidate) { return $candidate }
        }
    } catch {}
    return $Path
}

function Ensure-Directory {
    param([string]$Path)
    if (-not $Path) { return }
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-SafeName {
    param([string]$Path)
    ($Path -replace ':','' -replace '[\\\/]','_').Trim('_')
}

function Add-MapEntry {
    param(
        [System.Collections.Generic.List[object]]$List,
        [string]$BackupRelative,
        [string]$TargetPath,
        [ValidateSet('File','Directory')]$ItemType,
        [string]$Description,
        [bool]$Critical = $false
    )
    $List.Add([pscustomobject]@{
        BackupRelative = $BackupRelative
        TargetPath = $TargetPath
        ItemType = $ItemType
        Description = $Description
        Critical = $Critical
    }) | Out-Null
}

function New-GeneratedRestoreMap {
    $map = New-Object System.Collections.Generic.List[object]
    $codexRoot = "$HP\.codex"

    Add-MapEntry $map 'core\codex-home' $codexRoot 'Directory' '.codex full home' $true
    Add-MapEntry $map 'core\config.toml' "$codexRoot\config.toml" 'File' '.codex/config.toml' $true
    Add-MapEntry $map 'core\settings.json' "$codexRoot\settings.json" 'File' '.codex/settings.json' $true
    Add-MapEntry $map 'core\auth.json' "$codexRoot\auth.json" 'File' '.codex/auth.json' $true
    Add-MapEntry $map 'core\AGENTS.md' "$codexRoot\AGENTS.md" 'File' '.codex/AGENTS.md' $true
    Add-MapEntry $map 'core\CLAUDE.md' "$codexRoot\CLAUDE.md" 'File' '.codex/CLAUDE.md' $true
    Add-MapEntry $map 'core\learned.md' "$codexRoot\learned.md" 'File' '.codex/learned.md' $true
    Add-MapEntry $map 'core\MEMORY.md' "$codexRoot\MEMORY.md" 'File' '.codex/MEMORY.md' $true
    Add-MapEntry $map 'sessions\history.jsonl' "$codexRoot\history.jsonl" 'File' '.codex/history.jsonl' $true
    Add-MapEntry $map 'sessions\session_index.jsonl' "$codexRoot\session_index.jsonl" 'File' '.codex/session_index.jsonl' $true
    Add-MapEntry $map 'core\resource-config.json' "$codexRoot\resource-config.json" 'File' '.codex/resource-config.json' $false
    Add-MapEntry $map 'mcp\mcp-servers.json' "$codexRoot\mcp-servers.json" 'File' '.codex/mcp-servers.json' $false
    Add-MapEntry $map 'core\codex-global-state.json' "$codexRoot\.codex-global-state.json" 'File' '.codex global state' $false

    foreach ($name in @('prompts','skills','rules','hooks','scripts','channels','workspace','projects','sessions','memory','memories','sqlite','vendor_imports','bin','.sandbox')) {
        Add-MapEntry $map "core\subdirs\$name" (Join-Path $codexRoot $name) 'Directory' ".codex/$name" $false
    }

    Add-MapEntry $map 'agents\home-AGENTS.md' "$HP\AGENTS.md" 'File' 'Home AGENTS.md' $false
    Add-MapEntry $map 'agents\home-CLAUDE.md' "$HP\CLAUDE.md" 'File' 'Home CLAUDE.md' $false
    Add-MapEntry $map 'git\.gitconfig' "$HP\.gitconfig" 'File' '.gitconfig' $false
    Add-MapEntry $map 'git\.gitignore_global' "$HP\.gitignore_global" 'File' '.gitignore_global' $false
    Add-MapEntry $map 'git\.git-credentials' "$HP\.git-credentials" 'File' '.git-credentials' $false
    Add-MapEntry $map 'npm\.npmrc' "$HP\.npmrc" 'File' '.npmrc' $false
    Add-MapEntry $map 'powershell\ps5-profile.ps1' "$HP\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" 'File' 'PS5 profile' $false
    Add-MapEntry $map 'powershell\ps7-profile.ps1' "$HP\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" 'File' 'PS7 profile' $false
    Add-MapEntry $map 'tooling\backup-scripts' 'F:\study\repos\ai-ml\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\backup' 'Directory' 'Codex backup scripts workspace' $false
    Add-MapEntry $map 'tooling\codex-cli-root' 'F:\study\repos\ai-ml\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex' 'Directory' 'Codex CLI workspace' $false

    $wingetLinks = "$L\Microsoft\WinGet\Links"
    Add-MapEntry $map 'executables\winget-links-full' $wingetLinks 'Directory' 'WinGet links full' $false

    $rootsToScan = @(
        "$HP\.config",
        "$HP\.local\share",
        "$HP\.local\state",
        "$HP\.cache",
        $A,
        $L,
        "$HP\AppData\LocalLow",
        "$env:ProgramData"
    )
    foreach ($root in $rootsToScan) {
        if (Test-Path $root) {
            Get-ChildItem $root -Directory -Force -EA SilentlyContinue | Where-Object { $_.Name -match $MatchRx } | ForEach-Object {
                $safe = Get-SafeName $_.FullName
                Add-MapEntry $map "discovered\roots\$safe" $_.FullName 'Directory' "Discovered root: $($_.FullName)" $false
            }
        }
    }

    $browserProfiles = @(
        @{ Root = "$L\Google\Chrome\User Data"; Prefix = 'chrome' },
        @{ Root = "$L\Microsoft\Edge\User Data"; Prefix = 'edge' },
        @{ Root = "$L\BraveSoftware\Brave-Browser\User Data"; Prefix = 'brave' }
    )
    foreach ($browser in $browserProfiles) {
        if (Test-Path $browser.Root) {
            Get-ChildItem $browser.Root -Directory -EA SilentlyContinue | Where-Object { $_.Name -match '^(Default|Profile \d+)$' } | ForEach-Object {
                $profileDir = $_
                $profileName = $profileDir.Name -replace ' ','-'
                foreach ($storageName in @('IndexedDB','Local Storage','Session Storage','databases')) {
                    $sub = Join-Path $profileDir.FullName $storageName
                    if (Test-Path $sub) {
                        Get-ChildItem $sub -Force -EA SilentlyContinue | Where-Object { $_.Name -match $MatchRx } | ForEach-Object {
                            $destName = "$($browser.Prefix)-$profileName-$($_.Name -replace '[\\/:*?""<>| ]','_')"
                            Add-MapEntry $map "browsers\$destName" $_.FullName 'Directory' "$($browser.Prefix) $profileName $($_.Name)" $false
                        }
                    }
                }
            }
        }
    }
    if (Test-Path "$A\Mozilla\Firefox\Profiles") {
        Get-ChildItem "$A\Mozilla\Firefox\Profiles" -Directory -EA SilentlyContinue | ForEach-Object {
            $profile = $_
            $storage = Join-Path $profile.FullName 'storage\default'
            if (Test-Path $storage) {
                Get-ChildItem $storage -Directory -EA SilentlyContinue | Where-Object { $_.Name -match $MatchRx } | ForEach-Object {
                    $destName = "firefox-$($profile.Name)-$($_.Name -replace '[\\/:*?""<>| ]','_')"
                    Add-MapEntry $map "browsers\$destName" $_.FullName 'Directory' "Firefox $($profile.Name) $($_.Name)" $false
                }
            }
        }
    }

    $projectRoots = @("$HP\Projects","$HP\repos","$HP\dev","$HP\code","F:\Projects","D:\Projects","F:\study")
    foreach ($root in $projectRoots) {
        if (Test-Path $root) {
            try {
                foreach ($dir in [System.IO.Directory]::EnumerateDirectories($root, '.codex', [System.IO.SearchOption]::AllDirectories)) {
                    if ($dir -notmatch '\\(\.git|node_modules|dist|build|__pycache__|\.venv|venv)\\') {
                        $safe = ($dir -replace ':','_' -replace '\\','_').Trim('_')
                        Add-MapEntry $map "project-codex\$safe" $dir 'Directory' "Project .codex: $dir" $false
                    }
                }
            } catch {}
            try {
                foreach ($file in [System.IO.Directory]::EnumerateFiles($root, 'AGENTS.md', [System.IO.SearchOption]::AllDirectories)) {
                    if ($file -notmatch '\\(\.git|node_modules|dist|build|__pycache__|\.venv|venv)\\') {
                        $safe = ($file -replace ':','_' -replace '\\','_').Trim('_')
                        Add-MapEntry $map "project-instructions\$safe" $file 'File' "Project AGENTS.md: $file" $false
                    }
                }
            } catch {}
        }
    }

    if (Test-Path "$L\Packages") {
        Get-ChildItem "$L\Packages" -Directory -Filter '*CanonicalGroup*' -EA SilentlyContinue | ForEach-Object {
            $homeRoot = Join-Path $_.FullName 'LocalState\rootfs\home'
            if (Test-Path $homeRoot) {
                Get-ChildItem $homeRoot -Directory -EA SilentlyContinue | ForEach-Object {
                    $linuxHome = $_.FullName
                    foreach ($suffix in @('.codex','.config/codex','.local/share/codex','.local/state/codex','.cache/codex')) {
                        $candidate = Join-Path $linuxHome $suffix
                        if (Test-Path $candidate) {
                            $safe = ($candidate -replace ':','' -replace '[\\\/]','_').Trim('_')
                            Add-MapEntry $map "wsl\$safe" $candidate 'Directory' "WSL: $candidate" $false
                        }
                    }
                }
            }
        }
    }

    foreach ($driveRoot in @('D:\','E:\','F:\')) {
        if (Test-Path $driveRoot) {
            $drive = $driveRoot.Substring(0,1)
            Get-ChildItem $driveRoot -Directory -Depth 2 -EA SilentlyContinue | Where-Object {
                $_.Name -match $MatchRx -and
                $_.FullName -notlike "$BackupRoot*" -and
                $_.FullName -notlike 'F:\backup\codex*'
            } | ForEach-Object {
                $safe = Get-SafeName $_.FullName
                Add-MapEntry $map "drives\$drive-$safe" $_.FullName 'Directory' "Drive $drive discovered: $($_.FullName)" $false
            }
        }
    }

    [pscustomobject]@{
        GeneratedAt = (Get-Date -Format 'o')
        Computer = $env:COMPUTERNAME
        User = $env:USERNAME
        Entries = $map
    }
}

function Save-RestoreMap {
    param([string[]]$BackupBases)
    $map = New-GeneratedRestoreMap
    $json = $map | ConvertTo-Json -Depth 6
    foreach ($base in $BackupBases | Where-Object { $_ -and (Test-Path $_) } | Select-Object -Unique) {
        [System.IO.File]::WriteAllText((Join-Path $base 'RESTORE-MAP.json'), $json, [System.Text.UTF8Encoding]::new($false))
        Write-Stage "Wrote RESTORE-MAP.json to $base" 'OK'
    }
}

function Load-RestoreMap {
    param([string]$Base)
    $mapFile = Join-Path $Base 'RESTORE-MAP.json'
    if (Test-Path $mapFile) {
        return Get-Content $mapFile -Raw | ConvertFrom-Json
    }
    return $null
}

function Ensure-Winget {
    if (Get-Command winget -EA SilentlyContinue) { return $true }
    try {
        $pkg = Get-AppxPackage -Name 'Microsoft.DesktopAppInstaller' -EA SilentlyContinue
        if ($pkg) {
            Add-AppxPackage -RegisterByFamilyName -MainPackage $pkg.PackageFamilyName -EA Stop
            if (Get-Command winget -EA SilentlyContinue) { return $true }
        }
    } catch {}
    return $false
}

function Ensure-Prerequisites {
    if ($SkipPrerequisites) { return }
    Write-Stage 'Checking prerequisites' 'STEP'
    $hasWinget = Ensure-Winget
    if (-not $hasWinget) {
        Write-Stage 'winget unavailable; prerequisite install skipped' 'WARN'
        return
    }

    $packages = @(
        @{ Cmd = 'codex';  Id = 'OpenAI.Codex';            Name = 'Codex CLI' },
        @{ Cmd = 'git';    Id = 'Git.Git';                 Name = 'Git' },
        @{ Cmd = 'node';   Id = 'OpenJS.NodeJS.LTS';       Name = 'Node.js' },
        @{ Cmd = 'python'; Id = 'Python.Python.3.11';      Name = 'Python' },
        @{ Cmd = 'rg';     Id = 'BurntSushi.ripgrep.MSVC'; Name = 'ripgrep' }
    )
    foreach ($pkg in $packages) {
        if (Get-Command $pkg.Cmd -EA SilentlyContinue) { continue }
        Write-Stage "Installing $($pkg.Name) via winget" 'STEP'
        try {
            & winget install --id $pkg.Id --accept-package-agreements --accept-source-agreements | Out-Null
            if ($LASTEXITCODE -eq 0) {
                $script:Installed++
                Write-Stage "$($pkg.Name) installed" 'OK'
            } else {
                Write-Stage "$($pkg.Name) install returned exit code $LASTEXITCODE" 'WARN'
            }
        } catch {
            Write-Stage "$($pkg.Name) install failed: $($_.Exception.Message)" 'WARN'
        }
    }
}

function Test-SameFile {
    param([string]$Source,[string]$Target)
    if (-not ((Test-Path $Source) -and (Test-Path $Target))) { return $false }
    try {
        $s = Get-Item $Source -Force
        $t = Get-Item $Target -Force
        return ($s.Length -eq $t.Length) -and ([math]::Abs((New-TimeSpan -Start $s.LastWriteTimeUtc -End $t.LastWriteTimeUtc).TotalSeconds) -le 2)
    } catch {
        return $false
    }
}

function Restore-File {
    param([string]$Source,[string]$Target,[string]$Description)
    if (-not (Test-Path $Source)) {
        $script:Missing++
        Write-Stage "$Description missing in backup" 'WARN'
        return
    }
    $parent = Split-Path $Target -Parent
    Ensure-Directory $parent
    if (Test-SameFile -Source $Source -Target $Target) {
        $script:Skipped++
        return
    }
    try {
        Copy-Item -LiteralPath $Source -Destination $Target -Force
        $script:Restored++
    } catch {
        try {
            $srcItem = Get-Item $Source -Force -EA SilentlyContinue
            $dstItem = Get-Item $Target -Force -EA SilentlyContinue
            if ($srcItem -and $dstItem -and $srcItem.Length -eq $dstItem.Length -and [System.IO.Path]::GetExtension($Target) -ieq '.exe') {
                $script:Skipped++
                return
            }
        } catch {}
        $script:Failed++
        $script:Errors.Add("File restore failed: $Description -> $($_.Exception.Message)")
        Write-Stage "$Description failed: $($_.Exception.Message)" 'ERR'
    }
}

function Restore-Directory {
    param([string]$Source,[string]$Target,[string]$Description)
    if (-not (Test-Path $Source)) {
        $script:Missing++
        Write-Stage "$Description missing in backup" 'WARN'
        return
    }
    Ensure-Directory $Target
    $args = @($Source, $Target, '/E', '/XO', '/XN', '/XC', '/FFT', '/R:0', '/W:0', '/MT:16', '/COPY:DAT', '/DCOPY:T', '/NFL', '/NDL', '/NJH', '/NJS', '/NP')
    & robocopy @args | Out-Null
    $code = $LASTEXITCODE
    if ($code -lt 8) {
        if ($code -band 1 -or $code -band 2 -or $code -band 4) { $script:Restored++ } else { $script:Skipped++ }
    } else {
        $script:Failed++
        $script:Errors.Add("Directory restore failed: $Description (robocopy exit $code)")
        Write-Stage "$Description failed with robocopy exit $code" 'ERR'
    }
}

function Restore-Entry {
    param([string]$Base,[object]$Entry)
    $source = Join-Path $Base $Entry.BackupRelative
    if ($Entry.ItemType -eq 'File') {
        Restore-File -Source $source -Target $Entry.TargetPath -Description $Entry.Description
    } else {
        Restore-Directory -Source $source -Target $Entry.TargetPath -Description $Entry.Description
    }
}

function Get-FallbackEntries {
    $entries = New-Object System.Collections.Generic.List[object]
    $codexRoot = "$HP\.codex"
    Add-MapEntry $entries 'core\codex-home' $codexRoot 'Directory' '.codex full home' $true
    Add-MapEntry $entries 'core\config.toml' "$codexRoot\config.toml" 'File' '.codex/config.toml' $true
    Add-MapEntry $entries 'core\settings.json' "$codexRoot\settings.json" 'File' '.codex/settings.json' $true
    Add-MapEntry $entries 'core\auth.json' "$codexRoot\auth.json" 'File' '.codex/auth.json' $true
    Add-MapEntry $entries 'core\AGENTS.md' "$codexRoot\AGENTS.md" 'File' '.codex/AGENTS.md' $true
    Add-MapEntry $entries 'core\CLAUDE.md' "$codexRoot\CLAUDE.md" 'File' '.codex/CLAUDE.md' $true
    Add-MapEntry $entries 'core\learned.md' "$codexRoot\learned.md" 'File' '.codex/learned.md' $true
    Add-MapEntry $entries 'core\MEMORY.md' "$codexRoot\MEMORY.md" 'File' '.codex/MEMORY.md' $true
    Add-MapEntry $entries 'sessions\history.jsonl' "$codexRoot\history.jsonl" 'File' '.codex/history.jsonl' $true
    Add-MapEntry $entries 'sessions\session_index.jsonl' "$codexRoot\session_index.jsonl" 'File' '.codex/session_index.jsonl' $true
    Add-MapEntry $entries 'executables\winget-links-full' "$L\Microsoft\WinGet\Links" 'Directory' 'WinGet links full' $false
    Add-MapEntry $entries 'git\.gitconfig' "$HP\.gitconfig" 'File' '.gitconfig' $false
    Add-MapEntry $entries 'npm\.npmrc' "$HP\.npmrc" 'File' '.npmrc' $false
    Add-MapEntry $entries 'powershell\ps5-profile.ps1' "$HP\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1" 'File' 'PS5 profile' $false
    Add-MapEntry $entries 'powershell\ps7-profile.ps1' "$HP\Documents\PowerShell\Microsoft.PowerShell_profile.ps1" 'File' 'PS7 profile' $false
    Add-MapEntry $entries 'tooling\backup-scripts' 'F:\study\repos\ai-ml\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\backup' 'Directory' 'Codex backup scripts workspace' $false
    Add-MapEntry $entries 'tooling\codex-cli-root' 'F:\study\repos\ai-ml\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex' 'Directory' 'Codex CLI workspace' $false
    return $entries
}

function Restore-EnvironmentVariables {
    param([string]$Base)
    $envJson = Join-Path $Base 'env\environment-variables.json'
    if (-not (Test-Path $envJson)) { return }
    Write-Stage 'Restoring environment variables' 'STEP'
    try {
        $vars = Get-Content $envJson -Raw | ConvertFrom-Json
        foreach ($prop in $vars.PSObject.Properties) {
            $name = $prop.Name
            $value = [string]$prop.Value
            if ($name -eq 'PATH') { continue }
            $current = [Environment]::GetEnvironmentVariable($name, 'User')
            if ($current -ne $value) {
                [Environment]::SetEnvironmentVariable($name, $value, 'User')
            }
        }
        $localBin = "$HP\.local\bin"
        $userPath = [Environment]::GetEnvironmentVariable('Path','User')
        if ($userPath -notlike "*$localBin*") {
            $newPath = if ([string]::IsNullOrWhiteSpace($userPath)) { $localBin } else { "$localBin;$userPath" }
            [Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
        }
    } catch {
        $script:Errors.Add("Environment variable restore failed: $($_.Exception.Message)")
        Write-Stage "Environment variable restore failed: $($_.Exception.Message)" 'WARN'
    }
}

function Restore-ScheduledTasks {
    param([string]$Base)
    $taskDir = Join-Path $Base 'scheduled-tasks'
    if (-not (Test-Path $taskDir)) { return }
    Write-Stage 'Restoring scheduled tasks' 'STEP'
    Get-ChildItem $taskDir -Filter '*.xml' -File -EA SilentlyContinue | Where-Object {
        $_.BaseName -match $MatchRx
    } | ForEach-Object {
        try {
            $taskName = $_.BaseName
            schtasks /create /tn $taskName /xml $_.FullName /f 2>$null | Out-Null
        } catch {
            $script:Errors.Add("Scheduled task restore failed: $($_.FullName)")
        }
    }
}

function Restore-Registry {
    param([string]$Base)
    $regDir = Join-Path $Base 'registry'
    if (-not (Test-Path $regDir)) { return }
    Write-Stage 'Restoring registry exports' 'STEP'
    Get-ChildItem $regDir -Filter '*.reg' -File -EA SilentlyContinue | Where-Object {
        $_.Name -match $MatchRx
    } | ForEach-Object {
        try {
            reg import $_.FullName /reg:64 2>$null | Out-Null
        } catch {
            $script:Errors.Add("Registry import failed: $($_.FullName)")
        }
    }
}

$selectedBackup = Resolve-BackupPath -InputPath $BackupPath
$resolvedBackup = Resolve-PointerSnapshot -Path $selectedBackup
if (-not (Test-Path $resolvedBackup)) { throw "Backup path not found: $resolvedBackup" }

if ($RepairLatestBackupMap) {
    $targets = @()
    $latestPath = Join-Path $BackupRoot 'latest'
    if (Test-Path $latestPath) { $targets += $latestPath }
    $latestSnap = Get-LatestTimestampedBackup
    if ($latestSnap) { $targets += $latestSnap.FullName }
    if (-not $targets) { throw "No backup targets found under $BackupRoot for map repair" }
    Save-RestoreMap -BackupBases $targets
    return
}

$backupMap = Load-RestoreMap -Base $resolvedBackup
$entries = if ($backupMap -and $backupMap.Entries) { @($backupMap.Entries) } else { @(Get-FallbackEntries) }

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Write-Host ''
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host '  CODEX RESTORE - INCREMENTAL, EXACT-PATH WHEN MAP IS AVAILABLE' -ForegroundColor White
Write-Host "  Selected backup: $selectedBackup" -ForegroundColor DarkGray
if ($resolvedBackup -ne $selectedBackup) {
    Write-Host "  Resolved payload: $resolvedBackup" -ForegroundColor DarkGray
}
Write-Host "  Tasks: $($entries.Count)" -ForegroundColor Yellow
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host ''

Ensure-Prerequisites

if ($DryRun) {
    $entries | Select-Object Description,ItemType,BackupRelative,TargetPath | Format-Table -AutoSize
    Write-Stage "Dry run only. Planned restore entries: $($entries.Count)" 'OK'
    return
}

for ($i = 0; $i -lt $entries.Count; $i++) {
    $entry = $entries[$i]
    $pct = [int]((($i + 1) / [Math]::Max($entries.Count,1)) * 85)
    Update-OverallProgress -Status ("Task {0}/{1}: {2}" -f ($i + 1), $entries.Count, $entry.Description) -Percent $pct
    Write-Stage ("[{0}/{1}] {2}" -f ($i + 1), $entries.Count, $entry.Description) 'STEP'
    Restore-Entry -Base $resolvedBackup -Entry $entry
}

Update-OverallProgress -Status 'Restoring environment variables' -Percent 90
Restore-EnvironmentVariables -Base $resolvedBackup

Update-OverallProgress -Status 'Restoring registry' -Percent 93
Restore-Registry -Base $resolvedBackup

Update-OverallProgress -Status 'Restoring scheduled tasks' -Percent 96
Restore-ScheduledTasks -Base $resolvedBackup

Update-OverallProgress -Status 'Writing restore report' -Percent 99
$sw.Stop()
$report = [pscustomobject]@{
    Timestamp = (Get-Date -Format 'o')
    BackupPath = $resolvedBackup
    Restored = $script:Restored
    Skipped = $script:Skipped
    Missing = $script:Missing
    Failed = $script:Failed
    Installed = $script:Installed
    DurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds,1)
    ErrorCount = $script:Errors.Count
    Errors = @($script:Errors)
}

$reportDir = "$HP\.codex"
Ensure-Directory $reportDir
[System.IO.File]::WriteAllText((Join-Path $reportDir ("restore-report-{0}.json" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))), ($report | ConvertTo-Json -Depth 6), [System.Text.UTF8Encoding]::new($false))

Write-Progress -Id 0 -Activity 'Codex restore' -Completed
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host '  RESTORE COMPLETE' -ForegroundColor Green
Write-Host ('=' * 80) -ForegroundColor Cyan
Write-Host "Restored : $($script:Restored)" -ForegroundColor Green
Write-Host "Skipped  : $($script:Skipped)" -ForegroundColor Yellow
Write-Host "Missing  : $($script:Missing)" -ForegroundColor DarkGray
Write-Host "Failed   : $($script:Failed)" -ForegroundColor $(if($script:Failed -eq 0){'Green'}else{'Red'})
Write-Host "Installed: $($script:Installed)" -ForegroundColor Magenta
Write-Host "Duration : $([math]::Round($sw.Elapsed.TotalSeconds,1))s" -ForegroundColor Cyan
if ($script:Errors.Count -gt 0) {
    Write-Host ''
    Write-Host 'Errors:' -ForegroundColor Red
    $script:Errors | Select-Object -First 10 | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
}
