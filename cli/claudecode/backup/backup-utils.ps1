#Requires -Version 5.0
<#
.SYNOPSIS
Browser backup utilities - inspection, verification, comparison

.DESCRIPTION
Helper functions for:
- List backups
- Inspect backup contents
- Compare backups
- Calculate backup sizes
- Clean old backups
- Verify integrity

.EXAMPLE
.\backup-utils.ps1 -Action ListBackups
.\backup-utils.ps1 -Action InspectBackup -BackupPath "browser-backup-20240101-120000"
.\backup-utils.ps1 -Action CompareBackups -BackupPath1 "backup1" -BackupPath2 "backup2"
#>

param(
    [Parameter(Mandatory=$true)]
    [ValidateSet("ListBackups", "InspectBackup", "CompareBackups", "CalculateSize", "CleanOldBackups", "VerifyIntegrity")]
    [string]$Action,
    
    [string]$BackupPath,
    [string]$BackupPath1,
    [string]$BackupPath2,
    [int]$DaysOld = 30,
    [switch]$Force
)

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -lt 1KB) { return "$Bytes B" }
    if ($Bytes -lt 1MB) { return ([math]::Round($Bytes / 1KB, 2)).ToString() + " KB" }
    if ($Bytes -lt 1GB) { return ([math]::Round($Bytes / 1MB, 2)).ToString() + " MB" }
    return ([math]::Round($Bytes / 1GB, 2)).ToString() + " GB"
}

function Get-BackupMetadata {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        Write-Host "ERROR: Backup not found: $Path"
        return $null
    }
    
    $manifest = Join-Path $Path "BACKUP-MANIFEST.txt"
    if (Test-Path $manifest) {
        $content = Get-Content $manifest
        Write-Host $content
    }
    
    return $Path
}

function Get-BrowserDataSize {
    param([string]$Path, [string]$Browser)
    
    $browserPath = Join-Path $Path $Browser
    if (-not (Test-Path $browserPath)) {
        return 0
    }
    
    return (Get-ChildItem -Path $browserPath -Recurse -ErrorAction SilentlyContinue | 
            Measure-Object -Property Length -Sum).Sum
}

# ============================================================================
# ACTION: List Backups
# ============================================================================

function ListBackups {
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    
    Write-Host "`n📦 Browser Data Backups`n"
    Write-Host "Location: $scriptDir`n"
    
    $backups = Get-ChildItem -Path $scriptDir -Directory -Filter "browser-backup-*" | 
               Sort-Object -Property Name -Descending
    
    if ($backups.Count -eq 0) {
        Write-Host "No backups found."
        return
    }
    
    $backups | ForEach-Object {
        $manifest = Join-Path $_.FullName "BACKUP-MANIFEST.txt"
        $size = (Get-ChildItem -Path $_.FullName -Recurse | 
                 Measure-Object -Property Length -Sum).Sum
        
        $date = $_.LastWriteTime
        $sizeFormatted = Format-Bytes $size
        
        Write-Host "📅 $($_.Name)"
        Write-Host "   Created: $date"
        Write-Host "   Size: $sizeFormatted"
        
        # Show browsers in backup
        $browsers = Get-ChildItem -Path $_.FullName -Directory -ErrorAction SilentlyContinue | 
                    Where-Object { $_.Name -notin @("BACKUP-MANIFEST.txt", "backup-log.txt") } | 
                    Select-Object -ExpandProperty Name
        
        if ($browsers) {
            Write-Host "   Browsers: $($browsers -join ', ')"
        }
        
        Write-Host ""
    }
}

# ============================================================================
# ACTION: Inspect Backup
# ============================================================================

function InspectBackup {
    param([string]$Path)
    
    if (-not $Path) {
        Write-Host "ERROR: -BackupPath is required for InspectBackup action"
        return
    }
    
    Get-BackupMetadata -Path $Path
    
    Write-Host "`n" 
    Write-Host "📊 Backup Contents`n"
    
    $browsers = @("Chrome", "Edge", "Firefox", "Brave")
    
    foreach ($browser in $browsers) {
        $browserSize = Get-BrowserDataSize -Path $Path -Browser $browser
        if ($browserSize -gt 0) {
            $formatted = Format-Bytes $browserSize
            Write-Host "  $browser : $formatted"
            
            # Show data types
            $browserPath = Join-Path $Path $browser
            $dataTypes = Get-ChildItem -Path $browserPath -Directory | Select-Object -ExpandProperty Name
            Write-Host "    Contents: $($dataTypes -join ', ')"
        }
    }
    
    # Total size
    $totalSize = (Get-ChildItem -Path $Path -Recurse | 
                  Measure-Object -Property Length -Sum).Sum
    Write-Host "`n  Total: $(Format-Bytes $totalSize)`n"
    
    # Check for optional data
    Write-Host "📋 Optional Data:"
    $manifestPath = Join-Path $Path "BACKUP-MANIFEST.txt"
    if (Test-Path $manifestPath) {
        $manifest = Get-Content $manifestPath
        $hasHistory = $manifest -match "History:\s+True"
        $hasCookies = $manifest -match "Cookies:\s+True"
        
        Write-Host "  History: $(if ($hasHistory) { '✓ Yes' } else { '✗ No' })"
        Write-Host "  Cookies: $(if ($hasCookies) { '⚠️  Yes (SENSITIVE)' } else { '✗ No' })"
    }
}

