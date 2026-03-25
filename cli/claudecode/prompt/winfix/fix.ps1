# Windows System Fix Script
# Run with: powershell -NoProfile -ExecutionPolicy Bypass -File fix.ps1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "     WINDOWS SYSTEM FIX SCRIPT             " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

$fixCount = 0
$skipCount = 0

# FIX 1: LanmanWorkstation Service (fixes VSS errors)
Write-Host "=== FIX 1: LanmanWorkstation Service ===" -ForegroundColor Yellow
$svc = Get-Service LanmanWorkstation -ErrorAction SilentlyContinue
Write-Host "Current Status: $($svc.Status)"
Write-Host "Start Type: $($svc.StartType)"
if ($svc.Status -ne 'Running') {
    Write-Host "Starting service..." -ForegroundColor Cyan
    try {
        Start-Service LanmanWorkstation -ErrorAction Stop
        Start-Sleep -Seconds 2
        $svc = Get-Service LanmanWorkstation
        if ($svc.Status -eq 'Running') {
            Write-Host "SUCCESS: Service started" -ForegroundColor Green
            $fixCount++
        } else {
            Write-Host "WARNING: Service did not start" -ForegroundColor Yellow
        }
    } catch {
        Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
    }
} else {
    Write-Host "Service already running" -ForegroundColor Green
    $skipCount++
}
Write-Host ""

# FIX 2: Group Policy Service
Write-Host "=== FIX 2: Group Policy Service (gpsvc) ===" -ForegroundColor Yellow
$svc = Get-Service gpsvc -ErrorAction SilentlyContinue
Write-Host "Current Status: $($svc.Status)"
Write-Host "Start Type: $($svc.StartType)"
# gpsvc is trigger-start, don't force start
if ($svc.StartType -eq 'Automatic (Trigger Start)' -or $svc.StartType -eq 'Automatic') {
    Write-Host "NOTE: gpsvc is trigger-started, will start when needed" -ForegroundColor Green
    $skipCount++
} else {
    Write-Host "NOTE: Service configured as $($svc.StartType)" -ForegroundColor Yellow
}
Write-Host ""

# FIX 3: Software Protection Service
Write-Host "=== FIX 3: Software Protection Service (sppsvc) ===" -ForegroundColor Yellow
$svc = Get-Service sppsvc -ErrorAction SilentlyContinue
Write-Host "Current Status: $($svc.Status)"
Write-Host "Start Type: $($svc.StartType)"
Write-Host "NOTE: sppsvc is demand-start for license checks - stopped is normal" -ForegroundColor Green
$skipCount++
Write-Host ""

# FIX 4: Windows Biometric Service
Write-Host "=== FIX 4: Windows Biometric Service (WbioSrvc) ===" -ForegroundColor Yellow
$svc = Get-Service WbioSrvc -ErrorAction SilentlyContinue
if ($svc) {
    Write-Host "Current Status: $($svc.Status)"
    Write-Host "Start Type: $($svc.StartType)"
    if ($svc.Status -ne 'Running' -and $svc.StartType -eq 'Automatic') {
        Write-Host "Starting service..." -ForegroundColor Cyan
        try {
            Start-Service WbioSrvc -ErrorAction Stop
            Start-Sleep -Seconds 2
            $svc = Get-Service WbioSrvc
            if ($svc.Status -eq 'Running') {
                Write-Host "SUCCESS: Service started" -ForegroundColor Green
                $fixCount++
            }
        } catch {
            Write-Host "NOTE: Service may not be needed without biometric hardware" -ForegroundColor Yellow
            $skipCount++
        }
    } else {
        Write-Host "Service already running or not auto-start" -ForegroundColor Green
        $skipCount++
    }
} else {
    Write-Host "Service not installed" -ForegroundColor Yellow
}
Write-Host ""

# FIX 5: Re-register Network WMI Classes
Write-Host "=== FIX 5: Re-registering Network WMI Classes ===" -ForegroundColor Yellow
Write-Host "Checking NetAdapter WMI class..." -ForegroundColor Cyan
try {
    $netAdapters = Get-CimInstance -ClassName MSFT_NetAdapter -Namespace root/StandardCimv2 -ErrorAction Stop
    Write-Host "SUCCESS: NetAdapter WMI class is working ($($netAdapters.Count) adapters)" -ForegroundColor Green
    $skipCount++
} catch {
    Write-Host "NetAdapter WMI class not available - attempting repair..." -ForegroundColor Yellow

    # Try to re-register the network MOF files
    $mofPath = "$env:SystemRoot\System32\wbem"
    $networkMofs = @(
        "NetAdapterCim.mof",
        "NetAdapterCim.mfl",
        "NetEventPacketCapture.mof",
        "NetNat.mof",
        "NetSwitchTeam.mof",
        "NetTCPIP.mof",
        "MsNetImPlatform.mof"
    )

    foreach ($mof in $networkMofs) {
        $mofFile = Join-Path $mofPath $mof
        if (Test-Path $mofFile) {
            Write-Host "Registering $mof..." -ForegroundColor Cyan
            mofcomp $mofFile 2>$null | Out-Null
        }
    }

    # Restart WMI service
    Write-Host "Restarting WMI service..." -ForegroundColor Cyan
    Restart-Service Winmgmt -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    # Test again
    try {
        $netAdapters = Get-CimInstance -ClassName MSFT_NetAdapter -Namespace root/StandardCimv2 -ErrorAction Stop
        Write-Host "SUCCESS: NetAdapter WMI class repaired!" -ForegroundColor Green
        $fixCount++
    } catch {
        Write-Host "WARNING: WMI class still not available - may need reboot" -ForegroundColor Yellow
    }
}
Write-Host ""

