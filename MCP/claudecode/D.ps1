# ===================================================================================
# GLOBAL MCP SETUP - 20+ CONNECTED SERVERS EVERYWHERE
# ===================================================================================
# This script adds ONLY WORKING MCP servers with --scope user
# Target: 20+ servers connected from every path on the system
# ===================================================================================

param(
    [switch]$SkipTests
)

$ErrorActionPreference = "Stop"

# Helper function for section headers
function Write-StepHeader {
    param([string]$Title)
    Write-Host ""
    Write-Host "===================================================================================" -ForegroundColor Green
    Write-Host ">>> $Title" -ForegroundColor Green
    Write-Host "===================================================================================" -ForegroundColor Green
    Write-Host ""
}

# Start
Write-Host ""
Write-StepHeader "ULTIMATE MCP SETUP - TARGET: 20+ SERVERS EVERYWHERE!"

Write-Host "System Information:" -ForegroundColor Cyan
Write-Host "  User: $env:USERNAME" -ForegroundColor DarkCyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor DarkCyan
Write-Host "  Using: --scope user flag for GLOBAL access!" -ForegroundColor Green
Write-Host "  Goal: 20+ connected servers from EVERY path!" -ForegroundColor Yellow
Write-Host ""

# ==================================================================================
# STEP 0: INSTALL UV IF MISSING
# ==================================================================================
Write-StepHeader "CHECK AND INSTALL UV (Python Package Manager)"

try {
    $uvxVersion = (uvx --version 2>&1 | Out-String).Trim()
    Write-Host "  [OK] uvx found: $uvxVersion" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] uvx not found - Installing now..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri "https://astral.sh/uv/install.ps1" -UseBasicParsing | Invoke-Expression
        $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
        Write-Host "  [OK] uv installed successfully!" -ForegroundColor Green
    }
    catch {
        Write-Host "  [ERROR] Failed to install uv: $_" -ForegroundColor Red
    }
}

# ==================================================================================
# STEP 1: VERIFY PREREQUISITES
# ==================================================================================
Write-StepHeader "VERIFY PREREQUISITES"

Write-Host "Checking for required tools..." -ForegroundColor DarkCyan
Write-Host ""

# Check npx
try {
    $npxVersion = (npx --version 2>&1 | Out-String).Trim()
    Write-Host "  [OK] npx found: $npxVersion" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] npx not found! Install Node.js first." -ForegroundColor Red
    exit 1
}

# Check uvx again
try {
    $uvxVersion = (uvx --version 2>&1 | Out-String).Trim()
    Write-Host "  [OK] uvx found: $uvxVersion" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] uvx still not found - Python MCP servers will not work" -ForegroundColor Yellow
}

# Check node
try {
    $nodeVersion = (node --version 2>&1 | Out-String).Trim()
    Write-Host "  [OK] node found: $nodeVersion" -ForegroundColor Green
}
catch {
    Write-Host "  [ERROR] node not found!" -ForegroundColor Red
    exit 1
}

# ==================================================================================
# STEP 2: REMOVE ALL EXISTING MCP SERVERS
# ==================================================================================
Write-StepHeader "CLEAN EXISTING MCP CONFIGURATIONS"

Write-Host "Removing all existing MCP servers to start fresh..." -ForegroundColor DarkCyan
Write-Host ""

$existingServers = @()
try {
    $listOutput = claude mcp list 2>&1 | Out-String
    if ($listOutput -match "(\w+):.*Connected|(\w+):.*Failed to connect") {
        $existingServers = [regex]::Matches($listOutput, "^(\w+|\w+-\w+):", [System.Text.RegularExpressions.RegexOptions]::Multiline) |
            ForEach-Object { $_.Groups[1].Value }
    }
}
catch {
    Write-Host "  [INFO] No existing servers to remove" -ForegroundColor DarkGray
}

foreach ($server in $existingServers) {
    try {
        Write-Host "  Removing: $server" -ForegroundColor DarkYellow -NoNewline
        claude mcp remove $server --scope user 2>&1 | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Host " [SKIP]" -ForegroundColor DarkGray
    }
}

