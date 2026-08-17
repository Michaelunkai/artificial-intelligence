#Requires -Version 5.1
[CmdletBinding()]
param(
    [switch]$SkipResherValidate
)

$ErrorActionPreference = 'Stop'

$HermesBackupRoot = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backups'
$CodexBackupRoot = 'F:\backup\codex'
$PrimaryProfilePath = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$MirrorProfilePath = 'C:\Users\micha\Documents\PowerShell\Microsoft.PowerShell_profile.ps1'
$ProfilePaths = @(
    $PrimaryProfilePath,
    $MirrorProfilePath,
    'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.full.ps1',
    'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.full.definitions.ps1'
)
$ScriptPaths = @(
    'F:\study\repos\ai-ml\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\backup\backup-codex.ps1',
    'F:\study\repos\ai-ml\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\backup\restore-codex.ps1',
    'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\purge-backups-fast.ps1',
    'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backher-fast.ps1',
    'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\resher-fast.ps1'
)
$RequiredFunctionNames = 'codher','backcod','rmbackher','backher','listcod','rescod','resher','testcodher'

function Write-TestLine {
    param(
        [string]$Name,
        [string]$Status,
        [string]$Message
    )
    Write-Host ("[{0:HH:mm:ss}] {1,-24} {2,-6} {3}" -f (Get-Date), $Name, $Status, $Message)
}

function Assert-True {
    param(
        [bool]$Condition,
        [string]$Message
    )
    if (-not $Condition) { throw $Message }
}

function Assert-Contains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -notmatch $Pattern) {
        throw "$Message Pattern: $Pattern"
    }
}

function Assert-NotContains {
    param(
        [string]$Text,
        [string]$Pattern,
        [string]$Message
    )
    if ($Text -match $Pattern) {
        throw "$Message Pattern: $Pattern"
    }
}

