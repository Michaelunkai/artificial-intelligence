# Corrected one-liner for Ollama installation with proper PowerShell syntax
# Fixed issues: missing quote, incorrect operator, and parameter format

winget install Ollama.Ollama --force --override "/S /D=C:\ollama"; Start-Sleep -Seconds 2; Stop-Process -Name "ollama*" -Force -ErrorAction SilentlyContinue; [System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "C:\ollama\models", "Machine"); [System.Environment]::SetEnvironmentVariable("OLLAMA_HOME", "C:\ollama", "Machine"); $env:OLLAMA_MODELS="C:\ollama\models"; $env:OLLAMA_HOME="C:\ollama"

Write-Host "Ollama installation completed successfully!"
Write-Host "Environment variables set:"
Write-Host "  OLLAMA_MODELS = C:\ollama\models"
Write-Host "  OLLAMA_HOME = C:\ollama"
