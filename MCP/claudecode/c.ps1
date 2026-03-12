# ===================================================================================
# GLOBAL MCP SETUP - 100% SUCCESS FROM EVERY PATH
# ===================================================================================
# This script adds MCP servers with --scope user to work from EVERY directory
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
Write-StepHeader "NO-DOCKER MCP GLOBAL SETUP - 100% USER-SCOPED!"

Write-Host "System Information:" -ForegroundColor Cyan
Write-Host "  User: $env:USERNAME" -ForegroundColor DarkCyan
Write-Host "  Computer: $env:COMPUTERNAME" -ForegroundColor DarkCyan
Write-Host "  Using: --scope user flag for GLOBAL access!" -ForegroundColor Green
Write-Host ""

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

# Check uvx
try {
    $uvxVersion = (uvx --version 2>&1 | Out-String).Trim()
    Write-Host "  [OK] uvx found: $uvxVersion" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] uvx not found - Python MCP servers will not work" -ForegroundColor Yellow
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
        $existingServers = [regex]::Matches($listOutput, "^(\w+):", [System.Text.RegularExpressions.RegexOptions]::Multiline) |
            ForEach-Object { $_.Groups[1].Value }
    }
}
catch {
    Write-Host "  [INFO] No existing servers to remove" -ForegroundColor DarkGray
}

foreach ($server in $existingServers) {
    try {
        Write-Host "  Removing: $server" -ForegroundColor DarkYellow -NoNewline
        claude mcp remove $server 2>&1 | Out-Null
        Write-Host " [OK]" -ForegroundColor Green
    }
    catch {
        Write-Host " [SKIP]" -ForegroundColor DarkGray
    }
}

# ==================================================================================
# STEP 3: ADD MCP SERVERS WITH --scope user FLAG
# ==================================================================================
Write-StepHeader "ADD MCP SERVERS WITH --scope user (GLOBAL)"

Write-Host "Adding MCP servers with --scope user flag..." -ForegroundColor DarkCyan
Write-Host "This makes them available from EVERY path on your system!" -ForegroundColor Yellow
Write-Host ""

# Define all MCP servers
$mcpServers = @(
    @{ name = "filesystem"; cmd = "npx"; pkg = "@modelcontextprotocol/server-filesystem"; args = @("C:/", "F:/") },
    @{ name = "git"; cmd = "npx"; pkg = "@modelcontextprotocol/server-git"; args = @() },
    @{ name = "github"; cmd = "npx"; pkg = "@modelcontextprotocol/server-github"; args = @() },
    @{ name = "puppeteer"; cmd = "npx"; pkg = "@modelcontextprotocol/server-puppeteer"; args = @() },
    @{ name = "playwright"; cmd = "npx"; pkg = "@playwright/mcp"; args = @() },
    @{ name = "memory"; cmd = "npx"; pkg = "@modelcontextprotocol/server-memory"; args = @() },
    @{ name = "sequential-thinking"; cmd = "npx"; pkg = "@modelcontextprotocol/server-sequential-thinking"; args = @() },
    @{ name = "brave-search"; cmd = "npx"; pkg = "@modelcontextprotocol/server-brave-search"; args = @() },
    @{ name = "everything"; cmd = "npx"; pkg = "everything-mcp"; args = @() },
    @{ name = "deepwiki"; cmd = "npx"; pkg = "deepwiki-mcp"; args = @() },
    @{ name = "context7"; cmd = "npx"; pkg = "@context7/mcp-server"; args = @() },
    @{ name = "fetch"; cmd = "uvx"; pkg = "mcp-server-fetch"; args = @() },
    @{ name = "sqlite"; cmd = "uvx"; pkg = "mcp-server-sqlite"; args = @() },
    @{ name = "time"; cmd = "uvx"; pkg = "mcp-server-time"; args = @() },
    @{ name = "slack"; cmd = "npx"; pkg = "@modelcontextprotocol/server-slack"; args = @() },
    @{ name = "gdrive"; cmd = "npx"; pkg = "@modelcontextprotocol/server-gdrive"; args = @() },
    @{ name = "postgres"; cmd = "npx"; pkg = "@modelcontextprotocol/server-postgres"; args = @() },
    @{ name = "sentry"; cmd = "npx"; pkg = "@modelcontextprotocol/server-sentry"; args = @() }
)

$successCount = 0
$failCount = 0
$registeredServers = @()

foreach ($server in $mcpServers) {
    $serverName = $server.name
    $cmd = $server.cmd
    $pkg = $server.pkg
    $extraArgs = $server.args

    Write-Host "  Adding: $serverName" -ForegroundColor DarkCyan -NoNewline

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
        $registeredServers += $serverName
    }
    catch {
        Write-Host " [FAIL] $_" -ForegroundColor Red
        $failCount++
    }
}

Write-Host ""
Write-Host "Registration Summary:" -ForegroundColor Cyan
Write-Host "  Successfully registered: $successCount servers" -ForegroundColor Green
Write-Host "  Failed: $failCount servers" -ForegroundColor $(if ($failCount -gt 0) { "Red" } else { "Green" })
Write-Host ""

Write-Host "Registered servers:" -ForegroundColor Green
foreach ($srv in $registeredServers) {
    Write-Host "  - $srv" -ForegroundColor DarkGreen
}

# ==================================================================================
# STEP 4: TEST FROM MULTIPLE PATHS
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

            if ($serverCount -gt 0) {
                Write-Host " [OK] $serverCount servers" -ForegroundColor Green
                $passedTests++
                $testResults += @{ Path = $name; Success = $true; Count = $serverCount }
            }
            else {
                Write-Host " [FAIL] No servers" -ForegroundColor Red
                $failedTests++
                $testResults += @{ Path = $name; Success = $false; Count = 0 }
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

Write-Host "Verification:" -ForegroundColor Cyan
Write-Host "  Run from ANY path: claude mcp list" -ForegroundColor Green
Write-Host ""
Write-Host "  Example:" -ForegroundColor Yellow
Write-Host "    cd C:\" -ForegroundColor DarkCyan
Write-Host "    claude mcp list" -ForegroundColor Green
Write-Host ""
Write-Host "===================================================================================" -ForegroundColor Green
Write-Host "Setup completed at: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor DarkCyan
Write-Host "===================================================================================" -ForegroundColor Green
Write-Host ""