function Assert-PatternOrder {
    param(
        [string]$Text,
        [string]$FirstPattern,
        [string]$SecondPattern,
        [string]$Message
    )
    $first = [regex]::Match($Text, $FirstPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    $second = [regex]::Match($Text, $SecondPattern, [System.Text.RegularExpressions.RegexOptions]::Singleline)
    Assert-True $first.Success "$Message First pattern missing: $FirstPattern"
    Assert-True $second.Success "$Message Second pattern missing: $SecondPattern"
    Assert-True ($first.Index -lt $second.Index) "$Message First pattern must appear before second pattern."
}

function Assert-CommandBodyContains {
    param(
        [string]$Name,
        [string[]]$Patterns
    )

    $command = Get-Command $Name -CommandType Function -ErrorAction Stop
    $body = [string]$command.ScriptBlock
    foreach ($pattern in $Patterns) {
        Assert-Contains -Text $body -Pattern $pattern -Message "$Name body missing required implementation proof."
    }
}

function Get-HermesBackupState {
    $latestPath = Join-Path $HermesBackupRoot 'LATEST.txt'
    $tempPlanPaths = @(Get-ChildItem -LiteralPath ([System.IO.Path]::GetTempPath()) -Directory -Filter 'backher-plan-*' -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName)
    [pscustomobject]@{
        Count = @(Get-ChildItem -LiteralPath $HermesBackupRoot -Force -ErrorAction Stop).Count
        Latest = if (Test-Path -LiteralPath $latestPath -PathType Leaf) { (Get-Content -LiteralPath $latestPath -Raw).Trim() } else { '' }
        TempPlans = $tempPlanPaths.Count
        TempPlanPaths = $tempPlanPaths
    }
}

function Assert-HermesStateUnchanged {
    param(
        [pscustomobject]$Before,
        [string]$Label
    )
    $after = Get-HermesBackupState
    Assert-True ($after.Count -eq $Before.Count) "$Label changed Hermes backup item count: before=$($Before.Count) after=$($after.Count)"
    Assert-True ($after.Latest -eq $Before.Latest) "$Label changed Hermes LATEST.txt: before=$($Before.Latest) after=$($after.Latest)"
    $newTempPlans = @($after.TempPlanPaths | Where-Object { $Before.TempPlanPaths -notcontains $_ })
    Assert-True ($newTempPlans.Count -eq 0) "$Label left new backher-plan temp directories: $($newTempPlans -join ', ')"
}

function Assert-HermesLatestBackupReady {
    $latestPath = Join-Path $HermesBackupRoot 'LATEST.txt'
    Assert-True (Test-Path -LiteralPath $latestPath -PathType Leaf) "Hermes LATEST.txt missing: $latestPath"
    $latestId = (Get-Content -LiteralPath $latestPath -Raw).Trim()
    Assert-True (-not [string]::IsNullOrWhiteSpace($latestId)) "Hermes LATEST.txt is empty: $latestPath"
    $backupDir = Join-Path $HermesBackupRoot $latestId
    Assert-True (Test-Path -LiteralPath $backupDir -PathType Container) "Hermes latest backup directory missing: $backupDir"
    Assert-True (Test-Path -LiteralPath (Join-Path $backupDir 'manifest.json') -PathType Leaf) "Hermes latest manifest missing: $backupDir"
    Assert-True (Test-Path -LiteralPath (Join-Path $backupDir 'hermes-wsl-data.paths.txt') -PathType Leaf) "Hermes latest path list missing: $backupDir"
    $archiveCandidates = @(
        (Join-Path $backupDir 'hermes-wsl-data.tar.gz'),
        (Join-Path $backupDir 'hermes-wsl-data.tar.zst')
    )
    Assert-True (@($archiveCandidates | Where-Object { Test-Path -LiteralPath $_ -PathType Leaf }).Count -gt 0) "Hermes latest archive missing: $backupDir"
}

function Invoke-VerifierStep {
    param(
        [string]$Name,
        [scriptblock]$Script,
        [string[]]$RequiredPatterns = @(),
        [switch]$ExpectHermesStateUnchanged,
        [double]$MaxSeconds = 0
    )

    $before = if ($ExpectHermesStateUnchanged) { Get-HermesBackupState } else { $null }
    Write-TestLine $Name 'START' 'running'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = @()
    try {
        $output = @(& $Script *>&1 | ForEach-Object { [string]$_ })
        $exitCode = $global:LASTEXITCODE
        if ($null -ne $exitCode -and $exitCode -ne 0) {
            throw "$Name ended with LASTEXITCODE=$exitCode"
        }
    } catch {
        Write-TestLine $Name 'FAIL' $_.Exception.Message
        if ($output.Count) { $output | Select-Object -First 80 | ForEach-Object { Write-Host "  $_" } }
        throw
    } finally {
        $sw.Stop()
    }

    $text = ($output -join "`n")
    foreach ($pattern in $RequiredPatterns) {
        Assert-Contains -Text $text -Pattern $pattern -Message "$Name missing required proof."
    }
    if ($MaxSeconds -gt 0) {
        Assert-True ($sw.Elapsed.TotalSeconds -le $MaxSeconds) "$Name was too slow: $([math]::Round($sw.Elapsed.TotalSeconds, 3))s > ${MaxSeconds}s"
    }
    if ($ExpectHermesStateUnchanged) {
        Assert-HermesStateUnchanged -Before $before -Label $Name
    }

    Write-TestLine $Name 'PASS' ("{0:n1}s, output_lines={1}" -f $sw.Elapsed.TotalSeconds, $output.Count)
    return $text
}

function Invoke-ExpectedFailureStep {
    param(
        [string]$Name,
        [scriptblock]$Script,
        [string[]]$RequiredPatterns = @(),
        [switch]$ExpectHermesStateUnchanged
    )

    $before = if ($ExpectHermesStateUnchanged) { Get-HermesBackupState } else { $null }
    Write-TestLine $Name 'START' 'expecting controlled failure'
    $sw = [System.Diagnostics.Stopwatch]::StartNew()
    $output = @()
    $failed = $false
    try {
        $output = @(& $Script *>&1 | ForEach-Object { [string]$_ })
        $exitCode = $global:LASTEXITCODE
        if ($null -ne $exitCode -and $exitCode -ne 0) {
            $failed = $true
            $output += "LASTEXITCODE=$exitCode"
        }
    } catch {
        $failed = $true
        $output += $_.Exception.Message
    } finally {
        $sw.Stop()
    }

    Assert-True $failed "$Name unexpectedly succeeded"
    $text = ($output -join "`n")
    foreach ($pattern in $RequiredPatterns) {
        Assert-Contains -Text $text -Pattern $pattern -Message "$Name missing expected failure proof."
    }
    if ($ExpectHermesStateUnchanged) {
        Assert-HermesStateUnchanged -Before $before -Label $Name
    }
    Write-TestLine $Name 'PASS' ("controlled failure in {0:n1}s" -f $sw.Elapsed.TotalSeconds)
    return $text
}

function New-CodherVerifierTempDir {
    param([string]$Prefix)
    $path = Join-Path ([System.IO.Path]::GetTempPath()) ("$Prefix-$([System.Guid]::NewGuid().ToString('N'))")
    [void](New-Item -ItemType Directory -Path $path -Force)
    return $path
}

function New-MinimalHermesBackupFixture {
    param(
        [string]$Root,
        [string]$BackupId = '20260101-000000',
        [switch]$EmptyArchive,
        [switch]$SkipPathList,
        [string[]]$PathEntries,
        [Nullable[int64]]$ManifestArchiveBytes
    )
    $backupDir = Join-Path $Root $BackupId
    [void](New-Item -ItemType Directory -Path $backupDir -Force)
    $BackupId | Set-Content -LiteralPath (Join-Path $Root 'LATEST.txt') -Encoding ASCII
    $archivePath = Join-Path $backupDir 'hermes-wsl-data.tar.zst'
    if ($EmptyArchive) {
        [System.IO.File]::WriteAllBytes($archivePath, [byte[]]@())
    } else {
        [System.IO.File]::WriteAllBytes($archivePath, [byte[]](1,2,3,4))
    }
    if (-not $SkipPathList) {
        if (-not $PathEntries) {
            $PathEntries = @(
                'home/ubuntu/.hermes',
                'home/ubuntu/.hermes-mmmoltbot_bot',
                'home/ubuntu/.hermes-mmichael_moltbot_bot',
                'home/ubuntu/.hermes-michaopenclawbot',
                'home/ubuntu/.hermes-michahermes5bot',
                'home/ubuntu/.codex',
                'home/ubuntu/.local/state/hermes'
            )
        }
        $PathEntries | Set-Content -LiteralPath (Join-Path $backupDir 'hermes-wsl-data.paths.txt') -Encoding ASCII
    }
    if ($null -ne $ManifestArchiveBytes) {
        @{
            archive = 'hermes-wsl-data.tar.zst'
            archive_bytes = [int64]$ManifestArchiveBytes
        } | ConvertTo-Json | Set-Content -LiteralPath (Join-Path $backupDir 'manifest.json') -Encoding ASCII
    }
    return $backupDir
}

Write-TestLine 'environment' 'START' 'checking Windows PowerShell 5 runtime'
Assert-True ($PSVersionTable.PSVersion.Major -eq 5) "testcodher must run under Windows PowerShell 5. Current: $($PSVersionTable.PSVersion)"
Assert-True ($PROFILE -eq $PrimaryProfilePath) "Unexpected active PS5 profile. Expected=$PrimaryProfilePath Actual=$PROFILE"
Assert-True (Test-Path -LiteralPath $HermesBackupRoot -PathType Container) "Hermes backup root missing: $HermesBackupRoot"
Assert-True (Test-Path -LiteralPath $CodexBackupRoot -PathType Container) "Codex backup root missing: $CodexBackupRoot"
Assert-True (Test-Path -LiteralPath $PrimaryProfilePath -PathType Leaf) "Primary profile missing: $PrimaryProfilePath"
Assert-True (Test-Path -LiteralPath $MirrorProfilePath -PathType Leaf) "Mirror profile missing: $MirrorProfilePath"
$primaryHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $PrimaryProfilePath).Hash
$mirrorHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $MirrorProfilePath).Hash
Assert-True ($primaryHash -eq $mirrorHash) "Primary and mirror profile hashes differ: $primaryHash vs $mirrorHash"
Write-TestLine 'environment' 'PASS' "profile=$PROFILE"

