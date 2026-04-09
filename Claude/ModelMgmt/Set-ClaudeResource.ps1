param(
    [string]$Model,
    [bool]$Thinking = $false,
    [int]$ThinkingBudget = 0,
    [int]$MaxOutputTokens = 4096,
    [int]$BashTimeout = 120000,
    [int]$BashMaxTimeout = 300000,
    [int]$McpTimeout = 10000,
    [double]$CompactThreshold = 0.02,
    [int]$CompactBudget = 100,
    [string]$EffortLevel,
    [string]$Label,
    [string]$Color = "Cyan"
)
$settingsPath = "C:\Users\micha\.claude\settings.json"
if (-not (Test-Path $settingsPath)) {
    Write-Host "ERROR: settings.json not found at $settingsPath" -ForegroundColor Red
    return
}
if ($Label) { Write-Host "$Label" -ForegroundColor $Color }
try {
    $settings = Get-Content $settingsPath -Raw | ConvertFrom-Json
    if ($Model) {
        if ($settings.PSObject.Properties['model']) {
            $settings.model = $Model
        } else {
            $settings | Add-Member -NotePropertyName "model" -NotePropertyValue $Model -Force
        }
    }
    if ($PSBoundParameters.ContainsKey('Thinking')) {
        if ($settings.PSObject.Properties['thinking']) {
            $settings.thinking = [PSCustomObject]@{ enabled = $Thinking }
        } else {
            $settings | Add-Member -NotePropertyName "thinking" -NotePropertyValue ([PSCustomObject]@{ enabled = $Thinking }) -Force
        }
        if ($Thinking -and $ThinkingBudget -gt 0) {
            $settings.thinking | Add-Member -NotePropertyName "budgetTokens" -NotePropertyValue $ThinkingBudget -Force
        }
    }
    if (-not $settings.env) { $settings | Add-Member -NotePropertyName "env" -NotePropertyValue ([PSCustomObject]@{}) -Force }
    $envProps = @{
        "CLAUDE_CODE_MAX_OUTPUT_TOKENS" = "$MaxOutputTokens"
        "BASH_DEFAULT_TIMEOUT_MS" = "$BashTimeout"
        "BASH_MAX_TIMEOUT_MS" = "$BashMaxTimeout"
        "MCP_TOOL_TIMEOUT" = "$McpTimeout"
    }
    foreach ($key in $envProps.Keys) {
        if ($settings.env.PSObject.Properties[$key]) {
            $settings.env.$key = $envProps[$key]
        } else {
            $settings.env | Add-Member -NotePropertyName $key -NotePropertyValue $envProps[$key] -Force
        }
    }
    if ($EffortLevel) {
        if ($settings.PSObject.Properties['effortLevel']) {
            $settings.effortLevel = $EffortLevel
        } else {
            $settings | Add-Member -NotePropertyName "effortLevel" -NotePropertyValue $EffortLevel -Force
        }
    }
    if (-not $settings.autoCompact) { $settings | Add-Member -NotePropertyName "autoCompact" -NotePropertyValue ([PSCustomObject]@{}) -Force }
    $settings.autoCompact | Add-Member -NotePropertyName "enabled" -NotePropertyValue $true -Force
    $settings.autoCompact | Add-Member -NotePropertyName "threshold" -NotePropertyValue $CompactThreshold -Force
    $settings.autoCompact | Add-Member -NotePropertyName "budgetTokens" -NotePropertyValue $CompactBudget -Force
    $settings | ConvertTo-Json -Depth 10 | Set-Content $settingsPath -Encoding UTF8
    Write-Host "  Model: $Model | Thinking: $Thinking$(if($ThinkingBudget -gt 0){" ($ThinkingBudget tokens)"})$(if($EffortLevel){" | Effort: $EffortLevel"})" -ForegroundColor White
    Write-Host "  Output: $MaxOutputTokens | BashTO: $($BashTimeout/1000)s | McpTO: $($McpTimeout/1000)s" -ForegroundColor Gray
    Write-Host "  Applied! Restart Claude Code to take effect." -ForegroundColor Green
} catch {
    Write-Host "ERROR: $($_.Exception.Message)" -ForegroundColor Red
}
