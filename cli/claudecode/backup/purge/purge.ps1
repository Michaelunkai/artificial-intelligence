# purge - Force purge F:\backup\claudecode at maximum speed
$backupPath = 'F:\backup\claudecode'

if (-not [System.IO.Directory]::Exists($backupPath)) {
    Write-Host "Path not found: $backupPath" -ForegroundColor Red; return
}

$items = [System.IO.Directory]::GetFileSystemEntries($backupPath)
if ($items.Count -eq 0) {
    Write-Host "Already empty." -ForegroundColor Green; return
}

Write-Host "Purging $($items.Count) items in parallel..." -ForegroundColor Yellow

# Max threads = logical CPU count
$threadCount = [Environment]::ProcessorCount
$pool = [runspacefactory]::CreateRunspacePool(1, $threadCount)
$pool.ApartmentState = 'MTA'
$pool.Open()

$script = {
    param($p)
    # Try .NET first (fastest), then robocopy mirror trick, then cmd force
    try {
        if ([System.IO.Directory]::Exists($p)) {
            [System.IO.Directory]::Delete($p, $true)
        } else {
            [System.IO.File]::Delete($p)
        }
        return
    } catch {}
    # robocopy /MIR against empty dir is faster than rd for deep trees
    try {
        if ([System.IO.Directory]::Exists($p)) {
            $empty = [System.IO.Path]::Combine([System.IO.Path]::GetTempPath(), [System.Guid]::NewGuid().ToString())
            [System.IO.Directory]::CreateDirectory($empty) | Out-Null
            & robocopy $empty $p /MIR /NFL /NDL /NJH /NJS /NC /NS /NP 2>$null | Out-Null
            [System.IO.Directory]::Delete($empty, $true)
            [System.IO.Directory]::Delete($p, $true)
            return
        }
    } catch {}
    # Last resort: cmd force
    if ([System.IO.Directory]::Exists($p)) {
        & cmd /c "rd /s /q `"$p`"" 2>$null
    } else {
        & cmd /c "del /f /s /q `"$p`"" 2>$null
    }
}

$jobs = foreach ($item in $items) {
    $ps = [powershell]::Create()
    $ps.RunspacePool = $pool
    [void]$ps.AddScript($script)
    [void]$ps.AddArgument($item)
    [PSCustomObject]@{ PS = $ps; Handle = $ps.BeginInvoke() }
}

foreach ($j in $jobs) {
    try { $j.PS.EndInvoke($j.Handle) } catch {}
    $j.PS.Dispose()
}
$pool.Close(); $pool.Dispose()

# Verify empty
$remaining = [System.IO.Directory]::GetFileSystemEntries($backupPath)
if ($remaining.Count -eq 0) {
    Write-Host "Done. F:\backup\claudecode is empty." -ForegroundColor Green
} else {
    Write-Host "$($remaining.Count) items remain - retrying with cmd..." -ForegroundColor Yellow
    foreach ($r in $remaining) {
        & cmd /c "rd /s /q `"$r`"" 2>$null
        & cmd /c "del /f /s /q `"$r`"" 2>$null
    }
    $final = [System.IO.Directory]::GetFileSystemEntries($backupPath)
    if ($final.Count -eq 0) {
        Write-Host "Done. F:\backup\claudecode is empty." -ForegroundColor Green
    } else {
        Write-Host "Still locked: $($final -join ', ')" -ForegroundColor Red
    }
}