Write-TestLine 'parse' 'START' 'checking script syntax'
foreach ($path in ($ScriptPaths + $ProfilePaths)) {
    Assert-True (Test-Path -LiteralPath $path -PathType Leaf) "Required script missing: $path"
    $tokens = $null
    $errors = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
    Assert-True ($errors.Count -eq 0) "Parse failed for $path`: $($errors[0].Message)"
}
Write-TestLine 'parse' 'PASS' ("scripts={0} profiles={1}" -f $ScriptPaths.Count, $ProfilePaths.Count)

Write-TestLine 'safety-order' 'START' 'checking Hermes prune ordering'
$backherText = Get-Content -LiteralPath 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backher-fast.ps1' -Raw
$resherText = Get-Content -LiteralPath 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\resher-fast.ps1' -Raw
$restoreCodexText = Get-Content -LiteralPath 'F:\study\repos\ai-ml\AI_and_Machine_Learning\Artificial_Intelligence\cli\codex\backup\restore-codex.ps1' -Raw
Assert-Contains -Text $backherText -Pattern 'Remove-PreviousHermesBackups -Root \$BackupRoot -PreserveBackupId \$stamp' -Message 'backher-fast must preserve the freshly validated backup when pruning old backups.'
Assert-Contains -Text $backherText -Pattern 'PROGRESS backher-prune: preserving_current_backup=' -Message 'backher-fast must emit pruning preservation progress.'
Assert-NotContains -Text $backherText -Pattern 'if \(-not \$PlanOnly -and -not \$KeepPreviousBackup\)\s*\{\s*Remove-PreviousHermesBackups -Root \$BackupRoot\s*\}\s*\$stamp = Get-Date' -Message 'backher-fast must not prune all backups before creating the next backup.'
Assert-Contains -Text $resherText -Pattern '== full restore path list ==' -Message 'resher-fast plan mode must expose the restore path list.'
Assert-Contains -Text $resherText -Pattern '\(-not \$PlanOnly\) -and \$manifest\.archive_sha256' -Message 'resher-fast plan mode must not hash the full archive.'
Assert-Contains -Text $resherText -Pattern "reading saved restore path list" -Message 'resher-fast plan mode must use the saved path list directly.'
Assert-PatternOrder -Text $restoreCodexText -FirstPattern 'if \(\$DryRun\)\s*\{' -SecondPattern '(?m)^Ensure-Prerequisites\s*$' -Message 'restore-codex dry-run must be side-effect-free and skip prerequisite installation.'
Assert-Contains -Text $restoreCodexText -Pattern 'Dry-run planning' -Message 'restore-codex dry-run must emit visible progress.'
Assert-Contains -Text $restoreCodexText -Pattern 'Test-RestoreSourceCoverage' -Message 'restore-codex must validate restore sources before claiming a plan.'
Assert-Contains -Text $restoreCodexText -Pattern 'Critical restore source missing' -Message 'restore-codex must fail when critical backup payloads are missing.'
Write-TestLine 'safety-order' 'PASS' 'new backup is preserved before old backups are pruned'

