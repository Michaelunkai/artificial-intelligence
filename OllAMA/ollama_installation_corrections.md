# Ollama Installation Script Corrections

## Original Command Issues

The original one-liner had several syntax errors:

1. **Missing quote in environment variable assignment:**
   - Original: `[System.Environment]::SetEnvironmentVariable("OLLAMA_HOME", C:\ollama", "Machine")`
   - Fixed: `[System.Environment]::SetEnvironmentVariable("OLLAMA_HOME", "C:\ollama", "Machine")`

2. **Incorrect winget override parameter:**
   - Original: `--override "/DIR=C:\ /S"`
   - Fixed: `--override "/S /D=C:\ollama"`

3. **Missing quote in path:**
   - The installation path needed proper quoting

## Corrections Made

### Fixed One-liner (`ollama_oneliner_fixed.ps1`):
```powershell
winget install Ollama.Ollama --force --override "/S /D=C:\ollama"; Start-Sleep -Seconds 2; Stop-Process -Name "ollama*" -Force -ErrorAction SilentlyContinue; [System.Environment]::SetEnvironmentVariable("OLLAMA_MODELS", "C:\ollama\models", "Machine"); [System.Environment]::SetEnvironmentVariable("OLLAMA_HOME", "C:\ollama", "Machine"); $env:OLLAMA_MODELS="C:\ollama\models"; $env:OLLAMA_HOME="C:\ollama"
```

### Readable Script Version (`install_ollama_corrected.ps1`):
```powershell
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
```

## Key Changes

1. **Proper quoting**: All paths are now properly quoted
2. **Correct winget syntax**: Using `/D=C:\ollama` instead of `/DIR=C:\`
3. **Fixed environment variable assignment**: Added missing quote before "C:\ollama"
4. **Added delay**: Included `Start-Sleep -Seconds 2` to ensure installation completes before setting environment variables

## Usage

- Run `install_ollama_corrected.ps1` for the readable version
- Run `ollama_oneliner_fixed.ps1` for the one-liner version
- Both scripts will install Ollama to `C:\ollama` and set the appropriate environment variables
