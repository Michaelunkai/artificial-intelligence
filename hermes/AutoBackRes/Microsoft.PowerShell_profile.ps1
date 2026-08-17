function global:poweplans {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)
    powerplans @Arguments
}
function global:ccspacefast {
    [CmdletBinding()]
    param()
    $ErrorActionPreference = 'Continue'
    try {
        $drive = New-Object System.IO.DriveInfo 'C'
        $freeGb = [math]::Round(($drive.AvailableFreeSpace / 1GB), 3)
        $totalGb = [math]::Round(($drive.TotalSize / 1GB), 3)
        $usedPercent = if ($drive.TotalSize -gt 0) { [math]::Round(((($drive.TotalSize - $drive.AvailableFreeSpace) / $drive.TotalSize) * 100), 2) } else { 0 }
        Write-Output ("ccspacefast C: free={0}GB total={1}GB used={2}%" -f $freeGb, $totalGb, $usedPercent)
    } catch {
        Write-Warning ("ccspacefast could not read C: free space: {0}" -f $_.Exception.Message)
    }
}
# Slim fast PowerShell bootstrap generated on 2026-06-22 05:18:39.
# The exact previous runtime is preserved at:
# F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.runtime.ps1
$script:_prof_sw = [System.Diagnostics.Stopwatch]::StartNew()
$script:ProfileRuntimeSnapshotPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.runtime.ps1'
$script:FullProfileDefinitionsPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.definitions.ps1'
$script:FullProfileLibraryPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.ps1'
$script:ProfileRuntimeLoaded = $false
$script:ProfileRuntimeLoading = $false
$script:ProfilePowerShellArgs = @([Environment]::GetCommandLineArgs())
$script:ProfileIsCommandMode = $script:ProfilePowerShellArgs -contains '-Command' -or $script:ProfilePowerShellArgs -contains '-EncodedCommand' -or $script:ProfilePowerShellArgs -contains '-File' -or $script:ProfilePowerShellArgs -contains '-NonInteractive'
$script:ProfileIsInteractiveConsole = $Host.Name -eq 'ConsoleHost' -and [Environment]::UserInteractive -and -not $script:ProfileIsCommandMode

# Ensure child cmd.exe/batch launches can resolve core Windows executables even if PATH was clobbered.
$script:CoreWindowsPathEntries = @(
    "$env:SystemRoot\System32\WindowsPowerShell\v1.0",
    "$env:SystemRoot\System32\Wbem",
    "$env:SystemRoot",
    "$env:SystemRoot\System32"
) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
$script:CurrentPathEntries = @($env:Path -split ';' | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$script:CoreWindowsPathEntriesForPrepend = @($script:CoreWindowsPathEntries)
[array]::Reverse($script:CoreWindowsPathEntriesForPrepend)
foreach ($script:CoreWindowsPathEntry in $script:CoreWindowsPathEntriesForPrepend) {
    $script:ExpandedCoreWindowsPathEntry = [Environment]::ExpandEnvironmentVariables($script:CoreWindowsPathEntry).TrimEnd('\')
    $script:CoreWindowsPathExists = $false
    foreach ($script:CurrentPathEntry in $script:CurrentPathEntries) {
        if ([Environment]::ExpandEnvironmentVariables($script:CurrentPathEntry).TrimEnd('\') -ieq $script:ExpandedCoreWindowsPathEntry) {
            $script:CoreWindowsPathExists = $true
            break
        }
    }
    if (-not $script:CoreWindowsPathExists) {
        $script:CurrentPathEntries = @($script:CoreWindowsPathEntry) + $script:CurrentPathEntries
    }
}
$env:Path = ($script:CurrentPathEntries -join ';')

# Native system executable shims used by legacy repair functions.
function global:dism { & "$env:SystemRoot\System32\dism.exe" @args }
function global:sfc { & "$env:SystemRoot\System32\sfc.exe" @args }
function global:schtasks { & "$env:SystemRoot\System32\schtasks.exe" @args }
function global:schtasks.exe { & "$env:SystemRoot\System32\schtasks.exe" @args }
function global:shutdown { & "$env:SystemRoot\System32\shutdown.exe" @args }
function global:shutdown.exe { & "$env:SystemRoot\System32\shutdown.exe" @args }
function global:powershell { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @args }
function global:powershell.exe { & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @args }
function global:Resolve-WslExecutable {
    $roots = @($env:SystemRoot, $env:WINDIR) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique
    $candidates = @()
    foreach ($root in $roots) { $candidates += (Join-Path $root 'System32\wsl.exe') }
    if (-not [string]::IsNullOrWhiteSpace($env:ProgramFiles)) { $candidates += (Join-Path $env:ProgramFiles 'WSL\wsl.exe') }
    $candidates += @('C:\Windows\System32\wsl.exe', 'C:\Program Files\WSL\wsl.exe')
    foreach ($candidate in $candidates | Select-Object -Unique) {
        if (Test-Path -LiteralPath $candidate -PathType Leaf) { return $candidate }
    }
    throw ("wsl.exe not found. Checked: {0}" -f (($candidates | Select-Object -Unique) -join '; '))
}
function global:wsl { & (Resolve-WslExecutable) @args }
function global:wsl.exe { & (Resolve-WslExecutable) @args }

function global:100ccc {
    [CmdletBinding()]
    param(
        [switch]$Delete,
        [switch]$NoClipboard,
        [switch]$OpenReportFolder,
        [switch]$OnlyImmediatelyDeletable,
        [switch]$RefreshCache,
        [int]$EverythingLimit = 25000,
        [int]$MaxCandidates = 0,
        [string]$OutputRoot = 'F:\study\Platforms\windows\system-administration\scripts\powershell\cleanup\storage\CDriveDeleteAudit\reports\CDriveMaxSafeDeleteAudit',
        [string]$EfuPath = 'F:\downloads\A.efu',
        [int]$EfuScanLimit = 1000000
    )

    $scriptPath = 'F:\study\Platforms\windows\system-administration\scripts\powershell\cleanup\storage\CDriveDeleteAudit\Invoke-CDriveMaxSafeDeleteAudit.ps1'
    $ps5 = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "C-drive max safe cleanup script not found: $scriptPath" }
    if ((-not $Delete) -and (-not $NoClipboard) -and (-not $OpenReportFolder) -and (-not $OnlyImmediatelyDeletable) -and (-not $RefreshCache) -and ($MaxCandidates -le 0)) {
        $cacheDir = Join-Path $OutputRoot '_cache'
        $cacheCsv = Join-Path $cacheDir 'latest-max-safe-delete-candidates.csv'
        if (Test-Path -LiteralPath $cacheCsv -PathType Leaf) {
            $cacheRows = @(Import-Csv -LiteralPath $cacheCsv)
            $liveRows = New-Object System.Collections.ArrayList
            $liveBytes = 0L
            $badRows = 0
            foreach ($row in $cacheRows) {
                $item = Get-Item -LiteralPath $row.Path -ErrorAction SilentlyContinue
                if ((-not $item) -or $item.PSIsContainer) { $badRows++; continue }
                $pathText = [string]$row.Path
                if ($pathText -match '(?i)(docker|docker desktop|dockerdesktop|moby|containerd|Windows\\Containers)') { $badRows++; continue }
                if ($pathText -match '(?i)(\\|^)(ext4|docker_data|wsl|wsl2)[^\\]*\.vhdx$') { $badRows++; continue }
                if ($pathText -match '(?i)\.(vhd|vhdx|avhd|avhdx|vdi|vmdk)$') { $badRows++; continue }
                if ($pathText -match '(?i)\\(\.git|\.hg|\.svn|Hermes|\.hermes|IndexedDB|Local Storage|Session Storage|databases?)\\') { $badRows++; continue }
                if ($pathText -match '(?i)\\(Cookies|History|Login Data|Preferences|Secure Preferences|Sessions|Extensions)(\\|$)') { $badRows++; continue }
                if ([int64]$row.Bytes -ne [int64]$item.Length) { $badRows++; continue }
                $row.Bytes = [string][int64]$item.Length
                $row.LastWriteTime = $item.LastWriteTime.ToString('yyyy-MM-dd HH:mm:ss')
                $bytesForSize = [double]$item.Length
                if ($bytesForSize -ge 1GB) { $row.Size = ('{0:N1} GiB' -f ($bytesForSize / 1GB)) }
                elseif ($bytesForSize -ge 1MB) { $row.Size = ('{0:N1} MiB' -f ($bytesForSize / 1MB)) }
                elseif ($bytesForSize -ge 1KB) { $row.Size = ('{0:N1} KiB' -f ($bytesForSize / 1KB)) }
                else { $row.Size = ('{0:N0} B' -f $bytesForSize) }
                [void]$liveRows.Add($row)
                $liveBytes += [int64]$item.Length
            }
            if ($badRows -gt 0) {
                $cacheRows = @($liveRows | Sort-Object {[int64]$_.Bytes} -Descending)
                $rank = 1
                foreach ($row in $cacheRows) { if ($row.PSObject.Properties.Name -contains 'Rank') { $row.Rank = $rank }; $rank++ }
                $cacheRows | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $cacheCsv
                $jsonPath = Join-Path $cacheDir 'latest-max-safe-delete-candidates.json'
                if ($cacheRows.Count -gt 0) { $cacheRows | ConvertTo-Json -Depth 4 | Set-Content -Encoding UTF8 -Path $jsonPath } else { '[]' | Set-Content -Encoding UTF8 -Path $jsonPath }
                $summaryPathForRepair = Join-Path $cacheDir 'latest-max-safe-delete-summary.txt'
                @(
                    'C: Max Safe Delete Audit Cache'
                    ('Generated: {0}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss'))
                    'Repair: dropped stale missing/changed rows during fast 100ccc startup'
                    ('Dropped stale rows: {0}' -f $badRows)
                    ('Candidates: {0}' -f $cacheRows.Count)
                    ('Potential bytes: {0:N0}' -f $liveBytes)
                    ('Potential human: {0:N1} MiB' -f ($liveBytes / 1MB))
                    ('Source EFU: {0}' -f $EfuPath)
                ) | Set-Content -Encoding UTF8 -Path $summaryPathForRepair
            } else {
                $cacheRows = @($liveRows)
            }
            $liveGiB = [math]::Round($liveBytes / 1GB, 3)
            $payload = "`$ErrorActionPreference='Stop'; `$script='$scriptPath'; `$m='$cacheCsv'; if(-not (Test-Path -LiteralPath `$script -PathType Leaf)){ throw `"Cleanup script not found: `$script`" }; if(-not (Test-Path -LiteralPath `$m -PathType Leaf)){ throw `"Manifest not found: `$m`" }; & '$ps5' -NoProfile -ExecutionPolicy Bypass -File `$script -ForceDeleteListed -DeleteManifest `$m -ScheduleFailedForReboot; exit `$LASTEXITCODE"
            $oneLiner = ('{0} -NoProfile -ExecutionPolicy Bypass -EncodedCommand ' -f $ps5) + [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($payload))
            $oneLinerPath = Join-Path $cacheDir 'latest-max-safe-delete-one-liner.txt'
            Set-Content -Encoding ASCII -Path $oneLinerPath -Value $oneLiner
            Set-Clipboard -Value $oneLiner
            Start-Sleep -Milliseconds 50
            $actual = Get-Clipboard -Raw
            if (($null -eq $actual) -or ($actual.TrimEnd("`r","`n") -cne $oneLiner.TrimEnd("`r","`n"))) { throw '100ccc clipboard verification failed.' }
            $summaryPath = Join-Path $cacheDir 'latest-max-safe-delete-summary.txt'
            $summary = if (Test-Path -LiteralPath $summaryPath -PathType Leaf) { @(Get-Content -LiteralPath $summaryPath) } else { @() }
            $candidateLine = ($summary | Where-Object { $_ -match '^Candidates:' } | Select-Object -First 1)
            $potentialLine = ($summary | Where-Object { $_ -match '^Potential human:' } | Select-Object -First 1)
            $candidateText = $cacheRows.Count
            $potentialText = ('{0:N3} GiB live exact' -f $liveGiB)
            Write-Host ('C: max safe delete audit ready from cache. Candidates={0} Potential={1}' -f $candidateText,$potentialText) -ForegroundColor Green
            Write-Host ('CSV manifest: {0}' -f $cacheCsv) -ForegroundColor Green
            Write-Host ('One-liner file: {0}' -f $oneLinerPath) -ForegroundColor Green
            Write-Host 'The manifest-driven cleanup one-liner was copied to the clipboard.' -ForegroundColor Yellow
            return
        }
    }

    $auditArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$scriptPath,'-OutputRoot',$OutputRoot,'-EfuPath',$EfuPath,'-EfuScanLimit',[string]$EfuScanLimit,'-EverythingLimit',[string]$EverythingLimit)
    if ($MaxCandidates -gt 0) { $auditArgs += @('-MaxCandidates',[string]$MaxCandidates) }
    if ($NoClipboard -or $Delete) { $auditArgs += '-NoClipboard' }
    if ($OpenReportFolder) { $auditArgs += '-OpenReportFolder' }
    if ($OnlyImmediatelyDeletable) { $auditArgs += '-OnlyImmediatelyDeletable' }
    if ($RefreshCache) { $auditArgs += '-RefreshCache' }

    & $ps5 @auditArgs
    if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne 2)) { throw "100ccc audit failed with exit code $LASTEXITCODE" }

    if (-not $Delete) { return }

    $latest = Get-ChildItem -LiteralPath $OutputRoot -Directory -ErrorAction Stop |
        Sort-Object LastWriteTime -Descending |
        ForEach-Object { Join-Path $_.FullName 'max-safe-delete-candidates.csv' } |
        Where-Object { Test-Path -LiteralPath $_ -PathType Leaf } |
        Select-Object -First 1
    if (-not $latest) { throw "100ccc could not find a generated cleanup manifest under $OutputRoot" }

    if (-not $OnlyImmediatelyDeletable) {
        $pendingManifest = Join-Path $OutputRoot 'pending-startup-manifest.csv'
        Copy-Item -LiteralPath $latest -Destination $pendingManifest -Force
    }

    & $ps5 -NoProfile -ExecutionPolicy Bypass -File $scriptPath -ForceDeleteListed -DeleteManifest $latest -ScheduleFailedForReboot
    if (($LASTEXITCODE -ne 0) -and ($LASTEXITCODE -ne 2)) { throw "100ccc delete failed with exit code $LASTEXITCODE" }

    $taskCmd = 'cmd.exe /c "F:\study\Platforms\windows\system-administration\scripts\powershell\cleanup\storage\CDriveDeleteAudit\Run-PendingCleanup.cmd"'
    schtasks.exe /Create /TN 'CDriveMaxSafeDeleteAudit-PendingCleanup' /SC ONSTART /RU SYSTEM /RL HIGHEST /TR $taskCmd /F | Out-Null

    & $ps5 -NoProfile -ExecutionPolicy Bypass -File $scriptPath -OutputRoot $OutputRoot -EfuPath $EfuPath -EfuScanLimit $EfuScanLimit -EverythingLimit $EverythingLimit -RefreshCache -NoClipboard
}

function Repair-StandardWindowsProcessEnvironment {
    $systemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Process')
    if ([string]::IsNullOrWhiteSpace($systemRoot)) {
        $systemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
    }
    if ([string]::IsNullOrWhiteSpace($systemRoot)) { $systemRoot = 'C:\Windows' }

    $systemDrive = [Environment]::GetEnvironmentVariable('SystemDrive', 'Process')
    if ([string]::IsNullOrWhiteSpace($systemDrive) -and $systemRoot -match '^[A-Za-z]:') {
        $systemDrive = $systemRoot.Substring(0, 2)
    }
    if ([string]::IsNullOrWhiteSpace($systemDrive)) { $systemDrive = 'C:' }

    $defaults = @{
        SystemDrive = $systemDrive
        SystemRoot = $systemRoot
        windir = $systemRoot
        ProgramData = (Join-Path $systemDrive 'ProgramData')
        ALLUSERSPROFILE = (Join-Path $systemDrive 'ProgramData')
        PUBLIC = (Join-Path $systemDrive 'Users\Public')
    }

    foreach ($name in $defaults.Keys) {
        if ([string]::IsNullOrWhiteSpace([Environment]::GetEnvironmentVariable($name, 'Process'))) {
            Set-Item -Path "Env:$name" -Value $defaults[$name]
        }
    }
}

# BEGIN WILLOW-FORCE PSREADLINE HISTORY
function global:Enable-WillowForceVirtualTerminal {
    try {
        $consoleKey = 'HKCU:\Console'
        if (-not (Test-Path -LiteralPath $consoleKey)) {
            New-Item -Path $consoleKey -Force | Out-Null
        }
        New-ItemProperty -Path $consoleKey -Name 'VirtualTerminalLevel' -Value 1 -PropertyType DWord -Force | Out-Null
    } catch { }

    try {
        if (-not ('WillowForce.Console.NativeMethods' -as [type])) {
            Add-Type -TypeDefinition @"
namespace WillowForce.Console {
    using System;
    using System.Runtime.InteropServices;
    public static class NativeMethods {
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern IntPtr GetStdHandle(int nStdHandle);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool GetConsoleMode(IntPtr hConsoleHandle, out int lpMode);
        [DllImport("kernel32.dll", SetLastError=true)]
        public static extern bool SetConsoleMode(IntPtr hConsoleHandle, int dwMode);
    }
}
"@
        }
        foreach ($stdHandle in @(-11, -12)) {
            $handle = [WillowForce.Console.NativeMethods]::GetStdHandle($stdHandle)
            if ($handle -eq [IntPtr]::Zero -or $handle.ToInt64() -eq -1) { continue }
            $mode = 0
            if ([WillowForce.Console.NativeMethods]::GetConsoleMode($handle, [ref]$mode)) {
                [void][WillowForce.Console.NativeMethods]::SetConsoleMode($handle, ($mode -bor 4))
            }
        }
    } catch { }
}

function global:Initialize-FastProfilePsReadLineHistory {
    try {
        Enable-WillowForceVirtualTerminal

        $root = Join-Path $env:APPDATA 'Microsoft\Windows\PowerShell\PSReadLine'
        $sessionsDir = Join-Path $root 'sessions'
        $historyPath = Join-Path $root 'ConsoleHost_forever_history.txt'
        $archivePath = Join-Path $root 'ConsoleHost_forever_archive.txt'

        if (-not (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue)) {
            $moduleCandidates = @(
                'C:\Program Files\PowerShell\7\Modules\PSReadLine\PSReadLine.psd1',
                'C:\Program Files\WindowsPowerShell\Modules\PSReadLine\PSReadLine.psd1'
            )
            foreach ($modulePath in $moduleCandidates) {
                if (Test-Path -LiteralPath $modulePath -PathType Leaf) {
                    Import-Module $modulePath -Global -ErrorAction SilentlyContinue
                    if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) { break }
                }
            }
        }

        foreach ($dir in @($root, $sessionsDir)) {
            if (-not (Test-Path -LiteralPath $dir -PathType Container)) {
                New-Item -ItemType Directory -Path $dir -Force | Out-Null
            }
        }

        foreach ($file in @($historyPath, $archivePath)) {
            if (-not (Test-Path -LiteralPath $file -PathType Leaf)) {
                New-Item -ItemType File -Path $file -Force | Out-Null
            }
        }

        if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
            try { Set-PSReadLineOption -HistorySavePath $historyPath -HistorySaveStyle SaveIncrementally -MaximumHistoryCount 4096 -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -Colors @{ InlinePrediction = "$([char]0x1b)[38;5;244m" } -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -HistoryNoDuplicates:$false -ErrorAction SilentlyContinue } catch { }
            try { Set-PSReadLineOption -HistorySearchCursorMovesToEnd -ErrorAction SilentlyContinue } catch { }
        }
    } catch {
        if ($env:WILLOW_FORCE_HISTORY_DEBUG -eq '1') {
            Write-Error $_
        }
    }
}
# END WILLOW-FORCE PSREADLINE HISTORY

function global:nomouse {
    [Console]::Write("$([char]27)[?1000l$([char]27)[?1002l$([char]27)[?1003l$([char]27)[?1006l$([char]27)[?1015l$([char]27)[?1016l")
}

function Get-ProfileFunctionMap {
    [CmdletBinding()]
    param(
        [string]$ProfilePath = $PROFILE
    )

    if (-not (Test-Path -LiteralPath $ProfilePath)) {
        throw "Profile not found: $ProfilePath"
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ProfilePath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $parseSummary = ($errors | Select-Object -First 3 | ForEach-Object { $_.Message.Trim() }) -join ' | '
        throw "Unable to parse profile '$ProfilePath': $parseSummary"
    }

    $functionMap = @{}
    foreach ($functionAst in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $functionMap[$functionAst.Name] = $functionAst
    }

    return $functionMap
}

function Resolve-ProfileFunctionAst {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string] $FunctionName,
        [string[]] $SourcePaths
    )

    $lookupName = $FunctionName -replace '^(?i:global:)', ''
    if ([string]::IsNullOrWhiteSpace($lookupName)) { return $null }

    if (-not $SourcePaths -or $SourcePaths.Count -eq 0) {
        if (Get-Command Get-ProfileFunctionSourcePaths -CommandType Function -ErrorAction SilentlyContinue) {
            $SourcePaths = @(Get-ProfileFunctionSourcePaths)
        } else {
            $SourcePaths = @(
                $PROFILE,
                'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1',
                'C:\Users\micha\Documents\PowerShell\Microsoft.PowerShell_profile.ps1',
                $script:ProfileRuntimeSnapshotPath,
                $script:FullProfileDefinitionsPath,
                $script:FullProfileLibraryPath,
                'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.runtime.ps1',
                'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.definitions.ps1',
                'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.ps1',
                'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.ps1'
            )
        }
    }

    foreach ($sourcePath in @($SourcePaths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | Select-Object -Unique)) {
        if (-not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
        try {
            $functionMap = Get-ProfileFunctionMap -ProfilePath $sourcePath
            $actualLookupName = $functionMap.Keys | Where-Object { $_ -ieq $lookupName } | Select-Object -First 1
            if ($actualLookupName) {
                return [pscustomobject]@{
                    Name = $actualLookupName
                    Ast = $functionMap[$actualLookupName]
                    SourcePath = $sourcePath
                }
            }
        } catch {
            if ($env:CODEX_PROFILE_RESOLVE_DEBUG -eq '1') { Write-Warning $_.Exception.Message }
        }
    }

    return $null
}

