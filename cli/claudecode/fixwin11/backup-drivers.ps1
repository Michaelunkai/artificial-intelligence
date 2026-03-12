$timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$driverBackup = "C:\DriversBackup-$timestamp"
New-Item -ItemType Directory -Path $driverBackup -Force | Out-Null
Export-WindowsDriver -Online -Destination $driverBackup
Write-Host "SUCCESS: Drivers backed up to: $driverBackup"
