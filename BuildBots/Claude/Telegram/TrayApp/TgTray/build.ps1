$projectDir = $PSScriptRoot
$src  = Join-Path $projectDir "TgTray.cs"
$out  = Join-Path $projectDir "tg.exe"
$csc  = "C:\Windows\Microsoft.NET\Framework64\v4.0.30319\csc.exe"

$refs = @(
    "System.dll",
    "System.Windows.Forms.dll",
    "System.Drawing.dll",
    "System.Management.dll"
)
$refArgs = ($refs | ForEach-Object { "/reference:$_" }) -join " "

Write-Host "Compiling TgTray..." -ForegroundColor Cyan
$cmd = "& `"$csc`" /target:exe /optimize /out:`"$out`" $refArgs `"$src`""
Invoke-Expression $cmd

if (Test-Path $out) {
    Write-Host "SUCCESS: $out" -ForegroundColor Green
    # Kill running tg.exe instances before copying
    Get-Process -Name 'tg' -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 500
    # Copy to .local\bin so it's on PATH and tg function can call it
    $binDir = "$env:USERPROFILE\.local\bin"
    if (Test-Path $binDir) {
        Copy-Item $out "$binDir\tg.exe" -Force
        Write-Host "Deployed to $binDir\tg.exe" -ForegroundColor Green
    }
    Write-Host "Run: tg  |  tg status  |  tg start  |  tg stop  |  tg restart" -ForegroundColor Cyan
} else {
    Write-Host "FAILED - check errors above" -ForegroundColor Red
}
