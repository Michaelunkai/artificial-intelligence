Write-Host "=== DISK SPACE ===" -ForegroundColor Cyan
Get-WmiObject Win32_LogicalDisk -Filter "DriveType=3" | ForEach-Object {
    $sizeGB = [math]::Round($_.Size/1GB,2)
    $freeGB = [math]::Round($_.FreeSpace/1GB,2)
    $usedPct = [math]::Round((($_.Size-$_.FreeSpace)/$_.Size)*100,1)
    Write-Host "$($_.DeviceID) $($_.VolumeName) - Size: ${sizeGB}GB, Free: ${freeGB}GB, Used: ${usedPct}%"
}
