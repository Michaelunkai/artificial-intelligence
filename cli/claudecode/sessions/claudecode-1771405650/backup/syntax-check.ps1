# Syntax check script
$scriptPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1"
$content = Get-Content $scriptPath -Raw
$errors = $null
$tokens = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)

Write-Host "=== SYNTAX CHECK ===" -ForegroundColor Cyan
if ($errors.Count -eq 0) {
    Write-Host "SYNTAX OK - No errors found" -ForegroundColor Green
    Write-Host "Token count: $($tokens.Count)"
} else {
    Write-Host "SYNTAX ERRORS:" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host "  Line $($e.Token.StartLine): $($e.Message)" -ForegroundColor Red
    }
}
Write-Host "===================" -ForegroundColor Cyan

# Try to actually parse it
Write-Host ""
Write-Host "=== AST CHECK ===" -ForegroundColor Cyan
try {
    $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$errors)
    if ($errors.Count -eq 0) {
        Write-Host "AST OK - No parse errors" -ForegroundColor Green
    } else {
        Write-Host "AST ERRORS:" -ForegroundColor Red
        foreach ($e in $errors) {
            Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Red
        }
    }
} catch {
    Write-Host "AST Exception: $_" -ForegroundColor Red
}
Write-Host "===================" -ForegroundColor Cyan
