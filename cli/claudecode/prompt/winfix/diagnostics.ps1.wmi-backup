# Comprehensive Windows Diagnostics Script
$ErrorActionPreference = "SilentlyContinue"
$d = (Get-Date).AddDays(-7)

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SYSTEM EVENT LOG ERRORS (7 Days)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Get-WinEvent -FilterHashtable @{LogName='System';Level=2;StartTime=$d} -MaxEvents 20 |
    Select-Object TimeCreated, Id, ProviderName, Message |
    Format-Table -Wrap -AutoSize

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "APPLICATION EVENT LOG ERRORS (7 Days)" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Get-WinEvent -FilterHashtable @{LogName='Application';Level=2;StartTime=$d} -MaxEvents 20 |
    Select-Object TimeCreated, Id, ProviderName, Message |
    Format-Table -Wrap -AutoSize

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "CRASH DUMPS CHECK" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
$minidumps = Get-ChildItem "C:\Windows\Minidump" -ErrorAction SilentlyContinue
$memorydmp = Test-Path "C:\Windows\MEMORY.DMP"
if ($minidumps) {
    Write-Host "Minidumps found: $($minidumps.Count)" -ForegroundColor Red
    $minidumps | Select-Object Name, LastWriteTime, Length | Format-Table
} else {
    Write-Host "No minidumps found (good!)" -ForegroundColor Green
}
if ($memorydmp) {
    Write-Host "MEMORY.DMP exists - indicates BSOD occurred" -ForegroundColor Red
} else {
    Write-Host "No MEMORY.DMP (good!)" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "CRITICAL SERVICES STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$criticalServices = @(
    'wuauserv',     # Windows Update
    'BITS',         # Background Intelligent Transfer
    'Dnscache',     # DNS Client
    'Winmgmt',      # WMI
    'AudioSrv',     # Windows Audio
    'Spooler',      # Print Spooler
    'EventLog',     # Windows Event Log
    'Schedule',     # Task Scheduler
    'CryptSvc',     # Cryptographic Services
    'LanmanServer', # Server
    'LanmanWorkstation', # Workstation
    'RpcSs',        # Remote Procedure Call
    'SamSs',        # Security Accounts Manager
    'netprofm',     # Network List Service
    'NlaSvc',       # Network Location Awareness
    'Dhcp',         # DHCP Client
    'W32Time',      # Windows Time
    'wscsvc',       # Security Center
    'WinDefend',    # Windows Defender
    'mpssvc'        # Windows Firewall
)

