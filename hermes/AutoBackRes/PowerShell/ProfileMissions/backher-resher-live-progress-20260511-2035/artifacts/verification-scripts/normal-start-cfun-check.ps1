$ErrorActionPreference = 'Stop'
# This script is run without -NoProfile, so profile should already be loaded normally.
$back = (& cfun backher | Out-String)
$res = (& cfun resher | Out-String)
$cmdBack = [string](Get-Command backher -CommandType Function).ScriptBlock
$cmdRes = [string](Get-Command resher -CommandType Function).ScriptBlock
if ($back -notmatch 'backher-fast\.ps1' -or $back -match 'tar --xattrs') { throw 'cfun backher still stale/broken' }
if ($res -notmatch 'resher-fast\.ps1' -or $res -match 'tar --xattrs') { throw 'cfun resher still stale/broken' }
if ($cmdBack -notmatch 'backher-fast\.ps1' -or $cmdBack -match 'tar --xattrs') { throw 'runtime backher still stale/broken' }
if ($cmdRes -notmatch 'resher-fast\.ps1' -or $cmdRes -match 'tar --xattrs') { throw 'runtime resher still stale/broken' }
[ordered]@{
  NormalStartupProfileLoaded = $true
  CfunBackherClean = $true
  CfunResherClean = $true
  RuntimeBackherClean = $true
  RuntimeResherClean = $true
  BackherFirstLine = (($back -split "`n") | Select-Object -First 1)
  ResherFirstLine = (($res -split "`n") | Select-Object -First 1)
} | ConvertTo-Json -Depth 5
