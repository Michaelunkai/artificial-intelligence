$ErrorActionPreference = 'Stop'
$ProfilePath = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$paths = @($ProfilePath,'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\backher-fast.ps1','F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\resher-fast.ps1')
$parse = @()
foreach ($p in $paths) { $t=$null; $e=$null; [void][System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$t,[ref]$e); $parse += [pscustomobject]@{Path=$p;ParseErrors=@($e).Count} }
. $ProfilePath
$beforeBack = (& cfun backher | Out-String)
$beforeRes = (& cfun resher | Out-String)
Load-FullPowerShellProfile
$afterBack = (& cfun backher | Out-String)
$afterRes = (& cfun resher | Out-String)
$t=$null; $e=$null; $ast=[System.Management.Automation.Language.Parser]::ParseFile($ProfilePath,[ref]$t,[ref]$e)
$funcs=$ast.FindAll({param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst]},$true)|ForEach-Object{$_.Name}|Sort-Object
[ordered]@{
 Parse=$parse
 DotSource='ok'
 FunctionCount=@($funcs).Count
 BackherBeforeFast=($beforeBack -match 'backher-fast\.ps1')
 ResherBeforeFast=($beforeRes -match 'resher-fast\.ps1')
 BackherAfterFast=($afterBack -match 'backher-fast\.ps1')
 ResherAfterFast=($afterRes -match 'resher-fast\.ps1')
 BackherScriptProgress=((Get-Content -LiteralPath $paths[1] -Raw) -match 'PROGRESS \{0\}: elapsed=\{1\}s')
 ResherScriptProgress=((Get-Content -LiteralPath $paths[2] -Raw) -match 'PROGRESS \{0\}: elapsed=\{1\}s')
 FunctionNames=@($funcs)
} | ConvertTo-Json -Depth 10
