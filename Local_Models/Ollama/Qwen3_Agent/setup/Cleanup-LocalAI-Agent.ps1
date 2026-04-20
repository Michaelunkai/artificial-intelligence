<#
.SYNOPSIS
    FULL CLEANUP - Removes EVERYTHING the Setup script installed.
    Cleans F: drive AND any C: drive leaks. Restores system to pre-setup state.
    Fully automatic - no prompts.
#>

$ErrorActionPreference = "Continue"

Write-Host "`n============================================================" -ForegroundColor Red
Write-Host "  LOCAL AI AGENT - FULL CLEANUP (AUTOMATIC)" -ForegroundColor Red
Write-Host "============================================================`n" -ForegroundColor Red

$totalSteps = 12
$currentStep = 0
function Show-Step([int]$Step, [int]$Total, [string]$Msg) {
    $pct = [math]::Round(($Step / $Total) * 100)
    Write-Progress -Activity "Cleanup" -Status $Msg -PercentComplete $pct
    Write-Host "[$Step/$Total] ($pct%) $Msg" -ForegroundColor Yellow
}

# ============================================================
# STEP 1: Stop all processes
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Stopping processes..."
Get-Process -Name "ollama*" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Get-Process -Name "interpreter*" -EA SilentlyContinue | Stop-Process -Force -EA SilentlyContinue
Start-Sleep 2
Write-Host "  [OK] Stopped" -ForegroundColor Green

