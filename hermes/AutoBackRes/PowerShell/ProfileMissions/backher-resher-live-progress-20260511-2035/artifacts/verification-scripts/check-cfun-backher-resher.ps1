$ErrorActionPreference = 'Stop'
. 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$before = (& cfun backher | Out-String)
Load-FullPowerShellProfile
$afterBack = (& cfun backher | Out-String)
$afterRes = (& cfun resher | Out-String)
[ordered]@{
  CfunBackBeforeHasFast = ($before -match 'backher-fast\.ps1')
  CfunBackBeforeHasInlineTar = ($before -match 'tar --xattrs')
  CfunBackAfterHasFast = ($afterBack -match 'backher-fast\.ps1')
  CfunBackAfterHasInlineTar = ($afterBack -match 'tar --xattrs')
  CfunResAfterHasFast = ($afterRes -match 'resher-fast\.ps1')
  CfunResAfterHasInlineTar = ($afterRes -match 'tar --xattrs')
  CfunBackAfterFirst600 = ($afterBack.Substring(0, [Math]::Min(600,$afterBack.Length)))
  CfunResAfterFirst600 = ($afterRes.Substring(0, [Math]::Min(600,$afterRes.Length)))
} | ConvertTo-Json -Depth 6