Write-TestLine 'functions' 'START' 'checking command resolution'
foreach ($name in $RequiredFunctionNames) {
    [void](Get-Command $name -CommandType Function -ErrorAction Stop)
}
Assert-CommandBodyContains -Name 'codher' -Patterns @('param\(\[switch\]\$PlanOnly\)', 'backcod -DryRun', 'rmbackher -PlanOnly', 'listcod')
Assert-CommandBodyContains -Name 'backcod' -Patterns @('backup-codex\.ps1', '-Force @args')
Assert-CommandBodyContains -Name 'rmbackher' -Patterns @('purge-backups-fast\.ps1', 'if \(\$PlanOnly\)', '& \$purgeScript -PlanOnly', 'backher -PlanOnly')
$rmbackherBody = [string](Get-Command 'rmbackher' -CommandType Function -ErrorAction Stop).ScriptBlock
Assert-NotContains -Text $rmbackherBody -Pattern '& \$purgeScript -PlanOnly:\$PlanOnly' -Message 'rmbackher must not invoke the purge script before a full backup.'
Assert-CommandBodyContains -Name 'backher' -Patterns @('backher-fast\.ps1', '-PlanOnly:\$PlanOnly')
Assert-CommandBodyContains -Name 'listcod' -Patterns @('F:\\backup\\codex', 'metadata-unavailable', 'BACKUP-POINTER\.json')
Assert-CommandBodyContains -Name 'rescod' -Patterns @('restore-codex\.ps1', '-Force @args')
$listcodBody = [string](Get-Command 'listcod' -CommandType Function -ErrorAction Stop).ScriptBlock
$rescodBody = [string](Get-Command 'rescod' -CommandType Function -ErrorAction Stop).ScriptBlock
Assert-NotContains -Text $listcodBody -Pattern 'Load-FullPowerShellProfile' -Message 'listcod must stay lightweight and must not load the full profile.'
Assert-NotContains -Text $rescodBody -Pattern 'Load-FullPowerShellProfile' -Message 'rescod must stay lightweight and must not load the full profile.'
Assert-CommandBodyContains -Name 'resher' -Patterns @('resher-fast\.ps1', '-ValidateOnly:\$ValidateOnly', '-PlanOnly:\$PlanOnly')
Assert-CommandBodyContains -Name 'testcodher' -Patterns @('test-codher-backup-restore\.ps1', 'VerifierArgs')
Write-TestLine 'functions' 'PASS' ("all {0} functions resolved and body-checked" -f $RequiredFunctionNames.Count)

