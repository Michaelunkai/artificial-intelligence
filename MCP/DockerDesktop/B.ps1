Param(
    [switch]$SkipCatalogUpdate
);

$ErrorActionPreference = 'Stop';

function Get-ServerList {
    $raw = @'
SQLite
azure
chroma
curl
docker
duckduckgo
fetch
ffmpeg
gemini-api-docs
globalping
grafbase
hugging-face
linear
llmtxt
memory
microsoft-learn
node-code-sandbox
notion-remote
npm-sentinel
openmesh
openzeppelin-solidity
paper-search
playwright
prisma-postgres
pulumi-remote
puppeteer
ros2
scorecard
semgrep
sentry-remote
simplechecklist
stripe-remote
supabase
task-orchestrator
terraform
time
vizro
vuln-nist-mcp-server
waystation
webflow-remote
wikipedia-mcp
wix
youtube_transcript
'@;
    return $raw -split "`r?`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ };
}

function Update-CatalogIfNeeded {
    Param(
        [switch]$Skip
    );

    if ($Skip) {
        Write-Host "Skipping catalog refresh per request." -ForegroundColor Yellow;
        return;
    }

    Write-Host "Refreshing Docker MCP catalog (docker mcp catalog update docker-mcp)..." -ForegroundColor Cyan;
    & docker mcp catalog update docker-mcp;
    if ($LASTEXITCODE -ne 0) {
        Write-Warning "Catalog update failed (exit code $LASTEXITCODE). Continuing with existing catalog.";
    }
}

function Get-EnabledServers {
    $lookup = @{};
    try {
        $result = & docker mcp server ls --json 2>$null;
        if ($LASTEXITCODE -eq 0 -and $result) {
            foreach ($name in (ConvertFrom-Json $result)) {
                $lookup[$name] = $true;
            }
        } else {
            Write-Warning "Unable to read currently enabled servers (exit code $LASTEXITCODE). Assuming none.";
        }
    } catch {
        Write-Warning "Failed to query enabled servers: $_";
    }
    return $lookup;
}

function Deploy-Server {
    Param(
        [Parameter(Mandatory = $true)]
        [string]$Name
    );

    Write-Host "Deploying $Name..." -ForegroundColor Cyan;
    & docker mcp server deploy $Name;
    if ($LASTEXITCODE -eq 0) {
        return $true;
    }

    Write-Warning "Failed to deploy $Name (exit code $LASTEXITCODE).";
    return $false;
}

function Ensure-PathConfig {
    Param(
        [string]$Name,
        [string[]]$Paths
    );

    $configPath = Join-Path $env:USERPROFILE '.docker\mcp\config.yaml';
    $configDir = Split-Path $configPath -Parent;
    if (-not (Test-Path $configDir)) {
        New-Item -ItemType Directory -Path $configDir -Force | Out-Null;
    }

    $lines = @();
    if (Test-Path $configPath) {
        $lines = Get-Content -Path $configPath -ErrorAction SilentlyContinue;
    }

    $output = New-Object System.Collections.Generic.List[string];
    $skip = $false;
    $startPattern = '^\s*' + [regex]::Escape($Name) + ':\s*$';
    foreach ($line in $lines) {
        if (-not $skip -and $line -match $startPattern) {
            $skip = $true;
            continue;
        }

        if ($skip) {
            if ($line -match '^\s*$') {
                continue;
            }
            if ($line -match '^\S') {
                $skip = $false;
                # fall through to record this top-level line
            } else {
                continue;
            }
        }

        $output.Add($line);
    }

    while ($output.Count -gt 0 -and [string]::IsNullOrWhiteSpace($output[$output.Count - 1])) {
        $output.RemoveAt($output.Count - 1);
    }

    $normalized = @();
    foreach ($path in $Paths) {
        $formatted = ($path -replace '\\', '/').Trim();
        if ($formatted -match '^[A-Za-z]:$') {
            $formatted = "$formatted/";
        } elseif ($formatted -and $formatted[-1] -ne '/') {
            $formatted = "$formatted/";
        }
        $normalized += $formatted;
    }
    $normalized = $normalized | Sort-Object -Unique;

    $blockLines = @("${Name}:", '  paths:');
    foreach ($np in $normalized) {
        $blockLines += "    - $np";
    }
    $block = ($blockLines -join "`n");

    if ($output.Count -gt 0) {
        $output.Add('');
    }
    $output += $blockLines;

    Set-Content -Path $configPath -Value ($output -join "`n") -Encoding ascii;
}

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    Write-Error "Docker CLI not found. Install Docker Desktop first.";
    exit 1;
}

