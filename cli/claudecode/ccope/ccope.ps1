<#
.SYNOPSIS
    ccope
#>
Stop-Process -Name "opencode*" -Force -EA SilentlyContinue; Remove-Item "C:\Users\micha\.local\share\opencode\storage" -Recurse -Force; Remove-Item "C:\Users\micha\.local\state\opencode" -Recurse -Force -EA SilentlyContinue; Write-Host "Done" -ForegroundColor Green
