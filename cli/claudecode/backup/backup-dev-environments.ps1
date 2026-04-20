#Requires -Version 5.1
<#
.SYNOPSIS
    Backup development environments from F:\study

.PARAMETER BackupRoot
    Where to store the backup. Default: F:\backup\dev-environments

.PARAMETER SkipBuildArtifacts
    Skip build artifacts (dist, build, __pycache__, etc.)

.EXAMPLE
    .\backup-dev-environments.ps1
    .\backup-dev-environments.ps1 -BackupRoot "D:\backups\dev-envs" -SkipBuildArtifacts
#>
param(
    [string]$StudyRoot = "F:\study",
    [string]$BackupRoot = "F:\backup\dev-environments",
    [switch]$SkipBuildArtifacts
)

$ErrorActionPreference = "SilentlyContinue"
$timestamp = Get-Date -Format "yyyy-MM-dd_HH-mm"
$dest = Join-Path $BackupRoot $timestamp
$report = @{ backed=@(); skipped=@(); errors=@() }

function Log($msg, $color="White") { Write-Host "  $msg" -ForegroundColor $color }

New-Item -ItemType Directory -Force -Path $dest | Out-Null

Write-Host "`n🔧 Dev Environment Backup" -ForegroundColor Cyan
Write-Host "   Source: $StudyRoot"
Write-Host "   Dest  : $dest`n"

# ── Python venvs ──────────────────────────────────────────────────────────────
Write-Host "🐍 Python environments..." -ForegroundColor Yellow
$venvDirs = Get-ChildItem $StudyRoot -Recurse -Directory -Filter "pyvenv.cfg" -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Parent | Sort-Object FullName -Unique

foreach ($venv in $venvDirs) {
    $projDir = $venv.Parent.FullName
    $relPath = $projDir.Replace($StudyRoot, "").TrimStart('\')
    $reqFile = Join-Path $projDir "requirements.txt"

    # Try to extract requirements
    $pip = Join-Path $venv.FullName "Scripts\pip.exe"
    if (Test-Path $pip) {
        $outDir = Join-Path $dest "python\$relPath"
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        & $pip freeze 2>$null | Out-File (Join-Path $outDir "requirements.txt") -Encoding utf8
        Log "✅ Python venv: $relPath" Green
        $report.backed += "python/$relPath"
    } elseif (Test-Path $reqFile) {
        $outDir = Join-Path $dest "python\$relPath"
        New-Item -ItemType Directory -Force -Path $outDir | Out-Null
        Copy-Item $reqFile (Join-Path $outDir "requirements.txt") -Force
        Log "📋 requirements.txt: $relPath" Green
        $report.backed += "python/$relPath (requirements only)"
    }
}

# ── Node projects ─────────────────────────────────────────────────────────────
Write-Host "`n📦 Node.js projects..." -ForegroundColor Yellow
$pkgFiles = Get-ChildItem $StudyRoot -Recurse -File -Filter "package.json" -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch "node_modules" }

foreach ($pkg in $pkgFiles) {
    $projDir = $pkg.DirectoryName
    $relPath = $projDir.Replace($StudyRoot, "").TrimStart('\')
    $outDir = Join-Path $dest "node\$relPath"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    Copy-Item $pkg.FullName (Join-Path $outDir "package.json") -Force
    $lockFile = Join-Path $projDir "package-lock.json"
    if (Test-Path $lockFile) {
        Copy-Item $lockFile (Join-Path $outDir "package-lock.json") -Force
    }
    $yarnLock = Join-Path $projDir "yarn.lock"
    if (Test-Path $yarnLock) {
        Copy-Item $yarnLock (Join-Path $outDir "yarn.lock") -Force
    }
    Log "✅ Node: $relPath" Green
    $report.backed += "node/$relPath"
}

# ── Git repo metadata ─────────────────────────────────────────────────────────
Write-Host "`n🗂  Git repositories..." -ForegroundColor Yellow
$gitDirs = Get-ChildItem $StudyRoot -Recurse -Directory -Filter ".git" -ErrorAction SilentlyContinue |
    Where-Object { Test-Path (Join-Path $_.FullName "config") }

foreach ($git in $gitDirs) {
    $projDir = $git.Parent.FullName
    $relPath = $projDir.Replace($StudyRoot, "").TrimStart('\')
    $outDir = Join-Path $dest "git\$relPath"
    New-Item -ItemType Directory -Force -Path $outDir | Out-Null

    # Save remote URLs and branch info
    Push-Location $projDir
    $remotes = & git remote -v 2>$null
    $branch = & git branch --show-current 2>$null
    $log = & git log --oneline -10 2>$null
    Pop-Location

    [PSCustomObject]@{
        path    = $relPath
        branch  = $branch
        remotes = $remotes
        recent  = $log
    } | ConvertTo-Json | Out-File (Join-Path $outDir "git-meta.json") -Encoding utf8

    Log "✅ Git: $relPath ($branch)" Green
    $report.backed += "git/$relPath"
}

# ── Editor configs ────────────────────────────────────────────────────────────
Write-Host "`n⚙  Editor configs..." -ForegroundColor Yellow
$configPatterns = @(".vscode", ".idea", ".vim", ".editorconfig", "*.code-workspace")
foreach ($pat in $configPatterns) {
    $found = Get-ChildItem $StudyRoot -Recurse -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -like $pat -and $_.FullName -notmatch "node_modules" } |
        Select-Object -First 50

    foreach ($f in $found) {
        $relPath = $f.FullName.Replace($StudyRoot, "").TrimStart('\')
        $outPath = Join-Path $dest "configs\$relPath"
        New-Item -ItemType Directory -Force -Path (Split-Path $outPath) | Out-Null
        if ($f.PSIsContainer) {
            Copy-Item $f.FullName $outPath -Recurse -Force
        } else {
            Copy-Item $f.FullName $outPath -Force
        }
        $report.backed += "config/$relPath"
    }
}
Log "✅ Editor configs copied" Green

# ── Metadata file ─────────────────────────────────────────────────────────────
$meta = [PSCustomObject]@{
    timestamp = $timestamp
    studyRoot = $StudyRoot
    backed    = $report.backed.Count
    errors    = $report.errors.Count
    items     = $report.backed
}
$meta | ConvertTo-Json -Depth 5 | Out-File (Join-Path $dest "backup-metadata.json") -Encoding utf8

# ── Summary ───────────────────────────────────────────────────────────────────
$totalSize = (Get-ChildItem $dest -Recurse -File | Measure-Object Length -Sum).Sum
Write-Host "`n═══════════════════════════════════════════════════════" -ForegroundColor DarkGray
Write-Host "  ✅ Backup complete!" -ForegroundColor Green
Write-Host "  Items backed up : $($report.backed.Count)"
Write-Host "  Errors          : $($report.errors.Count)"
Write-Host "  Total size      : $([math]::Round($totalSize/1MB,2)) MB"
Write-Host "  Saved to        : $dest`n"