# ============================================================================
# ACTION: Compare Backups
# ============================================================================

function CompareBackups {
    param([string]$Path1, [string]$Path2)
    
    if (-not $Path1 -or -not $Path2) {
        Write-Host "ERROR: Both -BackupPath1 and -BackupPath2 are required"
        return
    }
    
    if (-not (Test-Path $Path1)) { Write-Host "ERROR: Backup 1 not found"; return }
    if (-not (Test-Path $Path2)) { Write-Host "ERROR: Backup 2 not found"; return }
    
    Write-Host "`n📊 Backup Comparison`n"
    Write-Host "Backup 1: $(Split-Path -Leaf $Path1)"
    Write-Host "Backup 2: $(Split-Path -Leaf $Path2)`n"
    
    $browsers = @("Chrome", "Edge", "Firefox", "Brave")
    
    Write-Host "Size Comparison:"
    Write-Host "-" * 60
    
    foreach ($browser in $browsers) {
        $size1 = Get-BrowserDataSize -Path $Path1 -Browser $browser
        $size2 = Get-BrowserDataSize -Path $Path2 -Browser $browser
        
        if ($size1 -gt 0 -or $size2 -gt 0) {
            $f1 = Format-Bytes $size1
            $f2 = Format-Bytes $size2
            
            $diff = $size2 - $size1
            $diffStr = if ($diff -gt 0) { "+$(Format-Bytes $diff)" } 
                       elseif ($diff -lt 0) { "-$(Format-Bytes [math]::Abs($diff))" }
                       else { "Same" }
            
            Write-Host "$browser".PadRight(15) " : $f1".PadRight(25) " → $f2".PadRight(15) " ($diffStr)"
        }
    }
    
    $total1 = (Get-ChildItem -Path $Path1 -Recurse | 
               Measure-Object -Property Length -Sum).Sum
    $total2 = (Get-ChildItem -Path $Path2 -Recurse | 
               Measure-Object -Property Length -Sum).Sum
    
    Write-Host "-" * 60
    Write-Host "Total".PadRight(15) " : $(Format-Bytes $total1)".PadRight(25) " → $(Format-Bytes $total2)"
    
    $totalDiff = $total2 - $total1
    if ($totalDiff -ne 0) {
        $totalDiffStr = if ($totalDiff -gt 0) { "+$(Format-Bytes $totalDiff)" } 
                        else { "-$(Format-Bytes [math]::Abs($totalDiff))" }
        Write-Host "Difference: $totalDiffStr`n"
    }
}

# ============================================================================
# ACTION: Calculate Size
# ============================================================================

function CalculateSize {
    param([string]$Path)
    
    if (-not $Path) {
        Write-Host "ERROR: -BackupPath is required for CalculateSize action"
        return
    }
    
    if (-not (Test-Path $Path)) {
        Write-Host "ERROR: Backup not found: $Path"
        return
    }
    
    Write-Host "`n📊 Backup Size Analysis`n"
    Write-Host "Path: $Path`n"
    
    $browsers = @("Chrome", "Edge", "Firefox", "Brave")
    $breakdown = @()
    
    foreach ($browser in $browsers) {
        $size = Get-BrowserDataSize -Path $Path -Browser $browser
        if ($size -gt 0) {
            $breakdown += @{ Browser = $browser; Size = $size }
        }
    }
    
    # Sort by size descending
    $breakdown = $breakdown | Sort-Object -Property Size -Descending
    
    $total = ($breakdown | Measure-Object -Property Size -Sum).Sum
    
    foreach ($item in $breakdown) {
        $percent = [math]::Round(($item.Size / $total) * 100, 1)
        $bar = "█" * [math]::Floor($percent / 5)
        Write-Host "$($item.Browser -PadRight(15)) : $(Format-Bytes $item.Size).PadRight(15) $percent% $bar"
    }
    
    Write-Host "`nTotal: $(Format-Bytes $total)`n"
}

# ============================================================================
# ACTION: Clean Old Backups
# ============================================================================

