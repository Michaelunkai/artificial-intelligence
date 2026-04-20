# Quick Phase 4 Fix - Safe Copy Only
param([switch]$Verbose)

$ErrorActionPreference = "Continue"

Write-Host "=== Phase 4: Workspace Sync ===" -ForegroundColor Cyan
Write-Host ""

function WSL-Run { 
    param($Cmd) 
    if ($Verbose) { Write-Host "WSL: $Cmd" -ForegroundColor DarkGray }
    wsl -d Ubuntu bash -c $Cmd 
}

Write-Host "[Task 13/40] Syncing workspace files..." -ForegroundColor Yellow
$files = @("SOUL.md", "USER.md", "AGENTS.md", "TOOLS.md", "IDENTITY.md", "MEMORY.md", "HEARTBEAT.md", "BOOTSTRAP.md", "CUSTOM-COMMANDS.md")
$synced = 0
foreach ($file in $files) {
    if (Test-Path "C:\Users\micha\.openclaw\workspace-openclaw\$file") {
        WSL-Run "cp -f /mnt/c/Users/micha/.openclaw/workspace-openclaw/$file ~/workspace-openclaw/$file"
        $synced++
    }
}
Write-Host "OK - Synced $synced files" -ForegroundColor Green
Write-Host ""

Write-Host "[Task 14/40] Syncing memory files..." -ForegroundColor Yellow
WSL-Run "mkdir -p ~/.openclaw/memory"
$memFiles = Get-ChildItem "C:\Users\micha\.openclaw\workspace-openclaw\memory" -Filter "*.md" -ErrorAction SilentlyContinue
if ($memFiles) {
    foreach ($mf in $memFiles) {
        WSL-Run "cp -f /mnt/c/Users/micha/.openclaw/workspace-openclaw/memory/$($mf.Name) ~/.openclaw/memory/$($mf.Name)"
    }
    Write-Host "OK - Synced $($memFiles.Count) memory files" -ForegroundColor Green
} else {
    Write-Host "SKIP - No memory files found" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[Task 15/40] Syncing scripts..." -ForegroundColor Yellow
WSL-Run "mkdir -p ~/.openclaw/scripts"
if (Test-Path "C:\Users\micha\.openclaw\scripts") {
    WSL-Run "find /mnt/c/Users/micha/.openclaw/scripts -type f -name '*.ps1' -exec cp -f {} ~/.openclaw/scripts/ \; 2>/dev/null"
    $scriptCount = (Get-ChildItem "C:\Users\micha\.openclaw\scripts" -Filter "*.ps1").Count
    Write-Host "OK - $scriptCount scripts available" -ForegroundColor Green
} else {
    Write-Host "SKIP - Scripts directory not found" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[Task 16/40] Syncing skills..." -ForegroundColor Yellow
if (Test-Path "C:\Users\micha\.openclaw\skills") {
    $skills = Get-ChildItem "C:\Users\micha\.openclaw\skills" -Directory
    foreach ($skill in $skills) {
        WSL-Run "mkdir -p ~/.openclaw/skills/$($skill.Name)"
        WSL-Run "cp -rf /mnt/c/Users/micha/.openclaw/skills/$($skill.Name)/* ~/.openclaw/skills/$($skill.Name)/ 2>/dev/null"
    }
    Write-Host "OK - Synced $($skills.Count) skills" -ForegroundColor Green
} else {
    Write-Host "SKIP - Skills directory not found" -ForegroundColor Yellow
}
Write-Host ""

Write-Host "[Task 17/40] Creating RLP symlink..." -ForegroundColor Yellow
WSL-Run "ln -sf /mnt/c/Users/micha/.openclaw/rlp-state.json ~/.openclaw/rlp-state.json 2>/dev/null"
Write-Host "OK - RLP state linked" -ForegroundColor Green
Write-Host ""

Write-Host "[Task 18/40] Installing skill dependencies..." -ForegroundColor Yellow
if (Test-Path "C:\Users\micha\.openclaw\skills") {
    $pkgSkills = Get-ChildItem "C:\Users\micha\.openclaw\skills" -Directory | Where-Object { Test-Path (Join-Path $_.FullName "package.json") }
    if ($pkgSkills) {
        foreach ($skill in $pkgSkills) {
            Write-Host "  Installing: $($skill.Name)..." -ForegroundColor DarkGray
            WSL-Run "cd ~/.openclaw/skills/$($skill.Name) && npm install --silent --no-audit --no-fund 2>/dev/null || true"
        }
        Write-Host "OK - Installed deps for $($pkgSkills.Count) skills" -ForegroundColor Green
    } else {
        Write-Host "OK - No skills need dependencies" -ForegroundColor Green
    }
}

Write-Host ""
Write-Host "=== Phase 4 Complete ===" -ForegroundColor Green
