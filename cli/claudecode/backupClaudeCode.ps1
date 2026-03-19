# Claude Code Backup & Sync Script with Comprehensive Bloat Cleanup
# This script cleans bloat, syncs Claude Code data, maintains only the latest backup, and updates PowerShell profile

# Configuration
$sourceBase = "C:\users\micha"
$backupBase = "F:\backup\claudecode"
$timestamp = Get-Date -Format "yyyy_MM_dd_HH_mm_ss"
$newBackupFolder = Join-Path $backupBase "backup_$timestamp"
$profilePath = "C:\users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"

# ONLY THESE FILES/FOLDERS ARE KEPT - EVERYTHING ELSE DELETED
$keepItems = @(
    "mcp.json",
    "settings.json",
    "config",
    "projects",
    "plugins",
    "hooks",
    "auto_rules"
)

# Paths to sync (Claude Code specific data)
$pathsToSync = @(
    @{Source = "$sourceBase\.claude"; Dest = "$newBackupFolder\.claude"; Name = "Claude Config"},
    @{Source = "$sourceBase\.config\claude"; Dest = "$newBackupFolder\.config\claude"; Name = "Claude Settings"},
    @{Source = "$sourceBase\AppData\Roaming\Claude"; Dest = "$newBackupFolder\AppData\Roaming\Claude"; Name = "Claude Roaming Data"},
    @{Source = "$sourceBase\AppData\Local\Claude"; Dest = "$newBackupFolder\AppData\Local\Claude"; Name = "Claude Local Data"},
    @{Source = "$sourceBase\.mcp"; Dest = "$newBackupFolder\.mcp"; Name = "MCP Config"},
    @{Source = "$sourceBase\.config\mcp"; Dest = "$newBackupFolder\.config\mcp"; Name = "MCP Settings"},
    @{Source = "$sourceBase\AppData\Roaming\mcp"; Dest = "$newBackupFolder\AppData\Roaming\mcp"; Name = "MCP Roaming Data"},
    @{Source = "$sourceBase\AppData\Local\mcp"; Dest = "$newBackupFolder\AppData\Local\mcp"; Name = "MCP Local Data"}
)

Write-Host "=== Claude Code Complete Backup & Sync ===" -ForegroundColor Cyan
Write-Host "Timestamp: $timestamp" -ForegroundColor Yellow
Write-Host ""

# Step 1: AGGRESSIVE CLEANUP - DELETE EVERYTHING NOT IN KEEP LIST
Write-Host "[1/5] AGGRESSIVE CLEANUP - Deleting ALL bloat..." -ForegroundColor Green
Write-Host "      Items to KEEP: $($keepItems -join ', ')" -ForegroundColor Yellow
Write-Host "      EVERYTHING ELSE WILL BE DELETED" -ForegroundColor Red
Write-Host ""

$totalCleaned = 0
$totalSizeCleaned = 0

# Clean .claude directory
$claudeDir = "$sourceBase\.claude"
if (Test-Path $claudeDir) {
    Write-Host "      → Cleaning $claudeDir..." -ForegroundColor Cyan
    
    $allItems = Get-ChildItem -Path $claudeDir -Force -ErrorAction SilentlyContinue
    $itemsToDelete = @()
    
    foreach ($item in $allItems) {
        $shouldKeep = $false
        foreach ($keepItem in $keepItems) {
            if ($item.Name -eq $keepItem) {
                $shouldKeep = $true
                break
            }
        }
        if (-not $shouldKeep) {
            $itemsToDelete += $item
        }
    }
    
    if ($itemsToDelete.Count -gt 0) {
        Write-Host "      → Found $($itemsToDelete.Count) items to DELETE" -ForegroundColor Yellow
        
        $cleanedCount = 0
        foreach ($item in $itemsToDelete) {
            $cleanedCount++
            $cleanPercent = [math]::Round(($cleanedCount / $itemsToDelete.Count) * 100)
            
            if ($item.PSIsContainer) {
                Write-Host "`r      → [$cleanedCount/$($itemsToDelete.Count)] ($cleanPercent%) Analyzing: $($item.Name)..." -NoNewline -ForegroundColor Cyan
                $itemFiles = Get-ChildItem -Path $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue
                $itemSize = ($itemFiles | Measure-Object -Property Length -Sum).Sum
                $itemSizeGB = [math]::Round($itemSize / 1GB, 2)
                $itemSizeMB = [math]::Round($itemSize / 1MB, 2)
                $itemFileCount = ($itemFiles | Measure-Object).Count
                
                if ($itemSizeGB -gt 0.1) {
                    Write-Host "`r      → [$cleanedCount/$($itemsToDelete.Count)] ($cleanPercent%) DELETING: $($item.Name) ($itemFileCount files, $itemSizeGB GB)..." -NoNewline -ForegroundColor Red
                } else {
                    Write-Host "`r      → [$cleanedCount/$($itemsToDelete.Count)] ($cleanPercent%) DELETING: $($item.Name) ($itemFileCount files, $itemSizeMB MB)..." -NoNewline -ForegroundColor Red
                }
                
                Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                
                $totalCleaned += $itemFileCount
                $totalSizeCleaned += $itemSize
            } else {
                $itemSize = $item.Length
                $itemSizeMB = [math]::Round($itemSize / 1MB, 2)
                
                Write-Host "`r      → [$cleanedCount/$($itemsToDelete.Count)] ($cleanPercent%) DELETING: $($item.Name) ($itemSizeMB MB)..." -NoNewline -ForegroundColor Red
                Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
                
                $totalCleaned += 1
                $totalSizeCleaned += $itemSize
            }
        }
        Write-Host ""
        Write-Host "      ✓ DELETED $($itemsToDelete.Count) items from .claude" -ForegroundColor Green
    } else {
        Write-Host "      ✓ .claude directory is clean" -ForegroundColor DarkGray
    }
}

