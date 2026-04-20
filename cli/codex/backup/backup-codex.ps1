#Requires -Version 5.1
<#
.SYNOPSIS
    Codex backup - incremental latest + timestamped snapshot.
.DESCRIPTION
    Copies Codex/OpenAI-related data into a persistent "latest" directory and then
    creates a timestamped snapshot in the same backup root used by the Claude tools.
    The copy path is intentionally visible so live progress remains on screen from
    the first task through the final snapshot.
.PARAMETER BackupPath
    Snapshot directory. Default: F:\backup\codex\backup_<timestamp>
.PARAMETER MaxJobs
    Parallelism for bulk sync operations. Default: 64
.PARAMETER DryRun
    Lists discovered tasks without copying files.
.PARAMETER Force
    Reserved for future use.
#>
[CmdletBinding()]
param(
    [string]$BackupPath = "F:\backup\claudecode\backup_$(Get-Date -Format 'yyyy_MM_dd_HH_mm_ss')",
    [int]$MaxJobs = 64,
    [switch]$DryRun,
    [switch]$Force
)

$ErrorActionPreference = 'Continue'
$ProgressPreference = 'Continue'
$script:Errors = [System.Collections.Concurrent.ConcurrentBag[string]]::new()
$script:DoneLog = [System.Collections.Concurrent.ConcurrentQueue[string]]::new()
$script:PreferVisibleProgress = $true

$HP = $env:USERPROFILE
$A = $env:APPDATA
$L = $env:LOCALAPPDATA
$backupRoot = Split-Path $BackupPath -Parent
if (-not $backupRoot) { $backupRoot = 'F:\backup\claudecode' }
$LatestDir = Join-Path $backupRoot 'latest'
$backupDriveLetter = (Split-Path $backupRoot -Qualifier).TrimEnd(':').Trim()
$backupFsType = try { (Get-Volume -DriveLetter $backupDriveLetter -EA Stop).FileSystemType } catch { 'Unknown' }
$script:IsExFat = $backupFsType -eq 'exFAT'

New-Item -ItemType Directory -Path $LatestDir -Force | Out-Null

function Get-EnvironmentBlockBytes {
    $bytes = 1
    foreach($entry in [System.Environment]::GetEnvironmentVariables().GetEnumerator()){
        $pair = "$($entry.Key)=$($entry.Value)"
        $bytes += ([System.Text.Encoding]::Unicode.GetByteCount($pair) + 2)
    }
    $bytes
}

function Invoke-RobocopySync {
    param(
        [string]$Source,
        [string]$Destination,
        [string[]]$ExcludeDirs
    )
    if (-not (Test-Path $Source)) { return $false }
    $isDir = (Get-Item $Source -Force).PSIsContainer
    if ($isDir) {
        New-Item -ItemType Directory -Path $Destination -Force | Out-Null
        $args = @($Source, $Destination, '/E', '/XO', '/FFT', '/R:0', '/W:0', '/TEE', '/ETA', "/MT:$([Math]::Min($MaxJobs,64))")
        foreach ($xd in @($ExcludeDirs)) {
            if ($xd) { $args += @('/XD', (Join-Path $Source $xd)) }
        }
        & robocopy @args
        return $LASTEXITCODE -lt 8
    }
    $destDir = Split-Path $Destination -Parent
    if ($destDir) { New-Item -ItemType Directory -Path $destDir -Force | Out-Null }
    try {
        Copy-Item -LiteralPath $Source -Destination $Destination -Force -EA Stop
        return $true
    } catch {
        return $false
    }
}

function Write-Utf8NoBom {
    param([string]$Path,[string]$Content)
    [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($false))
}

