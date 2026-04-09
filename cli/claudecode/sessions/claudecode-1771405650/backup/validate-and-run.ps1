# Self-validating backup runner
$ErrorActionPreference = 'Continue'

$scriptDir = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup"
$scriptPath = "$scriptDir\backup-claudecode.ps1"

Write-Host "================================" -ForegroundColor Cyan
Write-Host " BACKUP SCRIPT VALIDATOR" -ForegroundColor White
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

# Step 1: Validate syntax
Write-Host "[1/3] Validating syntax..." -ForegroundColor Yellow
$content = Get-Content $scriptPath -Raw
$errors = $null
$tokens = [System.Management.Automation.PSParser]::Tokenize($content, [ref]$errors)

if ($errors.Count -gt 0) {
    Write-Host "SYNTAX ERRORS:" -ForegroundColor Red
    foreach ($e in $errors) {
        Write-Host "  Line $($e.Token.StartLine): $($e.Message)" -ForegroundColor Red
    }
    exit 1
}
Write-Host "  Syntax OK ($($tokens.Count) tokens)" -ForegroundColor Green

# Step 2: Parse AST
Write-Host "[2/3] Parsing AST..." -ForegroundColor Yellow
$parseErrors = $null
$ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors)
if ($parseErrors.Count -gt 0) {
    Write-Host "PARSE ERRORS:" -ForegroundColor Red
    foreach ($e in $parseErrors) {
        Write-Host "  Line $($e.Extent.StartLineNumber): $($e.Message)" -ForegroundColor Red
    }
    exit 1
}
Write-Host "  AST OK" -ForegroundColor Green

# Step 3: Run backup
Write-Host "[3/3] Running backup..." -ForegroundColor Yellow
Write-Host ""
Write-Host "================================" -ForegroundColor Magenta
Write-Host " STARTING BACKUP" -ForegroundColor White
Write-Host "================================" -ForegroundColor Magenta
Write-Host ""

Set-Location $scriptDir
& $scriptPath

Write-Host ""
Write-Host "================================" -ForegroundColor Green
Write-Host " BACKUP FINISHED" -ForegroundColor White
Write-Host "================================" -ForegroundColor Green
