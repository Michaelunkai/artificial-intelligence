# Create the destination directory if it doesn't exist
if (!(Test-Path "C:\ollama")) {
    New-Item -ItemType Directory -Path "C:\ollama" -Force
}

# Stop any existing Ollama processes
Stop-Process -Name "ollama*" -Force -ErrorAction SilentlyContinue

# Install Ollama to C:\ollama
Write-Host "Installing Ollama to C:\ollama..."
winget install Ollama.Ollama --location "C:\ollama" --override "/DIR=C:\ollama /S"

# Wait a moment for installation to complete
Start-Sleep -Seconds 3

# Set machine-level environment variables
Write-Host "Setting environment variables..."
[System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "C:\ollama\models", "Machine")
[System.Environment]::SetEnvironmentVariable("OLLAMA_HOME", "C:\ollama", "Machine")

# Set current session environment variables
$env:OLLAMA_MODELS="C:\ollama\models"
$env:OLLAMA_HOME="C:\ollama"

# Refresh environment variables
Write-Host "Refreshing environment variables..."
refreshenv

# Add Ollama to PATH if not already there
$ollamaPath = "C:\ollama"
$currentPath = [System.Environment]::GetEnvironmentVariable("PATH", "Machine")
if ($currentPath -notlike "*$ollamaPath*") {
    $newPath = $currentPath + ";$ollamaPath"
    [System.Environment]::SetEnvironmentVariable("PATH", $newPath, "Machine")
    $env:PATH = $newPath
}

# Wait for PATH to update and verify Ollama is available
Start-Sleep -Seconds 2

# Check if ollama command is available
if (Get-Command ollama -ErrorAction SilentlyContinue) {
    Write-Host "Ollama is available. Pulling model..."
    ollama pull llama3.2:7b
} else {
    Write-Host "Ollama command not found. Waiting and retrying..."
    Start-Sleep -Seconds 5
    
    # Try to run ollama directly from the installation directory
    $ollamaExe = "C:\ollama\ollama.exe"
    if (Test-Path $ollamaExe) {
        Write-Host "Ollama executable found at $ollamaExe"
        & $ollamaExe pull llama3.2:7b
    } else {
        Write-Host "Ollama executable not found. Please restart your terminal and run 'ollama pull llama3.2:7b' manually."
    }
}
