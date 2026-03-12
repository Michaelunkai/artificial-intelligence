Param(
    [switch]$SkipCatalogUpdate
);

$ErrorActionPreference = 'Stop';

function Get-ServerList {
    $raw = @'
SQLite
amazon-bedrock-agentcore
amazon-kendra-index
amazon-neptune
amazon-qbusiness-anonymous
asana
astro-docs
audioscrape
aws-api
aws-appsync
aws-bedrock-custom-model-import
aws-bedrock-data-automation
aws-cdk-mcp-server
aws-core-mcp-server
aws-dataprocessing
aws-diagram
aws-documentation
aws-healthomics
aws-iot-sitewise
aws-location
aws-msk
aws-pricing
aws-terraform
awslabs-billing-cost-management
awslabs-ccapi
awslabs-cfn
awslabs-cloudtrail
awslabs-cloudwatch
awslabs-cloudwatch-appsignals
awslabs-cost-explorer
awslabs-dynamodb
awslabs-elasticache
awslabs-iam
awslabs-memcached
awslabs-nova-canvas
awslabs-redshift
awslabs-s3-tables
awslabs-timestream-for-influxdb
awslabs-valkey
azure
carbon-voice
chroma
cloudflare-ai-gateway
cloudflare-audit-logs
cloudflare-autorag
cloudflare-browser-rendering
cloudflare-container
cloudflare-digital-experience-monitoring
cloudflare-dns-analytics
cloudflare-docs
cloudflare-graphql
cloudflare-logpush
cloudflare-observability
cloudflare-one-casb
cloudflare-radar
cloudflare-workers-bindings
cloudflare-workers-builds
context7
curl
databutton
deepwiki
dialer
docker
duckduckgo
effect-mcp
fetch
ffmpeg
find-a-domain
firefly
gemini-api-docs
gitmcp
globalping
grafbase
hugging-face
instant
invideo
javadocs
linear
llmtxt
manifold
maven-tools-mcp
mcp-code-interpreter
mcp-hackernews
mcp-python-refactoring
memory
microsoft-learn
minecraft-wiki
monday
next-devtools-mcp
node-code-sandbox
notion-remote
novita
npm-sentinel
octagon
openbnb-airbnb
openmesh
openzeppelin-cairo
openzeppelin-solidity
openzeppelin-stellar
openzeppelin-stylus
osp_marketing_tools
paper-search
paypal
playwright
pref-editor
prisma-postgres
pulumi-remote
puppeteer
ramparts
remote-mcp
ros2
schogini-mcp-image-border
scorecard
securenote-link-mcp-server
semgrep
sentry-remote
sequentialthinking
simplechecklist
sqlite-mcp-server
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
$pathServers = @('desktop-commander','filesystem','git','markdownify','markitdown');
$pathAdded = 0;
$pathAlready = 0;

foreach ($name in $targets) {
    if ($enabledLookup.ContainsKey($name)) {
        $already++;
        continue;
    }

    Write-Host "Enabling $name..." -ForegroundColor Green;
    & docker mcp server enable $name;
    if ($LASTEXITCODE -eq 0) {
        $added++;
        $enabledLookup[$name] = $true;
    } else {
        $failures += $name;
        Write-Warning "Failed to enable $name (exit code $LASTEXITCODE).";
    }
}

Write-Host "Already enabled: $already" -ForegroundColor Gray;
Write-Host "Enabled this run: $added" -ForegroundColor Green;

$desiredPaths = @('C:/','F:/');
foreach ($pathServer in $pathServers) {
    Ensure-PathConfig -Name $pathServer -Paths $desiredPaths;
    if ($enabledLookup.ContainsKey($pathServer)) {
        $pathAlready++;
        continue;
    }

    Write-Host "Enabling $pathServer..." -ForegroundColor Green;
    & docker mcp server enable $pathServer;
    if ($LASTEXITCODE -eq 0) {
        $enabledLookup[$pathServer] = $true;
        $pathAdded++;
    } else {
        $failures += $pathServer;
        Write-Warning "Failed to enable $pathServer (exit code $LASTEXITCODE).";
    }
}

Write-Host "Path-based servers already enabled: $pathAlready" -ForegroundColor Gray;
Write-Host "Path-based servers enabled this run: $pathAdded" -ForegroundColor Green;

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
    Write-Host "✓ Docker MCP gateway started successfully" -ForegroundColor Green;
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
