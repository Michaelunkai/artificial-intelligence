# Remove specific global user-level rule from C:\users\micha\.claude\settings.json

param(
    [Parameter(Mandatory=$true)]
    [int]$RuleNumber
)

$settingsPath = 'C:\users\micha\.claude\settings.json'

# Read current settings
$content = Get-Content $settingsPath -Raw | ConvertFrom-Json

# Show current rules
Write-Host "`nCurrent rules in C:\users\micha\.claude\settings.json:" -ForegroundColor Cyan
Write-Host ("=" * 80) -ForegroundColor Gray
for ($i = 0; $i -lt $content.permissions.allow.Count; $i++) {
    $ruleNum = $i + 1
    $ruleText = $content.permissions.allow[$i]
    if ($ruleText.Length -gt 100) {
        $ruleText = $ruleText.Substring(0, 97) + "..."
    }
    Write-Host "$ruleNum. $ruleText" -ForegroundColor White
}
Write-Host ("=" * 80) -ForegroundColor Gray

# Validate rule number
if ($RuleNumber -lt 1 -or $RuleNumber -gt $content.permissions.allow.Count) {
    Write-Host "`n❌ Error: Rule number must be between 1 and $($content.permissions.allow.Count)" -ForegroundColor Red
    exit 1
}

# Get the rule to remove (display full text)
$ruleToRemove = $content.permissions.allow[$RuleNumber - 1]
Write-Host "`nRemoving rule #$RuleNumber`:" -ForegroundColor Yellow
Write-Host $ruleToRemove -ForegroundColor White

# Confirm
$confirm = Read-Host "`nAre you sure you want to remove this rule? (yes/no)"
if ($confirm -ne "yes") {
    Write-Host "❌ Operation cancelled" -ForegroundColor Red
    exit 0
}

# Backup original
Copy-Item $settingsPath "$settingsPath.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"

# Remove the rule (PowerShell arrays are 0-indexed)
$newRules = @()
for ($i = 0; $i -lt $content.permissions.allow.Count; $i++) {
    if ($i -ne ($RuleNumber - 1)) {
        $newRules += $content.permissions.allow[$i]
    }
}
$content.permissions.allow = $newRules

# Write updated settings
$content | ConvertTo-Json -Depth 10 | Set-Content $settingsPath

# Show confirmation
$totalRules = $content.permissions.allow.Count
Write-Host "`n✅ Rule removed successfully!" -ForegroundColor Green
Write-Host "C:\users\micha\.claude\settings.json: $totalRules total rules remaining" -ForegroundColor Cyan
