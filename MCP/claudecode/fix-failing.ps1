# Fix 8 failing MCP servers
$failingServers = @(
    @{name='mcp-cache'; pkg='mcp-cache'},
    @{name='mcp-summarization'; pkg='mcp-summarization-functions'},
    @{name='zip-mcp'; pkg='zip-mcp'},
    @{name='memory-keeper'; pkg='mcp-memory-keeper'},
    @{name='think-mcp'; pkg='think-mcp-server'},
    @{name='think-tank'; pkg='mcp-think-tank'},
    @{name='firecrawl'; pkg='firecrawl-mcp'},
    @{name='uplinq-typescript'; pkg='@uplinq/mcp-typescript'}
)

Write-Host ""
Write-Host "========== FIXING 8 FAILING MCP SERVERS ==========" -ForegroundColor Green
Write-Host ""

foreach ($server in $failingServers) {
    $name = $server.name
    $pkg = $server.pkg

    Write-Host "Fixing: $name..." -ForegroundColor Yellow -NoNewline

    # Remove
    claude mcp remove $name --scope user 2>&1 | Out-Null
    Start-Sleep -Seconds 1

    # Add with -y flag
    claude mcp add --scope user $name -- npx -y $pkg 2>&1 | Out-Null
    Start-Sleep -Seconds 2

    # Check status
    $output = (claude mcp list 2>&1 | Out-String)
    if ($output -match "$name.*Connected") {
        Write-Host " [OK] Connected" -ForegroundColor Green
    }
    else {
        Write-Host " [RETRY]" -ForegroundColor Yellow
        Start-Sleep -Seconds 2
        claude mcp remove $name --scope user 2>&1 | Out-Null
        Start-Sleep -Seconds 1
        claude mcp add --scope user $name -- npx -y $pkg 2>&1 | Out-Null
        Start-Sleep -Seconds 3

        $output2 = (claude mcp list 2>&1 | Out-String)
        if ($output2 -match "$name.*Connected") {
            Write-Host " [RETRY OK]" -ForegroundColor Green
        }
        else {
            Write-Host " [STILL FAILING]" -ForegroundColor Red
        }
    }
}

Write-Host ""
Write-Host "========== FINAL VERIFICATION ==========" -ForegroundColor Cyan
Write-Host ""

$finalOutput = claude mcp list 2>&1 | Out-String
$connected = ([regex]::Matches($finalOutput, "Connected")).Count
$failed = ([regex]::Matches($finalOutput, "Failed to connect")).Count

Write-Host "Connected: $connected" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })

if ($connected -ge 45) {
    Write-Host ""
    Write-Host "✅ SUCCESS! $connected SERVERS CONNECTED!" -ForegroundColor Green
}

Write-Host ""
Write-Host "Full list:" -ForegroundColor Cyan
Write-Host ""
Write-Host $finalOutput
