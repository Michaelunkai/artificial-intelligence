# FAST MCP SETUP - ONLY KNOWN WORKING SERVERS
Write-Host ""
Write-Host "========== FAST MCP SETUP ==========" -ForegroundColor Green
Write-Host ""

# Remove all first
Write-Host "Cleaning up old servers..." -ForegroundColor Yellow
$output = (claude mcp list 2>&1)
$servers = @()
$output | ForEach-Object {
    if ($_ -match '^([a-z0-9-]+):') {
        $servers += $matches[1]
    }
}

foreach ($server in $servers) {
    claude mcp remove $server --scope user 2>&1 | Out-Null
    Start-Sleep -Milliseconds 300
}

Write-Host "Cleaned!" -ForegroundColor Green
Write-Host ""

# NOW add ONLY proven working servers
$workingServers = @(
    @{name='filesystem'; pkg='@modelcontextprotocol/server-filesystem'; args='C:/ F:/'},
    @{name='github'; pkg='@modelcontextprotocol/server-github'; args=''},
    @{name='puppeteer'; pkg='@modelcontextprotocol/server-puppeteer'; args=''},
    @{name='playwright'; pkg='@playwright/mcp'; args=''},
    @{name='memory'; pkg='@modelcontextprotocol/server-memory'; args=''},
    @{name='sequential-thinking'; pkg='@modelcontextprotocol/server-sequential-thinking'; args=''},
    @{name='everything'; pkg='everything-mcp'; args=''},
    @{name='deepwiki'; pkg='deepwiki-mcp'; args=''},
    @{name='postgres'; pkg='@modelcontextprotocol/server-postgres'; args='postgresql://raz%40tovtech.org:CaptainForgotCreatureBreak@45.148.28.196:5432/TovPlay'},
    @{name='postgres-enhanced'; pkg='enhanced-postgres-mcp-server'; args='postgresql://raz%40tovtech.org:CaptainForgotCreatureBreak@45.148.28.196:5432/TovPlay'},
    @{name='figma'; pkg='figma-mcp'; args=''},
    @{name='notion'; pkg='@notionhq/notion-mcp-server'; args=''},
    @{name='puppeteer-hisma'; pkg='@hisma/server-puppeteer'; args=''},
    @{name='smart-crawler'; pkg='mcp-smart-crawler'; args=''},
    @{name='chrome-devtools'; pkg='chrome-devtools-mcp'; args=''},
    @{name='mcp-everything'; pkg='@modelcontextprotocol/server-everything'; args=''},
    @{name='ref-tools'; pkg='ref-tools-mcp'; args=''},
    @{name='mcp-starter'; pkg='mcp-starter'; args=''},
    @{name='gitlab'; pkg='@modelcontextprotocol/server-gitlab'; args=''},
    @{name='youtube'; pkg='@sinco-lab/mcp-youtube-transcript'; args=''},
    @{name='mcp-installer'; pkg='@anaisbetts/mcp-installer'; args=''},
    @{name='graphql'; pkg='mcp-graphql'; args=''},
    @{name='fetch'; pkg='@kazuph/mcp-fetch'; args=''},
    @{name='mongodb'; pkg='mongodb-mcp-server'; args=''},
    @{name='jira'; pkg='mcp-jira-server'; args=''},
    @{name='docker'; pkg='mcp-server-docker'; args=''},
    @{name='slack'; pkg='@modelcontextprotocol/server-slack'; args=''},
    @{name='brave-search'; pkg='brave-search-mcp'; args=''},
    @{name='todoist'; pkg='@abhiz123/todoist-mcp-server'; args=''},
    @{name='google-maps'; pkg='@modelcontextprotocol/server-google-maps'; args=''},
    @{name='context7'; pkg='@upstash/context7-mcp'; args='--api-key ctx7sk-c777d86e-785c-4d34-a350-71fb59250be7'},
    @{name='deep-research'; pkg='mcp-deep-research'; args=''},
    @{name='knowledge-graph'; pkg='mcp-knowledge-graph'; args=''},
    @{name='creative-thinking'; pkg='github:uddhav/creative-thinking'; args=''},
    @{name='thinking-tools'; pkg='mcp-sequentialthinking-tools'; args=''},
    @{name='token-optimizer'; pkg='token-optimizer-mcp'; args=''},
    @{name='collaborative-reasoning'; pkg='@waldzellai/collaborative-reasoning'; args=''},
    @{name='ucpl-compress'; pkg='ucpl-compress-mcp'; args=''},
    @{name='exa'; pkg='exa-mcp-server'; args=''},
    @{name='structured-thinking'; pkg='structured-thinking'; args=''},
    @{name='fast-playwright'; pkg='@tontoko/fast-playwright-mcp@latest'; args=''},
    @{name='read-website-fast'; pkg='@just-every/mcp-read-website-fast'; args=''},
    @{name='codex'; pkg='codex-mcp-server'; args=''},
    @{name='think-strategies'; pkg='think-strategies'; args=''}
)

Write-Host "Adding $($workingServers.Count) servers..." -ForegroundColor Cyan
$count = 0

foreach ($srv in $workingServers) {
    $count++
    Write-Host "[$count/$($workingServers.Count)] $($srv.name)..." -NoNewline

    if ($srv.args) {
        $cmd = "claude mcp add --scope user $($srv.name) -- npx $($srv.pkg) $($srv.args)"
    } else {
        $cmd = "claude mcp add --scope user $($srv.name) -- npx $($srv.pkg)"
    }

    Invoke-Expression $cmd 2>&1 | Out-Null
    Start-Sleep -Milliseconds 500
    Write-Host " OK" -ForegroundColor Green
}

Write-Host ""
Write-Host "Done! Checking status..." -ForegroundColor Cyan
Write-Host ""

Start-Sleep -Seconds 3
$result = claude mcp list 2>&1
$connected = ($result | Select-String "Connected" | Measure-Object).Count
$failed = ($result | Select-String "Failed to connect" | Measure-Object).Count

Write-Host "RESULTS:" -ForegroundColor Green
Write-Host "  Connected: $connected" -ForegroundColor Green
Write-Host "  Failed: $failed" -ForegroundColor $(if ($failed -gt 0) { "Red" } else { "Green" })
Write-Host ""

$result
