$ErrorActionPreference = 'Stop'
$ProfilePath = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$scriptPaths = @(
  'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backher-fast.ps1',
  'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\resher-fast.ps1'
)
function Parse-One($Path) {
  $tokens=$null; $errors=$null
  $ast=[System.Management.Automation.Language.Parser]::ParseFile($Path,[ref]$tokens,[ref]$errors)
  [pscustomobject]@{ Path=$Path; ParseErrors=@($errors).Count; ErrorMessages=@($errors | ForEach-Object { $_.Message }) }
}
$parseResults = @()
$parseResults += Parse-One $ProfilePath
foreach ($p in $scriptPaths) { $parseResults += Parse-One $p }
if (($parseResults | Measure-Object ParseErrors -Sum).Sum -ne 0) { $parseResults | ConvertTo-Json -Depth 6; throw 'Parse errors detected' }
. $ProfilePath
$back = Get-Command backher -CommandType Function
$res = Get-Command resher -CommandType Function
if ([string]$back.ScriptBlock -notmatch 'backher-fast\.ps1') { throw 'backher wrapper does not point to backher-fast.ps1' }
if ([string]$res.ScriptBlock -notmatch 'resher-fast\.ps1') { throw 'resher wrapper does not point to resher-fast.ps1' }
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ProfilePath,[ref]$tokens,[ref]$errors)
$funcs=$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name } | Sort-Object
$result = [ordered]@{
  ParseResults = $parseResults
  DotSource = 'ok'
  BackherScriptPathExists = (Test-Path -LiteralPath $scriptPaths[0] -PathType Leaf)
  ResherScriptPathExists = (Test-Path -LiteralPath $scriptPaths[1] -PathType Leaf)
  BackherWrapperPointsToScript = ([string]$back.ScriptBlock -match 'backher-fast\.ps1')
  ResherWrapperPointsToScript = ([string]$res.ScriptBlock -match 'resher-fast\.ps1')
  FunctionCount = @($funcs).Count
  FunctionNames = @($funcs)
}
$result | ConvertTo-Json -Depth 10
