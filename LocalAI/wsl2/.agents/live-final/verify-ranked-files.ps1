param(
    [Parameter(Mandatory = $true)]
    [string]$TerminalPath,

    [int]$ExpectedCount = 100
)

$ErrorActionPreference = 'Stop'
$ansi = [regex]::new(
    [string][char]27 + '\[[0-9;?]*[ -/]*[@-~]',
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)
$rankPattern = [regex]::new(
    '^\s*(\d+)\.\s+.+?\s+\(([\d,]+) bytes\)\s+\|\s+(.+?)\s*$',
    [System.Text.RegularExpressions.RegexOptions]::Compiled
)
$text = [System.IO.File]::ReadAllText($TerminalPath)
$rows = New-Object 'System.Collections.Generic.List[object]'
foreach ($fragment in ($text -split "[`r`n]+")) {
    $clean = $ansi.Replace($fragment, '')
    $match = $rankPattern.Match($clean)
    if (-not $match.Success) {
        continue
    }
    $rows.Add([PSCustomObject]@{
        Rank = [int]$match.Groups[1].Value
        ReportedBytes = [long]($match.Groups[2].Value -replace ',', '')
        Path = $match.Groups[3].Value.Trim()
    })
}

if ($rows.Count -ne $ExpectedCount) {
    throw "Expected $ExpectedCount ranked rows, found $($rows.Count)."
}

$expectedRanks = 1..$ExpectedCount
for ($index = 0; $index -lt $rows.Count; $index++) {
    if ($rows[$index].Rank -ne $expectedRanks[$index]) {
        throw "Rank sequence failed at row $($index + 1)."
    }
    if (
        $index -gt 0 -and
        $rows[$index - 1].ReportedBytes -lt $rows[$index].ReportedBytes
    ) {
        throw "Byte ordering failed between ranks $index and $($index + 1)."
    }
}

$missing = New-Object 'System.Collections.Generic.List[string]'
$sizeChanges = New-Object 'System.Collections.Generic.List[string]'
foreach ($row in $rows) {
    try {
        $item = Get-Item -LiteralPath $row.Path -Force -ErrorAction Stop
        if ([long]$item.Length -ne $row.ReportedBytes) {
            $message = (
                "Rank $($row.Rank): reported $($row.ReportedBytes), " +
                "current $($item.Length): $($row.Path)"
            )
            $sizeChanges.Add($message)
        }
    }
    catch {
        $missing.Add("Rank $($row.Rank): unreadable now: $($row.Path)")
    }
}

if ($missing.Count) {
    $missing | ForEach-Object { Write-Output $_ }
    throw "$($missing.Count) ranked paths are no longer readable."
}

[PSCustomObject]@{
    VerifiedRows = $rows.Count
    ExactRanks = $true
    DescendingBytes = $true
    ExistingPaths = $rows.Count - $missing.Count
    CurrentSizesStillMatch = $rows.Count - $sizeChanges.Count
    PostScanSizeChanges = @($sizeChanges)
    LargestPath = $rows[0].Path
    LargestBytes = $rows[0].ReportedBytes
    SmallestPath = $rows[$rows.Count - 1].Path
    SmallestBytes = $rows[$rows.Count - 1].ReportedBytes
} | ConvertTo-Json