# Clean .config\claude directory
$configClaudeDir = "$sourceBase\.config\claude"
if (Test-Path $configClaudeDir) {
    Write-Host "      → Cleaning $configClaudeDir..." -ForegroundColor Cyan
    
    $allItems = Get-ChildItem -Path $configClaudeDir -Force -ErrorAction SilentlyContinue
    $itemsToDelete = @()
    
    foreach ($item in $allItems) {
        $shouldKeep = $false
        foreach ($keepItem in $keepItems) {
            if ($item.Name -eq $keepItem) {
                $shouldKeep = $true
                break
            }
        }
        if (-not $shouldKeep) {
            $itemsToDelete += $item
        }
    }
    
    if ($itemsToDelete.Count -gt 0) {
        Write-Host "      → Found $($itemsToDelete.Count) items to DELETE" -ForegroundColor Yellow
        
        $cleanedCount = 0
        foreach ($item in $itemsToDelete) {
            $cleanedCount++
            $cleanPercent = [math]::Round(($cleanedCount / $itemsToDelete.Count) * 100)
            
            if ($item.PSIsContainer) {
                $itemSize = (Get-ChildItem -Path $item.FullName -Recurse -File -Force -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
                $itemSizeMB = [math]::Round($itemSize / 1MB, 2)
                
                Write-Host "`r      → [$cleanedCount/$($itemsToDelete.Count)] ($cleanPercent%) DELETING: $($item.Name) ($itemSizeMB MB)..." -NoNewline -ForegroundColor Red
                Remove-Item -Path $item.FullName -Recurse -Force -ErrorAction SilentlyContinue
                
                $totalSizeCleaned += $itemSize
            } else {
                Remove-Item -Path $item.FullName -Force -ErrorAction SilentlyContinue
                $totalSizeCleaned += $item.Length
            }
        }
        Write-Host ""
        Write-Host "      ✓ DELETED $($itemsToDelete.Count) items from .config\claude" -ForegroundColor Green
    }
}

if ($totalSizeCleaned -gt 0) {
    $totalCleanedGB = [math]::Round($totalSizeCleaned / 1GB, 2)
    Write-Host ""
    Write-Host "      ══════════════════════════════════════" -ForegroundColor Green
    Write-Host "      ✓ CLEANUP COMPLETE" -ForegroundColor Green
    Write-Host "      ✓ Freed: $totalCleanedGB GB" -ForegroundColor Green
    Write-Host "      ══════════════════════════════════════" -ForegroundColor Green
} else {
    Write-Host "      ✓ No bloat found" -ForegroundColor Green
}
Write-Host ""

# Create new backup folder
Write-Host "[2/5] Creating backup folder: $newBackupFolder" -ForegroundColor Green
New-Item -ItemType Directory -Path $newBackupFolder -Force | Out-Null
Write-Host "      ✓ Backup folder created" -ForegroundColor Green
Write-Host ""

# Sync each path
Write-Host "[3/5] Syncing Claude Code data..." -ForegroundColor Green
$currentPath = 0
$totalPaths = $pathsToSync.Count

foreach ($path in $pathsToSync) {
    $currentPath++
    $percentComplete = [math]::Round(($currentPath / $totalPaths) * 100)
    
    Write-Host "[$currentPath/$totalPaths] ($percentComplete%) $($path.Name)" -ForegroundColor Yellow
    Write-Host "      Source: $($path.Source)" -ForegroundColor DarkGray
    
    if (Test-Path $path.Source) {
        Write-Host "      → Scanning source files..." -ForegroundColor Cyan
        $files = Get-ChildItem -Path $path.Source -Recurse -File -ErrorAction SilentlyContinue
        $fileCount = ($files | Measure-Object).Count
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
        $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
        Write-Host "      → Found $fileCount files ($totalSizeMB MB) in source" -ForegroundColor Cyan
        
        $destDir = Split-Path $path.Dest -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }

        Write-Host "      → Syncing (mirror mode)..." -ForegroundColor Cyan
        
        $tempLog = [System.IO.Path]::GetTempFileName()
        
        $robocopyArgs = @(
            "`"$($path.Source)`"",
            "`"$($path.Dest)`"",
            "/MIR",
            "/R:2",
            "/W:1",
            "/MT:16",
            "/BYTES",
            "/LOG:$tempLog",
            "/TEE"
        )
        
        $process = Start-Process -FilePath "robocopy" -ArgumentList $robocopyArgs -NoNewWindow -PassThru
        
        $lastPosition = 0
        $filesCopied = 0
        $filesSkipped = 0
        $lastUpdateTime = Get-Date
        
        while (-not $process.HasExited) {
            Start-Sleep -Milliseconds 500
            
            if (Test-Path $tempLog) {
                $currentContent = Get-Content $tempLog -Raw -ErrorAction SilentlyContinue
                if ($currentContent.Length -gt $lastPosition) {
                    $newContent = $currentContent.Substring($lastPosition)
                    $lastPosition = $currentContent.Length
                    
                    $newCopies = ([regex]::Matches($newContent, "New File")).Count
                    $newSkips = ([regex]::Matches($newContent, "same")).Count
                    
                    $filesCopied += $newCopies
                    $filesSkipped += $newSkips
                    
                    if ($newCopies -gt 0 -or $newSkips -gt 0) {
                        $progressPercent = if ($fileCount -gt 0) { [math]::Round((($filesCopied + $filesSkipped) / $fileCount) * 100, 1) } else { 0 }
                        Write-Host "`r      → Progress: $progressPercent% | Copied: $filesCopied | Skipped: $filesSkipped" -NoNewline -ForegroundColor Cyan
                        $lastUpdateTime = Get-Date
                    }
                }
            }
            
            if (((Get-Date) - $lastUpdateTime).TotalSeconds -gt 3) {
                Write-Host "`r      → Processing... (Copied: $filesCopied | Skipped: $filesSkipped)     " -NoNewline -ForegroundColor Cyan
                $lastUpdateTime = Get-Date
            }
        }
        
        $process.WaitForExit()
        Write-Host ""
        
        if ($process.ExitCode -le 7) {
            $logContent = Get-Content $tempLog -Raw -ErrorAction SilentlyContinue
            
            if ($logContent -match "Copied\s*:\s*(\d+)") { $copiedFiles = $matches[1] }
            if ($logContent -match "Skipped\s*:\s*(\d+)") { $skippedFiles = $matches[1] }
            
            if ($copiedFiles -gt 0) {
                Write-Host "      ✓ Copied: $copiedFiles files" -ForegroundColor Green
            }
            if ($skippedFiles -gt 0) {
                Write-Host "      ↔ Skipped: $skippedFiles files (already synced)" -ForegroundColor DarkGray
            }
            if ($copiedFiles -eq 0) {
                Write-Host "      ✓ Already in sync" -ForegroundColor Green
            }
        }
        
        Remove-Item $tempLog -Force -ErrorAction SilentlyContinue
    } else {
        Write-Host "      ⚠ Source not found - skipping" -ForegroundColor DarkYellow
    }
    Write-Host ""
}

