param(
  [string]$Root = $PSScriptRoot
)

$ErrorActionPreference = 'Stop'
$source = Join-Path $Root 'HermesTray.cs'
$output = Join-Path $Root 'HermesTray.exe'
$csc = Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path -LiteralPath $csc -PathType Leaf)) {
  throw "C# compiler not found: $csc"
}
if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
  throw "Source not found: $source"
}

& $csc /nologo /target:winexe /platform:anycpu /optimize+ /out:$output /reference:System.dll /reference:System.Core.dll /reference:System.Drawing.dll /reference:System.Windows.Forms.dll $source
if ($LASTEXITCODE -ne 0) {
  throw "HermesTray compile failed with exit code $LASTEXITCODE"
}

Get-Item -LiteralPath $output | Select-Object FullName, Length, LastWriteTime