function Write-PointerSnapshot {
    param([string]$SnapshotPath,[string]$LatestPath)
    New-Item -ItemType Directory -Path $SnapshotPath -Force | Out-Null
    $pointer = @{
        Type = 'PointerSnapshot'
        Version = '2.0'
        CreatedAt = (Get-Date -Format 'o')
        TargetRelative = '..\latest'
        ResolvedPath = $LatestPath
        Notes = 'Timestamped snapshot points at latest to avoid full exFAT duplicate copies.'
    } | ConvertTo-Json -Depth 5
    Write-Utf8NoBom -Path (Join-Path $SnapshotPath 'BACKUP-POINTER.json') -Content $pointer
    foreach ($name in @('manifest.json','RESTORE-MAP.json','BACKUP-METADATA.json')) {
        $src = Join-Path $LatestPath $name
        if (Test-Path $src) {
            Copy-Item -LiteralPath $src -Destination (Join-Path $SnapshotPath $name) -Force -EA SilentlyContinue
        }
    }
}

$script:UseCompiledCopier = $false
if ((-not $script:PreferVisibleProgress) -and ((Get-EnvironmentBlockBytes) -lt 65000)) {
    Add-Type -ErrorAction Stop @"
using System;
using System.IO;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;

public class IncrementalCopier {
    public static int[] BulkSync(string[] srcs, string[] dsts, string[] descs, string[][] excludeDirs,
        ConcurrentBag<string> errBag, ConcurrentQueue<string> doneLog, int parallelism) {
        int done = 0, skipped = 0;
        var opts = new ParallelOptions { MaxDegreeOfParallelism = parallelism };
        Parallel.For(0, srcs.Length, opts, i => {
            var src = srcs[i];
            var dst = dsts[i];
            var desc = descs[i];
            var xd = (excludeDirs != null && i < excludeDirs.Length) ? excludeDirs[i] : null;
            try {
                if (Directory.Exists(src)) {
                    SyncDirRecursive(src, dst, xd);
                    doneLog.Enqueue("[OK] " + desc);
                    Interlocked.Increment(ref done);
                } else if (File.Exists(src)) {
                    var dir = Path.GetDirectoryName(dst);
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    File.Copy(src, dst, true);
                    doneLog.Enqueue("[OK] " + desc);
                    Interlocked.Increment(ref done);
                } else {
                    Interlocked.Increment(ref skipped);
                }
            } catch (Exception ex) {
                errBag.Add("FAIL: " + desc + " - " + ex.Message);
                doneLog.Enqueue("[FAIL] " + desc);
            }
        });
        return new int[] { done, skipped };
    }

    private static void SyncDirRecursive(string src, string dst, string[] excludeDirs) {
        var excludes = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        excludes.Add(".git");
        excludes.Add("node_modules");
        excludes.Add("__pycache__");
        if (excludeDirs != null) {
            foreach (var item in excludeDirs) excludes.Add(item);
        }
        if (!Directory.Exists(dst)) Directory.CreateDirectory(dst);
        foreach (var file in Directory.GetFiles(src)) {
            var name = Path.GetFileName(file);
            var target = Path.Combine(dst, name);
            if (File.Exists(target)) {
                var srcTime = File.GetLastWriteTimeUtc(file);
                var dstTime = File.GetLastWriteTimeUtc(target);
                if (srcTime <= dstTime.AddSeconds(2)) continue;
            }
            try { File.Copy(file, target, true); } catch {}
        }
        foreach (var dir in Directory.GetDirectories(src)) {
            var name = Path.GetFileName(dir);
            if (excludes.Contains(name)) continue;
            SyncDirRecursive(dir, Path.Combine(dst, name), excludeDirs);
        }
    }
}

public class HardLinkCloner {
    [System.Runtime.InteropServices.DllImport("kernel32.dll", SetLastError = true, CharSet = System.Runtime.InteropServices.CharSet.Unicode)]
    static extern bool CreateHardLink(string lpFileName, string lpExistingFileName, IntPtr lpSecurityAttributes);

    public static int[] CloneWithHardlinks(string sourceDir, string targetDir, int maxParallelism) {
        int linked = 0, failed = 0;
        Directory.CreateDirectory(targetDir);
        foreach (string d in Directory.EnumerateDirectories(sourceDir, "*", SearchOption.AllDirectories)) {
            Directory.CreateDirectory(targetDir + d.Substring(sourceDir.Length));
        }
        int srcLen = sourceDir.Length;
        var opts = new ParallelOptions { MaxDegreeOfParallelism = maxParallelism };
        Parallel.ForEach(Directory.EnumerateFiles(sourceDir, "*", SearchOption.AllDirectories), opts, f => {
            string target = targetDir + f.Substring(srcLen);
            if (CreateHardLink(target, f, IntPtr.Zero)) {
                Interlocked.Increment(ref linked);
            } else {
                try { File.Copy(f, target, true); Interlocked.Increment(ref linked); }
                catch { Interlocked.Increment(ref failed); }
            }
        });
        return new int[] { linked, failed };
    }
}
"@
    $script:UseCompiledCopier = $true
} else {
    if ($script:PreferVisibleProgress) {
        Write-Host "[INFO] Using visible copy engine so progress stays live throughout the backup." -ForegroundColor Yellow
    } else {
        Write-Warning "Add-Type skipped because the environment block is too large; using robocopy/copy fallback."
    }
}