function CleanOldBackups {
    param([int]$Days, [switch]$Force)
    
    $scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
    $cutoffDate = (Get-Date).AddDays(-$Days)
    
    Write-Host "`n🗑️  Cleaning Backups Older Than $Days Days`n"
    
    $oldBackups = Get-ChildItem -Path $scriptDir -Directory -Filter "browser-backup-*" |
                  Where-Object { $_.LastWriteTime -lt $cutoffDate }
    
    if ($oldBackups.Count -eq 0) {
        Write-Host "No backups older than $Days days found."
        return
    }
    
    Write-Host "Found $($oldBackups.Count) backup(s) to delete:`n"
    
    $totalSize = 0
    foreach ($backup in $oldBackups) {
        $size = (Get-ChildItem -Path $backup.FullName -Recurse | 
                 Measure-Object -Property Length -Sum).Sum
        $totalSize += $size
        Write-Host "  - $($backup.Name) ($(Format-Bytes $size))"
    }
    
    Write-Host "`nTotal space to free: $(Format-Bytes $totalSize)`n"
    
    if (-not $Force) {
        $response = Read-Host "Delete these backups? (yes/no)"
        if ($response -ne "yes") {
            Write-Host "Cancelled."
            return
        }
    }
    
    foreach ($backup in $oldBackups) {
        try {
            Remove-Item -Path $backup.FullName -Recurse -Force
            Write-Host "✓ Deleted: $($backup.Name)"
        }
        catch {
            Write-Host "✗ Failed to delete: $($backup.Name) - $_"
        }
    }
    
    Write-Host "`nCleanup complete. Freed $(Format-Bytes $totalSize)`n"
}

# ============================================================================
# ACTION: Verify Integrity
# ============================================================================

function VerifyIntegrity {
    param([string]$Path)
    
    if (-not $Path) {
        Write-Host "ERROR: -BackupPath is required for VerifyIntegrity action"
        return
    }
    
    if (-not (Test-Path $Path)) {
        Write-Host "ERROR: Backup not found: $Path"
        return
    }
    
    Write-Host "`n🔍 Verifying Backup Integrity`n"
    Write-Host "Path: $Path`n"
    
    $issues = 0
    
    # Check manifest
    $manifest = Join-Path $Path "BACKUP-MANIFEST.txt"
    if (Test-Path $manifest) {
        Write-Host "✓ Manifest found"
    }
    else {
        Write-Host "✗ Manifest missing (WARNING)"
        $issues++
    }
    
    # Check backup log
    $log = Join-Path $Path "backup-log.txt"
    if (Test-Path $log) {
        Write-Host "✓ Backup log found"
        $errors = (Select-String "ERROR" $log).Count
        if ($errors -gt 0) {
            Write-Host "  ⚠️  Found $errors errors in log"
            $issues++
        }
    }
    
    # Check for browser directories
    $browsers = @("Chrome", "Edge", "Firefox", "Brave")
    $found = 0
    foreach ($browser in $browsers) {
        $browserPath = Join-Path $Path $browser
        if (Test-Path $browserPath) {
            Write-Host "✓ $browser data found"
            $found++
        }
    }
    
    if ($found -eq 0) {
        Write-Host "✗ No browser data found (CRITICAL)"
        $issues += 2
    }
    
    # Check for empty directories
    $emptyDirs = Get-ChildItem -Path $Path -Recurse -Directory | 
                 Where-Object { @(Get-ChildItem $_.FullName).Count -eq 0 }
    
    if ($emptyDirs.Count -gt 0) {
        Write-Host "⚠️  Found $($emptyDirs.Count) empty directories"
    }
    
    # Check total size
    $totalSize = (Get-ChildItem -Path $Path -Recurse | 
                  Measure-Object -Property Length -Sum).Sum
    
    if ($totalSize -lt 1MB) {
        Write-Host "⚠️  Backup very small ($(Format-Bytes $totalSize)) - may be incomplete"
        $issues++
    }
    else {
        Write-Host "✓ Backup size reasonable: $(Format-Bytes $totalSize)"
    }
    
    Write-Host ""
    if ($issues -eq 0) {
        Write-Host "✅ Backup integrity verified - No issues found`n"
    }
    else {
        Write-Host "⚠️  Backup has $issues issue(s) - Review required`n"
    }
}

# ============================================================================
# MAIN DISPATCH
# ============================================================================

switch ($Action) {
    "ListBackups" { ListBackups }
    "InspectBackup" { InspectBackup -Path $BackupPath }
    "CompareBackups" { CompareBackups -Path1 $BackupPath1 -Path2 $BackupPath2 }
    "CalculateSize" { CalculateSize -Path $BackupPath }
    "CleanOldBackups" { CleanOldBackups -Days $DaysOld -Force:$Force }
    "VerifyIntegrity" { VerifyIntegrity -Path $BackupPath }
}
