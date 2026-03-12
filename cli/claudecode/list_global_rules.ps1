# List all global user-level rules from C:\users\micha\.claude\settings.json

$settingsPath = 'C:\users\micha\.claude\settings.json'

# Read current settings
$content = Get-Content $settingsPath -Raw | ConvertFrom-Json

# Show all rules
Write-Host "`nAll rules in C:\users\micha\.claude\settings.json:" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Gray

for ($i = 0; $i -lt $content.permissions.allow.Count; $i++) {
    $ruleNum = $i + 1
    $ruleText = $content.permissions.allow[$i]

    Write-Host "`n[$ruleNum]" -ForegroundColor Yellow -NoNewline
    Write-Host " $ruleText" -ForegroundColor White
}

Write-Host "`n" -NoNewline
Write-Host ("=" * 80) -ForegroundColor Gray
Write-Host "Total: $($content.permissions.allow.Count) rules" -ForegroundColor Cyan