function Update-BackupProgress {
    param(
        [int]$Id,
        [string]$Activity,
        [string]$Status,
        [int]$PercentComplete = -1
    )
    if ($PercentComplete -ge 0) {
        Write-Progress -Id $Id -Activity $Activity -Status $Status -PercentComplete $PercentComplete
    } else {
        Write-Progress -Id $Id -Activity $Activity -Status $Status
    }
}

function Invoke-BulkSync {
    param(
        [string[]]$Srcs,
        [string[]]$Dsts,
        [string[]]$Descs,
        [string[][]]$ExcludeDirs,
        [int]$Parallelism = 64
    )
    if ($script:UseCompiledCopier) {
        return [IncrementalCopier]::BulkSync($Srcs, $Dsts, $Descs, $ExcludeDirs, $script:Errors, $script:DoneLog, $Parallelism)
    }
    $done = 0
    $skipped = 0
    $total = [Math]::Max($Srcs.Length, 1)
    for ($i = 0; $i -lt $Srcs.Length; $i++) {
        $pct = [int](($i / $total) * 100)
        Update-BackupProgress -Id 1 -Activity 'Backing up Codex data' -Status ("Task {0}/{1}: {2}" -f ($i + 1), $Srcs.Length, $Descs[$i]) -PercentComplete $pct
        Write-Host ("[TASK {0}/{1}] {2}" -f ($i + 1), $Srcs.Length, $Descs[$i]) -ForegroundColor Cyan
        if (-not (Test-Path $Srcs[$i])) {
            $skipped++
            Write-Host "  [SKIP] Source not found" -ForegroundColor DarkYellow
            continue
        }
        if (Invoke-RobocopySync -Source $Srcs[$i] -Destination $Dsts[$i] -ExcludeDirs $ExcludeDirs[$i]) {
            $done++
            $script:DoneLog.Enqueue("[OK] $($Descs[$i])")
        } else {
            $script:Errors.Add("FAIL: $($Descs[$i])")
            $script:DoneLog.Enqueue("[FAIL] $($Descs[$i])")
        }
    }
    Update-BackupProgress -Id 1 -Activity 'Backing up Codex data' -Status 'Task sync complete' -PercentComplete 100
    return @($done, $skipped)
}

$allTasks = New-Object System.Collections.Generic.List[hashtable]
function Add-Task {
    param([string]$S,[string]$D,[string]$Desc,[string[]]$XD=$null)
    $allTasks.Add(@{ S=$S; D=$D; Desc=$Desc; XD=$XD }) | Out-Null
}

Write-Host ""
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  CODEX BACKUP - INCREMENTAL LATEST + SNAPSHOT" -ForegroundColor White
Write-Host "  Latest:   $LatestDir" -ForegroundColor DarkGray
Write-Host "  Snapshot: $BackupPath" -ForegroundColor DarkGray
Write-Host "  FS:       $backupFsType | Threads: $MaxJobs" -ForegroundColor Yellow
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host ""

$codexRoot = "$HP\.codex"
$wslPackageRoot = "$L\Packages"
$matchRx = 'codex|openai|chatgpt'

