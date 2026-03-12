$scriptPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1"
$errors = $null
$null = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
if ($errors.Count -eq 0) {
    Write-Host "[PASS] Syntax OK" -ForegroundColor Green
} else {
    Write-Host "[FAIL] $($errors.Count) errors" -ForegroundColor Red
    $errors | ForEach-Object { Write-Host $_.Message }
}
