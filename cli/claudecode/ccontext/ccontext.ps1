# ccontext - Set Claude Code autocompact threshold, budget, and compact max
param([string]$Threshold, [int]$Budget = 0, [int]$CompactMax = 0)
$s = 'C:\Users\micha\.claude\settings.json'
$j = Get-Content $s -Raw | ConvertFrom-Json
if (-not $j.PSObject.Properties['autoCompact']) { $j | Add-Member -NotePropertyName 'autoCompact' -NotePropertyValue ([PSCustomObject]@{}) -Force }
$j.autoCompact | Add-Member -NotePropertyName 'enabled' -NotePropertyValue $true -Force
if ($Threshold) { $j.autoCompact | Add-Member -NotePropertyName 'threshold' -NotePropertyValue ([double]$Threshold) -Force }
if ($Budget -gt 0) { $j.autoCompact | Add-Member -NotePropertyName 'budgetTokens' -NotePropertyValue $Budget -Force }
if ($CompactMax -gt 0) {
    if (-not $j.PSObject.Properties['env']) { $j | Add-Member -NotePropertyName 'env' -NotePropertyValue ([PSCustomObject]@{}) -Force }
    $j.env | Add-Member -NotePropertyName 'CLAUDE_CODE_MAX_OUTPUT_TOKENS' -NotePropertyValue "$CompactMax" -Force
}
$j | ConvertTo-Json -Depth 10 | Set-Content $s -Encoding UTF8
Write-Host "Context: Threshold=$Threshold Budget=$Budget CompactMax=$CompactMax" -ForegroundColor Cyan