#Requires -Version 5.1
<#
.SYNOPSIS
    Backup Cleanup Utility for F:\backup\claudecode\

.PARAMETER DryRun
    Show what would be deleted without actually deleting.

.PARAMETER Confirm
    Ask for confirmation before each deletion.

.PARAMETER Force
    Delete all matching criteria without asking.

.PARAMETER KeepDays
    Keep backups newer than this many days. Default: 30

.PARAMETER KeepMin
    Minimum number of backups to always keep. Default: 5

.PARAMETER BackupRoot
    Root backup directory. Default: F:\backup\claudecode

.EXAMPLE
    .\cleanup-backups.ps1 -DryRun
    .\cleanup-backups.ps1 -Confirm -KeepDays 14 -KeepMin 3
    .\cleanup-backups.ps1 -Force -KeepDays 7
#>
param(
    [switch]$DryRun,
    [switch]$Confirm,
    [switch]$Force,
    [int]$KeepDays = 30,
    [int]$KeepMin = 5,
    [string]$BackupRoot = "F:\backup\claudecode"
)

# Validate mode
if (-not ($DryRun -or $Confirm -or $Force)) {
    Write-Host "❌ Specify one of: -DryRun, -Confirm, or -Force" -ForegroundColor Red
    exit 1
}

$ErrorActionPreference = "SilentlyContinue"
$totalFreed = 0
$deletedCount = 0
$keptCount = 0
$report = @()

function Format-Size($bytes) {
    if ($bytes -gt 1GB) { return "{0:N2} GB" -f ($bytes / 1GB) }
    if ($bytes -gt 1MB) { return "{0:N2} MB" -f ($bytes / 1MB) }
    if ($bytes -gt 1KB) { return "{0:N2} KB" -f ($bytes / 1KB) }
    return "$bytes B"
}