function Load-FullPowerShellProfile {
    if ($script:ProfileRuntimeLoaded) { return }
    if ($script:ProfileRuntimeLoading) { return }
    if ([string]::IsNullOrWhiteSpace($script:ProfileRuntimeSnapshotPath)) {
        $script:ProfileRuntimeSnapshotPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.runtime.ps1'
    }
    if ([string]::IsNullOrWhiteSpace($script:FullProfileDefinitionsPath)) {
        $script:FullProfileDefinitionsPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.definitions.ps1'
    }
    if ([string]::IsNullOrWhiteSpace($script:FullProfileLibraryPath)) {
        $script:FullProfileLibraryPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.ps1'
    }
    $profileLoadPath = $script:ProfileRuntimeSnapshotPath
    if ([string]::IsNullOrWhiteSpace($profileLoadPath) -or -not (Test-Path -LiteralPath $profileLoadPath -PathType Leaf)) {
        $profileLoadPath = $script:FullProfileDefinitionsPath
    }
    if ([string]::IsNullOrWhiteSpace($profileLoadPath) -or -not (Test-Path -LiteralPath $profileLoadPath -PathType Leaf)) {
        $profileLoadPath = $script:FullProfileLibraryPath
    }
    if ([string]::IsNullOrWhiteSpace($profileLoadPath) -or -not (Test-Path -LiteralPath $profileLoadPath -PathType Leaf)) {
        throw "Full PowerShell profile library not found. Checked: $script:ProfileRuntimeSnapshotPath, $script:FullProfileDefinitionsPath, and $script:FullProfileLibraryPath"
    }

    $script:ProfileRuntimeLoading = $true
    try {
        $functionMap = Get-ProfileFunctionMap -ProfilePath $profileLoadPath
        foreach ($functionName in $functionMap.Keys) {
            if ($functionName -in @('Load-FullPowerShellProfile', 'fullprofile', 'Get-ProfileFunctionMap', 'Get-ProfileFunctionSourcePaths', 'cfun', 'fixwinpe', 'Repair-StandardWindowsProcessEnvironment')) { continue }
            $functionAst = $functionMap[$functionName]
            . ([scriptblock]::Create("function global:$functionName $($functionAst.Body.Extent.Text)"))
        }
        if (Get-Command Apply-HermesDockerProfileBridgeFix -CommandType Function -ErrorAction SilentlyContinue) { Apply-HermesDockerProfileBridgeFix }
        if (Test-Path -LiteralPath $script:LegacySafeProfileWrappersPath -PathType Leaf) { . $script:LegacySafeProfileWrappersPath }
        Set-Item -Path 'Function:\global:cc' -Value { Clear-Host } -Force
        $script:ProfileRuntimeLoaded = $true
    } finally {
        $script:ProfileRuntimeLoading = $false
    }
}

function global:fullprofile { Load-FullPowerShellProfile }

function global:ps527 {
    . 'F:\study\repos\shells\powershell\scripts\misc\ps527\ps527.ps1' @args
}

function global:pps527 {
    ps527 @args
}

function global:winupg {
    $ps5Path = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $scriptPath = 'F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\repair-upgrade.ps1'
    $preclearScriptPath = 'F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\Clear-RebootPendingForWinupg.ps1'
    if (Test-Path -LiteralPath $preclearScriptPath) {
        & $ps5Path -NoProfile -ExecutionPolicy Bypass -File $preclearScriptPath
    }
    $defaultArgs = @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', $scriptPath,
        '-IsoSource', 'E:\isos\Windows.iso',
        '-SkipLatestUpdateDownload',
        '-ForceClearRebootPending'
    )
    & $ps5Path @defaultArgs @args
}

function global:nupg {
    & 'F:\study\Platforms\windows\system-administration\scripts\powershell\repair\upgrade\inplace\win11\auto\repair-upgrade.ps1' @args
}

$script:LegacySafeProfileWrappersPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\legacy-safe-functions\profile-wrappers.ps1'
if (Test-Path -LiteralPath $script:LegacySafeProfileWrappersPath -PathType Leaf) {
    . $script:LegacySafeProfileWrappersPath
}

Repair-StandardWindowsProcessEnvironment

if ($script:ProfileIsInteractiveConsole) {
    try {
        $current = [System.Diagnostics.Process]::GetCurrentProcess()
        if ($current.PriorityClass -in @('Idle', 'BelowNormal', 'Normal')) {
            $current.PriorityClass = 'AboveNormal'
        }
    } catch { }
}

$gitBin = 'C:\Program Files\Git\usr\bin'
if ($env:Path -notlike "*$gitBin*") {
    $env:Path = "$gitBin;$env:Path"
}
foreach ($profilePathPart in @('F:\study\Dev_Toolchain\JavaScript\Bun\bin', 'F:\backup\Nodejs\global', 'F:\study\Shells\powershell\bin')) {
    if ($profilePathPart -and $env:Path -notlike "*$profilePathPart*") {
        $env:Path += ";$profilePathPart"
    }
}

$script:AhkX4ZCommandModePath = 'C:\Users\micha\Documents\WindowsPowerShell\legacy-safe-functions\Invoke-AhkX4ZFast.CommandMode.ps1'
if (Test-Path -LiteralPath $script:AhkX4ZCommandModePath -PathType Leaf) {
    . $script:AhkX4ZCommandModePath
}

function global:nvid {
    $script = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\ai-ml\nvidia\runtime-repair\NvidRuntimeRepair\Invoke-nvid.ps1'
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        throw "nvid backing script not found: $script"
    }
    & $script @args
}

function global:addfunc {
    $script = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\shells\powershell\profile-helpers\Addfunc\Invoke-addfunc.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        throw "addfunc script not found: $script"
    }
    if ($args -contains '-SelfTest') {
        & $script @args
        return
    }
    . $script @args
}

function global:rmfunc {
    $script = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\cleanup\maintenance-tools\Rmfunc\Invoke-rmfunc.ps1'
    if (-not (Test-Path -LiteralPath $script)) {
        throw "rmfunc script not found: $script"
    }
    if ($args -contains '-SelfTest') {
        & $script @args
        return
    }
    . $script @args
}

function global:adbcp {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Path
    )

    if (-not $Path -or $Path.Count -eq 0) {
        throw 'Usage: adbcp "file or folder or full path" ["same 2"] ["same 3"]'
    }

    foreach ($item in $Path) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        $resolved = Resolve-Path -LiteralPath $item -ErrorAction Stop
        foreach ($source in $resolved) {
            aadb push $source.ProviderPath '/sdcard/Download/'
        }
    }
}

# BEGIN CODEX MYISO COMMAND-MODE RESTORE 20260630
function myiso {
    $isoPath = 'E:\isos\Michrepair.iso'
    if (-not (Test-Path -LiteralPath $isoPath)) {
        throw "Michrepair ISO not found at $isoPath"
    }

    $ventoyDir = 'E:\ventoy'
    if (-not (Test-Path -LiteralPath $ventoyDir)) {
        New-Item -ItemType Directory -Path $ventoyDir | Out-Null
    }

    $cfg = '{"control":[{"VTOY_DEFAULT_MENU_MODE":"0"},{"VTOY_DEFAULT_SEARCH_ROOT":"/isos"},{"VTOY_MENU_TIMEOUT":"3"},{"VTOY_DEFAULT_IMAGE":"/isos/Michrepair.iso"},{"VTOY_SECONDARY_BOOT_MENU":"1"},{"VTOY_SECONDARY_TIMEOUT":"3"}]}'
    [System.IO.File]::WriteAllText((Join-Path $ventoyDir 'ventoy.json'), $cfg, [System.Text.Encoding]::ASCII)
    bcdedit /set '{fwbootmgr}' bootsequence '{ca3b1c02-399e-11f1-a7b4-f5aa42282247}'
    shutdown /r /t 0
}
# END CODEX MYISO COMMAND-MODE RESTORE 20260630

function Initialize-ProfileCommandModeFunctions {
    if (-not $script:ProfileIsCommandMode) { return }

    $proxy = {
        $calledName = $MyInvocation.MyCommand.Name
        if (-not $calledName -or $calledName -eq '&') { $calledName = $MyInvocation.InvocationName }
        if (-not $calledName -or $calledName -eq '&') { throw 'Full profile proxy could not determine the command name to reload.' }

        $lookupName = $calledName -replace '^(?i:global:)', ''
        $resolved = Resolve-ProfileFunctionAst -FunctionName $lookupName
        if ($resolved) {
            $lookupName = $resolved.Name
            . ([scriptblock]::Create("function global:$lookupName $($resolved.Ast.Body.Extent.Text)"))
            $targetCommand = Get-Command $lookupName -CommandType Function -ErrorAction Stop
            & $targetCommand @args
            return
        }

        Remove-Item -LiteralPath "Function:\global:$lookupName" -ErrorAction SilentlyContinue
        Write-Host "Function '$calledName' unavailable: profile resolver searched all known sources and found no saved definition." -ForegroundColor Yellow
    }

    $skip = @('Load-FullPowerShellProfile', 'fullprofile', 'nomouse', 'ps527', 'pps527', 'Get-ProfileFunctionMap', 'Get-ProfileFunctionSourcePaths', 'Resolve-ProfileFunctionAst', 'cfun', 'Repair-StandardWindowsProcessEnvironment', 'Apply-HermesDockerProfileBridgeFix', 'Initialize-FastProfilePsReadLineHistory', 'Initialize-ProfileCommandModeFunctions')
    foreach ($sourcePath in @($PROFILE)) {
        if ([string]::IsNullOrWhiteSpace($sourcePath) -or -not (Test-Path -LiteralPath $sourcePath -PathType Leaf)) { continue }
        $functionMap = Get-ProfileFunctionMap -ProfilePath $sourcePath
        foreach ($functionName in $functionMap.Keys) {
            $lookupName = $functionName -replace '^(?i:global:)', ''
            if ($lookupName -in $skip) { continue }
            if (Get-Command $lookupName -CommandType Function -ErrorAction SilentlyContinue) { continue }
            Set-Item -Path "Function:\global:$lookupName" -Value $proxy -Force
        }
    }
}

Initialize-ProfileCommandModeFunctions

# CODEx freeze-fix command-mode fast path 2026-06-28
function global:Get-ProfileFunctionSourcePaths {
    $paths = @(
        $PROFILE,
        'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1',
        'C:\Users\micha\Documents\PowerShell\Microsoft.PowerShell_profile.ps1',
        $script:ProfileRuntimeSnapshotPath,
        $script:FullProfileDefinitionsPath,
        $script:FullProfileLibraryPath,
        'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.runtime.ps1',
        'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.definitions.ps1',
        'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.ps1',
        'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.ps1'
    )
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([System.StringComparer]::OrdinalIgnoreCase)
    foreach ($path in $paths) {
        if ([string]::IsNullOrWhiteSpace($path)) { continue }
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { continue }
        $resolved = (Resolve-Path -LiteralPath $path).ProviderPath
        if ($seen.Add($resolved)) { $resolved }
    }
}

function global:cfun {
    param([Parameter(Mandatory = $true, Position = 0)][string]$FunctionName)
    $lookupName = $FunctionName -replace '^(?i:global:)', ''

    $liveCommand = Get-Command $lookupName -CommandType Function -ErrorAction SilentlyContinue
    if ($liveCommand) {
        $definition = '' + $liveCommand.Definition
        if ($definition -notmatch 'Full profile proxy could not determine the command name to reload') {
            if ($liveCommand.ScriptBlock -and $liveCommand.ScriptBlock.Ast) {
                $liveText = $liveCommand.ScriptBlock.Ast.Extent.Text
                if (-not [string]::IsNullOrWhiteSpace($liveText)) {
                    if ($liveText -match '^\s*param\s*\(' -or $liveText -notmatch '^\s*function\s+') {
                        return ("function global:{0} {{`r`n{1}`r`n}}" -f $lookupName, $liveText.TrimEnd())
                    }
                    return $liveText.TrimEnd()
                }
            }
            if (-not [string]::IsNullOrWhiteSpace($definition)) {
                return ("function global:{0} {{`r`n{1}`r`n}}" -f $lookupName, $definition.TrimEnd())
            }
        }
    }

    foreach ($sourcePath in Get-ProfileFunctionSourcePaths) {
        try {
            $functionMap = Get-ProfileFunctionMap -ProfilePath $sourcePath
            if ($functionMap.ContainsKey($lookupName)) {
                return $functionMap[$lookupName].Extent.Text.TrimEnd()
            }
        } catch { }
    }
    Write-Host "Function '$FunctionName' not found in live functions or profile sources: $((Get-ProfileFunctionSourcePaths) -join '; ')" -ForegroundColor Yellow
}
try { Initialize-FastProfilePsReadLineHistory } catch { }
function global:bleach {
    [CmdletBinding()]
    param([Parameter(ValueFromRemainingArguments = $true)][object[]]$Arguments)

    $script = 'F:\backup\windowsapps\installed\BleachBitAutoClean\Invoke-BleachAutoClean.ps1'
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        throw "bleach script not found: $script"
    }

    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File $script @Arguments
}

function global:scanmss {
    [CmdletBinding()]
    param(
        [switch]$Full,
        [int]$MaxMinutes = 45,
        [int]$ProgressSeconds = 3
    )

    $script = 'F:\backup\windowsapps\installed\msert\Run-MicrosoftSafetyScanner-Mega.ps1'
    if (!(Test-Path -LiteralPath $script)) {
        throw "scanmss script not found: $script"
    }

    $scanArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script, '-MaxMinutes', $MaxMinutes, '-ProgressSeconds', $ProgressSeconds)
    if ($Full) {
        $scanArgs += '-Full'
    }

    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @scanArgs
}

# BEGIN CODEX COMMAND-MODE MENU MMENU DOCKER WRAPPERS 20260706



# END CODEX COMMAND-MODE MENU MMENU DOCKER WRAPPERS 20260706

if ($script:ProfileIsCommandMode -and $env:POWERSHELL_PROFILE_FULL_IN_COMMAND -ne '1') { return }

if ($script:ProfileIsInteractiveConsole) {
    try { nomouse } catch { }
    try {
        Initialize-FastProfilePsReadLineHistory
        if (Get-Command Set-PSReadLineOption -ErrorAction SilentlyContinue) {
            Set-PSReadLineOption -PredictionSource History -ErrorAction SilentlyContinue
            Set-PSReadLineOption -PredictionViewStyle InlineView -ErrorAction SilentlyContinue
            Set-PSReadLineOption -Colors @{ InlinePrediction = "$([char]0x1b)[38;5;244m" } -ErrorAction SilentlyContinue
            Set-PSReadLineOption -HistorySearchCursorMovesToEnd -ErrorAction SilentlyContinue
        }
        if (Get-Command Set-PSReadLineKeyHandler -ErrorAction SilentlyContinue) {
            Set-PSReadLineKeyHandler -Key Tab -Function MenuComplete -ErrorAction SilentlyContinue
            Set-PSReadLineKeyHandler -Key UpArrow -Function HistorySearchBackward -ErrorAction SilentlyContinue
            Set-PSReadLineKeyHandler -Key DownArrow -Function HistorySearchForward -ErrorAction SilentlyContinue
            Set-PSReadLineKeyHandler -Key F2 -Function SwitchPredictionView -ErrorAction SilentlyContinue
        }
    } catch { }
}

