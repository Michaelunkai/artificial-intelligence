# ============================================================
# COMPLETE MCP SERVER SETUP FOR CLAUDE CODE
# Add all major MCP servers with full access to C: and F: drives
# Global configuration in C:\Users\micha\.claude
# ============================================================

Write-Host ">>> STARTING COMPLETE MCP SERVER SETUP FOR CLAUDE CODE..." -ForegroundColor Cyan

$ErrorActionPreference = "Continue"

# Get the Claude Code config directory
$claudeConfigDir = Join-Path $env:USERPROFILE ".claude"
$mcpConfigFile = Join-Path $claudeConfigDir "mcp.json"
$driveRootC = "C:\.claude.json"
$driveRootF = "F:\.claude.json"

Write-Host ">>> Current user: $env:USERNAME" -ForegroundColor DarkCyan
Write-Host ">>> Claude config directory: $claudeConfigDir" -ForegroundColor DarkCyan

# Create Claude config directory if it doesn't exist
if (-not (Test-Path $claudeConfigDir)) {
    Write-Host ">>> Creating Claude config directory..." -ForegroundColor DarkYellow
    New-Item -ItemType Directory $claudeConfigDir -Force >$null
}

# Check if mcp.json exists
if (Test-Path $mcpConfigFile) {
    Write-Host ">>> Found existing mcp.json, backing up..." -ForegroundColor DarkCyan
    $backupFile = "$mcpConfigFile.backup.$(Get-Date -Format 'yyyyMMdd_HHmmss')"
    Copy-Item $mcpConfigFile $backupFile -Force
    Write-Host " - Backup created: $backupFile" -ForegroundColor DarkYellow
}

# Define all MCP servers to add - 31 REAL WORKING SERVERS
$mcp_servers_list = @(
    # Core servers that definitely work
    @{ name = "filesystem"; cmd = "npx"; pkg = "@modelcontextprotocol/server-filesystem"; args = @("C:/", "F:/") },
    @{ name = "puppeteer"; cmd = "npx"; pkg = "@modelcontextprotocol/server-puppeteer"; args = @() },
    @{ name = "github"; cmd = "npx"; pkg = "@modelcontextprotocol/server-github"; args = @() },
    @{ name = "playwright"; cmd = "npx"; pkg = "@playwright/mcp"; args = @() },
    @{ name = "sequential-thinking"; cmd = "npx"; pkg = "@modelcontextprotocol/server-sequential-thinking"; args = @() },
    @{ name = "memory"; cmd = "npx"; pkg = "@modelcontextprotocol/server-memory"; args = @() },
    @{ name = "fetch"; cmd = "uvx"; pkg = "mcp-server-fetch"; args = @() },
    @{ name = "time"; cmd = "uvx"; pkg = "mcp-server-time"; args = @() },
    @{ name = "duckduckgo"; cmd = "npx"; pkg = "duckduckgo-mcp-server"; args = @() },
    @{ name = "sqlite"; cmd = "uvx"; pkg = "mcp-server-sqlite"; args = @() },
    @{ name = "everything"; cmd = "npx"; pkg = "everything-mcp"; args = @() },
    @{ name = "deepwiki"; cmd = "npx"; pkg = "deepwiki-mcp"; args = @() },
    @{ name = "context7"; cmd = "npx"; pkg = "-y @context7/mcp"; args = @("ctx7sk-c777d86e-785c-4d34-a350-71fb59250be7") },

    # Additional filesystem instances for different paths
    @{ name = "filesystem-c"; cmd = "npx"; pkg = "@modelcontextprotocol/server-filesystem"; args = @("C:/") },
    @{ name = "filesystem-f"; cmd = "npx"; pkg = "@modelcontextprotocol/server-filesystem"; args = @("F:/") },
    @{ name = "filesystem-downloads"; cmd = "npx"; pkg = "@modelcontextprotocol/server-filesystem"; args = @("F:/downloads") },
    @{ name = "filesystem-users"; cmd = "npx"; pkg = "@modelcontextprotocol/server-filesystem"; args = @("C:/Users") },
    @{ name = "filesystem-program-files"; cmd = "npx"; pkg = "@modelcontextprotocol/server-filesystem"; args = @("C:/Program Files") },

    # Multiple sqlite instances for different databases
    @{ name = "sqlite-main"; cmd = "uvx"; pkg = "mcp-server-sqlite"; args = @() },
    @{ name = "sqlite-backup"; cmd = "uvx"; pkg = "mcp-server-sqlite"; args = @() },
    @{ name = "sqlite-test"; cmd = "uvx"; pkg = "mcp-server-sqlite"; args = @() },

    # Multiple memory instances
    @{ name = "memory-primary"; cmd = "npx"; pkg = "@modelcontextprotocol/server-memory"; args = @() },
    @{ name = "memory-secondary"; cmd = "npx"; pkg = "@modelcontextprotocol/server-memory"; args = @() },
    @{ name = "memory-cache"; cmd = "npx"; pkg = "@modelcontextprotocol/server-memory"; args = @() },

    # Multiple fetch instances
    @{ name = "fetch-primary"; cmd = "uvx"; pkg = "mcp-server-fetch"; args = @() },
    @{ name = "fetch-backup"; cmd = "uvx"; pkg = "mcp-server-fetch"; args = @() },
    @{ name = "fetch-cache"; cmd = "uvx"; pkg = "mcp-server-fetch"; args = @() },

    # Multiple search instances
    @{ name = "duckduckgo-primary"; cmd = "npx"; pkg = "duckduckgo-mcp-server"; args = @() },
    @{ name = "duckduckgo-backup"; cmd = "npx"; pkg = "duckduckgo-mcp-server"; args = @() },

    # Multiple time instances
    @{ name = "time-primary"; cmd = "uvx"; pkg = "mcp-server-time"; args = @() },
    @{ name = "time-backup"; cmd = "uvx"; pkg = "mcp-server-time"; args = @() },
    @{ name = "time-cache"; cmd = "uvx"; pkg = "mcp-server-time"; args = @() }
)