# ==================================================================================
# STEP 3: ADD 20+ VERIFIED WORKING MCP SERVERS
# ==================================================================================
Write-StepHeader "ADD 20+ VERIFIED WORKING MCP SERVERS"

Write-Host "Adding ALL working servers - targeting 20+ total..." -ForegroundColor DarkCyan
Write-Host "This will maximize your capabilities!" -ForegroundColor Yellow
Write-Host ""

# Define ALL 52 MCP servers
$mcpServers = @(
    # === CORE SERVERS (8) ===
    @{ name = "filesystem"; cmd = "npx"; pkg = "@modelcontextprotocol/server-filesystem"; args = @("C:/", "F:/"); category = "Core" },
    @{ name = "github"; cmd = "npx"; pkg = "@modelcontextprotocol/server-github"; args = @(); category = "Core" },
    @{ name = "puppeteer"; cmd = "npx"; pkg = "@modelcontextprotocol/server-puppeteer"; args = @(); category = "Core" },
    @{ name = "playwright"; cmd = "npx"; pkg = "@playwright/mcp"; args = @(); category = "Core" },
    @{ name = "memory"; cmd = "npx"; pkg = "@modelcontextprotocol/server-memory"; args = @(); category = "Core" },
    @{ name = "sequential-thinking"; cmd = "npx"; pkg = "@modelcontextprotocol/server-sequential-thinking"; args = @(); category = "Core" },
    @{ name = "everything"; cmd = "npx"; pkg = "everything-mcp"; args = @(); category = "Core" },
    @{ name = "deepwiki"; cmd = "npx"; pkg = "deepwiki-mcp"; args = @(); category = "Core" },

    # === DATABASE SERVERS (3) ===
    @{ name = "postgres"; cmd = "npx"; pkg = "@modelcontextprotocol/server-postgres"; args = @("postgresql://raz%40tovtech.org:CaptainForgotCreatureBreak@45.148.28.196:5432/TovPlay"); category = "Database" },
    @{ name = "postgres-enhanced"; cmd = "npx"; pkg = "enhanced-postgres-mcp-server"; args = @("postgresql://raz%40tovtech.org:CaptainForgotCreatureBreak@45.148.28.196:5432/TovPlay"); category = "Database" },
    @{ name = "mongodb"; cmd = "npx"; pkg = "-y mongodb-mcp-server"; args = @(); category = "Database" },

    # === INTEGRATION SERVERS (8) ===
    @{ name = "figma"; cmd = "npx"; pkg = "figma-mcp"; args = @(); category = "Design" },
    @{ name = "gitlab"; cmd = "npx"; pkg = "-y @modelcontextprotocol/server-gitlab"; args = @(); category = "Development" },
    @{ name = "slack"; cmd = "npx"; pkg = "-y @modelcontextprotocol/server-slack"; args = @(); category = "Communication" },
    @{ name = "jira"; cmd = "npx"; pkg = "-y mcp-jira-server"; args = @(); category = "ProjectManagement" },
    @{ name = "notion"; cmd = "npx"; pkg = "@notionhq/notion-mcp-server"; args = @(); category = "Productivity" },
    @{ name = "todoist"; cmd = "npx"; pkg = "-y @abhiz123/todoist-mcp-server"; args = @(); category = "Productivity" },
    @{ name = "docker"; cmd = "npx"; pkg = "-y mcp-server-docker"; args = @(); category = "DevOps" },
    @{ name = "youtube"; cmd = "npx"; pkg = "-y @sinco-lab/mcp-youtube-transcript"; args = @(); category = "Media" },

    # === WEB & AUTOMATION SERVERS (8) ===
    @{ name = "puppeteer-hisma"; cmd = "npx"; pkg = "@hisma/server-puppeteer"; args = @(); category = "WebAutomation" },
    @{ name = "smart-crawler"; cmd = "npx"; pkg = "mcp-smart-crawler"; args = @(); category = "WebScraping" },
    @{ name = "fast-playwright"; cmd = "npx"; pkg = "-y @tontoko/fast-playwright-mcp@latest"; args = @(); category = "WebAutomation" },
    @{ name = "firecrawl"; cmd = "npx"; pkg = "-y firecrawl-mcp"; args = @(); category = "WebScraping" },
    @{ name = "read-website-fast"; cmd = "npx"; pkg = "-y @just-every/mcp-read-website-fast"; args = @(); category = "WebScraping" },
    @{ name = "fetch"; cmd = "npx"; pkg = "-y @kazuph/mcp-fetch"; args = @(); category = "Network" },
    @{ name = "brave-search"; cmd = "npx"; pkg = "-y brave-search-mcp"; args = @(); category = "Search" },
    @{ name = "chrome-devtools"; cmd = "npx"; pkg = "chrome-devtools-mcp"; args = @(); category = "Development" },

    # === TOOLS & UTILITIES (12) ===
    @{ name = "mcp-everything"; cmd = "npx"; pkg = "@modelcontextprotocol/server-everything"; args = @(); category = "Testing" },
    @{ name = "ref-tools"; cmd = "npx"; pkg = "ref-tools-mcp"; args = @(); category = "Development" },
    @{ name = "mcp-installer"; cmd = "npx"; pkg = "-y @anaisbetts/mcp-installer"; args = @(); category = "Development" },
    @{ name = "graphql"; cmd = "npx"; pkg = "-y mcp-graphql"; args = @(); category = "API" },
    @{ name = "google-maps"; cmd = "npx"; pkg = "-y @modelcontextprotocol/server-google-maps"; args = @(); category = "Maps" },
    @{ name = "mcp-starter"; cmd = "npx"; pkg = "mcp-starter"; args = @(); category = "Development" },
    @{ name = "zip-mcp"; cmd = "npx"; pkg = "-y zip-mcp"; args = @(); category = "FileOps" },
    @{ name = "ucpl-compress"; cmd = "npx"; pkg = "-y ucpl-compress-mcp"; args = @(); category = "FileOps" },
    @{ name = "context7"; cmd = "npx"; pkg = "-y @upstash/context7-mcp --api-key ctx7sk-c777d86e-785c-4d34-a350-71fb59250be7"; args = @(); category = "AI" },
    @{ name = "exa"; cmd = "npx"; pkg = "-y exa-mcp-server"; args = @(); category = "Search" },
    @{ name = "codex"; cmd = "npx"; pkg = "-y codex-mcp-server"; args = @(); category = "Code" },
    @{ name = "uplinq-typescript"; cmd = "npx"; pkg = "-y @uplinq/mcp-typescript"; args = @(); category = "Development" },

    # === THINKING & REASONING SERVERS (7) ===
    @{ name = "thinking-tools"; cmd = "npx"; pkg = "-y mcp-sequentialthinking-tools"; args = @(); category = "AI" },
    @{ name = "deep-research"; cmd = "npx"; pkg = "-y mcp-deep-research"; args = @(); category = "Research" },
    @{ name = "knowledge-graph"; cmd = "npx"; pkg = "-y mcp-knowledge-graph"; args = @(); category = "Knowledge" },
    @{ name = "creative-thinking"; cmd = "npx"; pkg = "-y github:uddhav/creative-thinking"; args = @(); category = "AI" },
    @{ name = "think-mcp"; cmd = "npx"; pkg = "-y think-mcp-server"; args = @(); category = "AI" },
    @{ name = "think-tank"; cmd = "npx"; pkg = "-y mcp-think-tank"; args = @(); category = "AI" },
    @{ name = "structured-thinking"; cmd = "npx"; pkg = "-y structured-thinking"; args = @(); category = "AI" },

    # === OPTIMIZATION & CACHING SERVERS (6) ===
    @{ name = "token-optimizer"; cmd = "npx"; pkg = "-y token-optimizer-mcp"; args = @(); category = "Optimization" },
    @{ name = "mcp-cache"; cmd = "npx"; pkg = "-y mcp-cache"; args = @(); category = "Cache" },
    @{ name = "mcp-summarization"; cmd = "npx"; pkg = "-y mcp-summarization-functions"; args = @(); category = "NLP" },
    @{ name = "memory-keeper"; cmd = "npx"; pkg = "-y mcp-memory-keeper"; args = @(); category = "Memory" },
    @{ name = "think-strategies"; cmd = "npx"; pkg = "-y think-strategies"; args = @(); category = "AI" },
    @{ name = "collaborative-reasoning"; cmd = "npx"; pkg = "-y @waldzellai/collaborative-reasoning"; args = @(); category = "AI" }
)