$script:FullProfileFunctionNames = @(
    'Invoke-ProfileStartupOnce',
    'oll1',
    'oll2',
    'oll3',
    'oll4',
    'oll5',
    'oll6',
    'oll7',
    'oll8',
    'oll9',
    'oll10',
    'oll11',
    'oll12',
    'oll13',
    'oll14',
    'oll15',
    'oll16',
    'oll17',
    'oll18',
    'oll19',
    'oll20',
    'oll21',
    'oll22',
    'oll23',
    'oll24',
    'oll25',
    'oll26',
    'oll27',
    'oll28',
    'oll29',
    'oll30',
    'oll31',
    'oll32',
    'oll33',
    'oll34',
    'oll35',
    'oll36',
    'oll37',
    'oll38',
    'oll39',
    'oll40',
    'oll41',
    'oll42',
    'oll43',
    'oll44',
    'oll45',
    'oll46',
    'oll47',
    'oll48',
    'oll49',
    'oll50',
    'oll51',
    'oll52',
    'oll53',
    'oll54',
    'oll55',
    'oll56',
    'oll57',
    'oll58',
    'oll59',
    'oll60',
    'oll61',
    'oll62',
    'oll63',
    'oll64',
    'oll65',
    'oll66',
    'oll67',
    'oll68',
    'oll69',
    'oll70',
    'oll71',
    'oll72',
    'oll73',
    'oll74',
    'oll75',
    'oll76',
    'oll77',
    'oll78',
    'oll79',
    'oll80',
    'oll81',
    'oll82',
    'oll83',
    'oll84',
    'oll85',
    'oll86',
    'oll87',
    'oll88',
    'oll89',
    'oll90',
    'oll-scan',
    '1start',
    '2start',
    'start1',
    'start2',
    'Repair-StandardWindowsProcessEnvironment',
    '_ApplyUltimatePowerPlan',
    '_DisableAllVisualEffects',
    '_SetNetworkThrottlingMax',
    '_SetBcdeditNuclear',
    '_DisableHPET',
    '_SetTimerResMin',
    '_SetNVIDIARegistryMax',
    '_SetRyzenMax',
    '_SetDPCMax',
    '_SetMemoryNuclear',
    '_DisableBackgroundServices',
    '_SetGameModeNuclear',
    '_SetIONuclear',
    '_UnparkAllCores',
    '_DisableDefenderRealtime',
    '_SetMMCSSNuclear',
    '_DisableTelemetryNuclear',
    '_SetPCIePowerMax',
    '_SetStorageNuclear',
    '_SetNVIDIAFullProfile',
    '_EnableHAGS_VRR',
    '_DisablePowerThrottling',
    '_DisableSecurityMitigationsGaming',
    '_SetAudioGamingNuclear',
    '_SetNetworkGamingNuclear',
    '_SetKernelNuclear',
    '_DisableWindowsInterference',
    '_ClearSystemMemory',
    '_SetAdvancedNuclear',
    '_ApplyAfterburnerFlatCurve',
    '_SetGpuFanDirect',
    'ob',
    'Remove-ForceFully',
    'upnpm',
    'addmcp',
    'addclip',
    'addclip2',
    'endtask',
    'bergres',
    'bergrs',
    'gitco',
    'nn',
    'gcop',
    'getc',
    'jobtask',
    'compile',
    'tinder',
    'bumble',
    'tindershow',
    'screen',
    'brc',
    'cc',
    'ubu',
    'rewsl2',
    'stack',
    'kali',
    'down',
    'stu',
    'backup',
    'windowsapps',
    'sprox',
    'sshubu',
    'sshubuntu',
    'bashrc',
    'linkedin',
    'scpstu',
    'c',
    'gitpush',
    'gitgos',
    'ubuntu2',
    'rmubu2',
    'ubu2',
    'vid',
    'wsls',
    'kwsl',
    'shrink',
    'shrink2',
    'ccwsl',
    'text',
    'updatepip',
    'getpip',
    'rmkali',
    'rmubu',
    'rmk',
    'rmu',
    'refresh',
    'update',
    'fixupdate',
    'exports',
    'track',
    'venv',
    'venv11',
    'word',
    'reubu2',
    'defender',
    'wallp',
    'cool',
    'hot',
    'fire',
    'autofill',
    'editfill',
    'sshec2',
    'exubu2',
    'fixwsl',
    '3way',
    'webhtml',
    'scanfast',
    'scanfull',
    'pya',
    'sshplex',
    'pipreq',
    'streamlit',
    'backupec2',
    'backupec2db',
    'awsl',
    'nalias',
    'restorewsl',
    'restorewsl2',
    'ds',
    'dps',
    'dpsa',
    'dim',
    'Initialize-BackupDockerEnvironment',
    'ConvertTo-BackupDockerSlug',
    'Resolve-BackupDockerProjectPath',
    'Get-BackupDockerKnownPathMap',
    'Get-BackupDockerRepoSlugFromPathText',
    'Get-BackupDockerKnownPathForRepoSlug',
    'Get-BackupDockerSourceMapPath',
    'Get-BackupMenuInvocationMapPath',
    'Get-ProfilePsReadLineRootPath',
    'Get-ProfilePsReadLineMergedHistoryPath',
    'Get-ProfilePsReadLineSessionHistoryDirectory',
    'Get-ProfilePsReadLineSessionHistoryPath',
    'Merge-ProfilePsReadLineHistoryShards',
    'Initialize-ProfilePsReadLineHistory',
    'Sync-ProfilePsReadLineHistory',
    'Get-BackupMenuHistoryPath',
    'Get-BackupMenuTraversalSchemaVersion',
    'Get-BackupComparablePath',
    'Get-BackupMenuRepoSlug',
    'Get-BackupMenuInvocationDetails',
    'Register-BackupMenuInvocation',
    'Get-BackupMenuInvocationFromMap',
    'ConvertFrom-BackupMenuHistorySegment',
    'Get-BackupMenuInvocationFromHistory',
    'Get-BackupLatestMenuInvocation',
    'Register-BackupDockerSourcePath',
    'Get-BackupDockerRegisteredSourcePath',
    'Find-BackupDockerSourcePathInWorkspace',
    'Get-BackupDockerRepoSlugFromReference',
    'Resolve-BackupDockerSourcePathFromRepoSlug',
    'Get-BackupMenuFoldersAtLayer',
    'Get-BackupDockerRepoSlug',
    'Get-BackupDockerRepository',
    'Get-BackupDockerRepositoryFromSlug',
    'Invoke-BackupDockerLatestRestoreForRepoSlug',
    'Get-BackupDockerLatestTagNameFromSet',
    'New-BackupDockerTag',
    'Get-BackupDockerNextImageRef',
    'Get-BackupDockerHubErrorStatusCode',
    'Get-BackupDockerHubErrorResponseText',
    'Test-BackupDockerRepositoryExists',
    'Ensure-BackupDockerRepository',
    'Ensure-BackupDockerRepositorySlug',
    'ConvertFrom-BackupDockerCredentialOutput',
    'Get-BackupDockerHubJwtToken',
    'Get-BackupDockerHubTagNames',
    'Get-BackupDockerLatestTag',
    'Get-BackupDockerLatestImageRef',
    'Get-BackupDockerLatestRemoteTag',
    'ConvertTo-BackupDockerBindMountPath',
    'Invoke-BackupDockerStreamingCommand',
    'Invoke-BackupDockerImageRestore',
    'Get-BackupDockerSourcePathFromImageRef',
    'Invoke-BackupDockerLatestRestore',
    'Invoke-BackupDockerLegacySharedRestore',
    'Invoke-BackupDockerInstalledAppRestore',
    'Import-BackupDockerTar',
    'built',
    'dp',
    'drun',
    'dr',
    'drc',
    'dri',
    'dc',
    'conip',
    'killc',
    'dcu',
    'backupwsl',
    'backupapps',
    'restoreapps',
    'RestoreLinux',
    'restorebackup',
    'restorestu',
    'dcreds',
    'saveweb',
    'savegames',
    'saveplex',
    'drmariadb',
    'dcode',
    'mp3',
    'mp4',
    'getjenkins',
    'getkuma',
    'getsplunk',
    'bbb',
    'rma',
    'rms',
    'applied',
    'link',
    'hardware',
    'mygames',
    'sweb',
    'slink',
    'wslgg',
    'telebot',
    'cbackup',
    'ex',
    'rmqb',
    'qb',
    'cchrome',
    'logs2',
    'doc',
    'mas',
    'maleware',
    'dislock',
    'rmg',
    'getorch',
    'click',
    'ld',
    'lu',
    'sjob',
    'rjob',
    'splex',
    'myapps',
    'rmp',
    'rmps',
    'fix',
    'lid',
    'getparsec',
    'getmodel',
    'timer',
    'scan',
    'dsubs',
    'subs',
    'cnwsl',
    'scpmyg',
    'keyubu',
    'keyprox',
    'sub',
    'exai',
    'updates',
    'ws2',
    'wsls1',
    'wsls2',
    'venvit',
    'venvit2',
    'subit',
    'getge',
    'display',
    'de1',
    'de2',
    'fxs',
    'Ensure-ProfilePowerShellModulePath',
    'ghistory',
    'wsgg',
    'bst',
    'latest',
    'clap',
    'mac',
    'bios',
    'add_keys',
    'ggrwsl',
    'ss',
    'ggss',
    'path',
    'audio',
    'html2db',
    'rmal',
    'summ',
    'paste',
    'dislog',
    'crere',
    'rmnps',
    'formatf',
    'backsys',
    'gs1',
    'gs2',
    'autocomplete',
    'ytmp',
    'newprofile',
    'sss',
    'rmdock',
    'vcx',
    'cpit',
    'ghe',
    'Safe',
    'sfil',
    'btf',
    'gs3',
    'gsteam',
    'rmgamebar',
    'ggss2',
    'nnn',
    'top',
    'desk',
    'fixtime',
    'g1337x',
    'trim',
    'myg',
    'bcu',
    'drim',
    'getssh',
    'cleanup',
    'wish',
    'draft',
    'rmn',
    'kil',
    'sand',
    'rewemod',
    'wemod',
    'desc',
    'SafeBoot',
    'DisableSafeBoot',
    'compress',
    'uninstall',
    'discord',
    'uac',
    'reuac',
    'ahk2exe',
    'smyg',
    'scp2ubu2',
    'compc',
    'sss2',
    'ee',
    'nets',
    'rmdocker',
    'specs',
    'steam',
    'game',
    'short3',
    'unlock',
    'get7z',
    'getarm',
    'getf4',
    'fixtaskbar',
    'sfol',
    'rche',
    'superf4',
    'ytp',
    'sg',
    'ssg',
    'FixWinStore',
    'disadmin',
    'win',
    'ytapi',
    'up',
    'cpsec',
    'ytp3',
    'ccpatch',
    'ext',
    'ext2',
    'wmpatch',
    'walls',
    'wallst',
    'sus',
    'res',
    'sused',
    'resed',
    'comps',
    'rmd',
    'setup',
    'close',
    'up2',
    'liners',
    'closeahk',
    'stopstart',
    'susp',
    'ahk2ps',
    'getdotnet',
    'nvc',
    'installall',
    'runall',
    'gchome',
    'macro',
    'dboost',
    'dbo',
    'time',
    'maxpower',
    'minpower',
    'killt',
    'ffhome',
    'ffyt',
    'Copy',
    'CopyClip',
    'updater',
    'updater2',
    'ccleaner',
    'Install-DockerDesktopRobust',
    'getdocker',
    'fitfit',
    'gssh',
    'ps7run',
    'uptown',
    'geek',
    'forge',
    'frag',
    'syncfiles',
    'updateit',
    'sssync',
    'ddesk',
    'dddesk',
    'fixnet',
    'resilio',
    'ahkit',
    'muteit',
    'umnute',
    'Get-BackupMenuDockerfileContent',
    'Invoke-BackupMenuBuildPush',
    'Invoke-BackupMenuForPath',
    'Resolve-BackupMenuRestoreDestinationPath',
    'Invoke-BackupDockerRestoreFromMenuHistory',
    'Invoke-BackupMenuLogged',
    'menus',
    'unem',
    'unem2',
    'Wait-BackupDockerDesktopReady',
    'remenu',
    'unem-map',
    'menu2',
    'menu3',
    'menu4',
    'menu5',
    'menu6',
    'menu7',
    'menu8',
    'menu9',
    'menu10',
    'menu11',
    'menu12',
    'menu13',
    'menu14',
    'menu15',
    'menu16',
    'menu17',
    'menu18',
    'menu19',
    'menu20',
    'Invoke-BackupMenuAtLayer',
    'pp2',
    'savetg',
    'update2',
    'myass',
    'setset',
    'fitg',
    'n',
    'reqb',
    'wall2',
    'wall',
    'top100',
    'rere',
    'free',
    'slack',
    'forge2',
    'chris',
    'gdownloads',
    'getdocker2',
    'ytp2',
    'upps',
    'revo',
    'wise',
    'fupdate',
    'upwing',
    'Repair-StandardWindowsEnvironment',
    'wingup',
    'rmscreen',
    'rmvol',
    '1337x',
    'debloat',
    'getcho',
    'current',
    'plans',
    'fixwmi',
    'rpagefile',
    'performance',
    'myram',
    'startup',
    'bbleach',
    'getwmi',
    'fixwim',
    'runsas',
    'sophos',
    'scanit',
    'hitman',
    'getdnet',
    'menuit',
    'firefox',
    'fixwinget',
    'rmph',
    'fixWin11',
    'rmstart2',
    'curr',
    'fixpywin32',
    'getrevo',
    'cclean',
    'ccreg',
    'gdotnet',
    'rmdotnet',
    'gfront',
    'rmfront',
    'screenit',
    'ccyber',
    'ggemini2',
    'rmgemini',
    'dkill5',
    'dkill4',
    'dkill2',
    'fixfix',
    'dkill3',
    'kvrt',
    'timel',
    'gcl',
    'nn2',
    'freespace',
    'unfixc',
    'fixf',
    'compcc',
    'cctemp',
    'ddf',
    'rmdefender',
    'rrrrrr',
    'volume',
    'waitit',
    'tools',
    'term',
    'dstop',
    'cctemp2',
    'gem',
    'ggem',
    'cla',
    'ggem2',
    'qwe',
    'sshtov',
    'stov',
    'ctemp',
    'caru',
    'rerewsl',
    'lockey',
    'savesnap',
    'qw',
    'fagp',
    'fagf',
    'smisha',
    'macres',
    'rmdex',
    'rmsnap',
    'repy',
    'renode',
    'upgrade',
    'restoreit',
    'restoreit2',
    'docwin',
    'doclin',
    'bacter',
    'rester',
    'repeat',
    'docdev2',
    'ddev',
    'ddevit',
    'devit',
    'nvidia',
    'compilenet',
    'ndef',
    'filecr',
    'cleannn',
    'getcode',
    'revog',
    'docdev',
    'smyapps',
    'grust',
    'rmrust',
    'ccop',
    'sophia',
    'berglog',
    'gcode',
    'bbbb',
    'bbbbbb',
    'gitadd',
    'bbbbn',
    'codeberg',
    'rmfolders2',
    'redocker',
    'rredocker',
    'fullpath',
    'getollama',
    'vscodext',
    'rmdmp',
    'alert',
    'wse',
    'rmthis',
    '7zit',
    'gnet3',
    'gnet5',
    'gnet6',
    'gnet7',
    'gnet8',
    'gnet9',
    'gnetpreview',
    'gnet',
    'gwebdock',
    'rm7z',
    '7z7z',
    'asst',
    'fsec',
    'gsystemd',
    'getvc',
    'ram',
    'wsrm',
    'ram50',
    'rovo',
    'grovo',
    'recli',
    'rmfe',
    'gfe',
    'refe',
    'rmfe2',
    'gfe2',
    'refe2',
    'bbbbb',
    'gg',
    'sstov',
    'mpsl846',
    'mem',
    'gdroid',
    'ffpop',
    'gcpop',
    'calias',
    'gkube',
    'rmkube',
    'cdroot',
    'revolog',
    'tovpull',
    'crestore',
    'lrestore',
    'gcodex',
    'gdmcp',
    'gitit2',
    'Start-GititProcess',
    'Write-GititLogDelta',
    'Stop-GititProcess',
    'Complete-GititProcess',
    'Invoke-GititProcess',
    'Test-GittWorkNeeded',
    'gitit',
    'gitt',
    'stashit',
    'fixfix2',
    'skill',
    'pipreq2',
    'stov2',
    'cdpower',
    'cleanc',
    'claumcp',
    '7z',
    'rules',
    'powerit',
    'wingit2',
    'gsnipp',
    'dfixer',
    'getph',
    'ewslg',
    'dwslg',
    'nodecontext256kb',
    'nodecontext1mb',
    'nodecontext8mb',
    'Start-FastClean',
    'mmm',
    'sizes',
    'ccsizes',
    'ccestimate',
    'cccleanup',
    'ccdaily',
    'ccschedule',
    'ccstatus',
    'ccdisable',
    'cclogs',
    'siz',
    'refresh-disk',
    'ccclau',
    'reup',
    'reclau',
    'nodenocap',
    'mcps',
    'mcpl',
    'mcpon',
    'mcpof',
    'mcpoff',
    'fixfixfix',
    'wings',
    'wingi',
    'gpipx',
    'gprom',
    'netdefault',
    'ubustop',
    'logs',
    'fixfixfixfix',
    'fix4',
    '4fix',
    '5fix',
    'mcpson',
    'listclau',
    'rmccc',
    'wingit',
    'logit',
    'slogit',
    'lines',
    'mxtok1',
    'mxtok2',
    'mxtok3',
    'mxtok4',
    'mxtok5',
    'mxtok6',
    'mxtok7',
    'mxtok8',
    'mxtok9',
    'mxtok10',
    'mxtokoff',
    'nodenv',
    'defmod1',
    'defmod2',
    'defmod3',
    'thinkoff',
    'thinkon',
    'ultrathink',
    'netmax',
    'megaclean',
    'rmboot',
    'pppp',
    'megawsl',
    'steep1',
    'initit',
    'wsbug',
    'gclau',
    'rmram',
    'cc1',
    'cc2',
    'cc3',
    'cc4',
    'cc5',
    'cc6',
    'cc7',
    'cc8',
    'cc9',
    'cc10',
    'cc11',
    'cc12',
    'cc13',
    'cc14',
    'cc15',
    'cc16',
    'cc17',
    'cc18',
    'cc19',
    'cc20',
    'cc21',
    'cc22',
    'cc23',
    'cc24',
    'cc25',
    'cc26',
    'cc27',
    'cc28',
    'cc29',
    'cc30',
    'cc31',
    'cc32',
    'cc33',
    'cc34',
    'cc35',
    'cc36',
    'cc37',
    'cc38',
    'cc39',
    'cc40',
    'cc41',
    'cc42',
    'cc43',
    'cc44',
    'cc45',
    'cc46',
    'cc47',
    'cc48',
    'cc49',
    'cc50',
    'cc51',
    'cc52',
    'cc53',
    'cc54',
    'cc55',
    'cc56',
    'cc57',
    'cc58',
    'cc59',
    'cc60',
    'cc61',
    'cc62',
    'cc63',
    'cc64',
    'cc65',
    'cc66',
    'cc67',
    'cc68',
    'cc69',
    'cc70',
    'cc71',
    'cc72',
    'cc73',
    'cc74',
    'cc75',
    'cc76',
    'cc77',
    'cc78',
    'cc79',
    'cc80',
    'cc81',
    'cc82',
    'cc83',
    'cc84',
    'cc85',
    'cc86',
    'cc87',
    'cc88',
    'cc89',
    'cc90',
    'cc91',
    'cc92',
    'cc93',
    'cc94',
    'cc95',
    'cc96',
    'cc97',
    'cc98',
    'cc99',
    'cc100',
    'cccontext',
    'ccontext',
    'sfc',
    'bios2',
    'gsnappy',
    'rmfunc',
    'brc5',
    'Enable-WindowsModules',
    'netboost',
    'mvfunc',
    'addfunc',
    'yyyt',
    'rebackclau',
    'clml',
    'cccclau',
    'closecc',
    'Get-ClaudeModel',
    'clau2',
    'Get-ClaudeProjectCwd',
    'Resolve-ClaudeSession',
    'claur',
    'clauc',
    'codr',
    'codc',
    'ola',
    'cclist',
    'docit',
    'getuvx',
    'brules',
    'stopscan',
    'scan1',
    'scan2',
    'scan3',
    'steep',
    'fsteep',
    'fixlow',
    'rmackback',
    'reredock',
    'enmic',
    'Set-DockerHyperV',
    'dockmin',
    'dock2',
    'dock3',
    'dock4',
    'dock5',
    'dock6',
    'dock7',
    'dock8',
    'dock9',
    'dock10',
    'dockmax',
    'docsize',
    'Set-ClaudeResource',
    'claude1',
    'claude2',
    'claude3',
    'claude4',
    'claude5',
    'claude6',
    'claude7',
    'claude8',
    'claude9',
    'claude10',
    'claude11',
    'claude12',
    'claude13',
    'claude14',
    'claude15',
    'claude16',
    'claude17',
    'claude18',
    'claude19',
    'claude20',
    'claude21',
    'claude22',
    'claude23',
    'claude24',
    'claude25',
    'claude26',
    'claude27',
    'claude28',
    'claude29',
    'claude30',
    'claude31',
    'claude32',
    'claude33',
    'claude34',
    'claude35',
    'claude36',
    'claude37',
    'claude38',
    'claude39',
    'claude40',
    'claude41',
    'claude42',
    'claude43',
    'claude44',
    'claude45',
    'claude46',
    'claude47',
    'claude48',
    'claude49',
    'claude50',
    'claude51',
    'claude52',
    'claude53',
    'claude54',
    'claude55',
    'claude56',
    'claude57',
    'claude58',
    'claude59',
    'claude60',
    'claude61',
    'claude62',
    'claude63',
    'claude64',
    'claude65',
    'claude66',
    'claude67',
    'claude68',
    'claude69',
    'claude70',
    'claude71',
    'claude72',
    'claude73',
    'claude74',
    'claude75',
    'claude76',
    'claude77',
    'claude78',
    'claude79',
    'claude80',
    'claude81',
    'claude82',
    'claude83',
    'claude84',
    'claude85',
    'claude86',
    'claude87',
    'claude88',
    'claude89',
    'claude90',
    'claude91',
    'claude92',
    'claude93',
    'claude94',
    'claude95',
    'claude96',
    'claude97',
    'claude98',
    'claude99',
    'claude100',
    'claude101',
    'claude102',
    'claude103',
    'claude104',
    'claude105',
    'claude106',
    'claude107',
    'claude108',
    'claude109',
    'claude110',
    'claude111',
    'claude112',
    'claude113',
    'claude114',
    'claude115',
    'claude116',
    'claude117',
    'claude118',
    'claude119',
    'claude120',
    'claude121',
    'claude122',
    'claude123',
    'claude124',
    'claude125',
    'claude126',
    'claude127',
    'claude128',
    'claude129',
    'claude130',
    'claude131',
    'claude132',
    'claude133',
    'claude134',
    'claude135',
    'claude136',
    'claude137',
    'claude138',
    'claude139',
    'claude140',
    'claude141',
    'claude142',
    'claude143',
    'claude144',
    'claude145',
    'claude146',
    'claude147',
    'claude148',
    'claude149',
    'claude150',
    'claude151',
    'claude152',
    'claude153',
    'claude154',
    'claude155',
    'claude156',
    'claude157',
    'claude158',
    'claude159',
    'claude160',
    'claude161',
    'claude162',
    'claude163',
    'claude164',
    'claude165',
    'claude166',
    'claude167',
    'claude168',
    'claude169',
    'claude170',
    'claude171',
    'claude172',
    'claude173',
    'claude174',
    'claude175',
    'claude176',
    'claude177',
    'claude178',
    'claude179',
    'claude180',
    'claude181',
    'claude182',
    'claude183',
    'claude184',
    'claude185',
    'claude186',
    'claude187',
    'claude188',
    'claude189',
    'claude190',
    'claude191',
    'claude192',
    'claude193',
    'claude194',
    'claude195',
    'claude196',
    'claude197',
    'claude198',
    'claude199',
    'claude200',
    'claude201',
    'claude202',
    'claude203',
    'claude204',
    'claude205',
    'claude206',
    'claude207',
    'claude208',
    'claude209',
    'claude210',
    'claude211',
    'claude212',
    'claude213',
    'claude214',
    'claude215',
    'claude216',
    'claude217',
    'claude218',
    'claude219',
    'claude220',
    'claude221',
    'claude222',
    'claude223',
    'claude224',
    'claude225',
    'claude226',
    'claude227',
    'claude228',
    'claude229',
    'claude230',
    'claude231',
    'claude232',
    'claude233',
    'claude234',
    'claude235',
    'claude236',
    'claude237',
    'claude238',
    'claude239',
    'claude240',
    'claude241',
    'claude242',
    'claude243',
    'claude244',
    'claude245',
    'claude246',
    'claude247',
    'claude248',
    'claude249',
    'claude250',
    'claude251',
    'claude252',
    'claude253',
    'claude254',
    'claude255',
    'claude256',
    'claude257',
    'claude258',
    'claude259',
    'claude260',
    'claude261',
    'claude262',
    'claude263',
    'claude264',
    'claude265',
    'claude266',
    'claude267',
    'claude268',
    'claude269',
    'claude270',
    'claude271',
    'claude272',
    'claude273',
    'claude274',
    'claude275',
    'claude276',
    'claude277',
    'claude278',
    'claude279',
    'claude280',
    'claude281',
    'claude282',
    'claude283',
    'claude284',
    'claude285',
    'claude286',
    'claude287',
    'claude288',
    'claude289',
    'claude290',
    'claude291',
    'claude292',
    'claude293',
    'claude294',
    'claude295',
    'claude296',
    'claude297',
    'claude298',
    'claude299',
    'claude300',
    'claude301',
    'claude302',
    'claude303',
    'claude304',
    'claude305',
    'claude306',
    'claude307',
    'claude308',
    'claude309',
    'claude310',
    'claude311',
    'claude312',
    'claude313',
    'claude314',
    'claude315',
    'claude316',
    'claude317',
    'claude318',
    'claude319',
    'claude320',
    'claude321',
    'claude322',
    'claude323',
    'claude324',
    'claude325',
    'claude326',
    'claude327',
    'claude328',
    'claude329',
    'claude330',
    'claude331',
    'claude332',
    'claude333',
    'claude334',
    'claude335',
    'claude336',
    'claude337',
    'claude338',
    'claude339',
    'claude340',
    'claude341',
    'claude342',
    'claude343',
    'claude344',
    'claude345',
    'claude346',
    'claude347',
    'claude348',
    'claude349',
    'claude350',
    'claude351',
    'claude352',
    'claude353',
    'claude354',
    'claude355',
    'claude356',
    'claude357',
    'claude358',
    'claude359',
    'claude360',
    'claudesize',
    'defrm',
    'defadd',
    'dddefender',
    'edefender',
    'todoit',
    'clauand',
    'netconnect',
    'tovrun',
    'tovp',
    'gitpub',
    'gitpri',
    'adw',
    'gitlog',
    'dush',
    'mmac',
    'reboot',
    'rws',
    'rwsl',
    'gsniff',
    'geverything',
    'wslfull',
    'subu',
    'cclau',
    'ccode',
    'megadush',
    'conit',
    'ccope',
    'runtec',
    'bin',
    'allenv',
    'fixmic',
    'dlog',
    'docker1',
    'docker2',
    'docker3',
    'docker4',
    'docker5',
    'docker6',
    'docker7',
    'docker8',
    'docker9',
    'docker10',
    'docker11',
    'docker12',
    'docker13',
    'docker14',
    'docker15',
    'docker16',
    'docker17',
    'docker18',
    'docker19',
    'docker20',
    'docker21',
    'docker22',
    'docker23',
    'docker24',
    'docker25',
    'docker26',
    'docker27',
    'docker28',
    'docker29',
    'docker30',
    'test-all-docker-configs',
    'reset-wsl-config',
    'onstart',
    'mas2',
    'arules',
    'gbeads',
    'snapit',
    'snapres',
    'snapback',
    'search',
    'search2',
    'tstart',
    'ope',
    'uni',
    'mmyg',
    'rlp',
    'rlpnext',
    'rlpchain',
    'rlpprog',
    'mgr',
    'aahk',
    'mvgames',
    'mmvgames',
    'rmrlp',
    'rmdone',
    'dism++',
    'msr',
    'rlp1',
    'rlp3',
    'rlp4',
    'disks',
    'clawt',
    'rmcc',
    'rrredock',
    'mmsr',
    'py',
    'dkill',
    'testcc',
    'tweek',
    'killgow',
    'killgame',
    'winrst',
    'winfix',
    'winchk',
    'winmenu',
    'fixc',
    'android',
    '_EnsureTls',
    'ccdata',
    'ccdata2',
    'mkc',
    'ccc1',
    '3dd',
    '7gg',
    '2gg',
    '3gg',
    '4gg',
    '5gg',
    '6gg',
    '8gg',
    '9gg',
    '10gg',
    '11gg',
    '12gg',
    '13gg',
    '14gg',
    '15gg',
    '16gg',
    '17gg',
    '18gg',
    '19gg',
    '20gg',
    '21gg',
    '22gg',
    '23gg',
    '24gg',
    '25gg',
    '26gg',
    '27gg',
    '28gg',
    '29gg',
    '30gg',
    '31gg',
    '32gg',
    '33gg',
    '34gg',
    '35gg',
    '36gg',
    '37gg',
    '38gg',
    '39gg',
    '40gg',
    'ccc2',
    'dsh',
    'dsh2',
    'dsh3',
    'getascen',
    'rmbackclau',
    'ccc3',
    'ccc',
    'noccc',
    'macres2',
    'gwinpe',
    'ccc4',
    'ccc5',
    'qbit',
    'mser',
    '_SafeStep',
    '_RunAllParallel',
    'wslmax',
    'cleanclau',
    'fixe',
    'ventoy',
    'fullfixf',
    'flyoobe',
    'ccc6',
    'cspacem',
    'cspacemax',
    'uopt',
    'ultopt',
    'webterm',
    'rmwebterm',
    'webapp',
    'rmwebapp',
    'lswebapp',
    'cleanf',
    'cflare',
    '30sub',
    '20sub',
    '10sub',
    'myclu',
    'mysiz',
    'mysiz2',
    'mysiz3',
    'oc-fast',
    'later',
    'endis',
    'disand',
    'ensand',
    'pwemod',
    'gclauded',
    'cpy',
    'ZZZ_WRAPPER_14',
    'finder',
    'clau',
    'tg',
    'claud',
    'ccstable',
    'cclatest',
    'rlp2',
    'clawskills',
    'clawhooks',
    'myrlp',
    'Update-Git',
    'getasc',
    'getascrm',
    'dockerfix',
    'tweak',
    'pp',
    'bleach',
    'newcd',
    'sj',
    'check-ai',
    'myprof',
    'chrome-profiles',
    'fixvss',
    'cctools',
    'classuni',
    'ccbots',
    'refresh2',
    'backclau',
    'backcod',
    'listcod',
    'resclau',
    'rescod',
    'rmbackcod',
    'winupg',
    'easyre',
    'fixwin',
    'hbcd',
    'o90',
    'fixvss2',
    'recc',
    'recc2',
    'backitup2',
    'quick-backup',
    'backup-status',
    'allstart',
    'allstart2',
    'ram2',
    'getoc',
    'drivers',
    'getoc2',
    'ConvertFrom-NvidUriText',
    'ConvertTo-NvidMarketingVersion',
    'Get-NvidUninstallEntry',
    'Test-NvidSmi',
    'Test-NvidNvDebugDump',
    'Get-NvidConnectedDisplayState',
    'Get-NvidDriverHealth',
    'Get-NvidOfficialDriverInfo',
    'Get-NvidOfficialAppInfo',
    'Get-NvidOfficialPhysXInfo',
    'Get-NvidOfficialDirectXInfo',
    'Get-NvidProtocolCommand',
    'Get-NvidAppLaunchState',
    'Expand-NvidArchive',
    'Restore-NvidAppPayload',
    'Get-NvidAppRuntimeSupport',
    'Get-NvidDriverSupportExtractRoot',
    'Restore-NvidAppRuntimeSupport',
    'Get-NvidControlPanelPackage',
    'Ensure-NvidStoreService',
    'Get-NvidDriverStoreEntries',
    'Remove-NvidObsoleteDriverStoreEntries',
    'Get-NvidPowerState',
    'Wait-NvidWindow',
    'Open-NvidStartApp',
    'Open-NvidDesktopApp',
    'Get-NvidUiAutomationProbe',
    'Register-NvidPowerLimitTask',
    'Register-NvidResumeTask',
    'nvid',
    'nvidia2',
    'nvid2',
    'Script:Write-Banner',
    'Script:Write-ManagerHeader',
    'Global:seit',
    'Global:init',
    'Global:setit',
    'winupg2',
    'claude-router',
    'stop-router',
    'late',
    'cro',
    'cpi',
    'cpr',
    'clu',
    'Get-PreferredCodexExecutablePath',
    'Invoke-PreferredCodexCommand',
    'codex',
    'cod',
    'codash',
    'codash-status',
    'codash-global',
    'codash-stop',
    'codash-test',
    'upgrader',
    'cop',
    'freram',
    'linespr',
    'linescu',
    'rebt',
    'dockhub',
    'dockfix',
    'nocccc',
    'gapk',
    'backdcim',
    'aadb',
    'aad',
    'longest',
    'short',
    '3ubu',
    'rewsl',
    'rrewsl',
    'getdirectx',
    'sdesktop',
    'Find-MainExecutable',
    'taskbar',
    '_out',
    'a2e',
    'amd',
    'armourycrate',
    'ashen',
    'backupf',
    'bbel',
    'bright0',
    'bright1',
    'bully',
    'ccbb',
    'ccbbr',
    'cccclean',
    'cco',
    'clean',
    'cleans',
    'compressedinstall',
    'ddefender',
    'disahk',
    'doom',
    'driverdu',
    'dsubs2',
    'everything',
    'gahk',
    'gccleaner',
    'gchrome',
    'gcompressedinstalled',
    'gcursor',
    'gdbooster',
    'gdriverbooster',
    'Get-CleanAppName',
    'getps7',
    'Get-UsedSpace',
    'getwinget',
    'Get-WSL2Memory',
    'gfirefox',
    'gobs',
    'gparsec',
    'gplaynite',
    'grambox',
    'greflect',
    'grevo',
    'grevouninstaller',
    'gsavestate',
    'gscoop',
    'gshort',
    'gstremio',
    'gtodoist',
    'gv1',
    'killmacrium',
    'lhunter',
    'local:Copy-NvidFile',
    'local:Copy-NvidFolderContent',
    'local:Ensure-NvidDirectory',
    'local:Test-DXInstalled',
    'macback',
    'n1',
    'phonel',
    'pipip',
    'Process-Folders',
    'ps5',
    'ps7',
    'psv',
    'renotes',
    'repoint',
    'Reset-WSL2Config',
    'ress',
    'restoref',
    'rgg',
    'rjoy',
    'rlas',
    'rmback',
    'rmdup',
    'rmf',
    'rmod',
    'rmrmrm',
    'rmwinold',
    'robs',
    'rr',
    'rr2',
    'runahk',
    'Run-WithTimeout',
    'sahk',
    'setups',
    'Set-WSL2CustomMemory',
    'Set-WSL2Memory',
    'short2',
    'ssave',
    'ssss',
    'startahk',
    'startit',
    'Start-WSLDistro',
    'swemod',
    'Sync-WithSpaceMonitoring',
    'terminaladmin',
    'Test-WSLDistroRunning',
    'tmnt',
    'ubu3',
    'updater3',
    'upit',
    'used2',
    'w10gb',
    'w11gb',
    'w12gb',
    'w13gb',
    'w14gb',
    'w15gb',
    'w16gb',
    'w1gb',
    'w2gb',
    'w3gb',
    'w4gb',
    'w5gb',
    'w6gb',
    'w7gb',
    'w8gb',
    'w9gb',
    'ws',
    'ytmp4',
    'disdis',
    'Get-MacriumStateToolPython',
    'backmac',
    'resmac',
    'Get-MacriumStateToolScript',
    'cdex',
    'getamd',
    'qaccess',
    'regate',
    'myfix',
    'Get-ProfileFunctionMap',
    'cfun',
    'ccfun',
    'profile',
    'profile2',
    'gspeedtest',
    'ps527',
    'pps527',
    'reass',
    'fixstore',
    'getamd2',
    'Wait-DockerCommanderVisibleSeconds',
    'ConvertTo-HermesMenuOneWordName',
    'Rename-HermesMenuDestinationPath'
)

