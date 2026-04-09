# ultrathink - Enable extended thinking with 100K budget
$s = 'C:\Users\micha\.claude\settings.json'
$j = Get-Content $s -Raw | ConvertFrom-Json
$t = [PSCustomObject]@{ enabled = $true; budgetTokens = 100000 }
if (-not $j.PSObject.Properties['thinking']) { $j | Add-Member -NotePropertyName 'thinking' -NotePropertyValue $t -Force }
else { $j.thinking = $t }
$j | ConvertTo-Json -Depth 10 | Set-Content $s -Encoding UTF8
Write-Host 'Thinking: ULTRA (100K tokens)' -ForegroundColor Magenta