# Core Codex home
Add-Task $codexRoot "$LatestDir\core\codex-home" ".codex full home"
@(
    @("$codexRoot\config.toml", "$LatestDir\core\config.toml", ".codex/config.toml"),
    @("$codexRoot\settings.json", "$LatestDir\core\settings.json", ".codex/settings.json"),
    @("$codexRoot\auth.json", "$LatestDir\core\auth.json", ".codex/auth.json"),
    @("$codexRoot\AGENTS.md", "$LatestDir\core\AGENTS.md", ".codex/AGENTS.md"),
    @("$codexRoot\CLAUDE.md", "$LatestDir\core\CLAUDE.md", ".codex/CLAUDE.md"),
    @("$codexRoot\learned.md", "$LatestDir\core\learned.md", ".codex/learned.md"),
    @("$codexRoot\MEMORY.md", "$LatestDir\core\MEMORY.md", ".codex/MEMORY.md"),
    @("$codexRoot\history.jsonl", "$LatestDir\sessions\history.jsonl", ".codex/history.jsonl"),
    @("$codexRoot\session_index.jsonl", "$LatestDir\sessions\session_index.jsonl", ".codex/session_index.jsonl"),
    @("$codexRoot\resource-config.json", "$LatestDir\core\resource-config.json", ".codex/resource-config.json"),
    @("$codexRoot\mcp-servers.json", "$LatestDir\mcp\mcp-servers.json", ".codex/mcp-servers.json"),
    @("$codexRoot\.codex-global-state.json", "$LatestDir\core\codex-global-state.json", ".codex/.codex-global-state.json")
) | ForEach-Object { Add-Task $_[0] $_[1] $_[2] }

# Core subdirs
@(
    'prompts','skills','rules','hooks','scripts','channels','workspace','projects','sessions',
    'memory','memories','sqlite','vendor_imports','bin','.sandbox'
) | ForEach-Object {
    Add-Task (Join-Path $codexRoot $_) "$LatestDir\core\subdirs\$_" ".codex/$_"
}

# Global context and shell profile files that Codex depends on
@(
    @("$HP\AGENTS.md", "$LatestDir\agents\home-AGENTS.md", "Home AGENTS.md"),
    @("$HP\CLAUDE.md", "$LatestDir\agents\home-CLAUDE.md", "Home CLAUDE.md"),
    @("$HP\.gitconfig", "$LatestDir\git\.gitconfig", ".gitconfig"),
    @("$HP\.gitignore_global", "$LatestDir\git\.gitignore_global", ".gitignore_global"),
    @("$HP\.git-credentials", "$LatestDir\git\.git-credentials", ".git-credentials"),
    @("$HP\.npmrc", "$LatestDir\npm\.npmrc", ".npmrc"),
    @("$HP\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1", "$LatestDir\powershell\ps5-profile.ps1", "PS5 profile"),
    @("$HP\Documents\PowerShell\Microsoft.PowerShell_profile.ps1", "$LatestDir\powershell\ps7-profile.ps1", "PS7 profile")
) | ForEach-Object { Add-Task $_[0] $_[1] $_[2] }

# Backup/restore tooling for Codex itself
$codexCliRoot = Split-Path $PSScriptRoot -Parent
Add-Task $PSScriptRoot "$LatestDir\tooling\backup-scripts" 'Codex backup scripts workspace'
Add-Task $codexCliRoot "$LatestDir\tooling\codex-cli-root" 'Codex CLI workspace'

# Launch surface and likely installed runtime
$codexCommand = Get-Command codex -ErrorAction SilentlyContinue
if ($codexCommand) {
    Add-Task $codexCommand.Source "$LatestDir\executables\codex.exe" "codex command target"
    $cmdDir = Split-Path $codexCommand.Source -Parent
    Add-Task $cmdDir "$LatestDir\executables\winget-links" "WinGet links dir"
}
Add-Task "$L\Microsoft\WinGet\Links" "$LatestDir\executables\winget-links-full" "WinGet links full"

