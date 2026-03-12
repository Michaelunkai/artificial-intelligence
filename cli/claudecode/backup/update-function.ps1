# Update backclau function to use perfect backup
$profilePath = "$env:USERPROFILE\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"
$content = Get-Content $profilePath -Raw
$newContent = $content -replace 'backup-claudecode\.ps1', 'perfect-backup-claudecode.ps1'
$newContent | Out-File -FilePath $profilePath -Encoding UTF8 -Force
Write-Host "Updated backclau function to use perfect backup script" -ForegroundColor Green