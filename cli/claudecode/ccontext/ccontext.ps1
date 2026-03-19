<#
.SYNOPSIS
    ccontext
#>
param([string]$t) $f="$env:USERPROFILE\.claude\settings.json"; (gc $f -Raw) -replace '"threshold":\s*[\d.]+',"`"threshold`": $t" | Set-Content $f; echo "Autocompact threshold: $t"