# NPM / Node / package installs
@(
    "$A\npm\node_modules",
    "$A\npm",
    "$A\npm-cache",
    "$HP\AppData\Roaming\npm\node_modules",
    "$HP\AppData\Roaming\npm"
) | ForEach-Object {
    if (Test-Path $_) {
        Get-ChildItem $_ -Directory -EA SilentlyContinue | Where-Object { $_.Name -match $matchRx } | ForEach-Object {
            Add-Task $_.FullName "$LatestDir\npm\discovered\$($_.Name)" "npm discovered: $($_.Name)"
        }
    }
}

# Config and cache roots
@(
    "$HP\.config",
    "$HP\.local\share",
    "$HP\.local\state",
    "$HP\.cache",
    $A,
    $L,
    "$HP\AppData\LocalLow",
    "$env:ProgramData"
) | ForEach-Object {
    if (Test-Path $_) {
        $root = $_
        Get-ChildItem $root -Directory -Force -EA SilentlyContinue | Where-Object { $_.Name -match $matchRx } | ForEach-Object {
            $safe = ($_.FullName -replace ':','' -replace '[\\\/]','_').Trim('_')
            Add-Task $_.FullName "$LatestDir\discovered\roots\$safe" "Discovered root: $($_.FullName)"
        }
    }
}

# VS Code / Cursor / Windsurf extensions with Codex/OpenAI affinity
@(
    "$HP\.vscode\extensions",
    "$HP\.cursor\extensions",
    "$HP\.windsurf\extensions"
) | ForEach-Object {
    if (Test-Path $_) {
        Get-ChildItem $_ -Directory -EA SilentlyContinue | Where-Object { $_.Name -match $matchRx } | ForEach-Object {
            $safe = ($_.FullName -replace ':','' -replace '[\\\/]','_').Trim('_')
            Add-Task $_.FullName "$LatestDir\extensions\$safe" "Editor extension: $($_.Name)"
        }
    }
}

# Browser storage relevant to Codex/OpenAI/ChatGPT
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
                    Get-ChildItem $sub -Force -EA SilentlyContinue | Where-Object { $_.Name -match $matchRx } | ForEach-Object {
                        Add-Task $_.FullName "$LatestDir\browsers\$($browser.Prefix)-$profileName-$($_.Name -replace '[\\/:*?""<>| ]','_')" "$($browser.Prefix) $profileName $($_.Name)"
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
            Get-ChildItem $storage -Directory -EA SilentlyContinue | Where-Object { $_.Name -match $matchRx } | ForEach-Object {
                Add-Task $_.FullName "$LatestDir\browsers\firefox-$($profile.Name)-$($_.Name -replace '[\\/:*?""<>| ]','_')" "firefox $($profile.Name) $($_.Name)"
            }
        }
    }
}

# Project-local .codex directories and instruction files
$projectRoots = @("$HP\Projects","$HP\repos","$HP\dev","$HP\code","F:\Projects","D:\Projects","F:\study")
$projectIndex = New-Object System.Collections.Generic.List[object]
foreach ($root in $projectRoots) {
    if (Test-Path $root) {
        try {
            foreach ($dir in [System.IO.Directory]::EnumerateDirectories($root, '.codex', [System.IO.SearchOption]::AllDirectories)) {
                if ($dir -notmatch '\\(\.git|node_modules|dist|build|__pycache__|\.venv|venv)\\') {
                    $safe = ($dir -replace ':','_' -replace '\\','_').Trim('_')
                    Add-Task $dir "$LatestDir\project-codex\$safe" "Project .codex: $dir"
                    $projectIndex.Add([pscustomobject]@{ OriginalPath = $dir; BackupName = $safe }) | Out-Null
                }
            }
        } catch {}
        try {
            foreach ($file in [System.IO.Directory]::EnumerateFiles($root, 'AGENTS.md', [System.IO.SearchOption]::AllDirectories)) {
                if ($file -notmatch '\\(\.git|node_modules|dist|build|__pycache__|\.venv|venv)\\') {
                    $safe = ($file -replace ':','_' -replace '\\','_').Trim('_')
                    Add-Task $file "$LatestDir\project-instructions\$safe" "Project AGENTS.md: $file"
                }
            }
        } catch {}
    }
}