Set-Item -Path 'Function:\global:Get-ProfileFunctionMap' -Value {
    [CmdletBinding()]
    param([string]$ProfilePath)
    if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = $script:FullProfileDefinitionsPath }
    if ([string]::IsNullOrWhiteSpace($ProfilePath)) { $ProfilePath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.definitions.ps1' }
    if (-not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { $ProfilePath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.full.ps1' }
    if ([string]::IsNullOrWhiteSpace($ProfilePath) -or -not (Test-Path -LiteralPath $ProfilePath -PathType Leaf)) { throw "Profile definitions not found: $ProfilePath" }
    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($ProfilePath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        $parseSummary = ($errors | Select-Object -First 3 | ForEach-Object { $_.Message.Trim() }) -join ' | '
        throw "Unable to parse profile definitions '$ProfilePath': $parseSummary"
    }
    $functionMap = @{}
    foreach ($functionAst in $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true)) {
        $name = $functionAst.Name -replace '^(?i:global:)', ''
        $isProxyBody = $functionAst.Body.Extent.Text -match 'Full profile proxy could not determine the command name to reload'
        if ($functionMap.ContainsKey($name)) {
            $existingIsProxyBody = $functionMap[$name].Body.Extent.Text -match 'Full profile proxy could not determine the command name to reload'
            if ($existingIsProxyBody -and -not $isProxyBody) {
                $functionMap[$name] = $functionAst
            } elseif (-not $existingIsProxyBody -and $isProxyBody) {
                continue
            } else {
                $functionMap[$name] = $functionAst
            }
        } else {
            $functionMap[$name] = $functionAst
        }
    }
    return $functionMap
} -Force

$script:FullProfileFunctionNames = @($script:FullProfileFunctionNames + (Get-ProfileFunctionMap).Keys) |
    ForEach-Object { $_ -replace '^(?i:global:)', '' } |
    Sort-Object -Unique

$script:FullProfileProxy = {
    $calledName = $MyInvocation.MyCommand.Name
    if (-not $calledName -or $calledName -eq '&') {
        $calledName = $MyInvocation.InvocationName
    }
    if (-not $calledName -or $calledName -eq '&') {
        throw 'Full profile proxy could not determine the command name to reload.'
    }

    # Materialize from the full definitions file directly; dot-sourcing it inside this proxy would scope definitions to the loader call.
    $targetCommand = Get-Command $calledName -CommandType Function -ErrorAction Stop
    if ($targetCommand.Definition -match 'Full profile proxy could not determine the command name to reload') {
        if (-not (Get-Command Get-ProfileFunctionMap -CommandType Function -ErrorAction SilentlyContinue)) {
            Write-Host "Function '$calledName' unavailable: full profile map is unavailable." -ForegroundColor Yellow
            return
        }

        $lookupName = $calledName -replace '^(?i:global:)', ''
        $resolved = Resolve-ProfileFunctionAst -FunctionName $lookupName
        if (-not $resolved) {
            Remove-Item -LiteralPath "Function:\global:$lookupName" -ErrorAction SilentlyContinue
            Write-Host "Function '$calledName' unavailable: profile resolver searched all known sources and found no saved definition." -ForegroundColor Yellow
            return
        }
        $lookupName = $resolved.Name

        $functionText = "function global:$lookupName $($resolved.Ast.Body.Extent.Text)"
        . ([scriptblock]::Create($functionText))
        $targetCommand = Get-Command $calledName -CommandType Function -ErrorAction Stop
        if ($targetCommand.Definition -match 'Full profile proxy could not determine the command name to reload') {
            Write-Host "Function '$calledName' unavailable: source definition could not be materialized." -ForegroundColor Yellow
            return
        }
    }

    try {
        & $targetCommand @args
    } catch {
        Write-Host "Function '$calledName' failed cleanly: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }
}

foreach ($functionName in $script:FullProfileFunctionNames) {
    if ($functionName -in @('Load-FullPowerShellProfile', 'fullprofile', 'nomouse', 'ps527', 'pps527', 'reass', 'fixstore', 'getamd2', 'Wait-DockerCommanderVisibleSeconds', 'ConvertTo-HermesMenuOneWordName', 'Rename-HermesMenuDestinationPath', 'Get-ProfileFunctionMap', 'Get-ProfileFunctionSourcePaths', 'Resolve-ProfileFunctionAst', 'cfun', 'fixwinpe', 'Repair-StandardWindowsProcessEnvironment')) { continue }
    Set-Item -Path "Function:\global:$functionName" -Value $script:FullProfileProxy -Force
}


Set-Item -Path 'Function:\global:cc' -Value { Clear-Host } -Force

function global:tweak {
    . 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\legacy-safe-functions\tweak.ps1'
    & 'tweak' @args
}






# Direct cfun override: inspect live/proxied functions before static full-profile map lookup.
# Hermes-managed Docker profile bridge fixes (2026-06-24)
# Fixes lazy/full-profile Docker switch forwarding and recovers Docker Desktop installs that leave Desktop/CLI executables missing.
function global:Apply-HermesDockerProfileBridgeFix {
    function global:Invoke-HermesDockerPreserveRedocker {
        [CmdletBinding()]
        param(
            [switch] $SelfTest,
            [switch] $SkipInstall,
            [switch] $NoPurge,
            [Parameter(ValueFromRemainingArguments = $true)] [object[]] $RemainingArgs
        )
        $scriptPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\legacy-safe-functions\Invoke-HermesDockerPreserveRedocker.ps1'
        if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Missing redocker implementation: $scriptPath" }

        $repairInstallFallback = {
            param([bool] $NoInstall)
            $desktopPath = 'C:\Program Files\Docker\Docker\Docker Desktop.exe'
            $dockerPath = 'C:\Program Files\Docker\Docker\resources\bin\docker.exe'
            $tempRoot = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\temp\hermes_psw'
            New-Item -ItemType Directory -Force -Path $tempRoot | Out-Null
            $installerPath = Join-Path $tempRoot 'DockerDesktopInstaller_repair.exe'
            $localInstaller = 'C:\Program Files\Docker\Docker\Docker Desktop Installer.exe'
            if ((-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) -and (Test-Path -LiteralPath $localInstaller -PathType Leaf)) {
                Copy-Item -LiteralPath $localInstaller -Destination $installerPath -Force -ErrorAction SilentlyContinue
            }
            if (-not (Test-Path -LiteralPath $installerPath -PathType Leaf)) {
                $downloadUrl = 'https://desktop.docker.com/win/main/amd64/Docker%20Desktop%20Installer.exe'
                Write-Host ("[redocker] downloading Docker Desktop installer fallback: {0}" -f $downloadUrl) -ForegroundColor Cyan
                (New-Object Net.WebClient).DownloadFile($downloadUrl, $installerPath)
            }
            foreach ($name in @('Docker Desktop','Docker Desktop Installer','com.docker.backend','com.docker.proxy','com.docker.build','docker-agent','docker-sandbox','dockerd','docker','vpnkit','com.docker.service')) {
                Get-Process -Name $name -ErrorAction SilentlyContinue | ForEach-Object {
                    try { Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue } catch { }
                }
            }
            try { Stop-Service -Name 'com.docker.service' -Force -ErrorAction SilentlyContinue } catch { }
            Start-Sleep -Seconds 2
            foreach ($stalePath in @('C:\Program Files\Docker\Docker.staging','C:\Program Files\Docker\Docker')) {
                if (Test-Path -LiteralPath $stalePath) {
                    $backupPath = Join-Path $tempRoot (('docker_programfiles_backup_{0}_{1}' -f (Get-Date -Format 'yyyyMMddHHmmss'), (Split-Path -Leaf $stalePath)))
                    try { Move-Item -LiteralPath $stalePath -Destination $backupPath -Force -ErrorAction Stop } catch { Remove-Item -LiteralPath $stalePath -Recurse -Force -ErrorAction SilentlyContinue }
                }
            }
            if (-not $NoInstall) {
                $proc = Start-Process -FilePath $installerPath -ArgumentList @('install','--quiet','--accept-license','--backend=hyper-v') -Wait -PassThru -ErrorAction Stop
                if ($proc.ExitCode -ne 0) { throw ("Docker Desktop fallback installer failed with exit {0}" -f $proc.ExitCode) }
            }
            $deadline = (Get-Date).AddSeconds(240)
            do {
                if ((Test-Path -LiteralPath $desktopPath -PathType Leaf) -and (Test-Path -LiteralPath $dockerPath -PathType Leaf)) { break }
                Start-Sleep -Seconds 2
            } while ((Get-Date) -lt $deadline)
            if (-not (Test-Path -LiteralPath $desktopPath -PathType Leaf)) { throw 'Docker Desktop executable still missing after fallback install.' }
            if (-not (Test-Path -LiteralPath $dockerPath -PathType Leaf)) { throw 'Docker CLI executable still missing after fallback install.' }
            try { Start-Service -Name 'com.docker.service' -ErrorAction SilentlyContinue } catch { }
            try { Start-Process -FilePath $desktopPath -ArgumentList @('--minimized') -WindowStyle Hidden | Out-Null } catch { }
            $ready = $false
            $readyDeadline = (Get-Date).AddSeconds(240)
            do {
                & $dockerPath info --format '{{.ServerVersion}}' 2>$null | Out-Null
                if ($LASTEXITCODE -eq 0) { $ready = $true; break }
                Start-Sleep -Seconds 3
            } while ((Get-Date) -lt $readyDeadline)
            if (-not $ready) { throw 'Docker daemon was not ready after fallback install/launch.' }
            [pscustomobject]@{ Fallback='DockerDesktopInstaller'; DesktopExe=$desktopPath; DockerExe=$dockerPath; DockerReady=$true; WslTouched=$false; Backend='Hyper-V' }
        }

        . $scriptPath
        $forward = @{}
        if ($PSBoundParameters.ContainsKey('SelfTest')) { $forward['SelfTest'] = [bool]$SelfTest }
        if ($PSBoundParameters.ContainsKey('SkipInstall')) { $forward['SkipInstall'] = [bool]$SkipInstall }
        if ($PSBoundParameters.ContainsKey('NoPurge')) { $forward['NoPurge'] = [bool]$NoPurge }
        try {
            if ($RemainingArgs -and $RemainingArgs.Count -gt 0) { & 'Invoke-HermesDockerPreserveRedocker' @forward @RemainingArgs } else { & 'Invoke-HermesDockerPreserveRedocker' @forward }
        } catch {
            $message = [string]$_.Exception.Message
            if ($message -match '(?i)Docker Desktop executable missing|Docker CLI executable missing|No Docker Desktop installation found|installer exited with status|first install did not restore executable') {
                Write-Host ("[redocker] primary path failed ({0}); running installer fallback without touching WSL." -f $message) -ForegroundColor Yellow
                & $repairInstallFallback -NoInstall:([bool]$SkipInstall)
                return
            }
            throw
        }
    }

    function global:redocker {
        [CmdletBinding()]
        param(
            [switch] $SelfTest,
            [switch] $SkipInstall,
            [switch] $NoPurge,
            [Parameter(ValueFromRemainingArguments = $true)] [object[]] $RemainingArgs
        )
        $forward = @{}
        if ($PSBoundParameters.ContainsKey('SelfTest')) { $forward['SelfTest'] = [bool]$SelfTest }
        if ($PSBoundParameters.ContainsKey('SkipInstall')) { $forward['SkipInstall'] = [bool]$SkipInstall }
        if ($PSBoundParameters.ContainsKey('NoPurge')) { $forward['NoPurge'] = [bool]$NoPurge }
        if ($RemainingArgs -and $RemainingArgs.Count -gt 0) { Invoke-HermesDockerPreserveRedocker @forward @RemainingArgs } else { Invoke-HermesDockerPreserveRedocker @forward }
    }

    function global:rredocker {
        [CmdletBinding()]
        param(
            [switch] $SelfTest,
            [switch] $SkipInstall,
            [switch] $NoPurge,
            [Parameter(ValueFromRemainingArguments = $true)] [object[]] $RemainingArgs
        )
        $forward = @{}
        if ($PSBoundParameters.ContainsKey('SelfTest')) { $forward['SelfTest'] = [bool]$SelfTest }
        if ($PSBoundParameters.ContainsKey('SkipInstall')) { $forward['SkipInstall'] = [bool]$SkipInstall }
        if ($PSBoundParameters.ContainsKey('NoPurge')) { $forward['NoPurge'] = [bool]$NoPurge }
        if ($RemainingArgs -and $RemainingArgs.Count -gt 0) { redocker @forward @RemainingArgs } else { redocker @forward }
    }
}
Apply-HermesDockerProfileBridgeFix
# End Hermes-managed Docker profile bridge fixes (2026-06-24)

# Hermes-managed Docker final bridge override (2026-06-26)
# Keep Docker public commands on legacy-safe wrappers even after Load-FullPowerShellProfile.
function global:Apply-HermesDockerProfileBridgeFix {
    $wrapperPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\legacy-safe-functions\profile-wrappers.ps1'
    if (Test-Path -LiteralPath $wrapperPath -PathType Leaf) { . $wrapperPath }

    foreach ($scriptPath in @(
        'C:\Users\micha\Documents\WindowsPowerShell\legacy-safe-functions\Invoke-HermesDockerPreserveRedocker.ps1',
        'C:\Users\micha\Documents\WindowsPowerShell\legacy-safe-functions\Invoke-HermesDockerForceDkill.ps1',
        'C:\Users\micha\Documents\WindowsPowerShell\legacy-safe-functions\Apply-HermesDockerCommanderFinalPublicSurfaceGuard.ps1',
        'C:\Users\micha\Documents\WindowsPowerShell\legacy-safe-functions\Apply-HermesDockerForceDkillGuard.ps1'
    )) {
        if (Test-Path -LiteralPath $scriptPath -PathType Leaf) { . $scriptPath }
    }

    if (Get-Command Apply-HermesDockerCommanderFinalPublicSurfaceGuard -CommandType Function -ErrorAction SilentlyContinue) {
        Apply-HermesDockerCommanderFinalPublicSurfaceGuard
    }
    if (Get-Command Apply-HermesDockerForceDkillGuard -CommandType Function -ErrorAction SilentlyContinue) {
        Apply-HermesDockerForceDkillGuard
    }

    function global:redocker {
        [CmdletBinding()]
        param(
            [switch] $SelfTest,
            [switch] $SkipInstall,
            [switch] $NoPurge,
            [Parameter(ValueFromRemainingArguments = $true)] [object[]] $RemainingArgs
        )
        $forward = @{}
        if ($PSBoundParameters.ContainsKey('SelfTest')) { $forward['SelfTest'] = [bool]$SelfTest }
        if ($PSBoundParameters.ContainsKey('SkipInstall')) { $forward['SkipInstall'] = [bool]$SkipInstall }
        if ($PSBoundParameters.ContainsKey('NoPurge')) { $forward['NoPurge'] = [bool]$NoPurge }
        if ($RemainingArgs -and $RemainingArgs.Count -gt 0) { Invoke-HermesDockerPreserveRedocker @forward @RemainingArgs } else { Invoke-HermesDockerPreserveRedocker @forward }
    }

    function global:rredocker {
        [CmdletBinding()]
        param(
            [switch] $SelfTest,
            [switch] $SkipInstall,
            [switch] $NoPurge,
            [Parameter(ValueFromRemainingArguments = $true)] [object[]] $RemainingArgs
        )
        $forward = @{}
        if ($PSBoundParameters.ContainsKey('SelfTest')) { $forward['SelfTest'] = [bool]$SelfTest }
        if ($PSBoundParameters.ContainsKey('SkipInstall')) { $forward['SkipInstall'] = [bool]$SkipInstall }
        if ($PSBoundParameters.ContainsKey('NoPurge')) { $forward['NoPurge'] = [bool]$NoPurge }
        if ($RemainingArgs -and $RemainingArgs.Count -gt 0) { Invoke-HermesDockerPreserveRedocker @forward @RemainingArgs } else { Invoke-HermesDockerPreserveRedocker @forward }
    }

    Set-Item -Path Function:\global:RREDOCKER -Force -Value ${function:rredocker}
}
Apply-HermesDockerProfileBridgeFix
# End Hermes-managed Docker final bridge override (2026-06-26)

Set-Alias -Name Afirgirl -Value 'afitgirl' -Force -ErrorAction SilentlyContinue
Set-Alias -Name afit -Value 'afitgirl' -Force -ErrorAction SilentlyContinue
Set-Alias -Name claudemax -Value 'claude360' -Force -ErrorAction SilentlyContinue
Set-Alias -Name claudemin -Value 'claude1' -Force -ErrorAction SilentlyContinue
Set-Alias -Name cphelp -Value 'copilot' -Force -ErrorAction SilentlyContinue
Set-Alias -Name fixfg -Value 'fixfitgirl' -Force -ErrorAction SilentlyContinue
Set-Alias -Name gitgo -Value 'gitco' -Force -ErrorAction SilentlyContinue
Set-Alias -Name gmodule -Value 'Enable-WindowsModules' -Force -ErrorAction SilentlyContinue
Set-Alias -Name refreshenv -Value 'Update-SessionEnvironment' -Force -ErrorAction SilentlyContinue
Set-Alias -Name rmwsl -Value 'nnn' -Force -ErrorAction SilentlyContinue
Set-Alias -Name run -Value 'Invoke-ChainedCommand' -Force -ErrorAction SilentlyContinue
Set-Alias -Name x -Value 'Invoke-ChainedCommand' -Force -ErrorAction SilentlyContinue

function global:resher {
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

    $scriptPath = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\resher-fast.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Write-Host "resher unavailable: Hermes AutoBackRes script is not ready: $scriptPath" -ForegroundColor Yellow
        Write-Host "Current filesystem drives: $((Get-PSDrive -PSProvider FileSystem | Select-Object -ExpandProperty Name) -join ', ')" -ForegroundColor DarkYellow
        return
    }

    try {
        & $scriptPath -BackupId $BackupId -Distro $Distro -BackupRoot $BackupRoot -ValidateOnly:$ValidateOnly -PlanOnly:$PlanOnly -NoTelegramProbe:$NoTelegramProbe -SlashCommandsOnly:$SlashCommandsOnly -Legacy:$Legacy @ResherArgs
    } catch {
        Write-Host "resher unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }
}

function global:arch {
    [CmdletBinding()]
    param(
        [switch] $AdbSelfTest,
        [int] $MaxArchives = 0,
        [Parameter(ValueFromRemainingArguments = $true)][string[]] $ArchArgs
    )

    $scriptPath = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\codex-android-old-chat-archiver\Archive-CodexIdle1HourChats.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Write-Host "arch unavailable: Android archiver script is not ready: $scriptPath" -ForegroundColor Yellow
        return
    }

    $adbPath = 'F:\study\Dev_Toolchain\Android\platform-tools\adb.exe'
    if (-not (Test-Path -LiteralPath $adbPath -PathType Leaf)) {
        $adbCommand = Get-Command adb.exe -ErrorAction SilentlyContinue
        if ($adbCommand) { $adbPath = $adbCommand.Source }
    }
    if (-not (Test-Path -LiteralPath $adbPath -PathType Leaf)) {
        Write-Host 'arch unavailable: adb.exe is not available.' -ForegroundColor Yellow
        return
    }
    $connectedDevices = @(& $adbPath devices 2>$null | Where-Object { $_ -match '\sdevice$' })
    if ($connectedDevices.Count -eq 0) {
        Write-Host 'arch unavailable: no connected Android device or emulator.' -ForegroundColor Yellow
        return
    }

    try {
        if ($AdbSelfTest) {
            if ($ArchArgs -and $ArchArgs.Count -gt 0) {
                & $scriptPath -AdbSelfTest -MaxArchives $MaxArchives -MinHours 1 @ArchArgs
            } else {
                & $scriptPath -AdbSelfTest -MaxArchives $MaxArchives -MinHours 1
            }
        } else {
            if ($ArchArgs -and $ArchArgs.Count -gt 0) {
                & $scriptPath -MaxArchives $MaxArchives -MinHours 1 @ArchArgs
            } else {
                & $scriptPath -MaxArchives $MaxArchives -MinHours 1
            }
        }
    } catch {
        Write-Host "arch unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }
}

function global:arch2 {
    [CmdletBinding()]
    param(
        [switch] $AdbSelfTest,
        [int] $MaxArchives = 0,
        [Parameter(ValueFromRemainingArguments = $true)][string[]] $ArchArgs
    )

    $scriptPath = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\codex-android-old-chat-archiver\Archive-CodexOldChats.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        Write-Host "arch2 unavailable: Android archiver script is not ready: $scriptPath" -ForegroundColor Yellow
        return
    }

    $adbPath = 'F:\study\Dev_Toolchain\Android\platform-tools\adb.exe'
    if (-not (Test-Path -LiteralPath $adbPath -PathType Leaf)) {
        $adbCommand = Get-Command adb.exe -ErrorAction SilentlyContinue
        if ($adbCommand) { $adbPath = $adbCommand.Source }
    }
    if (-not (Test-Path -LiteralPath $adbPath -PathType Leaf)) {
        Write-Host 'arch2 unavailable: adb.exe is not available.' -ForegroundColor Yellow
        return
    }
    $connectedDevices = @(& $adbPath devices 2>$null | Where-Object { $_ -match '\sdevice$' })
    if ($connectedDevices.Count -eq 0) {
        Write-Host 'arch2 unavailable: no connected Android device or emulator.' -ForegroundColor Yellow
        return
    }

    try {
        if ($AdbSelfTest) {
            if ($ArchArgs -and $ArchArgs.Count -gt 0) {
                & $scriptPath -AdbSelfTest -MaxArchives $MaxArchives -MinHours 24 @ArchArgs
            } else {
                & $scriptPath -AdbSelfTest -MaxArchives $MaxArchives -MinHours 24
            }
        } else {
            if ($ArchArgs -and $ArchArgs.Count -gt 0) {
                & $scriptPath -MaxArchives $MaxArchives -MinHours 24 @ArchArgs
            } else {
                & $scriptPath -MaxArchives $MaxArchives -MinHours 24
            }
        }
    } catch {
        Write-Host "arch2 unavailable: $($_.Exception.Message)" -ForegroundColor Yellow
        return
    }
}

if ($script:ProfileIsInteractiveConsole -and -not $env:OPENCLAW_EXEC) {
    Write-Host "[Profile loaded in $($script:_prof_sw.ElapsedMilliseconds)ms]" -ForegroundColor DarkGray
}
function renormal {    Unregister-ScheduledTask -TaskName OneTimeSafeModeTempCleanupFallback -Confirm:$false -ErrorAction SilentlyContinue;bcdedit /deletevalue "{current}" safeboot 2>$null;bcdedit /deletevalue "{current}" safebootalternateshell 2>$null;shutdown.exe /r /t 0 /f }

function synclip {    F:\study\Windows\Applications\Mobile\Android\Clipboard\Sync\TrayApps\MichAutoClipSync\MichAutoClipSyncTray.exe }

# Final override: compile C/C++ source files into same-folder executables.
function global:compcpp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $SourcePath,

        [Parameter(Position = 1)]
        [string] $OutputPath,

        [switch] $Run
    )

    $candidate = $SourcePath
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path (Get-Location).Path $candidate
    }

    $resolvedSource = $null
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $resolvedSource = (Resolve-Path -LiteralPath $candidate).Path
    }
    elseif (-not [System.IO.Path]::HasExtension($candidate)) {
        foreach ($extension in @('.cpp', '.cc', '.cxx', '.c++', '.C', '.c')) {
            $withExtension = $candidate + $extension
            if (Test-Path -LiteralPath $withExtension -PathType Leaf) {
                $resolvedSource = (Resolve-Path -LiteralPath $withExtension).Path
                break
            }
        }
    }

    if (-not $resolvedSource) {
        throw "Source file not found: $SourcePath"
    }

    $sourceItem = Get-Item -LiteralPath $resolvedSource
    $extensionLower = $sourceItem.Extension.ToLowerInvariant()
    if ($extensionLower -notin @('.cpp', '.cc', '.cxx', '.c++', '.c')) {
        Write-Warning "Compiling a non-standard C/C++ extension: $($sourceItem.Extension)"
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $sourceItem.DirectoryName ($sourceItem.BaseName + '.exe')
    }
    elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path (Get-Location).Path $OutputPath
    }

    $outputParent = [System.IO.Directory]::GetParent($OutputPath).FullName
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }

    $compiler = $null
    if ($extensionLower -eq '.c') {
        $compiler = Get-Command gcc -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $compiler) {
        foreach ($name in @('g++', 'clang++', 'cl')) {
            $compiler = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($compiler) { break }
        }
    }
    if (-not $compiler) {
        throw 'No C/C++ compiler found on PATH. Install g++, clang++, or Visual Studio cl.exe.'
    }

    $compilerPath = $compiler.Source
    $compilerName = [System.IO.Path]::GetFileNameWithoutExtension($compilerPath).ToLowerInvariant()
    $shimRoot = Join-Path $env:TEMP 'codex-mingw-compat'
    New-Item -ItemType Directory -Path $shimRoot -Force | Out-Null
    $hresetShim = Join-Path $shimRoot 'hresetintrin.h'
    if (-not (Test-Path -LiteralPath $hresetShim -PathType Leaf)) {
        Set-Content -LiteralPath $hresetShim -Value "#pragma once`n" -Encoding ASCII
    }

    if ($compilerName -eq 'cl') {
        $compileArgs = @('/nologo')
        if ($extensionLower -ne '.c') {
            $compileArgs += @('/EHsc', '/std:c++17')
        }
        $compileArgs += @('/O2', ('/I' + $shimRoot), ('/Fe:' + $OutputPath), $resolvedSource, 'ole32.lib', 'oleaut32.lib', 'ws2_32.lib', 'comctl32.lib', 'gdi32.lib', 'user32.lib', 'advapi32.lib', 'shell32.lib', 'uuid.lib')
    }
    else {
        $compileArgs = @($resolvedSource)
        if ($extensionLower -eq '.c' -and $compilerName -eq 'gcc') {
            $compileArgs += @('-std=c11')
        }
        else {
            $compileArgs += @('-std=c++17')
        }
        $compileArgs += @('-O2', '-Wall', '-Wextra', '-I', $shimRoot, '-o', $OutputPath, '-lole32', '-loleaut32', '-lws2_32', '-lcomctl32', '-lgdi32', '-luser32', '-ladvapi32', '-lshell32', '-luuid')
    }

    Write-Host "Compiler: $compilerPath"
    Write-Host "Source:   $resolvedSource"
    Write-Host "Output:   $OutputPath"
    & $compilerPath @compileArgs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Compilation failed with exit code $exitCode"
    }
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "Compiler reported success but output was not created: $OutputPath"
    }

    Write-Host "COMPCPP_OK: $OutputPath"
    if ($Run) {
        & $OutputPath
        exit $LASTEXITCODE
    }
}