foreach ($svc in $criticalServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        $color = if ($service.Status -eq 'Running') { 'Green' } elseif ($service.Status -eq 'Stopped') { 'Red' } else { 'Yellow' }
        Write-Host "$($service.Name.PadRight(25)) $($service.Status.ToString().PadRight(10)) $($service.DisplayName)" -ForegroundColor $color
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DOCKER/WSL SERVICES" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$wslServices = @('HNS', 'vmcompute', 'LxssManager', 'docker')
foreach ($svc in $wslServices) {
    $service = Get-Service -Name $svc -ErrorAction SilentlyContinue
    if ($service) {
        $color = if ($service.Status -eq 'Running') { 'Green' } else { 'Yellow' }
        Write-Host "$($service.Name.PadRight(20)) $($service.Status)" -ForegroundColor $color
    } else {
        Write-Host "$($svc.PadRight(20)) Not Installed" -ForegroundColor Gray
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "NETWORK CONFIGURATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Get-NetIPConfiguration | Where-Object { $_.IPv4DefaultGateway } | ForEach-Object {
    Write-Host "Interface: $($_.InterfaceAlias)"
    Write-Host "  IPv4: $($_.IPv4Address.IPAddress)"
    Write-Host "  Gateway: $($_.IPv4DefaultGateway.NextHop)"
    Write-Host "  DNS: $($_.DNSServer.ServerAddresses -join ', ')"
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "DNS CACHE STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$dnsCache = Get-DnsClientCache -ErrorAction SilentlyContinue | Measure-Object
Write-Host "DNS Cache Entries: $($dnsCache.Count)"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "MEMORY STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$os = Get-WmiObject Win32_OperatingSystem
$totalMem = [math]::Round($os.TotalVisibleMemorySize/1MB, 2)
$freeMem = [math]::Round($os.FreePhysicalMemory/1MB, 2)
$usedMem = $totalMem - $freeMem
$usedPct = [math]::Round(($usedMem/$totalMem)*100, 1)
Write-Host "Total Memory: ${totalMem}GB"
Write-Host "Used: ${usedMem}GB ($usedPct%)"
Write-Host "Free: ${freeMem}GB"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "PAGEFILE CONFIGURATION" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Get-WmiObject Win32_PageFileSetting | ForEach-Object {
    Write-Host "Location: $($_.Name)"
    Write-Host "Initial Size: $($_.InitialSize)MB"
    Write-Host "Maximum Size: $($_.MaximumSize)MB"
}
$pf = Get-WmiObject Win32_PageFileUsage
Write-Host "Current Usage: $($pf.CurrentUsage)MB / $($pf.AllocatedBaseSize)MB"

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "TOP MEMORY CONSUMERS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Get-Process | Sort-Object WorkingSet64 -Descending | Select-Object -First 10 Name, @{N='MemMB';E={[math]::Round($_.WorkingSet64/1MB,0)}} | Format-Table -AutoSize

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "DRIVER ERRORS (7 Days)" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
$driverErrors = Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Microsoft-Windows-DriverFrameworks-UserMode','Microsoft-Windows-Kernel-PnP';Level=2,3;StartTime=$d} -MaxEvents 10 -ErrorAction SilentlyContinue
if ($driverErrors) {
    $driverErrors | Select-Object TimeCreated, Message | Format-Table -Wrap
} else {
    Write-Host "No driver errors found (good!)" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Yellow
Write-Host "GPU TDR EVENTS (7 Days)" -ForegroundColor Yellow
Write-Host "========================================" -ForegroundColor Yellow
$tdrEvents = Get-WinEvent -FilterHashtable @{LogName='System';ProviderName='Display';Level=2,3;StartTime=$d} -MaxEvents 5 -ErrorAction SilentlyContinue
if ($tdrEvents) {
    $tdrEvents | Select-Object TimeCreated, Message | Format-Table -Wrap
} else {
    Write-Host "No GPU TDR events found (good!)" -ForegroundColor Green
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "STARTUP PROGRAMS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Get-CimInstance Win32_StartupCommand | Select-Object Name, Command, Location | Format-Table -Wrap -AutoSize

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "FAILED SCHEDULED TASKS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Get-ScheduledTask | Where-Object { $_.State -eq 'Ready' } | ForEach-Object {
    $info = Get-ScheduledTaskInfo -TaskName $_.TaskName -TaskPath $_.TaskPath -ErrorAction SilentlyContinue
    if ($info.LastTaskResult -ne 0 -and $info.LastRunTime -gt (Get-Date).AddDays(-7)) {
        Write-Host "$($_.TaskName) - Last Result: $($info.LastTaskResult) - $($info.LastRunTime)" -ForegroundColor Yellow
    }
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "POWER PLAN" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
powercfg /getactivescheme

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "SECURE BOOT STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Confirm-SecureBootUEFI -ErrorAction SilentlyContinue
if ($?) { Write-Host "Secure Boot: ENABLED" -ForegroundColor Green } else { Write-Host "Secure Boot: DISABLED or Not Supported" -ForegroundColor Yellow }

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "WINDOWS DEFENDER STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
$mpStatus = Get-MpComputerStatus -ErrorAction SilentlyContinue
if ($mpStatus) {
    Write-Host "Antivirus Enabled: $($mpStatus.AntivirusEnabled)"
    Write-Host "Real-time Protection: $($mpStatus.RealTimeProtectionEnabled)"
    Write-Host "Definitions Updated: $($mpStatus.AntivirusSignatureLastUpdated)"
    Write-Host "Last Quick Scan: $($mpStatus.QuickScanEndTime)"
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "FIREWALL STATUS" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Get-NetFirewallProfile | Select-Object Name, Enabled | Format-Table -AutoSize

Write-Host "`nDiagnostics complete!" -ForegroundColor Green