# WSL homes
if (Test-Path $wslPackageRoot) {
    Get-ChildItem $wslPackageRoot -Directory -Filter '*CanonicalGroup*' -EA SilentlyContinue | ForEach-Object {
        $homeRoot = Join-Path $_.FullName 'LocalState\rootfs\home'
        if (Test-Path $homeRoot) {
            Get-ChildItem $homeRoot -Directory -EA SilentlyContinue | ForEach-Object {
                $linuxHome = $_.FullName
                @('.codex','.config/codex','.local/share/codex','.local/state/codex','.cache/codex') | ForEach-Object {
                    $candidate = Join-Path $linuxHome $_
                    if (Test-Path $candidate) {
                        $safe = ($candidate -replace ':','' -replace '[\\\/]','_').Trim('_')
                        Add-Task $candidate "$LatestDir\wsl\$safe" "WSL: $candidate"
                    }
                }
            }
        }
    }
}

# Drive-level catch-all for nonstandard installations
@('D:\','E:\','F:\') | ForEach-Object {
    if (Test-Path $_) {
        $drive = $_.Substring(0,1)
        Get-ChildItem $_ -Directory -Depth 2 -EA SilentlyContinue | Where-Object {
            $_.Name -match $matchRx -and
            $_.FullName -notlike "$backupRoot*" -and
            $_.FullName -notlike "$BackupPath*"
        } | ForEach-Object {
            $safe = ($_.FullName -replace ':','' -replace '[\\\/]','_').Trim('_')
            Add-Task $_.FullName "$LatestDir\drives\$drive-$safe" "Drive $drive discovered: $($_.FullName)"
        }
    }
}

if ($DryRun) {
    $allTasks | Sort-Object Desc | Select-Object Desc,S,D | Format-Table -AutoSize
    Write-Host ("[DRY-RUN] {0} tasks discovered" -f $allTasks.Count) -ForegroundColor Yellow
    return
}

$srcs = [string[]]::new($allTasks.Count)
$dsts = [string[]]::new($allTasks.Count)
$descs = [string[]]::new($allTasks.Count)
$xds = [string[][]]::new($allTasks.Count)
for ($i = 0; $i -lt $allTasks.Count; $i++) {
    $srcs[$i] = $allTasks[$i].S
    $dsts[$i] = $allTasks[$i].D
    $descs[$i] = $allTasks[$i].Desc
    $xds[$i] = $allTasks[$i].XD
}

$sw = [System.Diagnostics.Stopwatch]::StartNew()
Update-BackupProgress -Id 0 -Activity 'Codex backup' -Status 'Preparing sync tasks' -PercentComplete 5
Write-Host "[P1] Syncing $($allTasks.Count) tasks..." -ForegroundColor Cyan
$result = Invoke-BulkSync -Srcs $srcs -Dsts $dsts -Descs $descs -ExcludeDirs $xds -Parallelism $MaxJobs
$m = $null
while ($script:DoneLog.TryDequeue([ref]$m)) {
    Write-Host "  $m" -ForegroundColor DarkGray
}
Write-Host "[P1] Done: $($result[0]) synced, $($result[1]) missing" -ForegroundColor Green

Update-BackupProgress -Id 0 -Activity 'Codex backup' -Status 'Capturing metadata' -PercentComplete 70
Write-Host "[P2] Capturing metadata..." -ForegroundColor Cyan
New-Item -ItemType Directory -Path "$LatestDir\meta" -Force | Out-Null
New-Item -ItemType Directory -Path "$LatestDir\credentials" -Force | Out-Null
New-Item -ItemType Directory -Path "$LatestDir\scheduled-tasks" -Force | Out-Null
New-Item -ItemType Directory -Path "$LatestDir\env" -Force | Out-Null

if ($projectIndex.Count -gt 0) {
    $projectIndex | ConvertTo-Json -Depth 4 | Out-File "$LatestDir\project-codex\project-codex-paths.json" -Encoding UTF8
}

