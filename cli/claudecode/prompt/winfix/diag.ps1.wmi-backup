# Windows System Diagnostic Script
# Run with: powershell -NoProfile -ExecutionPolicy Bypass -File diag.ps1

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "     WINDOWS SYSTEM DIAGNOSTIC REPORT      " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""

# SECTION 1: System Baseline
Write-Host "=== SYSTEM BASELINE ===" -ForegroundColor Yellow
$os = Get-CimInstance Win32_OperatingSystem
$cs = Get-CimInstance Win32_ComputerSystem
$cpu = Get-CimInstance Win32_Processor
Write-Host "OS: $($os.Caption) $($os.Version)"
Write-Host "Build: $($os.BuildNumber)"
Write-Host "Install Date: $($os.InstallDate)"
Write-Host "Last Boot: $($os.LastBootUpTime)"
$uptime = (Get-Date) - $os.LastBootUpTime
Write-Host "Uptime: $($uptime.Days) days $($uptime.Hours) hours $($uptime.Minutes) minutes"
Write-Host "Computer: $($cs.Name)"
Write-Host "CPU: $($cpu.Name)"
Write-Host "Cores: $($cpu.NumberOfCores) | Logical Processors: $($cpu.NumberOfLogicalProcessors)"
Write-Host "RAM: $([math]::Round($cs.TotalPhysicalMemory/1GB,1)) GB"
Write-Host ""

# SECTION 2: Application Log Errors (7 days)
Write-Host "=== APPLICATION LOG ERRORS (7 days) ===" -ForegroundColor Yellow
$startDate = (Get-Date).AddDays(-7)
try {
    $appErrors = Get-WinEvent -FilterHashtable @{LogName='Application'; Level=1,2; StartTime=$startDate} -MaxEvents 100 -ErrorAction Stop
    if ($appErrors) {
        Write-Host "Total Application Errors/Critical: $($appErrors.Count)" -ForegroundColor Red
        $appErrors | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object Count, Name -First 10 | Format-Table -AutoSize
    }
} catch {
    Write-Host "No critical/error events found in Application log" -ForegroundColor Green
}
Write-Host ""

# SECTION 3: System Log Errors (7 days)
Write-Host "=== SYSTEM LOG ERRORS (7 days) ===" -ForegroundColor Yellow
try {
    $sysErrors = Get-WinEvent -FilterHashtable @{LogName='System'; Level=1,2; StartTime=$startDate} -MaxEvents 100 -ErrorAction Stop
    if ($sysErrors) {
        Write-Host "Total System Errors/Critical: $($sysErrors.Count)" -ForegroundColor Red
        $sysErrors | Group-Object ProviderName | Sort-Object Count -Descending | Select-Object Count, Name -First 10 | Format-Table -AutoSize
    }
} catch {
    Write-Host "No critical/error events found in System log" -ForegroundColor Green
}
Write-Host ""

# SECTION 4: Kernel Power / BSOD Check (30 days)
Write-Host "=== KERNEL POWER / BSOD CHECK (30 days) ===" -ForegroundColor Yellow
$startDate30 = (Get-Date).AddDays(-30)
try {
    $kpEvents = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-Kernel-Power'; Id=41; StartTime=$startDate30} -MaxEvents 10 -ErrorAction Stop
    Write-Host "WARNING: Found $($kpEvents.Count) unexpected shutdown events!" -ForegroundColor Red
    $kpEvents | Select-Object TimeCreated, @{N='BugcheckCode';E={$_.Properties[0].Value}} | Format-Table -AutoSize
} catch {
    Write-Host "No unexpected shutdowns (Event 41) in last 30 days" -ForegroundColor Green
}

try {
    $bsodEvents = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-WER-SystemErrorReporting'; StartTime=$startDate30} -MaxEvents 10 -ErrorAction Stop
    Write-Host "WARNING: Found $($bsodEvents.Count) BSOD/crash events!" -ForegroundColor Red
} catch {
    Write-Host "No BSOD crash reports in last 30 days" -ForegroundColor Green
}
Write-Host ""

