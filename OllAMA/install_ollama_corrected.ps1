# Install Ollama with correct syntax
winget install Ollama.Ollama --force --override "/S /D=C:\ollama"

# Wait a moment for installation to complete
Start-Sleep -Seconds 2

# Stop any existing Ollama processes
Stop-Process -Name "ollama*" -Force -ErrorAction SilentlyContinue

# Set environment variables permanently
[System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "C:\ollama\models", "Machine")
[System.Environment]::SetEnvironmentVariable("OLLAMA_HOME", "C:\ollama", "Machine")

# Set environment variables for current session
$env:OLLAMA_MODELS = "C:\ollama\models"
$env:OLLAMA_HOME = "C:\ollama"

Write-Host "Ollama installation completed and environment variables set."
Write-Host "Models will be stored in: C:\ollama\models"
Write-Host "Ollama home directory: C:\ollama"