# ============================================================
# STEP 2: Remove ~/.ollama symlink
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Removing symlink ~/.ollama..."
$dotOllama = "$env:USERPROFILE\.ollama"
if (Test-Path $dotOllama) {
    $item = Get-Item $dotOllama -Force
    if ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) {
        cmd /c "rmdir `"$dotOllama`"" 2>$null
        Write-Host "  [OK] Symlink removed" -ForegroundColor Green
    } else {
        Remove-Item -Recurse -Force $dotOllama -EA SilentlyContinue
        Write-Host "  [OK] Deleted real .ollama on C:" -ForegroundColor Green
    }
} else { Write-Host "  [SKIP] Not found" -ForegroundColor Yellow }

# ============================================================
# STEP 3: Remove ALL environment variables
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Removing environment variables..."
$varsToRemove = @(
    "OLLAMA_MODELS","OLLAMA_TMPDIR","OLLAMA_RUNNERS_DIR","OLLAMA_HOME","OLLAMA_HOST",
    "OLLAMA_GPU_LAYERS","OLLAMA_FLASH_ATTENTION","OLLAMA_KV_CACHE_TYPE","OLLAMA_SCHED_SPREAD",
    "OLLAMA_GPU_OVERHEAD","OLLAMA_NUM_PARALLEL","OLLAMA_MAX_LOADED_MODELS","OLLAMA_MAX_QUEUE",
    "OLLAMA_KEEP_ALIVE","OLLAMA_LOAD_TIMEOUT","OLLAMA_NOPRUNE","OLLAMA_NOHISTORY",
    "CUDA_VISIBLE_DEVICES","CUDA_DEVICE_ORDER",
    "PIP_CACHE_DIR","PIP_TARGET","TMPDIR",
    "WDM_LOCAL","WDM_LOG_LEVEL","SE_CACHE_PATH",
    "OLLAMA_FLASH_ATTENTION","OLLAMA_KV_CACHE_TYPE"
)
foreach ($var in $varsToRemove) {
    [System.Environment]::SetEnvironmentVariable($var, $null, 'User')
    Remove-Item -Path "Env:\$var" -EA SilentlyContinue
}
# Restore TEMP/TMP if they were overridden
$defaultTemp = "$env:USERPROFILE\AppData\Local\Temp"
$currTemp = [System.Environment]::GetEnvironmentVariable("TEMP", 'User')
if ($currTemp -and $currTemp -like "*LocalAI*") {
    [System.Environment]::SetEnvironmentVariable("TEMP", $null, 'User')
    [System.Environment]::SetEnvironmentVariable("TMP", $null, 'User')
    Set-Item -Path "Env:\TEMP" -Value $defaultTemp
    Set-Item -Path "Env:\TMP" -Value $defaultTemp
}
Write-Host "  [OK] All env vars removed" -ForegroundColor Green

# ============================================================
# STEP 4: Clean PATH
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Cleaning PATH..."
$userPath = [System.Environment]::GetEnvironmentVariable('Path','User')
$cleanParts = ($userPath -split ';') | Where-Object {
    $_ -ne "" -and
    $_ -notlike "*backup\LocalAI*" -and
    $_ -notlike "*ollama\venv*" -and
    $_ -notlike "*ollama-app*"
}
$newPath = $cleanParts -join ';'
[System.Environment]::SetEnvironmentVariable('Path', $newPath, 'User')
$env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + $newPath
Write-Host "  [OK] PATH cleaned" -ForegroundColor Green

# ============================================================
# STEP 5: Delete ALL F: drive data
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Deleting F:\backup\LocalAI\ollama..."
$fBase = "F:\backup\LocalAI\ollama"
if (Test-Path $fBase) {
    $sizeBefore = (Get-ChildItem $fBase -Recurse -Force -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $sizeGB = [math]::Round($sizeBefore / 1GB, 2)
    Write-Host "  Deleting $sizeGB GB (includes models, venv, launchers, agent.py)..." -ForegroundColor DarkGray
    Remove-Item -Recurse -Force $fBase -EA SilentlyContinue
    Write-Host "  [OK] Deleted ($sizeGB GB freed)" -ForegroundColor Green
} else { Write-Host "  [SKIP] Not found" -ForegroundColor Yellow }
# Also clean parent dir if empty
$fParent = "F:\backup\LocalAI"
if ((Test-Path $fParent) -and -not (Get-ChildItem $fParent -Force -EA SilentlyContinue)) {
    Remove-Item -Force $fParent -EA SilentlyContinue
    Write-Host "  [OK] Removed empty parent F:\backup\LocalAI" -ForegroundColor Green
}

# ============================================================
# STEP 6: Clean C: pip cache
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Cleaning pip cache on C:..."
$pipPaths = @("$env:LOCALAPPDATA\pip", "$env:APPDATA\pip", "$env:USERPROFILE\pip")
foreach ($p in $pipPaths) {
    if (Test-Path $p) {
        $s = (Get-ChildItem $p -Recurse -Force -EA SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        Remove-Item -Recurse -Force $p -EA SilentlyContinue
        Write-Host "  [OK] Deleted $p ($([math]::Round($s/1MB,1)) MB)" -ForegroundColor Green
    }
}
pip cache purge 2>$null
Write-Host "  [OK] Pip caches purged" -ForegroundColor Green

# ============================================================
# STEP 7: Uninstall leaked packages from system Python
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Removing packages from system Python..."
pip uninstall -y open-interpreter pyautogui selenium webdriver-manager pyreadline3 rich 2>$null
Write-Host "  [OK] System packages cleaned" -ForegroundColor Green

# ============================================================
# STEP 8: Clean C: ChromeDriver caches
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Cleaning ChromeDriver on C:..."
foreach ($p in @("$env:USERPROFILE\.wdm", "$env:LOCALAPPDATA\SeleniumManager", "$env:USERPROFILE\.cache\selenium")) {
    if (Test-Path $p) {
        Remove-Item -Recurse -Force $p -EA SilentlyContinue
        Write-Host "  [OK] Deleted $p" -ForegroundColor Green
    }
}

# ============================================================
# STEP 9: Clean ALL Ollama leftovers on C:
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Cleaning Ollama leftovers on C:..."
$leftoverPaths = @(
    "$env:LOCALAPPDATA\Ollama",
    "$env:APPDATA\Ollama",
    "$env:LOCALAPPDATA\Programs\Ollama",
    "$env:USERPROFILE\.ollama"
)
foreach ($p in $leftoverPaths) {
    if (Test-Path $p) {
        Remove-Item -Recurse -Force $p -EA SilentlyContinue
        Write-Host "  [OK] Deleted $p" -ForegroundColor Green
    }
}
# Clean temp
$tempDir = [System.IO.Path]::GetTempPath()
foreach ($pattern in @("ollama*", "pip-*", "interpreter*", "open-interpreter*")) {
    Get-ChildItem -Path $tempDir -Filter $pattern -Force -EA SilentlyContinue | ForEach-Object {
        Remove-Item -Recurse -Force $_.FullName -EA SilentlyContinue
        Write-Host "  [OK] Temp: $($_.Name)" -ForegroundColor Green
    }
}

# ============================================================
# STEP 10: Uninstall Ollama via winget
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Uninstalling Ollama..."
winget uninstall Ollama.Ollama --silent --accept-source-agreements 2>$null
Write-Host "  [OK] Ollama uninstalled" -ForegroundColor Green

# ============================================================
# STEP 11: Clean Ollama from PATH (Machine level too)
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Final PATH cleanup..."
foreach ($scope in @('User','Machine')) {
    $p = [System.Environment]::GetEnvironmentVariable('Path', $scope)
    if ($p) {
        $parts = ($p -split ';') | Where-Object { $_ -ne "" -and $_ -notlike "*Ollama*" -and $_ -notlike "*ollama*" }
        [System.Environment]::SetEnvironmentVariable('Path', ($parts -join ';'), $scope)
    }
}
Write-Host "  [OK] PATH fully cleaned" -ForegroundColor Green

# ============================================================
# STEP 12: Final verification
# ============================================================
$currentStep++; Show-Step $currentStep $totalSteps "Verifying cleanup..."
Write-Progress -Activity "Cleanup" -Completed

$issues = @()
foreach ($p in @("$env:USERPROFILE\.ollama", "$env:LOCALAPPDATA\Ollama", "$env:LOCALAPPDATA\Programs\Ollama", "F:\backup\LocalAI\ollama")) {
    if (Test-Path $p) { $issues += $p }
}
$remainingVars = @()
foreach ($v in $varsToRemove) {
    if ([System.Environment]::GetEnvironmentVariable($v, 'User')) { $remainingVars += $v }
}

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host "  CLEANUP COMPLETE" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
if ($issues.Count -eq 0) {
    Write-Host "  C: drive:  CLEAN" -ForegroundColor Green
    Write-Host "  F: drive:  CLEAN" -ForegroundColor Green
} else {
    Write-Host "  Remaining:" -ForegroundColor Red
    foreach ($i in $issues) { Write-Host "    $i" -ForegroundColor Red }
}
if ($remainingVars.Count -eq 0) {
    Write-Host "  Env vars:  CLEAN" -ForegroundColor Green
} else {
    Write-Host "  Env vars still set:" -ForegroundColor Red
    foreach ($v in $remainingVars) { Write-Host "    $v" -ForegroundColor Red }
}
Write-Host "  Ollama:    Uninstalled" -ForegroundColor Green
Write-Host "  PATH:      Cleaned" -ForegroundColor Green
Write-Host "============================================================" -ForegroundColor Green
Write-Host "  All space reclaimed. System restored.`n" -ForegroundColor Green
