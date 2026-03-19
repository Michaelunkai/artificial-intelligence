Write-Host "`n=== DOCKER/WSL OPTIMIZATION (SAFE) ===" -ForegroundColor Cyan

Write-Host "`nShutting down WSL..." -ForegroundColor Yellow
wsl --shutdown
Start-Sleep -Seconds 5

Write-Host "`nEnabling sparse VHD for docker-desktop-data..." -ForegroundColor Yellow
wsl --manage docker-desktop-data --set-sparse true 2>&1

Write-Host "`nEnabling sparse VHD for docker-desktop..." -ForegroundColor Yellow
wsl --manage docker-desktop --set-sparse true 2>&1

Write-Host "`nWaiting for Docker to restart..." -ForegroundColor Yellow
Start-Sleep -Seconds 10

Write-Host "`nPruning Docker system (removing unused resources)..." -ForegroundColor Yellow
docker system prune -af --volumes 2>&1

Write-Host "`nPruning Docker build cache..." -ForegroundColor Yellow
docker builder prune -af 2>&1

Write-Host "`nDocker optimization complete!" -ForegroundColor Green
