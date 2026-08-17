$ErrorActionPreference = 'Stop'
$paths = @(
 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\PowerShell\ProfileMissions\backher-resher-live-progress-20260511-2035\artifacts\live-scripts\backher-fast.ps1',
 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes\PowerShell\ProfileMissions\backher-resher-live-progress-20260511-2035\artifacts\live-scripts\resher-fast.ps1'
)
foreach ($p in $paths) {
  $tokens=$null; $errors=$null
  [void][System.Management.Automation.Language.Parser]::ParseFile($p,[ref]$tokens,[ref]$errors)
  if (@($errors).Count -ne 0) { throw "Parse errors in $p" }
}
'PS5 parse ok for archived primary scripts'
