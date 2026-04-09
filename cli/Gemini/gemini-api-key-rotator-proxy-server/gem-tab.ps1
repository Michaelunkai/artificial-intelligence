$env:GOOGLE_GEMINI_BASE_URL = "http://127.0.0.1:4443"
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "  Gemini CLI routed through proxy on :4443" -ForegroundColor Green
Write-Host "  Proxy logs are in the other tab." -ForegroundColor Green
Write-Host "==============================================" -ForegroundColor Cyan
Write-Host "Waiting 4s for proxy to be ready..." -ForegroundColor Yellow
Start-Sleep -Seconds 4
Write-Host "Launching gem..." -ForegroundColor Green
gem
