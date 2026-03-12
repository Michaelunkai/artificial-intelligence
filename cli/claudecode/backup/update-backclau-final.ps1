# Update backclau function to use the fixed perfect backup
$profileContent = @'
function backclau {
    & "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\perfect-backup-fixed.ps1" @args
}
'@

$profilePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$profileContent | Out-File -FilePath $profilePath -Encoding UTF8 -Force

Write-Host "Updated backclau function to use the fixed perfect backup script" -ForegroundColor Green