function Get-DirSize($path) {
    (Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
}

# ── Scan ──────────────────────────────────────────────────────────────────────
Write-Host "`n📦 Claude Code Backup Cleanup Utility" -ForegroundColor Cyan
Write-Host "   Root: $BackupRoot"
Write-Host "   Keep: last $KeepDays days, minimum $KeepMin backups"
Write-Host "   Mode: $(if($DryRun){'DRY RUN'}elseif($Confirm){'CONFIRM'}else{'FORCE'})`n" -ForegroundColor Yellow

if (-not (Test-Path $BackupRoot)) {
    Write-Host "❌ Backup root not found: $BackupRoot" -ForegroundColor Red
    exit 1
}

# Gather backup entries (subdirs + zip files)
$entries = @()
$entries += Get-ChildItem $BackupRoot -Directory | Select-Object FullName, Name, LastWriteTime,
    @{N='Size';E={ Get-DirSize $_.FullName }},
    @{N='Type';E={'dir'}},
    @{N='IsComplete';E={ Test-Path (Join-Path $_.FullName 'backup-metadata.json') -or (Get-ChildItem $_.FullName -Recurse -File).Count -gt 0 }}

$entries += Get-ChildItem $BackupRoot -Filter "*.zip" | Select-Object FullName, Name, LastWriteTime,
    @{N='Size';E={ $_.Length }},
    @{N='Type';E={'zip'}},
    @{N='IsComplete';E={ $_.Length -gt 1KB }}

$entries = $entries | Sort-Object LastWriteTime -Descending

$totalSize = ($entries | Measure-Object Size -Sum).Sum

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  INVENTORY" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host ("  {0,-45} {1,8}  {2}" -f "Name", "Size", "Date")
Write-Host "  " + ("─" * 65)

foreach ($e in $entries) {
    $age = (New-TimeSpan -Start $e.LastWriteTime -End (Get-Date)).Days
    $status = if (-not $e.IsComplete) { "⚠ INCOMPLETE" } elseif ($age -gt $KeepDays) { "OLD" } else { "OK" }
    $color = switch ($status) { "OK" { "Green" } "OLD" { "Yellow" } default { "Red" } }
    Write-Host ("  {0,-45} {1,8}  {2}  [{3}]" -f $e.Name, (Format-Size $e.Size), $e.LastWriteTime.ToString("yyyy-MM-dd"), $status) -ForegroundColor $color
}

Write-Host "`n  Total storage used: $(Format-Size $totalSize) across $($entries.Count) backups`n"

# ── Classify ──────────────────────────────────────────────────────────────────
$cutoff = (Get-Date).AddDays(-$KeepDays)
$incomplete = $entries | Where-Object { -not $_.IsComplete }
$old = $entries | Where-Object { $_.IsComplete -and $_.LastWriteTime -lt $cutoff }

# Enforce KeepMin: never delete if it would leave fewer than KeepMin complete backups
$completeEntries = $entries | Where-Object { $_.IsComplete } | Sort-Object LastWriteTime -Descending
$safeToDelete = if ($completeEntries.Count -gt $KeepMin) {
    $old | Where-Object { $completeEntries.IndexOf($_) -ge $KeepMin }
} else { @() }

$toDelete = @($incomplete) + @($safeToDelete) | Sort-Object Size -Descending | Select-Object -Unique

Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  CLEANUP PLAN" -ForegroundColor White
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor DarkGray

if ($toDelete.Count -eq 0) {
    Write-Host "  ✅ Nothing to clean up!" -ForegroundColor Green
} else {
    $potentialSavings = ($toDelete | Measure-Object Size -Sum).Sum
    Write-Host "  Would delete $($toDelete.Count) backup(s), freeing $(Format-Size $potentialSavings)`n"
    foreach ($d in $toDelete) {
        $reason = if (-not $d.IsComplete) { "incomplete" } else { "older than $KeepDays days" }
        Write-Host ("  🗑  {0}  [{1}]  {2}" -f $d.Name, $reason, (Format-Size $d.Size)) -ForegroundColor Yellow
    }
}

# ── Execute ───────────────────────────────────────────────────────────────────
if (-not $DryRun -and $toDelete.Count -gt 0) {
    Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
    Write-Host "  DELETING" -ForegroundColor Red
    Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor DarkGray

    foreach ($item in $toDelete) {
        $doDelete = $false
        if ($Force) { $doDelete = $true }
        elseif ($Confirm) {
            $ans = Read-Host "  Delete '$($item.Name)' ($(Format-Size $item.Size))? [y/N]"
            $doDelete = $ans -match '^[Yy]'
        }

        if ($doDelete) {
            try {
                if ($item.Type -eq 'dir') {
                    Remove-Item $item.FullName -Recurse -Force -ErrorAction Stop
                } else {
                    Remove-Item $item.FullName -Force -ErrorAction Stop
                }
                $totalFreed += $item.Size
                $deletedCount++
                Write-Host "  ✅ Deleted: $($item.Name)" -ForegroundColor Green
                $report += [PSCustomObject]@{ Action="DELETED"; Name=$item.Name; Size=$item.Size; Reason="cleanup" }
            } catch {
                Write-Host "  ❌ Failed: $($item.Name) — $_" -ForegroundColor Red
                $report += [PSCustomObject]@{ Action="ERROR"; Name=$item.Name; Size=$item.Size; Reason=$_ }
            }
        } else {
            $keptCount++
            $report += [PSCustomObject]@{ Action="SKIPPED"; Name=$item.Name; Size=$item.Size; Reason="user skipped" }
        }
    }
}

# ── Final Report ──────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
if ($DryRun) {
    Write-Host "  [DRY RUN] No files were modified." -ForegroundColor Yellow
    Write-Host "  Would free: $(Format-Size (($toDelete | Measure-Object Size -Sum).Sum)) from $($toDelete.Count) backup(s)"
} else {
    Write-Host "  Deleted : $deletedCount backup(s)  |  Freed: $(Format-Size $totalFreed)"
    Write-Host "  Kept    : $($entries.Count - $deletedCount) backup(s)"
}
Write-Host ""