try {
    $toolInfo = @{}
    foreach ($tool in @('codex','node','npm','git','python','python3','uv','rg')) {
        $cmd = Get-Command $tool -ErrorAction SilentlyContinue
        if ($cmd) {
            $version = ''
            try { $version = (& $tool --version 2>$null) -join ' ' } catch {}
            $toolInfo[$tool] = @{ Path = $cmd.Source; Version = $version }
        }
    }
    $toolInfo | ConvertTo-Json -Depth 5 | Out-File "$LatestDir\meta\tool-versions.json" -Encoding UTF8
} catch { $script:Errors.Add("FAIL: tool version capture - $($_.Exception.Message)") }

try {
    $envPatterns = 'CODEX|OPENAI|CHATGPT|OPENROUTER|ANTHROPIC|MCP|PATH|NODE|NPM|PYTHON|UV'
    $envDump = @{}
    Get-ChildItem Env: | Where-Object { $_.Name -match $envPatterns } | ForEach-Object { $envDump[$_.Name] = $_.Value }
    $envDump | ConvertTo-Json -Depth 5 | Out-File "$LatestDir\env\environment-variables.json" -Encoding UTF8
    ($envDump.GetEnumerator() | Sort-Object Key | ForEach-Object { "$($_.Key)=$($_.Value)" }) | Out-File "$LatestDir\env\environment-variables.txt" -Encoding UTF8
} catch { $script:Errors.Add("FAIL: env capture - $($_.Exception.Message)") }

try {
    $credPatterns = 'codex|openai|chatgpt|github|npm|node'
    $cmdkey = cmdkey /list 2>$null
    if ($cmdkey) {
        ($cmdkey -join "`n") | Out-File "$LatestDir\credentials\credential-manager-full.txt" -Encoding UTF8
        ($cmdkey | Select-String -Pattern $credPatterns -Context 0,3) | Out-File "$LatestDir\credentials\credential-manager-filtered.txt" -Encoding UTF8
    }
} catch { $script:Errors.Add("FAIL: credential manager capture - $($_.Exception.Message)") }

try {
    $taskCsv = schtasks /query /fo CSV /v 2>$null
    if ($taskCsv) {
        ($taskCsv -join "`n") | Out-File "$LatestDir\scheduled-tasks\tasks.csv" -Encoding UTF8
        $relevant = $taskCsv | Select-String -Pattern $matchRx
        if ($relevant) { ($relevant -join "`n") | Out-File "$LatestDir\scheduled-tasks\relevant-lines.txt" -Encoding UTF8 }
    }
    Get-ScheduledTask -EA SilentlyContinue | Where-Object {
        $_.TaskName -match $matchRx -or $_.TaskPath -match $matchRx
    } | ForEach-Object {
        $safe = (($_.TaskPath + $_.TaskName) -replace '[\\/:*?""<>| ]','_').Trim('_')
        try {
            Export-ScheduledTask -TaskName $_.TaskName -TaskPath $_.TaskPath -EA Stop | Out-File "$LatestDir\scheduled-tasks\$safe.xml" -Encoding UTF8
        } catch {}
    }
} catch { $script:Errors.Add("FAIL: scheduled tasks capture - $($_.Exception.Message)") }