function ffixf {
    $runner = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\temp\fixf-profile-launch.ps1'
    Set-Content -LiteralPath $runner -Value (Get-Content -LiteralPath 'F:\study\Windows\System\Storage\Repair\PowerShell\Automation\fixf-exfat-no-dismount\artifacts\fixf-direct-one-liner.txt' -Raw) -Encoding UTF8
    Set-Location -LiteralPath 'F:\study'
    [Environment]::CurrentDirectory = 'F:\study'
    $p = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner) -WorkingDirectory 'F:\study' -WindowStyle Minimized -PassThru
    'FFIXF_STARTED pid=' + $p.Id + ' terminal_moved_to=F:\study'
}

function rmboots {    Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -EncodedCommand JABFAHIAcgBvAHIAQQBjAHQAaQBvAG4AUAByAGUAZgBlAHIAZQBuAGMAZQA9ACcAUwB0AG8AcAAnAAoAJABjAHUAcgAgAD0AIAAoAGIAYwBkAGUAZABpAHQAIAAvAGUAbgB1AG0AIAAnAHsAYwB1AHIAcgBlAG4AdAB9ACcAIAB8ACAAUwBlAGwAZQBjAHQALQBTAHQAcgBpAG4AZwAgACcAXgBpAGQAZQBuAHQAaQBmAGkAZQByAFwAcwArACgAXABTACsAKQAnACAAfAAgAFMAZQBsAGUAYwB0AC0ATwBiAGoAZQBjAHQAIAAtAEYAaQByAHMAdAAgADEAKQAuAE0AYQB0AGMAaABlAHMAWwAwAF0ALgBHAHIAbwB1AHAAcwBbADEAXQAuAFYAYQBsAHUAZQAKAGkAZgAgACgALQBuAG8AdAAgACQAYwB1AHIAKQAgAHsAIAB0AGgAcgBvAHcAIAAnAEMAbwB1AGwAZAAgAG4AbwB0ACAAcgBlAHMAbwBsAHYAZQAgAGMAdQByAHIAZQBuAHQAIABXAGkAbgBkAG8AdwBzACAAYgBvAG8AdAAgAGwAbwBhAGQAZQByACAAaQBkAGUAbgB0AGkAZgBpAGUAcgAuACcAIAB9AAoAYgBjAGQAZQBkAGkAdAAgAC8AZABlAGYAYQB1AGwAdAAgACQAYwB1AHIAIAB8ACAATwB1AHQALQBIAG8AcwB0AAoAJABpAGQAcwAgAD0AIABAACgAYgBjAGQAZQBkAGkAdAAgAC8AZQBuAHUAbQAgAG8AcwBsAG8AYQBkAGUAcgAgAHwAIABTAGUAbABlAGMAdAAtAFMAdAByAGkAbgBnACAAJwBeAGkAZABlAG4AdABpAGYAaQBlAHIAXABzACsAKABcAFMAKwApACcAIAB8ACAARgBvAHIARQBhAGMAaAAtAE8AYgBqAGUAYwB0ACAAewAgACQAXwAuAE0AYQB0AGMAaABlAHMAWwAwAF0ALgBHAHIAbwB1AHAAcwBbADEAXQAuAFYAYQBsAHUAZQAgAH0AIAB8ACAAVwBoAGUAcgBlAC0ATwBiAGoAZQBjAHQAIAB7ACAAJABfACAALQBhAG4AZAAgACQAXwAgAC0AbgBlACAAJABjAHUAcgAgAC0AYQBuAGQAIAAkAF8AIAAtAG4AZQAgACcAewBjAHUAcgByAGUAbgB0AH0AJwAgAH0AKQAKAGYAbwByAGUAYQBjAGgAIAAoACQAaQBkACAAaQBuACAAJABpAGQAcwApACAAewAgAGIAYwBkAGUAZABpAHQAIAAvAGQAZQBsAGUAdABlACAAJABpAGQAIAAvAGYAIAB8ACAATwB1AHQALQBIAG8AcwB0ACAAfQAKAGIAYwBkAGUAZABpAHQAIAAvAGQAaQBzAHAAbABhAHkAbwByAGQAZQByACAAJABjAHUAcgAgAHwAIABPAHUAdAAtAEgAbwBzAHQACgBiAGMAZABlAGQAaQB0ACAALwB0AGkAbQBlAG8AdQB0ACAAMAAgAHwAIABPAHUAdAAtAEgAbwBzAHQACgBiAGMAZABlAGQAaQB0ACAALwBzAGUAdAAgACcAewBiAG8AbwB0AG0AZwByAH0AJwAgAGQAaQBzAHAAbABhAHkAYgBvAG8AdABtAGUAbgB1ACAAbgBvACAAfAAgAE8AdQB0AC0ASABvAHMAdAAKAGIAYwBkAGUAZABpAHQAIAAvAGUAbgB1AG0AIABvAHMAbABvAGEAZABlAHIAIAB8ACAATwB1AHQALQBIAG8AcwB0AA==' }

function ffixe {
    $runner = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\temp\fixe-profile-launch.ps1'
    Set-Content -LiteralPath $runner -Value (Get-Content -LiteralPath 'F:\study\Windows\System\Storage\Repair\PowerShell\Automation\fixf-exfat-no-dismount\artifacts\fixe-direct-one-liner.txt' -Raw) -Encoding UTF8
    Set-Location -LiteralPath 'F:\study'
    [Environment]::CurrentDirectory = 'F:\study'
    $p = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner) -WorkingDirectory 'F:\study' -WindowStyle Minimized -PassThru
    'FFIXE_STARTED pid=' + $p.Id + ' terminal_moved_to=F:\study'
}

function fastcc { siz; ram; ccsizes; cleanc; rmvol; bin; ram; fff; siz }

function global:fixwinpe {
    gwinpe @args
}

$script:BackupDockerProfileOverridesPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\BackupDockerProfileOverrides.ps1'
if (Test-Path -LiteralPath $script:BackupDockerProfileOverridesPath -PathType Leaf) {
    . $script:BackupDockerProfileOverridesPath
}