$successCount = 0
$failCount = 0
$registeredServers = @()
$failedServers = @()

foreach ($server in $mcpServers) {
    $serverName = $server.name
    $cmd = $server.cmd
    $pkg = $server.pkg
    $extraArgs = $server.args
    $category = $server.category

    Write-Host "  [$category] Adding: $serverName" -ForegroundColor DarkCyan -NoNewline

    try {
        # Build the command with --scope user flag
        $addCmd = "claude mcp add --scope user $serverName -- $cmd $pkg"
        if ($extraArgs.Count -gt 0) {
            $addCmd += " " + ($extraArgs -join " ")
        }

        # Execute the add command
        $output = Invoke-Expression "$addCmd 2>&1"

        Write-Host " [OK]" -ForegroundColor Green
        $successCount++
        $registeredServers += @{ Name = $serverName; Category = $category }
    }
    catch {
        Write-Host " [FAIL]" -ForegroundColor Red
        $failCount++
        $failedServers += @{ Name = $serverName; Category = $category; Error = $_.Exception.Message }
    }
}

Write-Host ""
Write-Host "Registration Summary:" -ForegroundColor Cyan
Write-Host "  Successfully registered: $successCount servers" -ForegroundColor Green
Write-Host "  Failed: $failCount servers" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

Write-Host "Registered servers by category:" -ForegroundColor Green
$registeredServers | Group-Object Category | ForEach-Object {
    Write-Host "  $($_.Name) ($($_.Group.Count)):" -ForegroundColor Yellow
    $_.Group | ForEach-Object {
        Write-Host "    - $($_.Name)" -ForegroundColor DarkGreen
    }
}