try {
    Update-BackupProgress -Id 0 -Activity 'Codex backup' -Status 'Building manifest' -PercentComplete 82
    $manifestEntries = [System.Collections.Generic.List[hashtable]]::new()
    $payloadBytes = 0L
    $bpLen = $LatestDir.Length
    foreach ($fi in [System.IO.Directory]::EnumerateFiles($LatestDir, '*', [System.IO.SearchOption]::AllDirectories)) {
        try {
            $info = [System.IO.FileInfo]::new($fi)
            $payloadBytes += $info.Length
            $manifestEntries.Add(@{
                path = $fi.Substring($bpLen).TrimStart('\')
                size = $info.Length
                modified = $info.LastWriteTimeUtc.ToString('o')
            })
        } catch {}
    }
    @{
        version = '1.0'
        generated = (Get-Date -Format 'o')
        computer = $env:COMPUTERNAME
        fileCount = $manifestEntries.Count
        files = $manifestEntries
    } | ConvertTo-Json -Depth 5 | Out-File "$LatestDir\manifest.json" -Encoding UTF8
} catch { $script:Errors.Add("FAIL: manifest generation - $($_.Exception.Message)") }

Update-BackupProgress -Id 0 -Activity 'Codex backup' -Status 'Creating snapshot' -PercentComplete 90
Write-Host "[P3] Creating snapshot..." -ForegroundColor Cyan
Write-Host "[P3] Snapshot source: $LatestDir" -ForegroundColor DarkGray
Write-Host "[P3] Snapshot target: $BackupPath" -ForegroundColor DarkGray
if ($script:IsExFat) {
    Write-Host "[P3] exFAT detected: creating instant pointer snapshot to latest" -ForegroundColor Yellow
    try {
        Write-PointerSnapshot -SnapshotPath $BackupPath -LatestPath $LatestDir
        Write-Host "[P3] pointer snapshot created" -ForegroundColor Green
    } catch {
        $script:Errors.Add("FAIL: pointer snapshot - $($_.Exception.Message)")
        Write-Host "[P3] pointer snapshot failed" -ForegroundColor Red
    }
} elseif (Invoke-RobocopySync -Source $LatestDir -Destination $BackupPath -ExcludeDirs @()) {
    Write-Host "[P3] snapshot copy completed" -ForegroundColor Green
} else {
    $script:Errors.Add("FAIL: snapshot copy")
    Write-Host "[P3] snapshot copy failed" -ForegroundColor Yellow
}

$sw.Stop()
try {
    $meta = @{
        Version = '1.0'
        Timestamp = (Get-Date -Format 'o')
        Computer = $env:COMPUTERNAME
        User = $env:USERNAME
        LatestDir = $LatestDir
        SnapshotPath = $BackupPath
        FileSystem = $backupFsType
        PayloadBytes = $payloadBytes
        PayloadMB = [math]::Round($payloadBytes / 1MB, 2)
        PayloadGB = [math]::Round($payloadBytes / 1GB, 3)
        FileCount = $manifestEntries.Count
        DurationSeconds = [math]::Round($sw.Elapsed.TotalSeconds, 1)
        Errors = @($script:Errors)
    } | ConvertTo-Json -Depth 5
    Write-Utf8NoBom -Path "$LatestDir\BACKUP-METADATA.json" -Content $meta
    if (Test-Path $BackupPath) {
        Write-Utf8NoBom -Path "$BackupPath\BACKUP-METADATA.json" -Content $meta
    }
} catch {}

try {
    $restoreScript = Join-Path $PSScriptRoot 'restore-codex.ps1'
    if (Test-Path $restoreScript) {
        & powershell -NoProfile -ExecutionPolicy Bypass -File $restoreScript -RepairLatestBackupMap | Out-Null
        if ($script:IsExFat -and (Test-Path (Join-Path $LatestDir 'RESTORE-MAP.json')) -and (Test-Path $BackupPath)) {
            Copy-Item -LiteralPath (Join-Path $LatestDir 'RESTORE-MAP.json') -Destination (Join-Path $BackupPath 'RESTORE-MAP.json') -Force -EA SilentlyContinue
        }
    }
} catch {
    $script:Errors.Add("FAIL: restore map refresh - $($_.Exception.Message)")
}

$errCount = @($script:Errors).Count
Update-BackupProgress -Id 0 -Activity 'Codex backup' -Status 'Completed' -PercentComplete 100
Write-Progress -Id 1 -Activity 'Backing up Codex data' -Completed
Write-Progress -Id 0 -Activity 'Codex backup' -Completed
Write-Host ("=" * 80) -ForegroundColor Cyan
Write-Host "  DONE  $([math]::Round($sw.Elapsed.TotalSeconds,1))s  errors=$errCount" -ForegroundColor $(if($errCount -eq 0){'Green'}else{'Yellow'})
Write-Host "  Latest:   $LatestDir" -ForegroundColor DarkGray
Write-Host "  Snapshot: $BackupPath" -ForegroundColor DarkGray
Write-Host ("=" * 80) -ForegroundColor Cyan
