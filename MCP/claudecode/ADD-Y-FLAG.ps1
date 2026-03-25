# Add -y flag to all failing servers
Write-Host "Adding -y flag to all servers to fix connections..." -ForegroundColor Cyan

$servers = @(
    'filesystem','github','puppeteer','playwright','memory','sequential-thinking',
    'everything','deepwiki','postgres','postgres-enhanced','figma','notion',
    'puppeteer-hisma','smart-crawler','chrome-devtools','mcp-everything','ref-tools',
    'mcp-starter','gitlab','youtube','mcp-installer','graphql','fetch','mongodb',
    'jira','docker','slack','brave-search','todoist','google-maps','context7',
    'deep-research','knowledge-graph','creative-thinking','thinking-tools',
    'token-optimizer','collaborative-reasoning','ucpl-compress','exa',
    'structured-thinking','fast-playwright','read-website-fast','codex','think-strategies'
)

$count = 0
foreach ($server in $servers) {
    $count++
    Write-Host "[$count/$($servers.Count)] $server... " -NoNewline

    # Get current config
    $pattern = "^" + $server + ":"
    $current = (claude mcp list 2>&1 | Select-String $pattern)
    if ($current) {
        # Extract the package name and args
        if ($current -match "npx (.*?) ") {
            $pkg = $matches[1]

            # Remove current
            claude mcp remove $server --scope user 2>&1 | Out-Null
            Start-Sleep -Milliseconds 300

            # Re-add with -y
            $cmd = "claude mcp add --scope user $server -- npx -y $pkg"
            Invoke-Expression $cmd 2>&1 | Out-Null
            Write-Host "OK" -ForegroundColor Green
        } else {
            Write-Host "SKIP" -ForegroundColor Yellow
        }
    } else {
        Write-Host "NOT FOUND" -ForegroundColor DarkGray
    }

    Start-Sleep -Milliseconds 200
}

Write-Host ""
Write-Host "Waiting 5 seconds for registration..." -ForegroundColor Yellow
Start-Sleep -Seconds 5

Write-Host ""
Write-Host "FINAL STATUS:" -ForegroundColor Cyan
$result = claude mcp list 2>&1
$connected = ($result | Select-String "Connected" | Measure-Object).Count
$failed = ($result | Select-String "Failed to connect" | Measure-Object).Count

Write-Host "Connected: $connected" -ForegroundColor Green
Write-Host "Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""
Write-Host $result
