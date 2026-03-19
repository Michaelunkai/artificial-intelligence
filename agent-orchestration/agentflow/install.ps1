# AgentFlow Installation Script
# Installs AgentFlow extension into OpenClaw

Write-Host "🤖 AgentFlow - Installation Script" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Stop"

# Check if OpenClaw is installed
$openclawPath = "C:\Users\micha\.openclaw"
if (-not (Test-Path $openclawPath)) {
    Write-Host "❌ OpenClaw not found at $openclawPath" -ForegroundColor Red
    Write-Host "Please install OpenClaw first: npm install -g openclaw" -ForegroundColor Yellow
    exit 1
}

# Define paths
$extensionsPath = Join-Path $openclawPath "extensions"
$agentflowPath = Join-Path $extensionsPath "agentflow"
$sourcePath = $PSScriptRoot

Write-Host "📂 Source: $sourcePath" -ForegroundColor Gray
Write-Host "📁 Target: $agentflowPath" -ForegroundColor Gray
Write-Host ""

# Create extensions directory if it doesn't exist
if (-not (Test-Path $extensionsPath)) {
    New-Item -ItemType Directory -Force -Path $extensionsPath | Out-Null
    Write-Host "✅ Created extensions directory" -ForegroundColor Green
}

# Backup existing installation
if (Test-Path $agentflowPath) {
    $backupPath = "${agentflowPath}_backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Write-Host "📦 Backing up existing installation to: $backupPath" -ForegroundColor Yellow
    Move-Item -Path $agentflowPath -Destination $backupPath -Force
}

# Copy files
Write-Host "📋 Copying files..." -ForegroundColor Cyan
Copy-Item -Path $sourcePath -Destination $agentflowPath -Recurse -Force

# Install npm dependencies
Write-Host "📦 Installing dependencies..." -ForegroundColor Cyan
Push-Location $agentflowPath
try {
    npm install --silent
    Write-Host "✅ Dependencies installed" -ForegroundColor Green
} catch {
    Write-Host "⚠️  Warning: npm install failed. You may need to run 'npm install' manually." -ForegroundColor Yellow
}
Pop-Location

# Create data directory
$dataPath = Join-Path $agentflowPath "data"
if (-not (Test-Path $dataPath)) {
    New-Item -ItemType Directory -Force -Path $dataPath | Out-Null
}

Write-Host ""
Write-Host "✅ AgentFlow installed successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Next steps:" -ForegroundColor Cyan
Write-Host "1. Restart OpenClaw gateway:" -ForegroundColor White
Write-Host "   - Right-click tray icon → 'Restart Gateway'" -ForegroundColor Gray
Write-Host "   - OR run: openclaw gateway restart" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Access dashboard:" -ForegroundColor White
Write-Host "   http://localhost:18789/agentflow" -ForegroundColor Gray
Write-Host ""
Write-Host "3. (Optional) Add tray menu integration:" -ForegroundColor White
Write-Host "   Run: .\install-tray-integration.ps1" -ForegroundColor Gray
Write-Host ""
Write-Host "🎉 Ready to orchestrate your agents!" -ForegroundColor Green