# FIX 6: Disable Orphaned Scheduled Tasks
Write-Host "=== FIX 6: Analyzing Failed Scheduled Tasks ===" -ForegroundColor Yellow
$failedTasks = @()
$tasksToDisable = @()

Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' } | ForEach-Object {
    $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
    if ($info -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267009 -and $info.LastTaskResult -ne 267011) {
        # Check if this is an orphaned task (executable missing)
        $actions = $_.Actions
        $isOrphaned = $false
        foreach ($action in $actions) {
            if ($action.Execute -and !(Test-Path $action.Execute -ErrorAction SilentlyContinue)) {
                $isOrphaned = $true
            }
        }

        $failedTasks += [PSCustomObject]@{
            Name = $_.TaskName
            Path = $_.TaskPath
            LastResult = $info.LastTaskResult
            IsOrphaned = $isOrphaned
        }
    }
}

Write-Host "Found $($failedTasks.Count) failed tasks" -ForegroundColor Yellow

# List critical failed tasks (excluding known benign ones)
$benignTasks = @('RecoverabilityToastTask', 'AD RMS Rights Policy Template Management', 'EDP Policy Manager')
$criticalFailed = $failedTasks | Where-Object { $_.Name -notin $benignTasks } | Select-Object -First 10

if ($criticalFailed.Count -gt 0) {
    Write-Host "Top failed tasks:" -ForegroundColor Yellow
    $criticalFailed | Format-Table Name, LastResult -AutoSize

    # Disable orphaned tasks only (safe)
    $orphaned = $failedTasks | Where-Object { $_.IsOrphaned -eq $true }
    foreach ($task in $orphaned) {
        Write-Host "Disabling orphaned task: $($task.Name)" -ForegroundColor Cyan
        try {
            Disable-ScheduledTask -TaskName $task.Name -TaskPath $task.Path -ErrorAction SilentlyContinue | Out-Null
            $fixCount++
        } catch {
            Write-Host "  Could not disable: $($_.Exception.Message)" -ForegroundColor Yellow
        }
    }
} else {
    Write-Host "No critical failed tasks requiring action" -ForegroundColor Green
}
Write-Host ""

# FIX 7: Verify VSS is working now
Write-Host "=== FIX 7: Verifying VSS Service ===" -ForegroundColor Yellow
$vss = Get-Service VSS -ErrorAction SilentlyContinue
Write-Host "VSS Service Status: $($vss.Status)"
vssadmin list writers 2>&1 | Select-Object -First 5
Write-Host ""

# FIX 8: Check and fix Firewall
Write-Host "=== FIX 8: Checking Firewall ===" -ForegroundColor Yellow
try {
    $fwStatus = netsh advfirewall show allprofiles state
    Write-Host $fwStatus
    if ($fwStatus -match "State\s+OFF") {
        Write-Host "WARNING: Some firewall profiles are OFF" -ForegroundColor Yellow
    } else {
        Write-Host "Firewall profiles are enabled" -ForegroundColor Green
        $skipCount++
    }
} catch {
    Write-Host "Could not check firewall status via netsh" -ForegroundColor Yellow
}
Write-Host ""

# FIX 9: Check WSL
Write-Host "=== FIX 9: Checking WSL ===" -ForegroundColor Yellow
$wslInstalled = Get-Command wsl -ErrorAction SilentlyContinue
if ($wslInstalled) {
    Write-Host "WSL is installed" -ForegroundColor Green
    wsl --status 2>&1 | Select-Object -First 5
} else {
    Write-Host "WSL not installed" -ForegroundColor Yellow
}
Write-Host ""

# FIX 10: Check Docker/Hyper-V
Write-Host "=== FIX 10: Checking Docker/Hyper-V ===" -ForegroundColor Yellow
$hvEnabled = (Get-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -ErrorAction SilentlyContinue).State
if ($hvEnabled -eq 'Enabled') {
    Write-Host "Hyper-V is enabled" -ForegroundColor Green
} else {
    Write-Host "Hyper-V not enabled" -ForegroundColor Yellow
}

$dockerService = Get-Service com.docker.service -ErrorAction SilentlyContinue
if ($dockerService) {
    Write-Host "Docker service status: $($dockerService.Status)" -ForegroundColor $(if ($dockerService.Status -eq 'Running') {'Green'} else {'Yellow'})
} else {
    Write-Host "Docker not installed" -ForegroundColor Yellow
}
Write-Host ""

# Summary
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "     FIX SCRIPT COMPLETE                   " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "Fixes applied: $fixCount" -ForegroundColor Green
Write-Host "Skipped (already OK): $skipCount" -ForegroundColor Yellow
