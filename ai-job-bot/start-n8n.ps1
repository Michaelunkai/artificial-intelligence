# AI Job Bot - n8n Startup Script
# This script starts n8n with the correct environment variables

Write-Host "🚀 Starting AI Job Application Bot (n8n)..." -ForegroundColor Cyan

# Set working directory
Set-Location "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\ai-job-bot"

# Check if .env exists
if (-not (Test-Path ".env")) {
    Write-Host "❌ ERROR: .env file not found!" -ForegroundColor Red
    Write-Host "📝 Please copy .env.template to .env and fill in your API keys" -ForegroundColor Yellow
    Write-Host ""
    Write-Host "Steps:" -ForegroundColor Green
    Write-Host "  1. Copy-Item .env.template .env" -ForegroundColor White
    Write-Host "  2. Edit .env with your API keys (OpenAI, Apify, Google)" -ForegroundColor White
    Write-Host "  3. Run this script again" -ForegroundColor White
    exit 1
}

# Load environment variables from .env
Write-Host "📂 Loading environment variables from .env..." -ForegroundColor Green
Get-Content .env | ForEach-Object {
    if ($_ -match '^\s*([^#][^=]*)\s*=\s*(.*)') {
        $key = $matches[1].Trim()
        $value = $matches[2].Trim()
        [Environment]::SetEnvironmentVariable($key, $value, "Process")
        Write-Host "  ✓ $key loaded" -ForegroundColor Gray
    }
}

Write-Host ""
Write-Host "✅ Environment variables loaded!" -ForegroundColor Green
Write-Host ""
Write-Host "🌐 Starting n8n web interface..." -ForegroundColor Cyan
Write-Host "   URL: http://localhost:5678" -ForegroundColor Yellow
Write-Host "   Press Ctrl+C to stop" -ForegroundColor Yellow
Write-Host ""

# Start n8n
n8n start

# If n8n exits
Write-Host ""
Write-Host "👋 n8n stopped." -ForegroundColor Yellow
