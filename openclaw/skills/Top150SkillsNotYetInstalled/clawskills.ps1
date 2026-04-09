# clawskills - List available OpenClaw skills
$skillsDir = "$env:USERPROFILE\.claude\commands"
if (-not (Test-Path $skillsDir)) { Write-Host "No skills directory found" -ForegroundColor Yellow; return }
Write-Host "=== Available Skills ===" -ForegroundColor Cyan
Get-ChildItem $skillsDir -Filter "*.md" -Recurse -ErrorAction SilentlyContinue | ForEach-Object {
    $name = $_.BaseName
    $first = (Get-Content $_.FullName -TotalCount 3 | Select-String "description:" | ForEach-Object { $_ -replace '.*description:\s*', '' }) -join ''
    Write-Host "  /$name $(if($first){" - $first"})" -ForegroundColor White
}