Write-Host "[4/5] Cleaning up old backups..." -ForegroundColor Green

$allItems = Get-ChildItem -Path $backupBase -Directory -ErrorAction SilentlyContinue
$itemsToDelete = $allItems | Where-Object { $_.Name -ne "backup_$timestamp" -and $_.Name -ne ".git" }

if ($itemsToDelete.Count -gt 0) {
    $deleteCount = 0
    foreach ($item in $itemsToDelete) {
        $deleteCount++
        Write-Host "      [$deleteCount/$($itemsToDelete.Count)] Removing: $($item.Name)" -ForegroundColor Red
        Remove-Item -Path $item.FullName -Recurse -Force
    }
    Write-Host "      ✓ Removed $($itemsToDelete.Count) old backup(s)" -ForegroundColor Green
} else {
    Write-Host "      ✓ No old backups to remove" -ForegroundColor Green
}

$strayFiles = Get-ChildItem -Path $backupBase -File -ErrorAction SilentlyContinue
foreach ($file in $strayFiles) {
    Remove-Item -Path $file.FullName -Force
}
Write-Host ""

Write-Host "[5/5] Updating PowerShell profile..." -ForegroundColor Green

if (Test-Path $profilePath) {
    $profileContent = Get-Content $profilePath -Raw
    $pattern = '(function\s+resclau\s*{[^}]*backup_)\d{4}_\d{2}_\d{2}_\d{2}_\d{2}_\d{2}'
    $replacement = "`${1}$timestamp"

    if ($profileContent -match $pattern) {
        $updatedContent = $profileContent -replace $pattern, $replacement
        Set-Content -Path $profilePath -Value $updatedContent -NoNewline
        Write-Host "      ✓ Updated resclau function: backup_$timestamp" -ForegroundColor Green
    } else {
        Write-Host "      ⚠ Pattern not found" -ForegroundColor DarkYellow
    }
} else {
    Write-Host "      ✗ Profile not found" -ForegroundColor Red
}
Write-Host ""

Write-Host "══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host "                    SYNC COMPLETE                          " -ForegroundColor Green
Write-Host "══════════════════════════════════════════════════════════" -ForegroundColor Cyan
Write-Host ""
Write-Host "✓ All Claude Code data synced successfully!" -ForegroundColor Green
Write-Host ""
