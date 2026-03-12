# Display Global Rules count on session start
# Rules stored in timestamped backup folders per Rule 2

$backupRoot = 'F:\backup\claudecode'
$latestBackup = Get-ChildItem -Path $backupRoot -Directory -Filter "backup_*" -ErrorAction SilentlyContinue | Sort-Object Name -Descending | Select-Object -First 1
$ruleCount = 0
$source = "Unknown"

if ($latestBackup) {
    $globalRulesFile = Join-Path $latestBackup.FullName "GLOBAL_RULES.md"
    if (Test-Path $globalRulesFile) {
        $ruleCount = (Select-String -Path $globalRulesFile -Pattern '^## RULE \d+:' | Measure-Object).Count
        $source = "$($latestBackup.Name)/GLOBAL_RULES.md"
    } else {
        # Fallback: Count from settings.json in backup
        $settingsFile = Join-Path $latestBackup.FullName "User_Profile_.claude\settings.json"
        if (Test-Path $settingsFile) {
            try {
                $settings = Get-Content $settingsFile -Raw | ConvertFrom-Json
                $ruleCount = $settings.permissions.allow.Count
                $source = "$($latestBackup.Name)/settings.json"
            } catch {
                $ruleCount = 18
                $source = "Default (18 Global Rules)"
            }
        } else {
            $ruleCount = 18
            $source = "Default (18 Global Rules)"
        }
    }
} else {
    $ruleCount = 18
    $source = "Default (18 Global Rules)"
}

Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "  GLOBAL RULES SYSTEM INITIALIZED" -ForegroundColor Green
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "  Total Active Rules: $ruleCount" -ForegroundColor Yellow
Write-Host "  Source: $source" -ForegroundColor Gray
Write-Host "  Latest Backup: $($latestBackup.Name)" -ForegroundColor White
Write-Host "========================================`n" -ForegroundColor Cyan
