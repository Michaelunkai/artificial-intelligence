$ErrorActionPreference = 'Stop'
. 'C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1'
Write-Host '--- backher plan test ---'
backher -PlanOnly
Write-Host '--- resher validate test ---'
resher -ValidateOnly
