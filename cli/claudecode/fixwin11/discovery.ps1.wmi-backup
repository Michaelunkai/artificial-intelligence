Write-Host "`n=== PHASE 1: DISCOVERY (NO CHANGES) ===" -ForegroundColor Cyan

Write-Host "`n--- Hardware Info ---" -ForegroundColor Yellow
Get-CimInstance Win32_Processor | Select-Object Name, NumberOfCores, NumberOfLogicalProcessors | Format-List
Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, Status | Format-List
$ramGB = [math]::Round(((Get-CimInstance Win32_PhysicalMemory | Measure-Object Capacity -Sum).Sum / 1GB), 2)
Write-Host "Total RAM: $ramGB GB"
Get-CimInstance Win32_DiskDrive | Select-Object Model, MediaType, Status, @{Name="Size(GB)";Expression={[math]::Round($_.Size/1GB,2)}} | Format-Table -AutoSize

Write-Host "`n--- Network Adapters (DO NOT TOUCH) ---" -ForegroundColor Yellow
Get-WmiObject Win32_NetworkAdapter | Where-Object {$_.NetConnectionStatus -ne $null} | Select-Object Name, NetConnectionStatus, @{Name="Driver";Expression={$_.Name}} | Format-Table -AutoSize

Write-Host "`n--- All Devices Summary ---" -ForegroundColor Yellow
Get-PnpDevice | Where-Object {$_.Status -eq 'OK'} | Group-Object Class | Select-Object Count, Name | Sort-Object Count -Descending | Select-Object -First 20

Write-Host "`n--- Software Check ---" -ForegroundColor Yellow
$pythonVer = python --version 2>&1
$pipVer = pip --version 2>&1
$nodeVer = node --version 2>&1
$npmVer = npm --version 2>&1
$dockerVer = docker --version 2>&1

Write-Host "Python: $pythonVer"
Write-Host "Pip: $pipVer"
Write-Host "Node: $nodeVer"
Write-Host "NPM: $npmVer"
Write-Host "Docker: $dockerVer"

Write-Host "`n--- Docker/WSL Status ---" -ForegroundColor Yellow
wsl --list --verbose
