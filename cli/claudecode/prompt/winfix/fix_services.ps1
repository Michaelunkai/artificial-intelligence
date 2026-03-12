# Fix Stopped Critical Services
Write-Host "=== STARTING STOPPED CRITICAL SERVICES ===" -ForegroundColor Cyan
Write-Host ""

# LanmanWorkstation
Write-Host "Starting LanmanWorkstation..." -ForegroundColor Yellow
Start-Service LanmanWorkstation -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$svc = Get-Service LanmanWorkstation
Write-Host "  LanmanWorkstation: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })

# BITS
Write-Host "Starting BITS..." -ForegroundColor Yellow
Start-Service BITS -ErrorAction SilentlyContinue
Start-Sleep -Seconds 3
$svc = Get-Service BITS
Write-Host "  BITS: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })

# W32Time
Write-Host "Starting W32Time..." -ForegroundColor Yellow
Start-Service W32Time -ErrorAction SilentlyContinue
Start-Sleep -Seconds 2
$svc = Get-Service W32Time
Write-Host "  W32Time: $($svc.Status)" -ForegroundColor $(if ($svc.Status -eq 'Running') { 'Green' } else { 'Red' })

Write-Host ""
Write-Host "Service fix completed!" -ForegroundColor Green