[void](Invoke-VerifierStep -Name 'backcod -DryRun' -ExpectHermesStateUnchanged -RequiredPatterns @(
    '\[DRY-RUN\]\s+\d+\s+tasks discovered',
    'CODEX BACKUP'
) -Script { backcod -DryRun })

[void](Invoke-VerifierStep -Name 'rmbackher -PlanOnly' -ExpectHermesStateUnchanged -RequiredPatterns @(
    'PLANONLY_PURGE_BACKUPS_PATH=',
    'PLANONLY_PURGE_TOP_LEVEL_ITEMS=',
    'PLANONLY_BACKHER_NO_BACKUP_WRITTEN='
) -Script { rmbackher -PlanOnly })

[void](Invoke-VerifierStep -Name 'backher -PlanOnly' -ExpectHermesStateUnchanged -RequiredPatterns @(
    'PLANONLY_BACKHER_BACKUP_ROOT=',
    'PLANONLY_BACKHER_SKIP_WINDOWS_TOOL_COPY=1',
    'PROGRESS backher-wsl-archive: starting',
    'PROGRESS backher-wsl-archive: finished',
    'PLANONLY_BACKHER_NO_BACKUP_WRITTEN='
) -Script { backher -PlanOnly })

[void](Invoke-ExpectedFailureStep -Name 'backher plan failure cleanup' -ExpectHermesStateUnchanged -Script {
    backher -PlanOnly -NoRestartGateway -Distro '__codher_missing_distro_for_cleanup_test__'
})

[void](Invoke-ExpectedFailureStep -Name 'purge guard bad path' -ExpectHermesStateUnchanged -RequiredPatterns @(
    'Refusing to purge unexpected path'
) -Script {
    & 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\purge-backups-fast.ps1' -BackupsPath (Join-Path ([System.IO.Path]::GetTempPath()) 'codher-purge-refusal-test') -PlanOnly
})

[void](Invoke-VerifierStep -Name 'listcod' -RequiredPatterns @(
    'F:\\backup\\codex',
    '\[DIR\]\s+latest'
) -MaxSeconds 5 -Script { listcod })

[void](Invoke-VerifierStep -Name 'codher -PlanOnly' -ExpectHermesStateUnchanged -RequiredPatterns @(
    '\[DRY-RUN\]\s+\d+\s+tasks discovered',
    'PLANONLY_PURGE_BACKUPS_PATH=',
    'PLANONLY_BACKHER_NO_BACKUP_WRITTEN=',
    'F:\\backup\\codex'
) -Script { codher -PlanOnly })

[void](Invoke-VerifierStep -Name 'rescod -DryRun' -ExpectHermesStateUnchanged -RequiredPatterns @(
    'CODEX RESTORE',
    'Sources: available=',
    'Dry run only\. Planned restore entries:\s+\d+'
) -MaxSeconds 15 -Script { rescod -DryRun })

[void](Invoke-ExpectedFailureStep -Name 'rescod empty backup path' -ExpectHermesStateUnchanged -RequiredPatterns @(
    'Critical restore source missing'
) -Script {
    $temp = New-CodherVerifierTempDir -Prefix 'codher-empty-codex-backup'
    try {
        rescod -BackupPath $temp -DryRun
    } finally {
        Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
    }
})