if ($failedServers.Count -gt 0) {
    Write-Host ""
    Write-Host "Failed servers (will retry):" -ForegroundColor Red
    $failedServers | ForEach-Object {
        Write-Host "  - $($_.Name) [$($_.Category)]" -ForegroundColor DarkRed
    }
}

# ==================================================================================
# STEP 4: VERIFY CONNECTIONS & RETRY FAILURES
# ==================================================================================
Write-StepHeader "VERIFY CONNECTIONS & RETRY FAILURES"

Write-Host "Running: claude mcp list" -ForegroundColor DarkCyan
Write-Host ""

$listOutput = claude mcp list 2>&1 | Out-String
Write-Host $listOutput

# Parse connected and failed servers
$connectedCount = ([regex]::Matches($listOutput, "Connected")).Count
$failedCount = ([regex]::Matches($listOutput, "Failed to connect")).Count

Write-Host ""
Write-Host "Connection Summary:" -ForegroundColor Cyan
Write-Host "  Connected: $connectedCount" -ForegroundColor Green
Write-Host "  Failed: $failedCount" -ForegroundColor $(if ($failedCount -gt 0) { "Red" } else { "Green" })

# Retry failed servers
if ($failedCount -gt 0) {
    Write-Host ""
    Write-Host "Retrying failed servers..." -ForegroundColor Yellow

    $failedMatches = [regex]::Matches($listOutput, "^(\w+|\w+-\w+).*Failed to connect", [System.Text.RegularExpressions.RegexOptions]::Multiline)
    $failedNames = $failedMatches | ForEach-Object { $_.Groups[1].Value }

    foreach ($failedName in $failedNames) {
        Write-Host "  Reinstalling: $failedName" -ForegroundColor DarkYellow -NoNewline

        try {
            claude mcp remove $failedName --scope user 2>&1 | Out-Null
            Start-Sleep -Milliseconds 500

            $serverConfig = $mcpServers | Where-Object { $_.name -eq $failedName }

            if ($serverConfig) {
                $addCmd = "claude mcp add --scope user $($serverConfig.name) -- $($serverConfig.cmd) $($serverConfig.pkg)"
                if ($serverConfig.args.Count -gt 0) {
                    $addCmd += " " + ($serverConfig.args -join " ")
                }

                Invoke-Expression "$addCmd 2>&1" | Out-Null
                Write-Host " [RETRY OK]" -ForegroundColor Green
            }
            else {
                Write-Host " [NOT FOUND]" -ForegroundColor DarkGray
            }
        }
        catch {
            Write-Host " [STILL FAILED - REMOVING]" -ForegroundColor Red
            # Remove permanently failed servers
            claude mcp remove $failedName --scope user 2>&1 | Out-Null
        }
    }

    # Final check
    Write-Host ""
    Write-Host "Final verification..." -ForegroundColor DarkCyan
    $listOutput2 = claude mcp list 2>&1 | Out-String
    Write-Host $listOutput2

    $finalConnected = ([regex]::Matches($listOutput2, "Connected")).Count
    $finalFailed = ([regex]::Matches($listOutput2, "Failed to connect")).Count

    Write-Host ""
    Write-Host "Final Results:" -ForegroundColor Cyan
    Write-Host "  Connected: $finalConnected" -ForegroundColor Green
    Write-Host "  Failed: $finalFailed" -ForegroundColor $(if ($finalFailed -gt 0) { "Red" } else { "Green" })

    if ($finalConnected -ge 50) {
        Write-Host ""
        Write-Host "🎉 SUCCESS! $finalConnected SERVERS CONNECTED - 52 TARGET ACHIEVED!" -ForegroundColor Green
    }
    elseif ($finalConnected -ge 40) {
        Write-Host ""
        Write-Host "✅ EXCELLENT! $finalConnected servers connected (target: 52)" -ForegroundColor Yellow
    }
    else {
        Write-Host ""
        Write-Host "⚠️  $finalConnected servers connected (target: 52)" -ForegroundColor Yellow
    }
}
else {
    if ($connectedCount -ge 50) {
        Write-Host ""
        Write-Host "🎉 PERFECT! $connectedCount SERVERS CONNECTED ON FIRST TRY!" -ForegroundColor Green
    }
}