function bootfast1 {    $e='JABFAHIAcgBvAHIAQQBjAHQAaQBvAG4AUAByAGUAZgBlAHIAZQBuAGMAZQA9ACcAQwBvAG4AdABpAG4AdQBlACcAOwAgACQAcAA9AFsAbwByAGQAZQByAGUAZABdAEAAewBTAGMAYQBuAEEAdgBnAEMAUABVAEwAbwBhAGQARgBhAGMAdABvAHIAPQA1ADsARQBuAGEAYgBsAGUATABvAHcAQwBwAHUAUAByAGkAbwByAGkAdAB5AD0AJAB0AHIAdQBlADsAUwBjAGEAbgBPAG4AbAB5AEkAZgBJAGQAbABlAEUAbgBhAGIAbABlAGQAPQAkAHQAcgB1AGUAOwBEAGkAcwBhAGIAbABlAEMAcAB1AFQAaAByAG8AdAB0AGwAZQBPAG4ASQBkAGwAZQBTAGMAYQBuAHMAPQAkAGYAYQBsAHMAZQA7AFQAaAByAG8AdAB0AGwAZQBGAG8AcgBTAGMAaABlAGQAdQBsAGUAZABTAGMAYQBuAE8AbgBsAHkAPQAkAGYAYQBsAHMAZQA7AEQAaQBzAGEAYgBsAGUAQwBhAHQAYwBoAHUAcABGAHUAbABsAFMAYwBhAG4APQAkAHQAcgB1AGUAOwBEAGkAcwBhAGIAbABlAEMAYQB0AGMAaAB1AHAAUQB1AGkAYwBrAFMAYwBhAG4APQAkAHQAcgB1AGUAOwBEAGkAcwBhAGIAbABlAEEAcgBjAGgAaQB2AGUAUwBjAGEAbgBuAGkAbgBnAD0AJAB0AHIAdQBlADsARABpAHMAYQBiAGwAZQBFAG0AYQBpAGwAUwBjAGEAbgBuAGkAbgBnAD0AJAB0AHIAdQBlADsARABpAHMAYQBiAGwAZQBSAGUAbQBvAHYAYQBiAGwAZQBEAHIAaQB2AGUAUwBjAGEAbgBuAGkAbgBnAD0AJAB0AHIAdQBlADsARABpAHMAYQBiAGwAZQBTAGMAYQBuAG4AaQBuAGcATQBhAHAAcABlAGQATgBlAHQAdwBvAHIAawBEAHIAaQB2AGUAcwBGAG8AcgBGAHUAbABsAFMAYwBhAG4APQAkAHQAcgB1AGUAOwBEAGkAcwBhAGIAbABlAFMAYwBhAG4AbgBpAG4AZwBOAGUAdAB3AG8AcgBrAEYAaQBsAGUAcwA9ACQAdAByAHUAZQA7AE0AQQBQAFMAUgBlAHAAbwByAHQAaQBuAGcAPQAwADsAUwB1AGIAbQBpAHQAUwBhAG0AcABsAGUAcwBDAG8AbgBzAGUAbgB0AD0AMgA7AFMAYwBhAG4AUwBjAGgAZQBkAHUAbABlAEQAYQB5AD0AOAB9ADsAIAAkAG8AawA9AEAAKAApADsAIAAkAGYAYQBpAGwAZQBkAD0AQAAoACkAOwAgAGYAbwByAGUAYQBjAGgAKAAkAGsAIABpAG4AIAAkAHAALgBLAGUAeQBzACkAewB0AHIAeQB7ACQAaAA9AEAAewB9ADsAIAAkAGgAWwAkAGsAXQA9ACQAcABbACQAawBdADsAIABTAGUAdAAtAE0AcABQAHIAZQBmAGUAcgBlAG4AYwBlACAAQABoACAALQBFAHIAcgBvAHIAQQBjAHQAaQBvAG4AIABTAHQAbwBwADsAIAAkAG8AawArAD0AJABrAH0AYwBhAHQAYwBoAHsAJABmAGEAaQBsAGUAZAArAD0AKAAkAGsAKwAnADoAIAAnACsAJABfAC4ARQB4AGMAZQBwAHQAaQBvAG4ALgBNAGUAcwBzAGEAZwBlACkAfQB9ADsAIABXAHIAaQB0AGUALQBIAG8AcwB0ACAAKAAnAEEAUABQAEwASQBFAEQAOgAgACcAKwAoACQAbwBrACAALQBqAG8AaQBuACAAJwAsACAAJwApACkAOwAgAGkAZgAoACQAZgBhAGkAbABlAGQALgBDAG8AdQBuAHQAKQB7AFcAcgBpAHQAZQAtAFcAYQByAG4AaQBuAGcAIAAoACcARgBBAEkATABFAEQAXwBPAFIAXwBUAEEATQBQAEUAUgBfAFAAUgBPAFQARQBDAFQARQBEADoAIAAnACsAKAAkAGYAYQBpAGwAZQBkACAALQBqAG8AaQBuACAAJwAgAHwAIAAnACkAKQB9ADsAIABHAGUAdAAtAE0AcABQAHIAZQBmAGUAcgBlAG4AYwBlACAAfAAgAFMAZQBsAGUAYwB0AC0ATwBiAGoAZQBjAHQAIABTAGMAYQBuAEEAdgBnAEMAUABVAEwAbwBhAGQARgBhAGMAdABvAHIALABFAG4AYQBiAGwAZQBMAG8AdwBDAHAAdQBQAHIAaQBvAHIAaQB0AHkALABTAGMAYQBuAE8AbgBsAHkASQBmAEkAZABsAGUARQBuAGEAYgBsAGUAZAAsAEQAaQBzAGEAYgBsAGUAQwBwAHUAVABoAHIAbwB0AHQAbABlAE8AbgBJAGQAbABlAFMAYwBhAG4AcwAsAFQAaAByAG8AdAB0AGwAZQBGAG8AcgBTAGMAaABlAGQAdQBsAGUAZABTAGMAYQBuAE8AbgBsAHkALABEAGkAcwBhAGIAbABlAEMAYQB0AGMAaAB1AHAARgB1AGwAbABTAGMAYQBuACwARABpAHMAYQBiAGwAZQBDAGEAdABjAGgAdQBwAFEAdQBpAGMAawBTAGMAYQBuACwARABpAHMAYQBiAGwAZQBBAHIAYwBoAGkAdgBlAFMAYwBhAG4AbgBpAG4AZwAsAEQAaQBzAGEAYgBsAGUARQBtAGEAaQBsAFMAYwBhAG4AbgBpAG4AZwAsAEQAaQBzAGEAYgBsAGUAUgBlAG0AbwB2AGEAYgBsAGUARAByAGkAdgBlAFMAYwBhAG4AbgBpAG4AZwAsAEQAaQBzAGEAYgBsAGUAUwBjAGEAbgBuAGkAbgBnAE0AYQBwAHAAZQBkAE4AZQB0AHcAbwByAGsARAByAGkAdgBlAHMARgBvAHIARgB1AGwAbABTAGMAYQBuACwARABpAHMAYQBiAGwAZQBTAGMAYQBuAG4AaQBuAGcATgBlAHQAdwBvAHIAawBGAGkAbABlAHMALABNAEEAUABTAFIAZQBwAG8AcgB0AGkAbgBnACwAUwB1AGIAbQBpAHQAUwBhAG0AcABsAGUAcwBDAG8AbgBzAGUAbgB0ACwAUwBjAGEAbgBTAGMAaABlAGQAdQBsAGUARABhAHkAIAB8ACAARgBvAHIAbQBhAHQALQBMAGkAcwB0ADsAIABSAGUAYQBkAC0ASABvAHMAdAAgACcARABvAG4AZQAuACAAUAByAGUAcwBzACAARQBuAHQAZQByACAAdABvACAAYwBsAG8AcwBlACcA'; if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $e"; exit}; & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -EncodedCommand $e }


# Import the Chocolatey Profile that contains the necessary code to enable
# tab-completions to function for `choco`.
# Be aware that if you are missing these lines from your profile, tab completion
# for `choco` will not function.
# See https://ch0.co/tab-completion for details.
$ChocolateyProfile = "$env:ChocolateyInstall\helpers\chocolateyProfile.psm1"
if (Test-Path($ChocolateyProfile)) {
  Import-Module "$ChocolateyProfile"
}





function testram {    F:\study\Windows\Hardware\Diagnostics\Memory\RAM\Stability\ram-live-certainty-scanner\ram-live-progress-scan.ps1 }

function unstuck {    F:\study\Windows\PowerShell\System\Maintenance\Servicing\Tools\unstuck-command\unstuck-command.cmd  }

function testgpu {    F:\study\Windows\Hardware\Diagnostics\GPU\Stability\gpu-live-certainty-scanner\gpu-live-progress-scan.ps1 }

function testcpu {    F:\study\Windows\Hardware\Diagnostics\CPU\Stability\cpu-live-certainty-scanner\cpu-live-progress-scan.ps1 }

function testpsu {    F:\study\Windows\Hardware\Diagnostics\Power\PSU\Stability\psu-live-certainty-scanner\psu-live-progress-scan.ps1}

function powerplans {    F:\study\Platforms\windows\performance\powerplan\codex-ultimate-nuclear-performance-powerplan\PowerPlansUltimate.ps1 }

function testmother {    F:\study\Windows\Hardware\Diagnostics\Motherboard\Stability\motherboard-live-certainty-scanner\motherboard-live-progress-scan.ps1 }

function testmpther {    testmother }
function disher {    $ErrorActionPreference='SilentlyContinue';$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator');$hp='F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\HermesTray.exe';$p='F:\study\Windows\PowerShell\Profile\ps5-profile-portable\state\CodexWslHermesStartupState.json';$d='F:\study\Windows\PowerShell\Profile\ps5-profile-portable\state\CodexDisabledStartupItems';New-Item -ItemType Directory -Force -Path $d|Out-Null;$s=[ordered]@{SavedAt=(Get-Date).ToString('s');Admin=$admin;HermesTray=$hp;Tasks=@();Services=@();RunValues=@();StartupFiles=@();Killed=@()};$csv=schtasks /query /fo csv /v|ConvertFrom-Csv;$tasks=@($csv|?{(($_.'TaskName')+' '+($_.'Task To Run')+' '+($_.'Comment')) -match '(?i)Hermes|WSL|Ubuntu'}|Select -Expand TaskName -Unique)+@('\Codex\HermesTrayAutostart','\HermesTrayAutostart','\MichStartupMaster\CustomStartup_HermesTray_064be82f','\CustomStartup_HermesTray_064be82f')|Select -Unique;foreach($t in $tasks){$row=$csv|?{$_.TaskName -eq $t}|select -First 1;if($row -and $row.'Scheduled Task State' -eq 'Enabled'){$s.Tasks+=$t};schtasks /Change /TN $t /Disable|Out-Null};$roots='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce';foreach($r in $roots){if(Test-Path $r){(Get-ItemProperty $r).PSObject.Properties|?{$_.Name -notmatch '^PS' -and (($_.Name+' '+[string]$_.Value) -match '(?i)Hermes|WSL|Ubuntu')}|%{$s.RunValues+=[ordered]@{Path=$r;Name=$_.Name;Value=[string]$_.Value};Remove-ItemProperty -Path $r -Name $_.Name -Force}}};$sh=New-Object -ComObject WScript.Shell;$sf=@([Environment]::GetFolderPath('Startup'),'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup')|?{Test-Path $_};foreach($dir in $sf){gci $dir -Force|%{$target='';if($_.Extension -eq '.lnk'){$target=$sh.CreateShortcut($_.FullName).TargetPath};if((($_.Name+' '+$target) -match '(?i)Hermes|WSL|Ubuntu')){$dest=Join-Path $d ([guid]::NewGuid().ToString()+'.'+$_.Name);$s.StartupFiles+=[ordered]@{From=$_.FullName;To=$dest};Move-Item -LiteralPath $_.FullName -Destination $dest -Force}}};wsl.exe --shutdown;$svc='WSLService','LxssManager','com.docker.service'|?{Get-Service $_};foreach($n in $svc){$w=Get-WmiObject Win32_Service -Filter "Name='$n'";$s.Services+=[ordered]@{Name=$n;StartMode=$w.StartMode;State=$w.State};if($admin){Set-Service -Name $n -StartupType Manual;Stop-Service -Name $n -Force}};$procs=Get-Process|?{$_.ProcessName -match '(?i)^Hermes|HermesTray|wsl|vmmemWSL|msrdc'};foreach($pr in $procs){$s.Killed+=$pr.ProcessName;Stop-Process -Id $pr.Id -Force};$s|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $p;if($admin){"DISABLED: WSL2/Hermes autostart off, live resources stopped, state saved to $p"}else{"PARTIAL: run as Administrator to also change WSL/Docker services; user startup/task/process changes were attempted; state saved to $p"} }



function enher {      $ErrorActionPreference='SilentlyContinue';$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator');$hp='F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\HermesTray.exe';$p='F:\study\Windows\PowerShell\Profile\ps5-profile-portable\state\CodexWslHermesStartupState.json';$s=$null;if(Test-Path $p){$s=Get-Content $p -Raw|ConvertFrom-Json};foreach($t in @($s.Tasks)){if($t){schtasks /Change /TN $t /Enable|Out-Null}};foreach($t in '\MichStartupMaster\CustomStartup_HermesTray_064be82f','\CustomStartup_HermesTray_064be82f','\HermesDockerServiceEventGuard'){schtasks /Change /TN $t /Enable|Out-Null};foreach($rv in @($s.RunValues)){if($rv.Path -and $rv.Name){New-Item -Path $rv.Path -Force|Out-Null;New-ItemProperty -Path $rv.Path -Name $rv.Name -Value $rv.Value -PropertyType String -Force|Out-Null}};foreach($f in @($s.StartupFiles)){if($f.To -and $f.From -and (Test-Path -LiteralPath $f.To)){Move-Item -LiteralPath $f.To -Destination $f.From -Force}};foreach($sv in @($s.Services)){if($sv.Name -and $admin){$mode=@{Auto='auto';Manual='demand';Disabled='disabled'}[[string]$sv.StartMode];if($mode){sc.exe config $sv.Name start= $mode|Out-Null};if($sv.State -eq 'Running'){Start-Service -Name $sv.Name}}};if($admin){foreach($n in 'WSLService','com.docker.service'){if(Get-Service $n){sc.exe config $n start= auto|Out-Null;Start-Service $n}}};$tr='C:\Windows\System32\wscript.exe //B //Nologo "F:\study\Windows\PowerShell\Profile\ps5-profile-portable\tools\trayquiet-start.vbs" "'+$hp+'" 120 0 25';schtasks /Create /TN '\Codex\HermesTrayAutostart' /SC ONLOGON /TR $tr /F|Out-Null;schtasks /Change /TN '\Codex\HermesTrayAutostart' /Enable|Out-Null;schtasks /Run /TN '\Codex\HermesTrayAutostart'|Out-Null;if(Test-Path $hp -and !(Get-Process HermesTray)) {Start-Process -FilePath $hp};if(Get-Process HermesTray){"ENABLED: HermesTray is running now and will start at every Windows logon; WSL/Docker autostart restored where permissions allowed"}else{"RESTORED AUTOSTART BUT HERMESTRAY DID NOT START; check $hp"} }

function getoc2 {   F:\study\repos\Artificial_Intelligence\cli\opencode\50\b.ps1 }



function fixcodex {     F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\fixer\a.ps1 }



function ddown {     F:\study\Windows\Applications\Gaming\DownloadManagers\qBittorrent\Automation\GameTorrentDownloader\a.bat @args  }





function gminitool {    F:\STUDY\Windows\System\Administration\Maintenance\Performance\PowerShell\Automation\WUMT-Auto-Update\Install-Updates.ps1 }

function global:free {
    param(
        [switch]$SkipReboot,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$CommandParts
    )

    $historyLine = $null
    $historySavePath = $null
    $priorHistoryLine = $null
    try {
        if (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue) {
            $historySavePath = (Get-PSReadLineOption).HistorySavePath
            if ($historySavePath -and (Test-Path -LiteralPath $historySavePath -PathType Leaf)) {
                $priorHistoryLine = Get-Content -LiteralPath $historySavePath -Tail 1 -ErrorAction SilentlyContinue
            }
        }
    } catch { }
    try {
        $lastHistory = Get-History -Count 1 -ErrorAction Stop
        if ($lastHistory -and -not [string]::IsNullOrWhiteSpace($lastHistory.CommandLine)) {
            $historyLine = $lastHistory.CommandLine
        }
    } catch { }

    $scriptArgs = @{
        HistorySavePath = $historySavePath
        PriorHistoryLine = $priorHistoryLine
        HistoryLine = $historyLine
        RawLine = $MyInvocation.Line
        InvocationName = $MyInvocation.InvocationName
        ArgumentList = $CommandParts
    }
    if ($SkipReboot) { $scriptArgs.SkipReboot = $true }

    & F:\study\shells\powershell\scripts\AfterReboot\FreeType\e.ps1 @scriptArgs
}

function mysand {    F:\backup\windowsapps\AfterFormatSandbox\LAUNCH-AFTERFORMAT-SANDBOX.cmd }
function disgames {    $sh = New-Object -ComObject Shell.Application; Get-CimInstance Win32_Volume | Where-Object { $_.DriveType -eq 5 -and $_.DriveLetter } | ForEach-Object { $drive = $_.DriveLetter.TrimEnd(':') + ':'; $item = $sh.Namespace(17).ParseName($drive); if ($item) { $item.InvokeVerb('Eject') } } }

function stats {    while ($true) { $cpu=(Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue; $os=Get-CimInstance Win32_OperatingSystem; $ramUsed=[math]::Round((($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100,1); $gpu=0; try { $gpu=[math]::Round(((Get-Counter '\GPU Engine(*)\Utilization Percentage').CounterSamples | Measure-Object CookedValue -Sum).Sum,1) } catch { $gpu=-1 }; Write-Host ("{0:HH:mm:ss} CPU {1:n1}% | RAM {2:n1}% | GPU {3}%" -f (Get-Date),$cpu,$ramUsed,($(if($gpu -ge 0){"$gpu%"}else{"N/A"}))); Start-Sleep -Seconds 1 } }function fixeverything {    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "F:\study\Windows\Maintenance\repair\tools\everything-index-repair\Repair-EverythingIndex.ps1" }function fixmouse {    F:\study\Windows\Hardware\Input\Mouse\Logitech\PowerShell\Automation\mouse-smoothness-fix\Invoke-MouseSmoothnessFix.ps1}function QQQ { GDBOOSTER;GCCLEANER; getasc }



function www {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $RemainingArgs
    )

    $ps5 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        $ps5 = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    $insScript = 'F:\study\Windows\Applications\Gaming\DownloadManagers\qBittorrent\FitGirl\Automation\AutoInstall\qbittorrent-fitgirl-force-auto-install-20260601\ins.ps1'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        throw "Windows PowerShell 5 executable not found: $ps5"
    }
    if (-not (Test-Path -LiteralPath $insScript -PathType Leaf)) {
        throw "ins launcher not found: $insScript"
    }

    & $ps5 -NoProfile -ExecutionPolicy Bypass -File $insScript
    $insExit = $LASTEXITCODE
    if ($null -ne $insExit -and $insExit -ne 0) {
        throw "ins failed with exit code $insExit"
    }

    ddown @RemainingArgs
}

# Codex hardening 2026-07-06: keep www in the parent shell while ins runs in a child process.
function global:www {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $RemainingArgs
    )

    $ps5 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        $ps5 = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    $insScript = 'F:\study\Windows\Applications\Gaming\DownloadManagers\qBittorrent\FitGirl\Automation\AutoInstall\qbittorrent-fitgirl-force-auto-install-20260601\ins.ps1'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        throw "Windows PowerShell 5 executable not found: $ps5"
    }
    if (-not (Test-Path -LiteralPath $insScript -PathType Leaf)) {
        throw "ins launcher not found: $insScript"
    }

    & $ps5 -NoProfile -ExecutionPolicy Bypass -File $insScript
    $insExit = $LASTEXITCODE
    if ($null -ne $insExit -and $insExit -ne 0) {
        throw "ins failed with exit code $insExit"
    }

    ddown @RemainingArgs
}
function FIXHERMES2 {    & 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\HermesFleetDoctor\HermesFleetDoctor.cmd' -Iterations 1 -HealthTimeoutSeconds 90 -SettleSeconds 5 }
function gwiniso {    irm https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1 -OutFile "F:\Downloads\Fido.ps1"; & "F:\Downloads\Fido.ps1" -Win 11 -Rel Latest -Ed Pro -Lang English -Arch x64 }




function nvi {    nvid; RRM "C:\ProgramData\NVID"   }

function fixwsl {     F:\study\Operating_Systems\Windows\Subsystems\WSL2\Repair\wsl2-permanent-repair-kit\scripts\Repair-WSL2-Permanent.ps1 }

function cdwin {    cd F:\backup\windowsapps }

function duwin {     cd F:\backup\windowsapps; dush }

function fixrdp {   F:\study\Learning\01\01\Systems_Virtualization\Remote\RemoteDesktop\AutoEnableRDP\a.ps1 }

function goc {    & 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\opencode\opencode-free-zen-installer\src\aa.ps1' @args }

function aad {
    & 'F:\study\Shells\powershell\scripts\android\adb\aadb\Invoke-AndroidAdbBridge.ps1' @args
} function aadb {
    & 'F:\study\Shells\powershell\scripts\android\adb\aadb\Invoke-AndroidAdbBridge.ps1' @args
} function bootfast1 {    $e='JABFAHIAcgBvAHIAQQBjAHQAaQBvAG4AUAByAGUAZgBlAHIAZQBuAGMAZQA9ACcAQwBvAG4AdABpAG4AdQBlACcAOwAgACQAcAA9AFsAbwByAGQAZQByAGUAZABdAEAAewBTAGMAYQBuAEEAdgBnAEMAUABVAEwAbwBhAGQARgBhAGMAdABvAHIAPQA1ADsARQBuAGEAYgBsAGUATABvAHcAQwBwAHUAUAByAGkAbwByAGkAdAB5AD0AJAB0AHIAdQBlADsAUwBjAGEAbgBPAG4AbAB5AEkAZgBJAGQAbABlAEUAbgBhAGIAbABlAGQAPQAkAHQAcgB1AGUAOwBEAGkAcwBhAGIAbABlAEMAcAB1AFQAaAByAG8AdAB0AGwAZQBPAG4ASQBkAGwAZQBTAGMAYQBuAHMAPQAkAGYAYQBsAHMAZQA7AFQAaAByAG8AdAB0AGwAZQBGAG8AcgBTAGMAaABlAGQAdQBsAGUAZABTAGMAYQBuAE8AbgBsAHkAPQAkAGYAYQBsAHMAZQA7AEQAaQBzAGEAYgBsAGUAQwBhAHQAYwBoAHUAcABGAHUAbABsAFMAYwBhAG4APQAkAHQAcgB1AGUAOwBEAGkAcwBhAGIAbABlAEMAYQB0AGMAaAB1AHAAUQB1AGkAYwBrAFMAYwBhAG4APQAkAHQAcgB1AGUAOwBEAGkAcwBhAGIAbABlAEEAcgBjAGgAaQB2AGUAUwBjAGEAbgBuAGkAbgBnAD0AJAB0AHIAdQBlADsARABpAHMAYQBiAGwAZQBFAG0AYQBpAGwAUwBjAGEAbgBuAGkAbgBnAD0AJAB0AHIAdQBlADsARABpAHMAYQBiAGwAZQBSAGUAbQBvAHYAYQBiAGwAZQBEAHIAaQB2AGUAUwBjAGEAbgBuAGkAbgBnAD0AJAB0AHIAdQBlADsARABpAHMAYQBiAGwAZQBTAGMAYQBuAG4AaQBuAGcATQBhAHAAcABlAGQATgBlAHQAdwBvAHIAawBEAHIAaQB2AGUAcwBGAG8AcgBGAHUAbABsAFMAYwBhAG4APQAkAHQAcgB1AGUAOwBEAGkAcwBhAGIAbABlAFMAYwBhAG4AbgBpAG4AZwBOAGUAdAB3AG8AcgBrAEYAaQBsAGUAcwA9ACQAdAByAHUAZQA7AE0AQQBQAFMAUgBlAHAAbwByAHQAaQBuAGcAPQAwADsAUwB1AGIAbQBpAHQAUwBhAG0AcABsAGUAcwBDAG8AbgBzAGUAbgB0AD0AMgA7AFMAYwBhAG4AUwBjAGgAZQBkAHUAbABlAEQAYQB5AD0AOAB9ADsAIAAkAG8AawA9AEAAKAApADsAIAAkAGYAYQBpAGwAZQBkAD0AQAAoACkAOwAgAGYAbwByAGUAYQBjAGgAKAAkAGsAIABpAG4AIAAkAHAALgBLAGUAeQBzACkAewB0AHIAeQB7ACQAaAA9AEAAewB9ADsAIAAkAGgAWwAkAGsAXQA9ACQAcABbACQAawBdADsAIABTAGUAdAAtAE0AcABQAHIAZQBmAGUAcgBlAG4AYwBlACAAQABoACAALQBFAHIAcgBvAHIAQQBjAHQAaQBvAG4AIABTAHQAbwBwADsAIAAkAG8AawArAD0AJABrAH0AYwBhAHQAYwBoAHsAJABmAGEAaQBsAGUAZAArAD0AKAAkAGsAKwAnADoAIAAnACsAJABfAC4ARQB4AGMAZQBwAHQAaQBvAG4ALgBNAGUAcwBzAGEAZwBlACkAfQB9ADsAIABXAHIAaQB0AGUALQBIAG8AcwB0ACAAKAAnAEEAUABQAEwASQBFAEQAOgAgACcAKwAoACQAbwBrACAALQBqAG8AaQBuACAAJwAsACAAJwApACkAOwAgAGkAZgAoACQAZgBhAGkAbABlAGQALgBDAG8AdQBuAHQAKQB7AFcAcgBpAHQAZQAtAFcAYQByAG4AaQBuAGcAIAAoACcARgBBAEkATABFAEQAXwBPAFIAXwBUAEEATQBQAEUAUgBfAFAAUgBPAFQARQBDAFQARQBEADoAIAAnACsAKAAkAGYAYQBpAGwAZQBkACAALQBqAG8AaQBuACAAJwAgAHwAIAAnACkAKQB9ADsAIABHAGUAdAAtAE0AcABQAHIAZQBmAGUAcgBlAG4AYwBlACAAfAAgAFMAZQBsAGUAYwB0AC0ATwBiAGoAZQBjAHQAIABTAGMAYQBuAEEAdgBnAEMAUABVAEwAbwBhAGQARgBhAGMAdABvAHIALABFAG4AYQBiAGwAZQBMAG8AdwBDAHAAdQBQAHIAaQBvAHIAaQB0AHkALABTAGMAYQBuAE8AbgBsAHkASQBmAEkAZABsAGUARQBuAGEAYgBsAGUAZAAsAEQAaQBzAGEAYgBsAGUAQwBwAHUAVABoAHIAbwB0AHQAbABlAE8AbgBJAGQAbABlAFMAYwBhAG4AcwAsAFQAaAByAG8AdAB0AGwAZQBGAG8AcgBTAGMAaABlAGQAdQBsAGUAZABTAGMAYQBuAE8AbgBsAHkALABEAGkAcwBhAGIAbABlAEMAYQB0AGMAaAB1AHAARgB1AGwAbABTAGMAYQBuACwARABpAHMAYQBiAGwAZQBDAGEAdABjAGgAdQBwAFEAdQBpAGMAawBTAGMAYQBuACwARABpAHMAYQBiAGwAZQBBAHIAYwBoAGkAdgBlAFMAYwBhAG4AbgBpAG4AZwAsAEQAaQBzAGEAYgBsAGUARQBtAGEAaQBsAFMAYwBhAG4AbgBpAG4AZwAsAEQAaQBzAGEAYgBsAGUAUgBlAG0AbwB2AGEAYgBsAGUARAByAGkAdgBlAFMAYwBhAG4AbgBpAG4AZwAsAEQAaQBzAGEAYgBsAGUAUwBjAGEAbgBuAGkAbgBnAE0AYQBwAHAAZQBkAE4AZQB0AHcAbwByAGsARAByAGkAdgBlAHMARgBvAHIARgB1AGwAbABTAGMAYQBuACwARABpAHMAYQBiAGwAZQBTAGMAYQBuAG4AaQBuAGcATgBlAHQAdwBvAHIAawBGAGkAbABlAHMALABNAEEAUABTAFIAZQBwAG8AcgB0AGkAbgBnACwAUwB1AGIAbQBpAHQAUwBhAG0AcABsAGUAcwBDAG8AbgBzAGUAbgB0ACwAUwBjAGEAbgBTAGMAaABlAGQAdQBsAGUARABhAHkAIAB8ACAARgBvAHIAbQBhAHQALQBMAGkAcwB0ADsAIABSAGUAYQBkAC0ASABvAHMAdAAgACcARABvAG4AZQAuACAAUAByAGUAcwBzACAARQBuAHQAZQByACAAdABvACAAYwBsAG8AcwBlACcA'; if(-not ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)){Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList "-NoProfile -ExecutionPolicy Bypass -EncodedCommand $e"; exit}; & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -EncodedCommand $e } function cdwin {    cd F:\backup\windowsapps } function global:compcpp {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true, Position = 0)]
        [string] $SourcePath,

        [Parameter(Position = 1)]
        [string] $OutputPath,

        [switch] $Run
    )

    $candidate = $SourcePath
    if (-not [System.IO.Path]::IsPathRooted($candidate)) {
        $candidate = Join-Path (Get-Location).Path $candidate
    }

    $resolvedSource = $null
    if (Test-Path -LiteralPath $candidate -PathType Leaf) {
        $resolvedSource = (Resolve-Path -LiteralPath $candidate).Path
    }
    elseif (-not [System.IO.Path]::HasExtension($candidate)) {
        foreach ($extension in @('.cpp', '.cc', '.cxx', '.c++', '.C', '.c')) {
            $withExtension = $candidate + $extension
            if (Test-Path -LiteralPath $withExtension -PathType Leaf) {
                $resolvedSource = (Resolve-Path -LiteralPath $withExtension).Path
                break
            }
        }
    }

    if (-not $resolvedSource) {
        throw "Source file not found: $SourcePath"
    }

    $sourceItem = Get-Item -LiteralPath $resolvedSource
    $extensionLower = $sourceItem.Extension.ToLowerInvariant()
    if ($extensionLower -notin @('.cpp', '.cc', '.cxx', '.c++', '.c')) {
        Write-Warning "Compiling a non-standard C/C++ extension: $($sourceItem.Extension)"
    }

    if ([string]::IsNullOrWhiteSpace($OutputPath)) {
        $OutputPath = Join-Path $sourceItem.DirectoryName ($sourceItem.BaseName + '.exe')
    }
    elseif (-not [System.IO.Path]::IsPathRooted($OutputPath)) {
        $OutputPath = Join-Path (Get-Location).Path $OutputPath
    }

    $outputParent = [System.IO.Directory]::GetParent($OutputPath).FullName
    if (-not (Test-Path -LiteralPath $outputParent -PathType Container)) {
        New-Item -ItemType Directory -Path $outputParent -Force | Out-Null
    }

    $compiler = $null
    if ($extensionLower -eq '.c') {
        $compiler = Get-Command gcc -ErrorAction SilentlyContinue | Select-Object -First 1
    }
    if (-not $compiler) {
        foreach ($name in @('g++', 'clang++', 'cl')) {
            $compiler = Get-Command $name -ErrorAction SilentlyContinue | Select-Object -First 1
            if ($compiler) { break }
        }
    }
    if (-not $compiler) {
        throw 'No C/C++ compiler found on PATH. Install g++, clang++, or Visual Studio cl.exe.'
    }

    $compilerPath = $compiler.Source
    $compilerName = [System.IO.Path]::GetFileNameWithoutExtension($compilerPath).ToLowerInvariant()
    $shimRoot = Join-Path $env:TEMP 'codex-mingw-compat'
    New-Item -ItemType Directory -Path $shimRoot -Force | Out-Null
    $hresetShim = Join-Path $shimRoot 'hresetintrin.h'
    if (-not (Test-Path -LiteralPath $hresetShim -PathType Leaf)) {
        Set-Content -LiteralPath $hresetShim -Value "#pragma once`n" -Encoding ASCII
    }

    if ($compilerName -eq 'cl') {
        $compileArgs = @('/nologo')
        if ($extensionLower -ne '.c') {
            $compileArgs += @('/EHsc', '/std:c++17')
        }
        $compileArgs += @('/O2', ('/I' + $shimRoot), ('/Fe:' + $OutputPath), $resolvedSource, 'ole32.lib', 'oleaut32.lib', 'ws2_32.lib', 'comctl32.lib', 'gdi32.lib', 'user32.lib', 'advapi32.lib', 'shell32.lib', 'uuid.lib')
    }
    else {
        $compileArgs = @($resolvedSource)
        if ($extensionLower -eq '.c' -and $compilerName -eq 'gcc') {
            $compileArgs += @('-std=c11')
        }
        else {
            $compileArgs += @('-std=c++17')
        }
        $compileArgs += @('-O2', '-Wall', '-Wextra', '-I', $shimRoot, '-o', $OutputPath, '-lole32', '-loleaut32', '-lws2_32', '-lcomctl32', '-lgdi32', '-luser32', '-ladvapi32', '-lshell32', '-luuid')
    }

    Write-Host "Compiler: $compilerPath"
    Write-Host "Source:   $resolvedSource"
    Write-Host "Output:   $OutputPath"
    & $compilerPath @compileArgs
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        throw "Compilation failed with exit code $exitCode"
    }
    if (-not (Test-Path -LiteralPath $OutputPath -PathType Leaf)) {
        throw "Compiler reported success but output was not created: $OutputPath"
    }

    Write-Host "COMPCPP_OK: $OutputPath"
    if ($Run) {
        & $OutputPath
        exit $LASTEXITCODE
    }
} function ddown {     F:\study\Windows\Applications\Gaming\DownloadManagers\qBittorrent\Automation\GameTorrentDownloader\a.bat @args  } function disgames {    $sh = New-Object -ComObject Shell.Application; Get-CimInstance Win32_Volume | Where-Object { $_.DriveType -eq 5 -and $_.DriveLetter } | ForEach-Object { $drive = $_.DriveLetter.TrimEnd(':') + ':'; $item = $sh.Namespace(17).ParseName($drive); if ($item) { $item.InvokeVerb('Eject') } } } function disher {    $ErrorActionPreference='SilentlyContinue';$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator');$hp='F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\HermesTray.exe';$p='F:\study\Windows\PowerShell\Profile\ps5-profile-portable\state\CodexWslHermesStartupState.json';$d='F:\study\Windows\PowerShell\Profile\ps5-profile-portable\state\CodexDisabledStartupItems';New-Item -ItemType Directory -Force -Path $d|Out-Null;$s=[ordered]@{SavedAt=(Get-Date).ToString('s');Admin=$admin;HermesTray=$hp;Tasks=@();Services=@();RunValues=@();StartupFiles=@();Killed=@()};$csv=schtasks /query /fo csv /v|ConvertFrom-Csv;$tasks=@($csv|?{(($_.'TaskName')+' '+($_.'Task To Run')+' '+($_.'Comment')) -match '(?i)Hermes|WSL|Ubuntu'}|Select -Expand TaskName -Unique)+@('\Codex\HermesTrayAutostart','\HermesTrayAutostart','\MichStartupMaster\CustomStartup_HermesTray_064be82f','\CustomStartup_HermesTray_064be82f')|Select -Unique;foreach($t in $tasks){$row=$csv|?{$_.TaskName -eq $t}|select -First 1;if($row -and $row.'Scheduled Task State' -eq 'Enabled'){$s.Tasks+=$t};schtasks /Change /TN $t /Disable|Out-Null};$roots='HKCU:\Software\Microsoft\Windows\CurrentVersion\Run','HKLM:\Software\Microsoft\Windows\CurrentVersion\Run','HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce','HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce';foreach($r in $roots){if(Test-Path $r){(Get-ItemProperty $r).PSObject.Properties|?{$_.Name -notmatch '^PS' -and (($_.Name+' '+[string]$_.Value) -match '(?i)Hermes|WSL|Ubuntu')}|%{$s.RunValues+=[ordered]@{Path=$r;Name=$_.Name;Value=[string]$_.Value};Remove-ItemProperty -Path $r -Name $_.Name -Force}}};$sh=New-Object -ComObject WScript.Shell;$sf=@([Environment]::GetFolderPath('Startup'),'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\Startup')|?{Test-Path $_};foreach($dir in $sf){gci $dir -Force|%{$target='';if($_.Extension -eq '.lnk'){$target=$sh.CreateShortcut($_.FullName).TargetPath};if((($_.Name+' '+$target) -match '(?i)Hermes|WSL|Ubuntu')){$dest=Join-Path $d ([guid]::NewGuid().ToString()+'.'+$_.Name);$s.StartupFiles+=[ordered]@{From=$_.FullName;To=$dest};Move-Item -LiteralPath $_.FullName -Destination $dest -Force}}};wsl.exe --shutdown;$svc='WSLService','LxssManager','com.docker.service'|?{Get-Service $_};foreach($n in $svc){$w=Get-WmiObject Win32_Service -Filter "Name='$n'";$s.Services+=[ordered]@{Name=$n;StartMode=$w.StartMode;State=$w.State};if($admin){Set-Service -Name $n -StartupType Manual;Stop-Service -Name $n -Force}};$procs=Get-Process|?{$_.ProcessName -match '(?i)^Hermes|HermesTray|wsl|vmmemWSL|msrdc'};foreach($pr in $procs){$s.Killed+=$pr.ProcessName;Stop-Process -Id $pr.Id -Force};$s|ConvertTo-Json -Depth 8|Set-Content -Encoding UTF8 $p;if($admin){"DISABLED: WSL2/Hermes autostart off, live resources stopped, state saved to $p"}else{"PARTIAL: run as Administrator to also change WSL/Docker services; user startup/task/process changes were attempted; state saved to $p"} } function duwin {     cd F:\backup\windowsapps; dush } function enher {      $ErrorActionPreference='SilentlyContinue';$admin=([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]'Administrator');$hp='F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\HermesTray.exe';$p='F:\study\Windows\PowerShell\Profile\ps5-profile-portable\state\CodexWslHermesStartupState.json';$s=$null;if(Test-Path $p){$s=Get-Content $p -Raw|ConvertFrom-Json};foreach($t in @($s.Tasks)){if($t){schtasks /Change /TN $t /Enable|Out-Null}};foreach($t in '\MichStartupMaster\CustomStartup_HermesTray_064be82f','\CustomStartup_HermesTray_064be82f','\HermesDockerServiceEventGuard'){schtasks /Change /TN $t /Enable|Out-Null};foreach($rv in @($s.RunValues)){if($rv.Path -and $rv.Name){New-Item -Path $rv.Path -Force|Out-Null;New-ItemProperty -Path $rv.Path -Name $rv.Name -Value $rv.Value -PropertyType String -Force|Out-Null}};foreach($f in @($s.StartupFiles)){if($f.To -and $f.From -and (Test-Path -LiteralPath $f.To)){Move-Item -LiteralPath $f.To -Destination $f.From -Force}};foreach($sv in @($s.Services)){if($sv.Name -and $admin){$mode=@{Auto='auto';Manual='demand';Disabled='disabled'}[[string]$sv.StartMode];if($mode){sc.exe config $sv.Name start= $mode|Out-Null};if($sv.State -eq 'Running'){Start-Service -Name $sv.Name}}};if($admin){foreach($n in 'WSLService','com.docker.service'){if(Get-Service $n){sc.exe config $n start= auto|Out-Null;Start-Service $n}}};$tr='C:\Windows\System32\wscript.exe //B //Nologo "F:\study\Windows\PowerShell\Profile\ps5-profile-portable\tools\trayquiet-start.vbs" "'+$hp+'" 120 0 25';schtasks /Create /TN '\Codex\HermesTrayAutostart' /SC ONLOGON /TR $tr /F|Out-Null;schtasks /Change /TN '\Codex\HermesTrayAutostart' /Enable|Out-Null;schtasks /Run /TN '\Codex\HermesTrayAutostart'|Out-Null;if(Test-Path $hp -and !(Get-Process HermesTray)) {Start-Process -FilePath $hp};if(Get-Process HermesTray){"ENABLED: HermesTray is running now and will start at every Windows logon; WSL/Docker autostart restored where permissions allowed"}else{"RESTORED AUTOSTART BUT HERMESTRAY DID NOT START; check $hp"} } function fastcc { siz; ram; ccsizes; cleanc; rmvol; bin; ram; fff; siz } function ffixe {
    $runner = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\temp\fixe-profile-launch.ps1'
    Set-Content -LiteralPath $runner -Value (Get-Content -LiteralPath 'F:\study\Windows\System\Storage\Repair\PowerShell\Automation\fixf-exfat-no-dismount\artifacts\fixe-direct-one-liner.txt' -Raw) -Encoding UTF8
    Set-Location -LiteralPath 'F:\study'
    [Environment]::CurrentDirectory = 'F:\study'
    $p = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner) -WorkingDirectory 'F:\study' -WindowStyle Minimized -PassThru
    'FFIXE_STARTED pid=' + $p.Id + ' terminal_moved_to=F:\study'
} function ffixf {
    $runner = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\temp\fixf-profile-launch.ps1'
    Set-Content -LiteralPath $runner -Value (Get-Content -LiteralPath 'F:\study\Windows\System\Storage\Repair\PowerShell\Automation\fixf-exfat-no-dismount\artifacts\fixf-direct-one-liner.txt' -Raw) -Encoding UTF8
    Set-Location -LiteralPath 'F:\study'
    [Environment]::CurrentDirectory = 'F:\study'
    $p = Start-Process -FilePath 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runner) -WorkingDirectory 'F:\study' -WindowStyle Minimized -PassThru
    'FFIXF_STARTED pid=' + $p.Id + ' terminal_moved_to=F:\study'
} function fixcodex {     F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\fixer\a.ps1 } function fixeverything {    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -NoProfile -ExecutionPolicy Bypass -File "F:\study\Windows\Maintenance\repair\tools\everything-index-repair\Repair-EverythingIndex.ps1" } function FIXHERMES2 {    & 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\HermesFleetDoctor\HermesFleetDoctor.cmd' -Iterations 1 -HealthTimeoutSeconds 90 -SettleSeconds 5 } function fixmouse {    F:\study\Windows\Hardware\Input\Mouse\Logitech\PowerShell\Automation\mouse-smoothness-fix\Invoke-MouseSmoothnessFix.ps1} function fixrdp {   F:\study\Learning\01\01\Systems_Virtualization\Remote\RemoteDesktop\AutoEnableRDP\a.ps1 } function global:fixwinpe {
    gwinpe @args
} function fixwsl {     F:\study\Operating_Systems\Windows\Subsystems\WSL2\Repair\wsl2-permanent-repair-kit\scripts\Repair-WSL2-Permanent.ps1 } function global:free {
    param(
        [switch]$SkipReboot,
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]]$CommandParts
    )

    $historyLine = $null
    $historySavePath = $null
    $priorHistoryLine = $null
    try {
        if (Get-Command Get-PSReadLineOption -ErrorAction SilentlyContinue) {
            $historySavePath = (Get-PSReadLineOption).HistorySavePath
            if ($historySavePath -and (Test-Path -LiteralPath $historySavePath -PathType Leaf)) {
                $priorHistoryLine = Get-Content -LiteralPath $historySavePath -Tail 1 -ErrorAction SilentlyContinue
            }
        }
    } catch { }
    try {
        $lastHistory = Get-History -Count 1 -ErrorAction Stop
        if ($lastHistory -and -not [string]::IsNullOrWhiteSpace($lastHistory.CommandLine)) {
            $historyLine = $lastHistory.CommandLine
        }
    } catch { }

    $scriptArgs = @{
        HistorySavePath = $historySavePath
        PriorHistoryLine = $priorHistoryLine
        HistoryLine = $historyLine
        RawLine = $MyInvocation.Line
        InvocationName = $MyInvocation.InvocationName
        ArgumentList = $CommandParts
    }
    if ($SkipReboot) { $scriptArgs.SkipReboot = $true }

    & F:\study\shells\powershell\scripts\AfterReboot\FreeType\e.ps1 @scriptArgs
} function getoc2 {   F:\study\repos\Artificial_Intelligence\cli\opencode\50\b.ps1 } function gminitool {    F:\STUDY\Windows\System\Administration\Maintenance\Performance\PowerShell\Automation\WUMT-Auto-Update\Install-Updates.ps1 } function goc {    & 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\opencode\opencode-free-zen-installer\src\aa.ps1' @args } function gwiniso {    irm https://raw.githubusercontent.com/pbatard/Fido/master/Fido.ps1 -OutFile "F:\Downloads\Fido.ps1"; & "F:\Downloads\Fido.ps1" -Win 11 -Rel Latest -Ed Pro -Lang English -Arch x64 }    function mysand {    F:\backup\windowsapps\AfterFormatSandbox\LAUNCH-AFTERFORMAT-SANDBOX.cmd } function nvi {    nvid; RRM "C:\ProgramData\NVID"   } function powerplans {    F:\study\Platforms\windows\performance\powerplan\codex-ultimate-nuclear-performance-powerplan\PowerPlansUltimate.ps1 } function QQQ { GDBOOSTER;GCCLEANER; getasc } function renormal {    Unregister-ScheduledTask -TaskName OneTimeSafeModeTempCleanupFallback -Confirm:$false -ErrorAction SilentlyContinue;bcdedit /deletevalue "{current}" safeboot 2>$null;bcdedit /deletevalue "{current}" safebootalternateshell 2>$null;shutdown.exe /r /t 0 /f } function rmboots {    Start-Process -FilePath "C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe" -Verb RunAs -ArgumentList '-NoProfile -ExecutionPolicy Bypass -EncodedCommand JABFAHIAcgBvAHIAQQBjAHQAaQBvAG4AUAByAGUAZgBlAHIAZQBuAGMAZQA9ACcAUwB0AG8AcAAnAAoAJABjAHUAcgAgAD0AIAAoAGIAYwBkAGUAZABpAHQAIAAvAGUAbgB1AG0AIAAnAHsAYwB1AHIAcgBlAG4AdAB9ACcAIAB8ACAAUwBlAGwAZQBjAHQALQBTAHQAcgBpAG4AZwAgACcAXgBpAGQAZQBuAHQAaQBmAGkAZQByAFwAcwArACgAXABTACsAKQAnACAAfAAgAFMAZQBsAGUAYwB0AC0ATwBiAGoAZQBjAHQAIAAtAEYAaQByAHMAdAAgADEAKQAuAE0AYQB0AGMAaABlAHMAWwAwAF0ALgBHAHIAbwB1AHAAcwBbADEAXQAuAFYAYQBsAHUAZQAKAGkAZgAgACgALQBuAG8AdAAgACQAYwB1AHIAKQAgAHsAIAB0AGgAcgBvAHcAIAAnAEMAbwB1AGwAZAAgAG4AbwB0ACAAcgBlAHMAbwBsAHYAZQAgAGMAdQByAHIAZQBuAHQAIABXAGkAbgBkAG8AdwBzACAAYgBvAG8AdAAgAGwAbwBhAGQAZQByACAAaQBkAGUAbgB0AGkAZgBpAGUAcgAuACcAIAB9AAoAYgBjAGQAZQBkAGkAdAAgAC8AZABlAGYAYQB1AGwAdAAgACQAYwB1AHIAIAB8ACAATwB1AHQALQBIAG8AcwB0AAoAJABpAGQAcwAgAD0AIABAACgAYgBjAGQAZQBkAGkAdAAgAC8AZQBuAHUAbQAgAG8AcwBsAG8AYQBkAGUAcgAgAHwAIABTAGUAbABlAGMAdAAtAFMAdAByAGkAbgBnACAAJwBeAGkAZABlAG4AdABpAGYAaQBlAHIAXABzACsAKABcAFMAKwApACcAIAB8ACAARgBvAHIARQBhAGMAaAAtAE8AYgBqAGUAYwB0ACAAewAgACQAXwAuAE0AYQB0AGMAaABlAHMAWwAwAF0ALgBHAHIAbwB1AHAAcwBbADEAXQAuAFYAYQBsAHUAZQAgAH0AIAB8ACAAVwBoAGUAcgBlAC0ATwBiAGoAZQBjAHQAIAB7ACAAJABfACAALQBhAG4AZAAgACQAXwAgAC0AbgBlACAAJABjAHUAcgAgAC0AYQBuAGQAIAAkAF8AIAAtAG4AZQAgACcAewBjAHUAcgByAGUAbgB0AH0AJwAgAH0AKQAKAGYAbwByAGUAYQBjAGgAIAAoACQAaQBkACAAaQBuACAAJABpAGQAcwApACAAewAgAGIAYwBkAGUAZABpAHQAIAAvAGQAZQBsAGUAdABlACAAJABpAGQAIAAvAGYAIAB8ACAATwB1AHQALQBIAG8AcwB0ACAAfQAKAGIAYwBkAGUAZABpAHQAIAAvAGQAaQBzAHAAbABhAHkAbwByAGQAZQByACAAJABjAHUAcgAgAHwAIABPAHUAdAAtAEgAbwBzAHQACgBiAGMAZABlAGQAaQB0ACAALwB0AGkAbQBlAG8AdQB0ACAAMAAgAHwAIABPAHUAdAAtAEgAbwBzAHQACgBiAGMAZABlAGQAaQB0ACAALwBzAGUAdAAgACcAewBiAG8AbwB0AG0AZwByAH0AJwAgAGQAaQBzAHAAbABhAHkAYgBvAG8AdABtAGUAbgB1ACAAbgBvACAAfAAgAE8AdQB0AC0ASABvAHMAdAAKAGIAYwBkAGUAZABpAHQAIAAvAGUAbgB1AG0AIABvAHMAbABvAGEAZABlAHIAIAB8ACAATwB1AHQALQBIAG8AcwB0AA==' } function stats {    while ($true) { $cpu=(Get-Counter '\Processor(_Total)\% Processor Time').CounterSamples.CookedValue; $os=Get-CimInstance Win32_OperatingSystem; $ramUsed=[math]::Round((($os.TotalVisibleMemorySize-$os.FreePhysicalMemory)/$os.TotalVisibleMemorySize)*100,1); $gpu=0; try { $gpu=[math]::Round(((Get-Counter '\GPU Engine(*)\Utilization Percentage').CounterSamples | Measure-Object CookedValue -Sum).Sum,1) } catch { $gpu=-1 }; Write-Host ("{0:HH:mm:ss} CPU {1:n1}% | RAM {2:n1}% | GPU {3}%" -f (Get-Date),$cpu,$ramUsed,($(if($gpu -ge 0){"$gpu%"}else{"N/A"}))); Start-Sleep -Seconds 1 } } function synclip {    F:\study\Windows\Applications\Mobile\Android\Clipboard\Sync\TrayApps\MichAutoClipSync\MichAutoClipSyncTray.exe } function testcpu {    F:\study\Windows\Hardware\Diagnostics\CPU\Stability\cpu-live-certainty-scanner\cpu-live-progress-scan.ps1 } function testgpu {    F:\study\Windows\Hardware\Diagnostics\GPU\Stability\gpu-live-certainty-scanner\gpu-live-progress-scan.ps1 } function testmother {    F:\study\Windows\Hardware\Diagnostics\Motherboard\Stability\motherboard-live-certainty-scanner\motherboard-live-progress-scan.ps1 } function testmpther {    testmother } function testpsu {    F:\study\Windows\Hardware\Diagnostics\Power\PSU\Stability\psu-live-certainty-scanner\psu-live-progress-scan.ps1} function testram {    F:\study\Windows\Hardware\Diagnostics\Memory\RAM\Stability\ram-live-certainty-scanner\ram-live-progress-scan.ps1 } function unstuck {    F:\study\Windows\PowerShell\System\Maintenance\Servicing\Tools\unstuck-command\unstuck-command.cmd  } function www {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $RemainingArgs
    )

    $ps5 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        $ps5 = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    $insScript = 'F:\study\Windows\Applications\Gaming\DownloadManagers\qBittorrent\FitGirl\Automation\AutoInstall\qbittorrent-fitgirl-force-auto-install-20260601\ins.ps1'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        throw "Windows PowerShell 5 executable not found: $ps5"
    }
    if (-not (Test-Path -LiteralPath $insScript -PathType Leaf)) {
        throw "ins launcher not found: $insScript"
    }

    & $ps5 -NoProfile -ExecutionPolicy Bypass -File $insScript
    $insExit = $LASTEXITCODE
    if ($null -ne $insExit -and $insExit -ne 0) {
        throw "ins failed with exit code $insExit"
    }

    ddown @RemainingArgs
}
function global:Invoke-AhkX4ZFast {
    [CmdletBinding()]
    param(
        [switch] $DryRun,
        [switch] $SelfTest,
        [switch] $SoftFailSelfTest
    )

    if ($SoftFailSelfTest) {
        Write-Host 'AHKX4Z_SOFTFAIL_SELFTEST_OK=1 tab_mode_no_job_failure_path'
        return
    }

    $parallelTabs = @(
        [pscustomobject]@{ Name = 'rescod'; Commands = @('rescod') },
        [pscustomobject]@{ Name = 'resher'; Commands = @('resher') },
        [pscustomobject]@{ Name = 'reass'; Commands = @('reass') },
        [pscustomobject]@{ Name = 'gwinpe'; Commands = @('gwinpe') },
        [pscustomobject]@{ Name = 'fixstore'; Commands = @('fixstore', 'fixstore') },
        [pscustomobject]@{ Name = 'fff'; Commands = @('fff') },
        [pscustomobject]@{ Name = 'rmboot'; Commands = @('rmboot') }
    )
    $parallelCommands = @($parallelTabs | ForEach-Object { $_.Name })
    $afterParallelCommands = @('upup', 'pwemod', 'cccc')
    $allCommands = @($parallelTabs | ForEach-Object { $_.Commands }) + $afterParallelCommands
    $wtCommand = Get-Command wt.exe -ErrorAction SilentlyContinue
    $ps5Path = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $profilePath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\Microsoft.PowerShell_profile.ps1'

    if ($DryRun) {
        $terminal = if ($wtCommand) { 'wt.exe' } else { 'ps5_windows_fallback' }
        $tabSummary = ($parallelTabs | ForEach-Object { '{0}=({1})' -f $_.Name, ($_.Commands -join ';') }) -join ','
        Write-Host ("AHKX4Z_DRYRUN parallel_tabs={0} wait_for=all after_parallel={1} terminal={2} window=0 progress=tab_output_plus_marker_polling" -f $tabSummary, ($afterParallelCommands -join ','), $terminal)
        return
    }

    if (Get-Command Load-FullPowerShellProfile -CommandType Function -ErrorAction SilentlyContinue) {
        try { Load-FullPowerShellProfile } catch { Write-Warning ("AHKX4Z_FULL_PROFILE_LOAD_WARNING {0}" -f $_.Exception.Message) }
    }

    if (-not (Test-Path -LiteralPath $ps5Path -PathType Leaf)) {
        throw "Invoke-AhkX4ZFast missing Windows PowerShell 5 executable: $ps5Path"
    }

    $missingCommands = @()
    foreach ($commandName in $allCommands) {
        if (-not (Get-Command $commandName -ErrorAction SilentlyContinue)) {
            $missingCommands += $commandName
        }
    }
    if ($missingCommands.Count -gt 0) {
        throw ("Invoke-AhkX4ZFast missing required command(s): {0}" -f (($missingCommands | Sort-Object -Unique) -join ', '))
    }

    if ($SelfTest) {
        Write-Host ("AHKX4Z_SELFTEST_WT={0}" -f $(if ($wtCommand) { $wtCommand.Source } else { 'missing_fallback_available' }))
        Write-Host ("AHKX4Z_SELFTEST_PS5={0}" -f $ps5Path)
        foreach ($commandName in $allCommands) {
            $cmd = Get-Command $commandName -ErrorAction Stop
            Write-Host ('AHKX4Z_SELFTEST_COMMAND {0}={1}' -f $commandName, $cmd.CommandType)
        }
        Write-Host 'AHKX4Z_SELFTEST_OK=1'
        return
    }

    if (-not $wtCommand) {
        Write-Host 'AHKX4Z_NO_WT_FALLBACK=ps5_windows reason=wt.exe_missing' -ForegroundColor Yellow
    }

    $runId = 'ahkx4z-' + (Get-Date -Format 'yyyyMMdd-HHmmss') + '-' + ([guid]::NewGuid().ToString('N').Substring(0, 8))
    $runDir = Join-Path $env:TEMP $runId
    New-Item -ItemType Directory -Path $runDir -Force | Out-Null
    $markers = @{}

    foreach ($tab in $parallelTabs) {
        $tabName = $tab.Name
        $tabCommands = @($tab.Commands)
        $markerPath = Join-Path $runDir ($tabName + '.done')
        $markers[$tabName] = $markerPath
        $escapedTabName = $tabName.Replace("'", "''")
        $escapedCommands = @($tabCommands | ForEach-Object { $_.Replace("'", "''") })
        $commandArrayLiteral = "@('" + ($escapedCommands -join "','") + "')"
        $escapedMarker = $markerPath.Replace("'", "''")
        $escapedProfile = $profilePath.Replace("'", "''")
        $childScript = @"
`$ErrorActionPreference = 'Continue'
`$ProgressPreference = 'Continue'
`$global:LASTEXITCODE = 0
`$tabName = '$escapedTabName'
`$tabCommands = $commandArrayLiteral
`$markerPath = '$escapedMarker'
`$profilePath = '$escapedProfile'
Write-Host ("AHKX4Z_TAB_START {0} commands={1} {2:o}" -f `$tabName, (`$tabCommands -join ';'), (Get-Date))
try {
    if (Test-Path -LiteralPath `$profilePath -PathType Leaf) {
        . `$profilePath
    }
    foreach (`$commandName in `$tabCommands) {
        Write-Host ("AHKX4Z_TAB_COMMAND_START {0} command={1} {2:o}" -f `$tabName, `$commandName, (Get-Date))
        & `$commandName
        Write-Host ("AHKX4Z_TAB_COMMAND_DONE {0} command={1} {2:o}" -f `$tabName, `$commandName, (Get-Date))
    }
} catch {
    Write-Host ("AHKX4Z_TAB_ERROR_SOFT {0} error={1}" -f `$tabName, `$_.Exception.Message) -ForegroundColor Yellow
} finally {
    try {
        [pscustomobject]@{
            tab = `$tabName
            commands = `$tabCommands
            done_at = (Get-Date).ToString('o')
        } | ConvertTo-Json -Compress | Set-Content -LiteralPath `$markerPath -Encoding UTF8 -Force
    } catch {
        Write-Host ("AHKX4Z_MARKER_ERROR {0} error={1}" -f `$tabName, `$_.Exception.Message) -ForegroundColor Yellow
    }
    Write-Host ("AHKX4Z_TAB_DONE {0} {1:o}" -f `$tabName, (Get-Date))
}
"@
        $encodedChild = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($childScript))
        if ($wtCommand) {
            & $wtCommand.Source -w 0 new-tab --title ('ahkx4z-' + $tabName) $ps5Path -NoLogo -NoExit -ExecutionPolicy Bypass -EncodedCommand $encodedChild | Out-Null
        } else {
            Start-Process -FilePath $ps5Path -ArgumentList @('-NoLogo','-NoExit','-ExecutionPolicy','Bypass','-EncodedCommand',$encodedChild) -WorkingDirectory 'F:\study' | Out-Null
        }
        Start-Sleep -Milliseconds 200
    }

    Write-Host ("AHKX4Z_TABS_STARTED {0}" -f (($parallelCommands | ForEach-Object { $_ + '=' + $markers[$_] }) -join ', '))
    Write-Host 'AHKX4Z_PROGRESS_POLLING wait_for=all'

    $startedAt = Get-Date
    $remaining = @($parallelCommands)
    $lastStatusAt = (Get-Date).AddSeconds(-10)
    while ($remaining.Count -gt 0) {
        foreach ($commandName in @($remaining)) {
            if (Test-Path -LiteralPath $markers[$commandName] -PathType Leaf) {
                Write-Host ("AHKX4Z_TAB_COMPLETE {0}" -f $commandName)
                $remaining = @($remaining | Where-Object { $_ -ne $commandName })
            }
        }

        if (((Get-Date) - $lastStatusAt).TotalSeconds -ge 2) {
            $elapsed = [int]((Get-Date) - $startedAt).TotalSeconds
            $states = ($parallelCommands | ForEach-Object {
                $state = if ($remaining -contains $_) { 'Running' } else { 'Done' }
                '{0}={1}' -f $_, $state
            }) -join ' '
            Write-Host ("AHKX4Z_PROGRESS elapsed={0}s {1}" -f $elapsed, $states)
            $lastStatusAt = Get-Date
        }

        if ($remaining.Count -gt 0) {
            Start-Sleep -Seconds 1
        }
    }

    Write-Host 'AHKX4Z_PARALLEL_DONE'

    upup
    pwemod
    cccc
}