Update-CatalogIfNeeded -Skip:$SkipCatalogUpdate;

$targets = Get-ServerList;
$enabledLookup = Get-EnabledServers;
$failures = @();
$already = 0;
$added = 0;
$deployments = 0;
$pathServers = @('desktop-commander','filesystem','git','markdownify','markitdown');
$pathAdded = 0;
$pathAlready = 0;

foreach ($name in $targets) {
    $enableFailed = $false;
    if ($enabledLookup.ContainsKey($name)) {
        $already++;
    } else {
        Write-Host "Enabling $name..." -ForegroundColor Green;
        & docker mcp server enable $name;
        if ($LASTEXITCODE -eq 0) {
            $added++;
            $enabledLookup[$name] = $true;
        } else {
            $failures += $name;
            Write-Warning "Failed to enable $name (exit code $LASTEXITCODE).";
            $enableFailed = $true;
        }
    }

    if (-not $enableFailed) {
        if (Deploy-Server -Name $name) {
            $deployments++;
        } else {
            $failures += "$name (deploy)";
        }
    }
}

Write-Host "Already enabled: $already" -ForegroundColor Gray;
Write-Host "Enabled this run: $added" -ForegroundColor Green;

$desiredPaths = @('C:/','F:/');
foreach ($pathServer in $pathServers) {
    Ensure-PathConfig -Name $pathServer -Paths $desiredPaths;
    $pathEnableFailed = $false;
    if ($enabledLookup.ContainsKey($pathServer)) {
        $pathAlready++;
    } else {
        Write-Host "Enabling $pathServer..." -ForegroundColor Green;
        & docker mcp server enable $pathServer;
        if ($LASTEXITCODE -eq 0) {
            $enabledLookup[$pathServer] = $true;
            $pathAdded++;
        } else {
            $failures += $pathServer;
            Write-Warning "Failed to enable $pathServer (exit code $LASTEXITCODE).";
            $pathEnableFailed = $true;
        }
    }

    if (-not $pathEnableFailed) {
        if (Deploy-Server -Name $pathServer) {
            $deployments++;
        } else {
            $failures += "$pathServer (deploy)";
        }
    }
}

Write-Host "Path-based servers already enabled: $pathAlready" -ForegroundColor Gray;
Write-Host "Path-based servers enabled this run: $pathAdded" -ForegroundColor Green;
Write-Host "Servers deployed this run: $deployments" -ForegroundColor Cyan;

if ($failures.Count -gt 0) {
    $failurePath = Join-Path $PSScriptRoot 'aa.failures.txt';
    $failures | Set-Content -Path $failurePath -Encoding ascii;
    Write-Warning ("{0} servers failed. See {1}" -f $failures.Count, $failurePath);
}

# ============================================================================
# ENSURE DOCKER MCP GATEWAY IS RUNNING
# ============================================================================
Write-Host "`n=== STARTING DOCKER MCP GATEWAY ===" -ForegroundColor Magenta;

# Stop any existing gateway
Write-Host "Stopping existing gateway..." -ForegroundColor Yellow;
& docker mcp gateway stop 2>&1 | Out-Null;

# Start the gateway
Write-Host "Starting Docker MCP gateway..." -ForegroundColor Cyan;
& docker mcp gateway start;

if ($LASTEXITCODE -eq 0) {
    Write-Host "`u{2713} Docker MCP gateway started successfully" -ForegroundColor Green;
} else {
    Write-Warning "Failed to start Docker MCP gateway (exit code $LASTEXITCODE)";
}

# Wait for gateway to initialize
Write-Host "Waiting for gateway to initialize..." -ForegroundColor Gray;
Start-Sleep -Seconds 3;

# Test connection
Write-Host "`n=== TESTING CLIENT CONNECTIONS ===" -ForegroundColor Magenta;

Write-Host "`nTesting codex connection..." -ForegroundColor Cyan;
& codex mcp list 2>&1;

Write-Host "`nTesting claude connection..." -ForegroundColor Cyan;
& claude mcp list 2>&1;

Write-Host "`n=== SETUP COMPLETE ===" -ForegroundColor Cyan;
Write-Host "All target servers are now enabled." -ForegroundColor Green;
Write-Host "If connections failed, try running: docker mcp gateway restart" -ForegroundColor Gray;
