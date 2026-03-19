# Discover ALL Claude-related paths on system
Write-Host "=== CLAUDE DISCOVERY SCAN ===" -ForegroundColor Cyan

# 1. NPM Packages
Write-Host "`n[NPM Packages]" -ForegroundColor Yellow
$npmRoot = "$env:APPDATA\npm\node_modules"
Get-ChildItem -Path $npmRoot -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude|anthropic' } | ForEach-Object { Write-Host "  $_" }

# NPM Binaries
Write-Host "`n[NPM Binaries]" -ForegroundColor Yellow
Get-ChildItem -Path "$env:APPDATA\npm" -File -Filter "claude*" -ErrorAction SilentlyContinue | ForEach-Object { Write-Host "  $($_.Name)" }

# 2. AppData Roaming
Write-Host "`n[AppData Roaming]" -ForegroundColor Yellow
Get-ChildItem -Path $env:APPDATA -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude|anthropic' } | ForEach-Object { Write-Host "  $_" }

# 3. AppData Local
Write-Host "`n[AppData Local]" -ForegroundColor Yellow
Get-ChildItem -Path $env:LOCALAPPDATA -Directory -ErrorAction SilentlyContinue | Where-Object { $_.Name -match 'claude|anthropic' } | ForEach-Object { Write-Host "  $_" }

# 4. User Profile Root
Write-Host "`n[User Profile Root]" -ForegroundColor Yellow
Get-ChildItem -Path $env:USERPROFILE -ErrorAction SilentlyContinue | Where-Object { $_.Name -match '^\.?claude' } | ForEach-Object { Write-Host "  $($_.Name)" }

# 5. Nested npm packages
Write-Host "`n[Nested Claude in npm packages]" -ForegroundColor Yellow
Get-ChildItem -Path $npmRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
    $nested = Join-Path $_.FullName "node_modules\@anthropic-ai\claude-code"
    if (Test-Path $nested) {
        Write-Host "  $($_.Name) -> @anthropic-ai/claude-code"
    }
}

# 6. Environment Variables
Write-Host "`n[Environment Variables]" -ForegroundColor Yellow
[Environment]::GetEnvironmentVariables('User').GetEnumerator() | Where-Object { $_.Key -match 'claude|anthropic' -or $_.Value -match 'claude|anthropic' } | ForEach-Object { Write-Host "  $($_.Key) = $($_.Value)" }

# 7. PATH entries with node/npm
Write-Host "`n[PATH with node/npm]" -ForegroundColor Yellow
$env:PATH -split ';' | Where-Object { $_ -match 'node|npm' } | ForEach-Object { Write-Host "  $_" }

Write-Host "`n=== SCAN COMPLETE ===" -ForegroundColor Cyan
