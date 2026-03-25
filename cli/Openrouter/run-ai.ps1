# Simple OpenRouter CLI Wrapper
param(
    [Parameter(Mandatory=$true)]
    [string]$Model,
    
    [Parameter(Mandatory=$true)]
    [string]$Message
)

# Set UTF-8 encoding for console
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Add to PATH
$env:PATH += ";C:\Users\micha\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\LocalCache\local-packages\Python313\Scripts"

Write-Host "Model: $Model" -ForegroundColor Green
Write-Host "Message: $Message" -ForegroundColor Yellow
Write-Host "Response:" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Gray

# Set PYTHONIOENCODING to handle Unicode
$env:PYTHONIOENCODING = "utf-8"

try {
    echo $Message | openrouter-cli run $Model --raw
} catch {
    Write-Host "Error: $($_.Exception.Message)" -ForegroundColor Red
}