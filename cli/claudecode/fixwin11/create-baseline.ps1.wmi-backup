$baseline = [ordered]@{
    Timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
    ComputerName = $env:COMPUTERNAME
    WiFiAdapter = Get-NetAdapter | Where-Object {$_.InterfaceDescription -match 'Wi-Fi|Wireless|WLAN'} | Select-Object Name, InterfaceDescription, Status, DriverVersion, DriverDate
    EthernetAdapter = Get-NetAdapter | Where-Object {$_.InterfaceDescription -notmatch 'Wi-Fi|Wireless|WLAN|Virtual|Hyper-V|Bluetooth|VMware|VirtualBox'} | Select-Object Name, InterfaceDescription, Status, DriverVersion
    NetworkConnected = (Get-NetAdapter | Where-Object {$_.Status -eq 'Up'}).Count
    InternetWorks = Test-NetConnection google.com -InformationLevel Quiet -WarningAction SilentlyContinue -ErrorAction SilentlyContinue
    AllDevicesOK = (Get-PnpDevice | Where-Object {$_.Status -ne 'OK'} | Measure-Object).Count -eq 0
    DeviceErrors = Get-PnpDevice | Where-Object {$_.Status -ne 'OK'} | Select-Object FriendlyName, Status, Class
    TotalDevicesOK = (Get-PnpDevice | Where-Object {$_.Status -eq 'OK'} | Measure-Object).Count
    GPU = Get-CimInstance Win32_VideoController | Select-Object Name, DriverVersion, DriverDate, Status
    RunningServicesCount = (Get-Service | Where-Object {$_.Status -eq 'Running'} | Measure-Object).Count
}

$baseline | ConvertTo-Json -Depth 5 | Out-File 'C:\SystemBaseline.json' -Encoding UTF8
Write-Host "Baseline saved to C:\SystemBaseline.json"

Write-Host "`n=== CURRENT SYSTEM STATE ===" -ForegroundColor Cyan
Write-Host "Computer: $($baseline.ComputerName)"
Write-Host "Timestamp: $($baseline.Timestamp)"
Write-Host "Network Adapters Up: $($baseline.NetworkConnected)"
Write-Host "Internet Working: $($baseline.InternetWorks)"
Write-Host "All Devices OK: $($baseline.AllDevicesOK)"
Write-Host "Total Devices OK: $($baseline.TotalDevicesOK)"
Write-Host "Running Services: $($baseline.RunningServicesCount)"

if ($baseline.DeviceErrors) {
    Write-Host "`n=== DEVICE ERRORS FOUND ===" -ForegroundColor Yellow
    $baseline.DeviceErrors | Format-Table FriendlyName, Status, Class -AutoSize
}
