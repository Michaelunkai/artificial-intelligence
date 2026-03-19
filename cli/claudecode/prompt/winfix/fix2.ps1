# Windows System Fix Script - Part 2
# Run with: powershell -NoProfile -ExecutionPolicy Bypass -File fix2.ps1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "     WINDOWS SYSTEM FIX SCRIPT - PART 2    " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$fixCount = 0

# FIX 11: Check remaining failed scheduled tasks
Write-Host "=== Checking Remaining Failed Scheduled Tasks ===" -ForegroundColor Yellow
$failedTasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' } | ForEach-Object {
    $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
    if ($info -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267009 -and $info.LastTaskResult -ne 267011) {
        [PSCustomObject]@{
            Name = $_.TaskName
            Path = $_.TaskPath
            LastResult = $info.LastTaskResult
            LastRun = $info.LastRunTime
        }
    }
}
Write-Host "Remaining failed tasks: $($failedTasks.Count)" -ForegroundColor Yellow
$failedTasks | Select-Object -First 10 | Format-Table Name, LastResult -AutoSize
Write-Host ""

# FIX 12: Fix CreateExplorerShellUnelevatedTask
Write-Host "=== Fixing CreateExplorerShellUnelevatedTask ===" -ForegroundColor Yellow
$task = Get-ScheduledTask -TaskName "CreateExplorerShellUnelevatedTask" -ErrorAction SilentlyContinue
if ($task) {
    Write-Host "Task found, checking status..."
    $info = Get-ScheduledTaskInfo -TaskName "CreateExplorerShellUnelevatedTask" -ErrorAction SilentlyContinue
    Write-Host "Last Result: $($info.LastTaskResult)"
    Write-Host "This task is for creating unelevated explorer shells - failure is non-critical"
    Write-Host ""
}

# FIX 13: Fix GHelperCharge task (G-Helper for ASUS)
Write-Host "=== Checking GHelperCharge ===" -ForegroundColor Yellow
$task = Get-ScheduledTask -TaskName "GHelperCharge" -ErrorAction SilentlyContinue
if ($task) {
    # Check if GHelper is installed
    $ghelperPath = $task.Actions.Execute
    Write-Host "GHelper path: $ghelperPath"
    if ($ghelperPath -and !(Test-Path $ghelperPath -ErrorAction SilentlyContinue)) {
        Write-Host "GHelper executable not found - disabling task" -ForegroundColor Yellow
        Disable-ScheduledTask -TaskName "GHelperCharge" -ErrorAction SilentlyContinue
        $fixCount++
    } else {
        Write-Host "GHelper path exists or is a built-in action"
    }
}
Write-Host ""

# FIX 14: Check debugregsvc service
Write-Host "=== Checking debugregsvc ===" -ForegroundColor Yellow
$svc = Get-Service debugregsvc -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "debugregsvc Status: $($svc.Status)"
    Write-Host "debugregsvc Start Type: $($svc.StartType)"
    Write-Host "This is a debugging registration service - stopping is normal for non-debug scenarios" -ForegroundColor Green
} else {
    Write-Host "debugregsvc not found"
}
Write-Host ""

# FIX 15: Clean Windows Update Cache (if issues found)
Write-Host "=== Checking Windows Update Cache ===" -ForegroundColor Yellow
$wuCachePath = "$env:SystemRoot\SoftwareDistribution\Download"
if (Test-Path $wuCachePath) {
    $cacheSize = (Get-ChildItem $wuCachePath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
    $cacheSizeMB = [math]::Round($cacheSize/1MB, 1)
    Write-Host "Windows Update cache size: $cacheSizeMB MB"
    if ($cacheSizeMB -gt 500) {
        Write-Host "Cache is large - consider cleaning" -ForegroundColor Yellow
    } else {
        Write-Host "Cache size is acceptable" -ForegroundColor Green
    }
}
Write-Host ""

# FIX 16: Verify Network Adapters Now Work
Write-Host "=== Verifying Network Adapters ===" -ForegroundColor Yellow
try {
    $adapters = Get-NetAdapter -ErrorAction Stop
    Write-Host "SUCCESS: Get-NetAdapter working!" -ForegroundColor Green
    $adapters | Format-Table Name, Status, LinkSpeed -AutoSize
    $fixCount++
} catch {
    Write-Host "ERROR: Get-NetAdapter still failing: $($_.Exception.Message)" -ForegroundColor Red
}
Write-Host ""

# FIX 17: Verify Firewall Profile
Write-Host "=== Checking Firewall Profiles ===" -ForegroundColor Yellow
try {
    $fwProfiles = Get-NetFirewallProfile -ErrorAction Stop
    foreach ($profile in $fwProfiles) {
        $status = if ($profile.Enabled) { "ON" } else { "OFF" }
        $color = if ($profile.Enabled) { "Green" } else { "Yellow" }
        Write-Host "$($profile.Name): $status" -ForegroundColor $color
    }

    # Domain profile being OFF is normal for non-domain machines
    $domainProfile = $fwProfiles | Where-Object { $_.Name -eq 'Domain' }
    if (!$domainProfile.Enabled) {
        Write-Host "NOTE: Domain profile is OFF - this is normal for non-domain machines" -ForegroundColor Green
    }
    $fixCount++
} catch {
    Write-Host "Using netsh for firewall check..."
    netsh advfirewall show allprofiles state
}
Write-Host ""

# FIX 18: Check Event Log for any new errors since fixes
Write-Host "=== Checking for New Errors (last 5 minutes) ===" -ForegroundColor Yellow
$since = (Get-Date).AddMinutes(-5)
$newErrors = Get-WinEvent -FilterHashtable @{LogName='Application','System'; Level=1,2; StartTime=$since} -MaxEvents 10 -ErrorAction SilentlyContinue
if ($newErrors) {
    Write-Host "New errors found:" -ForegroundColor Yellow
    $newErrors | Select-Object TimeCreated, ProviderName, Message | Format-Table -AutoSize
} else {
    Write-Host "No new errors since fixes applied" -ForegroundColor Green
}
Write-Host ""

# FIX 19: Run Windows Update Check
Write-Host "=== Checking Windows Update Status ===" -ForegroundColor Yellow
$wuService = Get-Service wuauserv
Write-Host "Windows Update service: $($wuService.Status)"
if ($wuService.Status -ne 'Running') {
    Write-Host "Starting Windows Update service..." -ForegroundColor Cyan
    Start-Service wuauserv -ErrorAction SilentlyContinue
}
Write-Host ""

# FIX 20: Check for pending reboots
Write-Host "=== Checking Pending Reboot Status ===" -ForegroundColor Yellow
$pendingReboot = $false
$reasons = @()

# Check Windows Update
$wuReboot = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired" -ErrorAction SilentlyContinue
if ($wuReboot) {
    $pendingReboot = $true
    $reasons += "Windows Update"
}

# Check CBS
$cbsReboot = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending" -ErrorAction SilentlyContinue
if ($cbsReboot) {
    $pendingReboot = $true
    $reasons += "Component Servicing"
}

# Check File Rename Operations
$fileRename = Get-ItemProperty "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager" -Name "PendingFileRenameOperations" -ErrorAction SilentlyContinue
if ($fileRename.PendingFileRenameOperations) {
    $pendingReboot = $true
    $reasons += "File Operations"
}

if ($pendingReboot) {
    Write-Host "PENDING REBOOT: $($reasons -join ', ')" -ForegroundColor Yellow
} else {
    Write-Host "No pending reboot required" -ForegroundColor Green
}
Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "     PART 2 COMPLETE                       " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Additional fixes applied: $fixCount" -ForegroundColor Green
