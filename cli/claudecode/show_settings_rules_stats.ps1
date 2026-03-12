$content = Get-Content 'C:\users\micha\.claude\settings.json' -Raw | ConvertFrom-Json
$rules = $content.permissions.allow.Count
Write-Host "C:\users\micha\.claude\settings.json: $rules total rules"
