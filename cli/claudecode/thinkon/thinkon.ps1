# thinkon - Enable thinking mode
$s = 'C:\Users\micha\.claude\settings.json'
$j = Get-Content $s -Raw | ConvertFrom-Json
if (-not $j.PSObject.Properties['thinking']) { $j | Add-Member -NotePropertyName 'thinking' -NotePropertyValue ([PSCustomObject]@{ enabled = $true }) -Force }
else { $j.thinking = [PSCustomObject]@{ enabled = $true } }
$j | ConvertTo-Json -Depth 10 | Set-Content $s -Encoding UTF8
Write-Host 'Thinking: ON' -ForegroundColor Green