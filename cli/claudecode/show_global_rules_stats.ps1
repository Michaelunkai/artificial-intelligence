$lines = (Get-Content 'F:\backup\claudecode\GLOBAL_RULES.md').Count
$rules = (Select-String -Path 'F:\backup\claudecode\GLOBAL_RULES.md' -Pattern '^## Rule').Count
Write-Host "F:\backup\claudecode\GLOBAL_RULES.md: $rules rules | $lines lines total"