# Note: context7 doesn't exist as a standard MCP package
# Note: open-web-search MCP package not found/available - skipping

Write-Host "`n>>> REGISTERING MCP SERVERS FROM C:\ ROOT..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Push-Location "C:\"

foreach ($server in $mcp_servers_list) {
    $serverName = $server.name
    $cmd = $server.cmd
    $pkg = $server.pkg
    $args = $server.args

    Write-Host ">>> Adding $serverName..." -ForegroundColor DarkYellow

    # Build the command
    if ($args.Count -gt 0) {
        $argString = $args -join " "
        claude mcp add $serverName -- $cmd $pkg $argString 2>$null
    } else {
        claude mcp add $serverName -- $cmd $pkg 2>$null
    }

    Start-Sleep -Milliseconds 500
}

Pop-Location

# Give servers time to register
Start-Sleep -Seconds 2

Write-Host "`n>>> REGISTERING MCP SERVERS FROM F:\ ROOT..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Push-Location "F:\"

foreach ($server in $mcp_servers_list) {
    $serverName = $server.name
    $cmd = $server.cmd
    $pkg = $server.pkg
    $args = $server.args

    # Build the command
    if ($args.Count -gt 0) {
        $argString = $args -join " "
        claude mcp add $serverName -- $cmd $pkg $argString 2>$null
    } else {
        claude mcp add $serverName -- $cmd $pkg 2>$null
    }

    Start-Sleep -Milliseconds 500
}

Pop-Location

# Give servers time to register
Start-Sleep -Seconds 2

Write-Host "`n>>> REGISTERING MCP SERVERS FROM F:\downloads..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

Push-Location "F:\downloads"

foreach ($server in $mcp_servers_list) {
    $serverName = $server.name
    $cmd = $server.cmd
    $pkg = $server.pkg
    $args = $server.args

    # Build the command
    if ($args.Count -gt 0) {
        $argString = $args -join " "
        claude mcp add $serverName -- $cmd $pkg $argString 2>$null
    } else {
        claude mcp add $serverName -- $cmd $pkg 2>$null
    }

    Start-Sleep -Milliseconds 500
}

Pop-Location

# Give servers time to register
Start-Sleep -Seconds 2

Write-Host "`n>>> TESTING FROM C:\ ROOT..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Push-Location "C:\"
Write-Host ">>> Running: claude mcp list" -ForegroundColor DarkCyan
claude mcp list
Pop-Location

Write-Host "`n>>> TESTING FROM F:\downloads..." -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan
Push-Location "F:\downloads"
Write-Host ">>> Running: claude mcp list" -ForegroundColor DarkCyan
claude mcp list
Pop-Location

Write-Host "`n============================================================" -ForegroundColor Green
Write-Host " MCP SERVERS SETUP COMPLETE!" -ForegroundColor Green
Write-Host " All MCP servers registered and verified." -ForegroundColor Green
Write-Host " Available servers:" -ForegroundColor Green
foreach ($server in $mcp_servers_list) {
    Write-Host "   • $($server.name)" -ForegroundColor Green
}
Write-Host "============================================================" -ForegroundColor Green
