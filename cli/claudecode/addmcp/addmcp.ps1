<#
.SYNOPSIS
    addmcp
#>
param(
        [Parameter(Mandatory=$true, ValueFromRemainingArguments=$true)]
        [string[]]$servers
    )

    cd C:/users/micha

    $serverList = $servers -join "', '"
    $serverList = "'$serverList'"

    $prompt = @"
=== CRITICAL MISSION: ADD MCP SERVERS ===

READ AND FOLLOW ALL RULES IN CLAUDE.MD - EVERY SINGLE RULE WITHOUT EXCEPTION!

SERVERS TO ADD: $serverList

YOUR MISSION (100% AUTONOMOUS - NO STOPPING):
1. Read C:\users\micha\Documents\WindowsPowerShell\CLAUDE.md completely
2. Follow Rule 2 EXACTLY for EACH server:
   - Search npm/web for the MCP package name
   - Install globally with npm install -g <package-name>
   - Find installed path with npm list -g <package-name>
   - Locate the main .js file in node_modules
   - Create .cmd wrapper in C:\Users\micha\.claude\
   - Add to Claude with: claude mcp add <name> C:\Users\micha\.claude\<name>.cmd -s user
   - Verify connection with claude mcp list
   - If Failed to connect, immediately remove with: claude mcp remove <name> -s user
   - ONLY after confirming Connected status, add to C:\Users\micha\.claude\mcp-ondemand.ps1

3. For EACH server added to mcp-ondemand.ps1:
   - Add server definition to `$script:MCPServers hashtable with format:
     "<name>" = @{ wrapper = "<name>.cmd"; description = "<desc>" }
   - Add server name to the CORRECT category in `$script:MCPCategories hashtable:
     * BROWSER: puppeteer, playwright, fast-playwright
     * DATABASE: postgres, mongodb, graphql
     * DEVTOOLS: docker, sentry, mcp-installer, mcp-server-commands, llm-context, kubernetes-mcp, python-repl-mcp
     * DOCS: context7, deepwiki, youtube, figma
     * GIT: github, git-mcp
     * MEMORY: memory, knowledge-graph, sequential-thinking
     * PRODUCTIVITY: task-master-mcp
     * SCRAPING: smart-crawler, read-website-fast
     * SEARCH: exa, deep-research, duckduckgo-search, open-websearch, mcp-compass
     * SECURITY: atomic-red-team-mcp
     * SYSTEM: filesystem, everything, windows-mcp, darbot-windows-mcp, computer-use-mcp, wmi-mcp, registry-mcp, eventlog-mcp, services-mcp, device-manager-mcp, disk-usage-mcp, startup-mcp, restore-point-mcp, network-info-mcp, scheduled-tasks-mcp, mcp-pyautogui, desktop-commander, mcp-shell-server, powershell-mcp, clipboard-mcp
     * UTILS: time-mcp, document-generator-mcp, pypi-query-mcp, npm-search-mcp

4. DO NOT STOP UNTIL YOU RUN THIS EXACT VERIFICATION SEQUENCE AND ALL PASS:
   down; claude mcp list; c; claude mcp list; mcps; mcpl

   Helper functions available:
   - down: cd F:\downloads
   - c: cd C:\
   - clau: rules; claude --dangerously-skip-permissions
   - mcps: mcp-status
   - mcpl: mcp-list

5. VERIFICATION REQUIREMENTS (ALL MUST PASS):
   - claude mcp list shows ALL servers with Connected status
   - mcps (mcp-status) shows ALL servers in correct categories
   - mcpl (mcp-list) shows ALL servers available

6. NEVER STOP until:
   - ALL servers successfully added
   - ALL servers show Connected in claude mcp list
   - ALL servers appear in mcps with correct category
   - ALL servers appear in mcpl
   - Verification sequence completes successfully

REMEMBER: You are FORBIDDEN from ending prematurely or marking tasks done without proof. Work 100% autonomously. Never ask user to do anything manually.

BEGIN NOW!
"@

    Write-Host "`n=== LAUNCHING MCP SERVER ADDITION MISSION ===" -ForegroundColor Green
    Write-Host "Servers to add: $serverList" -ForegroundColor Cyan
    Write-Host "`nExecuting: mcpoff; defmod2; thinkoff; clau prompt..." -ForegroundColor Yellow
    Write-Host ""

    Invoke-Expression "mcpoff; defmod2; thinkoff; clau prompt `"$prompt`""
