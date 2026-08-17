$ErrorActionPreference = 'Stop'
$paths = @(
 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1',
 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backher-fast.ps1',
 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\resher-fast.ps1'
)
$results = @()
foreach ($p in $paths) {
  $tokens=$null; $errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  $results += [pscustomobject]@{ Path=$p; ParseErrors=@($errors).Count; ErrorMessages=@($errors | ForEach-Object { $_.Message }) }
}
. $paths[0]
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($paths[0],[ref]$tokens,[ref]$errors)
$funcs=$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name } | Sort-Object
[ordered]@{
 ParseResults=$results
 DotSource='ok'
 FunctionCount=@($funcs).Count
 BackherCfunHasFast=((& cfun backher | Out-String) -match 'backher-fast\.ps1')
 ResherCfunHasFast=((& cfun resher | Out-String) -match 'resher-fast\.ps1')
 BackherScriptHasProgress=((Get-Content -LiteralPath $paths[1] -Raw) -match 'PROGRESS \{0\}: elapsed=\{1\}s')
 ResherScriptHasProgress=((Get-Content -LiteralPath $paths[2] -Raw) -match 'PROGRESS \{0\}: elapsed=\{1\}s')
} | ConvertTo-Json -Depth 8