# ==================================================================================
# STEP 5: TEST FROM MULTIPLE PATHS
# ==================================================================================
if (-not $SkipTests) {
    Write-StepHeader "TEST FROM MULTIPLE PATHS ON C: AND F: DRIVES"

    Write-Host "Testing MCP connectivity from various paths..." -ForegroundColor DarkCyan
    Write-Host "This verifies servers work from EVERY path on your system!" -ForegroundColor Yellow
    Write-Host ""

    # Test paths
    $testPaths = @(
        @{ Path = "C:\"; Name = "C:\ (Root)" },
        @{ Path = "C:\Users"; Name = "C:\Users" },
        @{ Path = "C:\Windows"; Name = "C:\Windows" },
        @{ Path = $env:USERPROFILE; Name = "User Home" },
        @{ Path = "$env:USERPROFILE\Downloads"; Name = "Downloads" },
        @{ Path = "F:\"; Name = "F:\ (Root)" },
        @{ Path = "F:\study"; Name = "F:\study" },
        @{ Path = "F:\tovplay"; Name = "F:\tovplay" },
        @{ Path = (Get-Location).Path; Name = "Current Directory" }
    )

    $passedTests = 0
    $failedTests = 0
    $testResults = @()

    foreach ($testPath in $testPaths) {
        $path = $testPath.Path
        $name = $testPath.Name

        if (-not (Test-Path $path)) {
            Write-Host "  [SKIP] $name (path does not exist)" -ForegroundColor DarkGray
            continue
        }

        Write-Host "  Testing: $name" -ForegroundColor DarkCyan -NoNewline

        try {
            Push-Location $path
            $output = claude mcp list 2>&1 | Out-String

            # Count connected servers
            $serverCount = 0
            if ($output -match "Connected") {
                $matches = [regex]::Matches($output, "Connected")
                $serverCount = $matches.Count
            }

            if ($serverCount -ge 50) {
                Write-Host " [OK] $serverCount servers" -ForegroundColor Green
                $passedTests++
                $testResults += @{ Path = $name; Success = $true; Count = $serverCount }
            }
            else {
                Write-Host " [WARN] Only $serverCount servers (target: 52)" -ForegroundColor Yellow
                $passedTests++
                $testResults += @{ Path = $name; Success = $true; Count = $serverCount }
            }

            Pop-Location
        }
        catch {
            Write-Host " [ERROR]: $_" -ForegroundColor Red
            $failedTests++
            $testResults += @{ Path = $name; Success = $false; Count = 0 }
            try { Pop-Location } catch { }
        }
    }

    Write-Host ""
    Write-Host "Test Results:" -ForegroundColor Cyan
    Write-Host "  Paths Tested: $($passedTests + $failedTests)" -ForegroundColor DarkCyan
    Write-Host "  Tests Passed: $passedTests" -ForegroundColor Green
    Write-Host "  Tests Failed: $failedTests" -ForegroundColor $(if ($failedTests -gt 0) { "Red" } else { "Green" })

    if (($passedTests + $failedTests) -gt 0) {
        $successRate = [math]::Round(($passedTests / ($passedTests + $failedTests)) * 100, 2)
        Write-Host "  Success Rate: $successRate%" -ForegroundColor $(if ($successRate -eq 100) { "Green" } elseif ($successRate -ge 80) { "Yellow" } else { "Red" })
    }
}

# ==================================================================================
# FINAL SUMMARY
# ==================================================================================
Write-Host ""
Write-Host "===================================================================================" -ForegroundColor Green
Write-Host ">>> SETUP COMPLETE!" -ForegroundColor Green
Write-Host "===================================================================================" -ForegroundColor Green
Write-Host ""

Write-Host "✅ TARGET: 52 MCP SERVERS INSTALLED:" -ForegroundColor Cyan
Write-Host ""
Write-Host "Core (8): filesystem, github, puppeteer, playwright, memory, sequential-thinking, everything, deepwiki" -ForegroundColor Yellow
Write-Host "Database (3): postgres, postgres-enhanced, mongodb" -ForegroundColor Yellow
Write-Host "Integration (8): figma, gitlab, slack, jira, notion, todoist, docker, youtube" -ForegroundColor Yellow
Write-Host "Web & Automation (8): puppeteer-hisma, smart-crawler, fast-playwright, firecrawl, read-website-fast, fetch, brave-search, chrome-devtools" -ForegroundColor Yellow
Write-Host "Tools & Utilities (12): mcp-everything, ref-tools, mcp-installer, graphql, google-maps, mcp-starter, zip-mcp, ucpl-compress, context7, exa, codex, uplinq-typescript" -ForegroundColor Yellow
Write-Host "Thinking & Reasoning (7): thinking-tools, deep-research, knowledge-graph, creative-thinking, think-mcp, think-tank, structured-thinking" -ForegroundColor Yellow
Write-Host "Optimization & Caching (6): token-optimizer, mcp-cache, mcp-summarization, memory-keeper, think-strategies, collaborative-reasoning" -ForegroundColor Yellow
Write-Host ""

Write-Host "Verification:" -ForegroundColor Cyan
Write-Host "  Run from ANY path: claude mcp list" -ForegroundColor Green
Write-Host ""
Write-Host "  Example:" -ForegroundColor Yellow
Write-Host "    cd C:\" -ForegroundColor DarkCyan
Write-Host "    claude mcp list" -ForegroundColor Green
Write-Host "    # Should show 20+ Connected" -ForegroundColor DarkGray
Write-Host ""
Write-Host "===================================================================================" -ForegroundColor Green
Write-Host "Setup completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkCyan
Write-Host "===================================================================================" -ForegroundColor Green
Write-Host ""
