$ProfilePath = 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
$tokens=$null; $errors=$null
$ast=[System.Management.Automation.Language.Parser]::ParseFile($ProfilePath,[ref]$tokens,[ref]$errors)
$funcs=$ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true) | Sort-Object Name
$result = [ordered]@{
  ProfilePath = $ProfilePath
  ParseErrors = @($errors).Count
  FunctionCount = @($funcs).Count
  FunctionNames = @($funcs | ForEach-Object { $_.Name })
  RelevantFunctions = @()
}
foreach ($name in @('backher','resher')) {
  $f = $funcs | Where-Object { $_.Name -eq $name -or $_.Name -eq "global:$name" } | Select-Object -First 1
  if ($f) {
    $result.RelevantFunctions += [ordered]@{
      Name = $f.Name
      StartLine = $f.Extent.StartLineNumber
      EndLine = $f.Extent.EndLineNumber
      Text = $f.Extent.Text
    }
  } else {
    $result.RelevantFunctions += [ordered]@{ Name=$name; Found=$false }
  }
}
$result | ConvertTo-Json -Depth 20
