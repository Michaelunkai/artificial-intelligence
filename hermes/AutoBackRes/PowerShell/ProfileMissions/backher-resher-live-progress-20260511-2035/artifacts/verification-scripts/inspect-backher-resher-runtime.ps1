$ErrorActionPreference = 'Stop'
$ProfilePath = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ProfilePath,[ref]$tokens,[ref]$errors)
$funcs=$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | ForEach-Object { $_.Name } | Sort-Object
. $ProfilePath
$preBack = [string](Get-Command backher -CommandType Function).ScriptBlock
$preRes = [string](Get-Command resher -CommandType Function).ScriptBlock
$loadResult = 'not-called'
try { if (Get-Command Load-FullPowerShellProfile -ErrorAction SilentlyContinue) { Load-FullPowerShellProfile; $loadResult='ok' } } catch { $loadResult = 'ERROR: ' + $_.Exception.Message }
$postBack = [string](Get-Command backher -CommandType Function).ScriptBlock
$postRes = [string](Get-Command resher -CommandType Function).ScriptBlock
$result=[ordered]@{
  ParseErrors=@($errors).Count
  FunctionCount=@($funcs).Count
  FunctionNames=@($funcs)
  PreBackherHasFast=($preBack -match 'backher-fast\.ps1')
  PreBackherHasInlineTar=($preBack -match 'tar --xattrs')
  PreResherHasFast=($preRes -match 'resher-fast\.ps1')
  PreResherHasInlineTar=($preRes -match 'tar --xattrs')
  LoadFullPowerShellProfile=$loadResult
  PostBackherHasFast=($postBack -match 'backher-fast\.ps1')
  PostBackherHasInlineTar=($postBack -match 'tar --xattrs')
  PostResherHasFast=($postRes -match 'resher-fast\.ps1')
  PostResherHasInlineTar=($postRes -match 'tar --xattrs')
  PostBackherFirst300=($postBack.Substring(0, [Math]::Min(300,$postBack.Length)))
  PostResherFirst300=($postRes.Substring(0, [Math]::Min(300,$postRes.Length)))
}
$result | ConvertTo-Json -Depth 10