# BEGIN CODEX COG RESTORE 20260630
function cog {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]]$ArgumentList
    )

    $opencodeCommand = Get-Command opencode -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $opencodeCommand) {
        throw 'cog could not find opencode on PATH.'
    }

    & $opencodeCommand @ArgumentList
}
# END CODEX COG RESTORE 20260630

# >>> adbcp Android Downloads copy helper >>>
function global:adbcp {
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [string[]] $Path
    )

    if (-not $Path -or $Path.Count -eq 0) {
        throw 'Usage: adbcp "file or folder or full path" ["same 2"] ["same 3"]'
    }

    foreach ($item in $Path) {
        if ([string]::IsNullOrWhiteSpace($item)) {
            continue
        }

        $resolved = Resolve-Path -LiteralPath $item -ErrorAction Stop
        foreach ($source in $resolved) {
            aadb push $source.ProviderPath '/sdcard/Download/'
        }
    }
}
# <<< adbcp Android Downloads copy helper <<<
























function ghistory {     F:\study\Windows\PowerShell\Profile\history\Enable-WillowForcePowerShellHistory.ps1 }


function startgui {   F:\study\Windows\Applications\Desktop\Utilities\System\Startup\Managers\mich-startup-master\build\MichStartupMaster.exe }


# region Codex rrr startup/tray repair
function rrr {
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 180
    )

    & 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\micha\bin\rrr.ps1' -TimeoutSeconds $TimeoutSeconds
    if ($LASTEXITCODE -ne 0) {
        throw "rrr failed with exit code $LASTEXITCODE"
    }
    return

    $ErrorActionPreference = 'Stop'
    $launcher = 'C:\Users\micha\bin\Start-CodexStartupItemWithRetry.ps1'
    if (-not (Test-Path -LiteralPath $launcher)) {
        throw "rrr launcher missing: $launcher"
    }

    $items = @(
        [pscustomobject]@{ Item = 'HermesTray'; ProcessName = 'HermesTray'; Required = $true },
        [pscustomobject]@{ Item = 'MichStartupMasterApp'; ProcessName = 'MichStartupMaster'; Required = $true },
        [pscustomobject]@{ Item = 'AutorunCurrentAhk'; ProcessName = 'AutoHotkey64'; Required = $true },
        [pscustomobject]@{ Item = 'Everything'; ProcessName = 'Everything'; ServiceName = 'Everything'; Required = $true },
        [pscustomobject]@{ Item = 'MichAutoClipSyncTray'; ProcessName = 'MichAutoClipSyncTray'; Required = $true },
        [pscustomobject]@{ Item = 'ProcessLasso'; ProcessName = 'ProcessLasso'; Required = $true },
        [pscustomobject]@{ Item = 'Telegram'; ProcessName = 'Telegram'; Required = $true },
        [pscustomobject]@{ Item = 'OpenSpeedy'; ProcessName = 'Speedy'; Required = $true }
    )

    $ps5 = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    $results = @()

    foreach ($entry in $items) {
        & $ps5 -NoProfile -ExecutionPolicy Bypass -File $launcher -Item $entry.Item -TimeoutSeconds $TimeoutSeconds | Out-Null
        $exitCode = $LASTEXITCODE
        Start-Sleep -Milliseconds 500

        $proc = Get-Process -Name $entry.ProcessName -ErrorAction SilentlyContinue
        $serviceStatus = $null
        if ($entry.PSObject.Properties.Name -contains 'ServiceName') {
            $service = Get-Service -Name $entry.ServiceName -ErrorAction SilentlyContinue
            if ($service) {
                $serviceStatus = $service.Status.ToString()
                if ($service.Status -ne 'Running') {
                    Start-Service -Name $entry.ServiceName
                    Start-Sleep -Seconds 1
                    $service = Get-Service -Name $entry.ServiceName -ErrorAction SilentlyContinue
                    if ($service) { $serviceStatus = $service.Status.ToString() }
                }
            }
        }

        $running = [bool]$proc
        $results += [pscustomobject]@{
            Item = $entry.Item
            ProcessName = $entry.ProcessName
            Running = $running
            Pids = (($proc | Select-Object -ExpandProperty Id) -join ',')
            ServiceStatus = $serviceStatus
            LauncherExitCode = $exitCode
        }
    }

    $failed = $results | Where-Object { -not $_.Running -and $_.ServiceStatus -ne 'Running' }
    $results | Format-Table -AutoSize
    if ($failed) {
        throw ("rrr failed to restore: " + (($failed | ForEach-Object { $_.Item }) -join ', '))
    }

    Write-Host 'RRR_OK'
    return $results
}
# endregion Codex rrr startup/tray repair


