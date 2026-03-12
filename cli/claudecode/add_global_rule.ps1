# Add new global user-level rule to C:\users\micha\.claude\settings.json

param(
    [Parameter(Mandatory=$true)]
    [string]$NewRule
)

$settingsPath = 'C:\users\micha\.claude\settings.json'

# Read current settings
$content = Get-Content $settingsPath -Raw | ConvertFrom-Json

# Add new rule to permissions.allow array
$content.permissions.allow += $NewRule

# Backup original
Copy-Item $settingsPath "$settingsPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Write updated settings
$content | ConvertTo-Json -Depth 10 | Set-Content $settingsPath

# Show confirmation
$totalRules = $content.permissions.allow.Count
Write-Host "✅ Rule added successfully!" -ForegroundColor Green
Write-Host "C:\users\micha\.claude\settings.json: $totalRules total rules" -ForegroundColor Cyan
Write-Host "`nNew rule:" -ForegroundColor Yellow
Write-Host $NewRule