if ($SkipResherValidate) {
    Write-TestLine 'resher -ValidateOnly' 'SKIP' 'SkipResherValidate was set'
} else {
    [void](Invoke-VerifierStep -Name 'resher -PlanOnly' -ExpectHermesStateUnchanged -RequiredPatterns @(
        'PROGRESS resher-wsl-restore: starting',
        'PROGRESS resher-wsl-restore: finished'
    ) -MaxSeconds 5 -Script { resher -PlanOnly -NoTelegramProbe })

    [void](Invoke-ExpectedFailureStep -Name 'resher bad BackupId' -ExpectHermesStateUnchanged -RequiredPatterns @(
        'Refusing unsafe Hermes backup id'
    ) -Script { resher -BackupId '..\escape' -ValidateOnly -NoTelegramProbe })

    [void](Invoke-ExpectedFailureStep -Name 'resher missing latest' -ExpectHermesStateUnchanged -RequiredPatterns @(
        'LATEST\.txt not found under'
    ) -Script {
        $temp = New-CodherVerifierTempDir -Prefix 'codher-hermes-missing-latest'
        try {
            resher -BackupRoot $temp -PlanOnly -NoTelegramProbe
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    })

    [void](Invoke-ExpectedFailureStep -Name 'resher empty archive' -ExpectHermesStateUnchanged -RequiredPatterns @(
        'Hermes data archive is empty'
    ) -Script {
        $temp = New-CodherVerifierTempDir -Prefix 'codher-hermes-empty-archive'
        try {
            [void](New-MinimalHermesBackupFixture -Root $temp -EmptyArchive)
            resher -BackupRoot $temp -BackupId '20260101-000000' -PlanOnly -NoTelegramProbe
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    })

    [void](Invoke-ExpectedFailureStep -Name 'resher missing path list' -ExpectHermesStateUnchanged -RequiredPatterns @(
        'Missing Hermes data path list'
    ) -Script {
        $temp = New-CodherVerifierTempDir -Prefix 'codher-hermes-missing-pathlist'
        try {
            [void](New-MinimalHermesBackupFixture -Root $temp -SkipPathList)
            resher -BackupRoot $temp -BackupId '20260101-000000' -PlanOnly -NoTelegramProbe
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    })

    [void](Invoke-ExpectedFailureStep -Name 'resher byte mismatch' -ExpectHermesStateUnchanged -RequiredPatterns @(
        'Hermes data archive byte size mismatch'
    ) -Script {
        $temp = New-CodherVerifierTempDir -Prefix 'codher-hermes-byte-mismatch'
        try {
            [void](New-MinimalHermesBackupFixture -Root $temp -ManifestArchiveBytes 999)
            resher -BackupRoot $temp -BackupId '20260101-000000' -PlanOnly -NoTelegramProbe
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    })

    [void](Invoke-ExpectedFailureStep -Name 'resher required path missing' -ExpectHermesStateUnchanged -RequiredPatterns @(
        'Backup path list is missing required Hermes restore path'
    ) -Script {
        $temp = New-CodherVerifierTempDir -Prefix 'codher-hermes-required-path-missing'
        try {
            [void](New-MinimalHermesBackupFixture -Root $temp -PathEntries @('home/ubuntu/.hermes'))
            resher -BackupRoot $temp -BackupId '20260101-000000' -PlanOnly -NoTelegramProbe
        } finally {
            Remove-Item -LiteralPath $temp -Recurse -Force -ErrorAction SilentlyContinue
        }
    })

    [void](Invoke-VerifierStep -Name 'resher -ValidateOnly' -ExpectHermesStateUnchanged -RequiredPatterns @(
        'PROGRESS resher-wsl-restore: starting',
        'PROGRESS resher-wsl-restore: finished'
    ) -Script { resher -ValidateOnly -NoTelegramProbe })
    Assert-HermesLatestBackupReady
}

$finalState = Get-HermesBackupState
Write-Host ("TESTCODHER_RESULT=PASS functions={0} profile_hash_match=true hermes_backup_count={1} hermes_latest={2}" -f $RequiredFunctionNames.Count, $finalState.Count, $finalState.Latest)
