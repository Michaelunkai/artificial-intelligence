Write-Host "Removing all MCP servers..." -ForegroundColor Yellow

$output = (claude mcp list 2>&1)
$servers = @()

$output | ForEach-Object {
    if ($_ -match '^([a-z0-9-]+):') {
        $servers += $matches[1]
    }
}

Write-Host "Found $($servers.Count) servers to remove" -ForegroundColor Cyan
Write-Host ""

foreach ($server in $servers) {
    Write-Host "  Removing: $server" -NoNewline
    claude mcp remove $server --scope user 2>&1 | Out-Null
    Write-Host " [OK]" -ForegroundColor Green
    Start-Sleep -Milliseconds 500
}

Write-Host ""
Write-Host "Cleanup complete!" -ForegroundColor Green
Write-Host ""
Write-Host "Running D.ps1 to reinstall all working servers..." -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 2
& "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\MCP\claudecode\D.ps1" -SkipTests
