$ProfilePath = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ProfilePath,[ref]$tokens,[ref]$errors)
$funcs=$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name } | Sort-Object
[ordered]@{ ParseErrors=@($errors).Count; FunctionCount=@($funcs).Count; FunctionNames=@($funcs) } | ConvertTo-Json -Depth 8
