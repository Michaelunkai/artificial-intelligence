#Requires -Version 5.1
<#
.SYNOPSIS
    Restore development environments from backup

.PARAMETER BackupPath
    Path to specific backup timestamp folder, or "latest" to auto-detect.

.PARAMETER StudyRoot
    Where to restore. Default: F:\study

.PARAMETER WhatIf
    Show what would be restored without doing it.

.EXAMPLE
    .\restore-dev-environments.ps1 -BackupPath latest
    .\restore-dev-environments.ps1 -BackupPath "F:\backup\dev-environments\2026-03-23_14-00" -WhatIf
#>
param(
    [string]$BackupPath = "latest",
    [string]$BackupRoot = "F:\backup\dev-environments",
    [string]$StudyRoot  = "F:\study",
    [switch]$WhatIf
)

$ErrorActionPreference = "SilentlyContinue"

# Resolve backup path
if ($BackupPath -eq "latest") {
    $BackupPath = Get-ChildItem $BackupRoot -Directory | Sort-Object Name -Descending | Select-Object -First 1 -ExpandProperty FullName
    if (-not $BackupPath) { Write-Host "❌ No backups found in $BackupRoot" -ForegroundColor Red; exit 1 }
}

if (-not (Test-Path $BackupPath)) {
    Write-Host "❌ Backup not found: $BackupPath" -ForegroundColor Red; exit 1
}

Write-Host "`n🔄 Dev Environment Restore" -ForegroundColor Cyan
Write-Host "   Source: $BackupPath"
Write-Host "   Dest  : $StudyRoot"
if ($WhatIf) { Write-Host "   Mode  : WhatIf (no changes)" -ForegroundColor Yellow }
Write-Host ""

# Load metadata
$meta = Get-Content (Join-Path $BackupPath "backup-metadata.json") | ConvertFrom-Json
Write-Host "  Backup from: $($meta.timestamp) | $($meta.backed) items`n"

$restored = 0; $skipped = 0; $errors = 0

# ── Python venvs ──────────────────────────────────────────────────────────────
Write-Host "🐍 Restoring Python environments..." -ForegroundColor Yellow
$pyBackups = Get-ChildItem (Join-Path $BackupPath "python") -Recurse -File -Filter "requirements.txt" -ErrorAction SilentlyContinue

foreach ($req in $pyBackups) {
    $relPath = $req.DirectoryName.Replace((Join-Path $BackupPath "python"), "").TrimStart('\')
    $projDir = Join-Path $StudyRoot $relPath
    $destReq  = Join-Path $projDir "requirements.txt"

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would restore requirements → $projDir" -ForegroundColor DarkCyan
        $skipped++
        continue
    }

    New-Item -ItemType Directory -Force -Path $projDir | Out-Null
    Copy-Item $req.FullName $destReq -Force

    # Recreate venv if python available
    $py = Get-Command python -ErrorAction SilentlyContinue
    if ($py -and -not (Test-Path (Join-Path $projDir "venv\Scripts\python.exe"))) {
        Write-Host "  Creating venv in $relPath..." -ForegroundColor DarkYellow
        & python -m venv (Join-Path $projDir "venv") 2>$null
        $pip = Join-Path $projDir "venv\Scripts\pip.exe"
        if (Test-Path $pip) {
            & $pip install -r $destReq --quiet 2>$null
            Write-Host "  ✅ Python restored: $relPath" -ForegroundColor Green
        }
    } else {
        Write-Host "  📋 requirements.txt placed: $relPath" -ForegroundColor Green
    }
    $restored++
}

# ── Node projects ─────────────────────────────────────────────────────────────
Write-Host "`n📦 Restoring Node.js projects..." -ForegroundColor Yellow
$nodeBackups = Get-ChildItem (Join-Path $BackupPath "node") -Recurse -File -Filter "package.json" -ErrorAction SilentlyContinue

foreach ($pkg in $nodeBackups) {
    $relPath = $pkg.DirectoryName.Replace((Join-Path $BackupPath "node"), "").TrimStart('\')
    $projDir = Join-Path $StudyRoot $relPath

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would restore Node project → $projDir" -ForegroundColor DarkCyan
        $skipped++; continue
    }

    New-Item -ItemType Directory -Force -Path $projDir | Out-Null
    Copy-Item $pkg.FullName (Join-Path $projDir "package.json") -Force

    $lockSrc = Join-Path $pkg.DirectoryName "package-lock.json"
    if (Test-Path $lockSrc) { Copy-Item $lockSrc (Join-Path $projDir "package-lock.json") -Force }

    $npm = Get-Command npm -ErrorAction SilentlyContinue
    if ($npm -and -not (Test-Path (Join-Path $projDir "node_modules"))) {
        Write-Host "  npm install in $relPath..." -ForegroundColor DarkYellow
        Push-Location $projDir
        & npm install --silent 2>$null
        Pop-Location
    }
    Write-Host "  ✅ Node restored: $relPath" -ForegroundColor Green
    $restored++
}

# ── Editor configs ────────────────────────────────────────────────────────────
Write-Host "`n⚙  Restoring editor configs..." -ForegroundColor Yellow
$configSrc = Join-Path $BackupPath "configs"
if (Test-Path $configSrc) {
    if (-not $WhatIf) {
        Get-ChildItem $configSrc | ForEach-Object {
            $destPath = Join-Path $StudyRoot $_.Name
            Copy-Item $_.FullName $destPath -Recurse -Force
        }
        Write-Host "  ✅ Configs restored" -ForegroundColor Green
        $restored++
    } else {
        Write-Host "  [WhatIf] Would restore editor configs" -ForegroundColor DarkCyan
        $skipped++
    }
}

# ── Git remotes info ──────────────────────────────────────────────────────────
Write-Host "`n🗂  Git repository info..." -ForegroundColor Yellow
$gitMetas = Get-ChildItem (Join-Path $BackupPath "git") -Recurse -File -Filter "git-meta.json" -ErrorAction SilentlyContinue
foreach ($gm in $gitMetas) {
    $info = Get-Content $gm.FullName | ConvertFrom-Json
    Write-Host "  📋 $($info.path) — branch: $($info.branch)" -ForegroundColor DarkGray
}

# ── Validation ────────────────────────────────────────────────────────────────
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  SUMMARY" -ForegroundColor Cyan
Write-Host "═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
if ($WhatIf) {
    Write-Host "  [WhatIf] Would restore $($pyBackups.Count + $nodeBackups.Count) items. Run without -WhatIf to apply." -ForegroundColor Yellow
} else {
    Write-Host "  ✅ Restored : $restored items"
    Write-Host "  ⏭  Skipped  : $skipped"
    Write-Host "  ❌ Errors   : $errors"
}
Write-Host ""
