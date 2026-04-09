# clawhooks - List and manage OpenClaw hooks
$hooksDir = "$env:USERPROFILE\.openclaw\hooks"
if (-not (Test-Path $hooksDir)) { Write-Host "No hooks directory found" -ForegroundColor Yellow; return }
Write-Host "=== OpenClaw Hooks ===" -ForegroundColor Cyan
Get-ChildItem $hooksDir -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "  $($_.Name) ($([math]::Round($_.Length/1KB, 1))KB)" -ForegroundColor White
}