# SECTION 5: Services Status
Write-Host "=== WINDOWS SERVICES STATUS ===" -ForegroundColor Yellow
$criticalServices = @('wuauserv','BITS','Dnscache','Dhcp','LanmanWorkstation','LanmanServer',
    'Spooler','Audiosrv','Themes','ShellHWDetection','PlugPlay','RpcSs','EventSystem',
    'SENS','WSearch','SysMain','DiagTrack','WinDefend','mpssvc','CryptSvc','DcomLaunch',
    'Schedule','W32Time','lfsvc','DeviceAssociationService','AppReadiness','StateRepository',
    'StorSvc','WerSvc','SecurityHealthService')

$stoppedCritical = @()
$failedServices = @()

foreach ($svc in $criticalServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        if ($service.Status -ne 'Running' -and $service.StartType -eq 'Automatic') {
            $stoppedCritical += "$svc ($($service.Status))"
        }
    }
}

# Check for any failed/crashed services
$allServices = Get-Service | Where-Object { $_.Status -eq 'Stopped' -and $_.StartType -eq 'Automatic' }
foreach ($svc in $allServices) {
    $failedServices += "$($svc.Name) ($($svc.DisplayName))"
}

if ($stoppedCritical.Count -gt 0) {
    Write-Host "CRITICAL SERVICES NOT RUNNING:" -ForegroundColor Red
    $stoppedCritical | ForEach-Object { Write-Host "  - $_" -ForegroundColor Red }
} else {
    Write-Host "All critical services running" -ForegroundColor Green
}

if ($failedServices.Count -gt 0) {
    Write-Host "Automatic services that are stopped ($($failedServices.Count)):" -ForegroundColor Yellow
    $failedServices | Select-Object -First 15 | ForEach-Object { Write-Host "  - $_" }
}
Write-Host ""

# SECTION 6: Disk Health
Write-Host "=== DISK HEALTH ===" -ForegroundColor Yellow
try {
    $disks = Get-CimInstance Win32_DiskDrive
    foreach ($disk in $disks) {
        Write-Host "Disk: $($disk.Model) | Size: $([math]::Round($disk.Size/1GB,1)) GB | Status: $($disk.Status)"
    }
} catch {
    Write-Host "Could not retrieve disk information"
}

# Disk Space
Write-Host ""
Write-Host "Disk Space:" -ForegroundColor Yellow
$volumes = Get-CimInstance Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
foreach ($vol in $volumes) {
    $freeGB = [math]::Round($vol.FreeSpace/1GB,1)
    $totalGB = [math]::Round($vol.Size/1GB,1)
    $usedPercent = [math]::Round(($vol.Size - $vol.FreeSpace)/$vol.Size * 100, 1)
    $color = if ($usedPercent -gt 90) { "Red" } elseif ($usedPercent -gt 80) { "Yellow" } else { "Green" }
    Write-Host "  $($vol.DeviceID) $freeGB GB free / $totalGB GB total ($usedPercent% used)" -ForegroundColor $color
}
Write-Host ""

# SECTION 7: Memory Status
Write-Host "=== MEMORY STATUS ===" -ForegroundColor Yellow
$mem = Get-CimInstance Win32_OperatingSystem
$totalMem = [math]::Round($mem.TotalVisibleMemorySize/1MB,1)
$freeMem = [math]::Round($mem.FreePhysicalMemory/1MB,1)
$usedMem = $totalMem - $freeMem
$memPercent = [math]::Round($usedMem/$totalMem * 100, 1)
Write-Host "Physical Memory: $usedMem GB used / $totalMem GB total ($memPercent% used)"

# Page File
$pagefile = Get-CimInstance Win32_PageFileUsage -ErrorAction SilentlyContinue
if ($pagefile) {
    Write-Host "Page File: $($pagefile.CurrentUsage) MB used / $($pagefile.AllocatedBaseSize) MB allocated"
}
Write-Host ""