# final Codex rrr PATH-backed override
function rrr {
    [CmdletBinding()]
    param(
        [int]$TimeoutSeconds = 180
    )

    & 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe' -NoProfile -ExecutionPolicy Bypass -File 'C:\Users\micha\bin\rrr.ps1' -TimeoutSeconds $TimeoutSeconds
    if ($LASTEXITCODE -ne 0) {
        throw "rrr failed with exit code $LASTEXITCODE"
    }
}

# region Codex profile latest-functions helpers
function ps10 {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    if (-not $profilePath) { $profilePath = $PROFILE }
    if (-not (Test-Path -LiteralPath $profilePath)) {
        throw "Profile file not found: $profilePath"
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw ("Profile parse failed: " + (($errors | ForEach-Object { $_.Message }) -join '; '))
    }

    $rank = 0
    $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $_.Name -notin @('ps10', 'ps20') } |
        Sort-Object { $_.Extent.StartLineNumber } -Descending |
        Select-Object -First 10 |
        ForEach-Object {
            $rank++
            [pscustomobject]@{
                Rank = $rank
                Name = $_.Name
                Line = $_.Extent.StartLineNumber
                Profile = $profilePath
            }
        }
}

function ps20 {
    $profilePath = $PROFILE.CurrentUserCurrentHost
    if (-not $profilePath) { $profilePath = $PROFILE }
    if (-not (Test-Path -LiteralPath $profilePath)) {
        throw "Profile file not found: $profilePath"
    }

    $tokens = $null
    $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$tokens, [ref]$errors)
    if ($errors -and $errors.Count -gt 0) {
        throw ("Profile parse failed: " + (($errors | ForEach-Object { $_.Message }) -join '; '))
    }

    $rank = 0
    $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) |
        Where-Object { $_.Name -notin @('ps10', 'ps20') } |
        Sort-Object { $_.Extent.StartLineNumber } -Descending |
        Select-Object -First 20 |
        ForEach-Object {
            $rank++
            [pscustomobject]@{
                Rank = $rank
                Name = $_.Name
                Line = $_.Extent.StartLineNumber
                Profile = $profilePath
            }
        }
}
# endregion Codex profile latest-functions helpers

# region Codex backup direct wrappers
function global:backcod {
    $scriptPath = 'F:\study\repos\ai-ml\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\backup\backup-codex.ps1'
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) {
        throw "backcod script not found: $scriptPath"
    }
    & $scriptPath -Force @args
}
# endregion Codex backup direct wrappers

function screds { cd F:\backup\windowsapps\credentials }

function scankvrt { $exe = "F:\backup\windowsapps\installed\kvrt\KVRT.exe"; $dir = Split-Path $exe; $dataDir = "$dir\KVRT_Data"; if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }; if (!(Test-Path $exe)) { Invoke-WebRequest -Uri "https://devbuilds.s.kaspersky-labs.com/devbuilds/KVRT/latest/full/KVRT.exe" -OutFile $exe -UseBasicParsing }; & $exe -accepteula -silent -processlevel 3 -d $dataDir -dontencrypt -details; while (Get-Process KVRT -ErrorAction SilentlyContinue) { Start-Sleep -Seconds 2 }; $log = Get-ChildItem -Path $dataDir -Filter "*.log" -Recurse -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1; if ($log) { Get-Content $log.FullName } else { Write-Host "No log found in $dataDir" } }

function codexchrome {    F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\codex-chrome-bridge-repair\Repair-CodexChromeBridge.ps1 }

function fixnode {    F:\study\projects\resumeLinkedinSender\scripts\Repair-JobPortableNode.ps1 }

function before { F:\study\Devops\backup\backup\profile\profile.ps1; F:\study\Devops\backup\backup\profile\profile.ps1; backcod; ass; fff }function recodex {    F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\codex-desktop-fast-restart\CodexDesktopFastRestart.exe }
# >>> aadb Android ADB bridge >>>
function aadb {
    & 'F:\study\Shells\powershell\scripts\android\adb\aadb\Invoke-AndroidAdbBridge.ps1' @args
}
function aad {
    & 'F:\study\Shells\powershell\scripts\android\adb\aadb\Invoke-AndroidAdbBridge.ps1' @args
}
# <<< aadb Android ADB bridge <<<


function myres {    F:\study\projects\AfterFormatNoC\native-vhd\executables\AfterFormat-Restore-Windows11.exe    }



function scaneek { $dir="F:\backup\windowsapps\installed\eek"; $exe="$dir\bin64\a2cmd.exe"; $q="$dir\quarantine"; New-Item -ItemType Directory -Path $dir,$q,"$dir\bin64" -Force | Out-Null; if (!(Test-Path $exe)) { $installer="$env:TEMP\EmsisoftEmergencyKit.exe"; if (!(Test-Path $installer)) { Invoke-WebRequest -Uri "https://dl.emsisoft.com/EmsisoftEmergencyKit.exe" -OutFile $installer -UseBasicParsing }; Start-Process -FilePath $installer -ArgumentList "/S" -Wait; Get-Process a2emergencykit -ErrorAction SilentlyContinue | Stop-Process -Force; if (Test-Path "C:\EEK\bin64\a2cmd.exe") { Copy-Item "C:\EEK\bin64\*" "$dir\bin64" -Recurse -Force } }; Get-Process a2emergencykit -ErrorAction SilentlyContinue | Stop-Process -Force; $log="$dir\scan_C_only_$(Get-Date -Format yyyyMMdd_HHmmss).log"; Push-Location (Split-Path $exe); try { & $exe /u; & $exe '/f=C:\' "/q=$q" "/log=$log"; Write-Host "LOG=$log"; if (Test-Path $log) { Get-Content $log } } finally { Pop-Location } }


# Codex ultimate repair executable override. This later fixcodex definition wins over older definitions above.
function fixcodex {
    & 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\codex-ultimate-mega-repair\bin\CodexUltimateMegaRepair.exe' @args
}
function global:scanmss {
    [CmdletBinding()]
    param(
        [switch]$Full,
        [int]$MaxMinutes = 45,
        [int]$ProgressSeconds = 3
    )

    $script = 'F:\backup\windowsapps\installed\msert\Run-MicrosoftSafetyScanner-Mega.ps1'
    if (!(Test-Path -LiteralPath $script)) {
        throw "scanmss script not found: $script"
    }

    $args = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script, '-MaxMinutes', $MaxMinutes, '-ProgressSeconds', $ProgressSeconds)
    if ($Full) {
        $args += '-Full'
    }

    & "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" @args
}

# BEGIN CODEX GNET RESTORE 20260705
function global:gnet {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $ArgumentList
    )

    $script = 'F:\study\Learning\01\01\Shells\powershell\profile-functions\windows\system\hardware-tools\Gnet\Invoke-gnet.ps1'
    if (-not (Test-Path -LiteralPath $script -PathType Leaf)) {
        throw "gnet script not found: $script"
    }

    $ps5 = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        throw "Windows PowerShell 5 executable not found: $ps5"
    }

    $cleanArgs = @($ArgumentList | Where-Object { $null -ne $_ -and -not [string]::IsNullOrWhiteSpace([string]$_) })
    $argList = @('-NoLogo','-NoProfile','-ExecutionPolicy','Bypass','-File',$script) + $cleanArgs
    Write-Host ("gnet: running command={0} {1}" -f $ps5, ($argList -join ' ')) -ForegroundColor Cyan
    & $ps5 @argList
    $global:LASTEXITCODE = $LASTEXITCODE
}
# END CODEX GNET RESTORE 20260705
function scanems {    F:\backup\windowsapps\installed\a2cmd-c-only\Run-Emsisoft-C-Only-AutoScan.ps1 }

# BEGIN CODEX FASTCC STALE-WRAPPER REFRESH 20260705
function global:Invoke-CodexFastccWrapperRefresh {
    $wrapperPath = 'F:\study\Windows\PowerShell\Profile\ps5-profile-portable\legacy-safe-functions\profile-wrappers.ps1'
    if (Test-Path -LiteralPath $wrapperPath -PathType Leaf) {
        . $wrapperPath
    }
}

function global:fastcc {
    Invoke-CodexFastccWrapperRefresh
    siz
    ram
    ccsizes
    cleanc
    rmvol
    bin
    ram
    fff
    siz
}
# END CODEX FASTCC STALE-WRAPPER REFRESH 20260705

function CCCT {    F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\cccc-turbo-ps5-2x\dist\CcccTurbo.exe }

function myback {    F:\study\projects\AfterFormatNoC\native-vhd\executables\AfterFormat-Backup-Sink.exe}

function be {    F:\study\Devops\backup\backup\profile\profile.ps1; F:\study\Devops\backup\backup\profile\profile.ps1 }

function mybe {    repeat 'be' 60  }

# BEGIN CODEX MENU MMENU DOCKER WRAPPERS 20260706



# END CODEX MENU MMENU DOCKER WRAPPERS 20260706

function fixnotepad {    $ErrorActionPreference='Stop';$win="$env:WINDIR\System32\notepad.exe";$bin=Join-Path $env:USERPROFILE 'bin';New-Item -ItemType Directory -Force -Path $bin|Out-Null;Set-Content -LiteralPath (Join-Path $bin 'notepad.cmd') -Encoding ASCII -Value "@echo off`r`n`"$win`" %*`r`n";$bad='C:\Program Files\Git\usr\bin';foreach($scope in 'User','Machine'){try{$p=[Environment]::GetEnvironmentVariable('Path',$scope);if($p){$parts=$p -split ';'|?{$_ -and ($_.TrimEnd('\') -ine $bad)};$must=@($bin,"$env:WINDIR\System32","$env:WINDIR");$new=($must+$parts|?{$_}|Select-Object -Unique)-join ';';if($new -ne $p){[Environment]::SetEnvironmentVariable('Path',$new,$scope)}}}catch{Write-Warning "PATH $scope not changed: $($_.Exception.Message)"}};$env:Path=($bin,"$env:WINDIR\System32","$env:WINDIR",(($env:Path -split ';')|?{$_ -and ($_.TrimEnd('\') -ine $bad)})) -join ';';$profiles=@($PROFILE.CurrentUserCurrentHost,$PROFILE.CurrentUserAllHosts,(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\profile.ps1'),(Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'PowerShell\profile.ps1'))|Select-Object -Unique;$start='# BEGIN force-windows-notepad';$end='# END force-windows-notepad';$block="# BEGIN force-windows-notepad`r`nfunction global:notepad { & '$win' @args }`r`nSet-Alias -Name notepad.exe -Value '$win' -Scope Global -Force`r`n# END force-windows-notepad`r`n";foreach($f in $profiles){if($f){New-Item -ItemType Directory -Force -Path (Split-Path -Parent $f)|Out-Null;$raw=if(Test-Path -LiteralPath $f){Get-Content -LiteralPath $f -Raw}else{''};$raw=[regex]::Replace($raw,'(?ms)^# BEGIN force-windows-notepad.*?# END force-windows-notepad\r?\n?','');Set-Content -LiteralPath $f -Encoding UTF8 -Value ($raw.TrimEnd()+"`r`n"+$block)}};function global:notepad { & $win @args };Set-Alias -Name notepad.exe -Value $win -Scope Global -Force;Write-Host "FIXED: notepad now points to $win. Open a new PowerShell and run: notepad a.txt" }
function github {    gcl  https://github.com/Michaelunkai?tab=repositories }
function job2 {    F:\study\projects\jobBrowserApplyBot\release\job-browser-apply-bot\job-browser-apply-bot.exe @args }



function piper {    F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\Speech\Windows\Dictation\Tray\PiperVoicePaste\PiperVoicePaste.exe }


function build2 {    cp F:\study\Learning\01\01\Containers\docker\dockerfiles\buildthispath\buildthispath ./Dockerfile }







function rrm { . 'C:\Users\micha\Documents\WindowsPowerShell\legacy-safe-functions\rrm.ps1'; & 'rrm' @args }

# BEGIN CODEX WWW CHILD-INS OVERRIDE 20260706
function global:www {
    [CmdletBinding()]
    param(
        [Parameter(ValueFromRemainingArguments = $true)]
        [object[]] $RemainingArgs
    )

    $ps5 = Join-Path $env:WINDIR 'System32\WindowsPowerShell\v1.0\powershell.exe'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        $ps5 = 'C:\Windows\System32\WindowsPowerShell\v1.0\powershell.exe'
    }

    $insScript = 'F:\study\Windows\Applications\Gaming\DownloadManagers\qBittorrent\FitGirl\Automation\AutoInstall\qbittorrent-fitgirl-force-auto-install-20260601\ins.ps1'
    if (-not (Test-Path -LiteralPath $ps5 -PathType Leaf)) {
        throw "Windows PowerShell 5 executable not found: $ps5"
    }
    if (-not (Test-Path -LiteralPath $insScript -PathType Leaf)) {
        throw "ins launcher not found: $insScript"
    }

    & $ps5 -NoProfile -ExecutionPolicy Bypass -File $insScript
    $insExit = $LASTEXITCODE
    if ($null -ne $insExit -and $insExit -ne 0) {
        throw "ins failed with exit code $insExit"
    }

    ddown @RemainingArgs
}
# END CODEX WWW CHILD-INS OVERRIDE 20260706

function qq {    GDBOOSTER;GCCLEANER }

# BEGIN CODEX DUSH DIRECT WRAPPER 20260706
function global:dush { & 'F:\study\Dev_Toolchain\programming\python\apps\systemTools\sizes\dush.exe' @args }
# END CODEX DUSH DIRECT WRAPPER 20260706











function ins { F:\study\Windows\Applications\Gaming\DownloadManagers\qBittorrent\FitGirl\Automation\AutoInstall\qbittorrent-fitgirl-force-auto-install-20260601\dist\FitGirlAutoInstall.exe }

function handy {    F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\Speech\Windows\Dictation\Tray\PiperVoicePaste\handy.exe }

function mmenu { F:\study\projects\docker-desktop-powershell-fast-push-700mbps-exe\dist\DockerDesktopFastPush700.exe @args }

function befo {     F:\study\Devops\backup\backup\profile\profile.ps1; F:\study\Devops\backup\backup\profile\profile.ps1; backcod; ass }

function menu {    F:\study\projects\docker-desktop-folder-repo-autotag-exe\dist\DockerDesktopFolderRepoAutoTag.exe @args }

function wintest { F:\study\projects\AfterFormatNoC\native-vhd\executables\AfterFormat-Reboot-Into-Formatted-Windows11.exe }

