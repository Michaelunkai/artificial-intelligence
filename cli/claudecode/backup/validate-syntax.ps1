$scripts = @(
    "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1",
    "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\restore-claudecode.ps1"
)

foreach ($script in $scripts) {
    $name = Split-Path $script -Leaf
    $errors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($script, [ref]$null, [ref]$errors)
    if ($errors.Count -eq 0) {
        Write-Host "[PASS] $name" -ForegroundColor Green
    } else {
        Write-Host "[FAIL] $name - $($errors.Count) errors:" -ForegroundColor Red
        foreach ($e in $errors) {
            Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Yellow
        }
    }
}