# SECTION 8: Network Status
Write-Host "=== NETWORK STATUS ===" -ForegroundColor Yellow
$adapters = Get-NetAdapter | Where-Object { $_.Status -eq 'Up' }
foreach ($adapter in $adapters) {
    Write-Host "  $($adapter.Name): $($adapter.InterfaceDescription) - $($adapter.LinkSpeed)"
}

# DNS Check
$dns = Get-DnsClientServerAddress -AddressFamily IPv4 | Where-Object { $_.ServerAddresses } | Select-Object -First 1
if ($dns) {
    Write-Host "DNS Servers: $($dns.ServerAddresses -join ', ')"
}
Write-Host ""

# SECTION 9: Driver Problems
Write-Host "=== DRIVER STATUS ===" -ForegroundColor Yellow
$problemDrivers = Get-CimInstance Win32_PnPEntity | Where-Object { $_.ConfigManagerErrorCode -ne 0 }
if ($problemDrivers) {
    Write-Host "PROBLEM DEVICES FOUND: $($problemDrivers.Count)" -ForegroundColor Red
    $problemDrivers | Select-Object Name, @{N='ErrorCode';E={$_.ConfigManagerErrorCode}} | Format-Table -AutoSize
} else {
    Write-Host "No driver problems detected" -ForegroundColor Green
}
Write-Host ""

# SECTION 10: Windows Update Status
Write-Host "=== WINDOWS UPDATE STATUS ===" -ForegroundColor Yellow
try {
    $wu = Get-Service wuauserv
    Write-Host "Windows Update Service: $($wu.Status)"

    # Recent update history
    $session = New-Object -ComObject Microsoft.Update.Session
    $searcher = $session.CreateUpdateSearcher()
    $historyCount = $searcher.GetTotalHistoryCount()
    $history = $searcher.QueryHistory(0, [math]::Min(5, $historyCount))
    Write-Host "Recent Updates:"
    foreach ($update in $history) {
        $result = switch ($update.ResultCode) { 2 { "Success" } 4 { "Failed" } default { "Other" } }
        Write-Host "  [$result] $($update.Date.ToString('yyyy-MM-dd')) - $($update.Title.Substring(0, [math]::Min(60, $update.Title.Length)))..."
    }
} catch {
    Write-Host "Could not retrieve Windows Update information"
}
Write-Host ""

# SECTION 11: DCOM Errors
Write-Host "=== DCOM/COM+ ERRORS ===" -ForegroundColor Yellow
try {
    $dcomErrors = Get-WinEvent -FilterHashtable @{LogName='System'; ProviderName='Microsoft-Windows-DistributedCOM'; Level=2,3; StartTime=$startDate} -MaxEvents 20 -ErrorAction Stop
    Write-Host "DCOM Errors found: $($dcomErrors.Count)" -ForegroundColor Yellow
    $dcomErrors | Group-Object Id | Select-Object Count, Name | Format-Table -AutoSize
} catch {
    Write-Host "No DCOM errors in last 7 days" -ForegroundColor Green
}
Write-Host ""

# SECTION 12: Startup Programs
Write-Host "=== STARTUP PROGRAMS ===" -ForegroundColor Yellow
$startupRun = Get-ItemProperty "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
$startupRunUser = Get-ItemProperty "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run" -ErrorAction SilentlyContinue
$startupCount = ($startupRun.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
$startupCount += ($startupRunUser.PSObject.Properties | Where-Object { $_.Name -notlike 'PS*' }).Count
Write-Host "Startup programs: $startupCount"
Write-Host ""

# SECTION 13: Scheduled Task Failures
Write-Host "=== SCHEDULED TASK FAILURES ===" -ForegroundColor Yellow
$failedTasks = Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' } | ForEach-Object {
    $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
    if ($info -and $info.LastTaskResult -ne 0 -and $info.LastTaskResult -ne 267009) {
        [PSCustomObject]@{
            Name = $_.TaskName
            LastResult = $info.LastTaskResult
            LastRun = $info.LastRunTime
        }
    }
} | Where-Object { $_ -ne $null }

if ($failedTasks) {
    Write-Host "Failed Tasks: $($failedTasks.Count)" -ForegroundColor Yellow
    $failedTasks | Select-Object -First 10 | Format-Table -AutoSize
} else {
    Write-Host "No failed scheduled tasks" -ForegroundColor Green
}
Write-Host ""

# SECTION 14: Windows Defender Status
Write-Host "=== WINDOWS DEFENDER STATUS ===" -ForegroundColor Yellow
try {
    $defender = Get-MpComputerStatus -ErrorAction Stop
    Write-Host "Real-time Protection: $(if ($defender.RealTimeProtectionEnabled) {'Enabled'} else {'DISABLED'})" -ForegroundColor $(if ($defender.RealTimeProtectionEnabled) {'Green'} else {'Red'})
    Write-Host "Antivirus Signature: $($defender.AntivirusSignatureLastUpdated)"
    Write-Host "Last Quick Scan: $($defender.QuickScanEndTime)"
} catch {
    Write-Host "Could not retrieve Defender status"
}
Write-Host ""

# SECTION 15: Firewall Status
Write-Host "=== FIREWALL STATUS ===" -ForegroundColor Yellow
$fwProfiles = Get-NetFirewallProfile
foreach ($profile in $fwProfiles) {
    $status = if ($profile.Enabled) { "Enabled" } else { "DISABLED" }
    $color = if ($profile.Enabled) { "Green" } else { "Red" }
    Write-Host "$($profile.Name) Profile: $status" -ForegroundColor $color
}
Write-Host ""

# SECTION 16: Temp Folder Sizes
Write-Host "=== TEMP FOLDER SIZES ===" -ForegroundColor Yellow
$tempPaths = @(
    "$env:TEMP",
    "$env:WINDIR\Temp",
    "$env:LOCALAPPDATA\Microsoft\Windows\INetCache"
)
foreach ($path in $tempPaths) {
    if (Test-Path $path) {
        $size = (Get-ChildItem $path -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum
        $sizeGB = [math]::Round($size/1GB,2)
        $sizeMB = [math]::Round($size/1MB,0)
        Write-Host "  $path : $sizeMB MB"
    }
}
Write-Host ""

# SECTION 17: Visual C++ Redistributables
Write-Host "=== VISUAL C++ REDISTRIBUTABLES ===" -ForegroundColor Yellow
$vcRedists = Get-ItemProperty HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*, HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\* -ErrorAction SilentlyContinue |
    Where-Object { $_.DisplayName -like "*Visual C++*Redistributable*" } |
    Select-Object DisplayName, DisplayVersion |
    Sort-Object DisplayName
Write-Host "Installed VC++ Redistributables: $($vcRedists.Count)"
Write-Host ""

# SECTION 18: .NET Framework Versions
Write-Host "=== .NET FRAMEWORK ===" -ForegroundColor Yellow
$netVersions = Get-ChildItem 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP' -Recurse -ErrorAction SilentlyContinue |
    Get-ItemProperty -Name Version -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty Version -Unique |
    Sort-Object
Write-Host ".NET Versions: $($netVersions -join ', ')"
Write-Host ""

# SECTION 19: Power Plan
Write-Host "=== POWER PLAN ===" -ForegroundColor Yellow
$powerPlan = powercfg /getactivescheme
Write-Host $powerPlan
Write-Host ""

# SECTION 20: Boot Configuration
Write-Host "=== BOOT CONFIGURATION ===" -ForegroundColor Yellow
$bootConfig = bcdedit /enum {current} 2>$null
if ($bootConfig) {
    $bootConfig | Select-String "identifier|device|path|recoveryenabled" | ForEach-Object { Write-Host $_ }
}
Write-Host ""

Write-Host "============================================" -ForegroundColor Cyan
Write-Host "     DIAGNOSTIC SCAN COMPLETE              " -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
