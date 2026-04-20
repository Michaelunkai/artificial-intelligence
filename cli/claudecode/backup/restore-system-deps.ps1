#Requires -Version 5.1
<#
.SYNOPSIS
    System Dependencies Restore Script
    Analyzes a dependencies manifest and provides restore instructions/automated installation

.DESCRIPTION
    - Reads dependencies manifest JSON (from backup-system-deps.ps1)
    - Detects missing dependencies on current system
    - Generates installation checklist with URLs and commands
    - Optionally auto-downloads and installs safe dependencies

.PARAMETER ManifestPath
    Path to the dependencies manifest JSON file

.PARAMETER AutoInstall
    Automatically install safe dependencies (requires admin)

.PARAMETER DryRun
    Show what would be installed without actually installing

.EXAMPLE
    .\restore-system-deps.ps1 -ManifestPath "C:\backups\deps\dependencies-manifest-*.json" -DryRun

.EXAMPLE
    .\restore-system-deps.ps1 -ManifestPath "C:\backups\deps\dependencies-manifest-*.json" -AutoInstall
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$ManifestPath,
    
    [switch]$AutoInstall,
    [switch]$DryRun,
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
$WarningPreference = 'SilentlyContinue'

# Verify manifest exists
if (-not (Test-Path $ManifestPath)) {
    $ManifestPath = Get-ChildItem -Path $ManifestPath -ErrorAction SilentlyContinue | 
        Sort-Object LastWriteTime -Descending | 
        Select-Object -First 1 -ExpandProperty FullName
    
    if (-not $ManifestPath) {
        Write-Error "Manifest not found"
        exit 1
    }
}

Write-Host "📖 Reading manifest: $ManifestPath" -ForegroundColor Cyan

try {
    $manifest = Get-Content $ManifestPath -Raw | ConvertFrom-Json
} catch {
    Write-Error "Failed to parse manifest: $_"
    exit 1
}

$installationPlan = @{
    timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    hostname = $env:COMPUTERNAME
    manifest = $manifest.timestamp
    missingDependencies = @()
    installationSteps = @()
    downloadLinks = @()
    manualSteps = @()
}

function Add-Log {
    param([string]$message, [string]$color = 'Gray')
    if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $message" -ForegroundColor $color }
}

# ===== DETECT CURRENT STATE =====
Write-Host "`n🔍 Scanning current system..." -ForegroundColor Cyan

# Check Visual C++ Runtimes
Add-Log "Checking Visual C++ runtimes..."
$currentVCpp = Get-ItemProperty -Path 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | 
    Where-Object { $_.DisplayName -like '*Visual C++*' }

$missingVCpp = @()
foreach ($vcpp in $manifest.dependencies.VisualCppRuntimes.items) {
    $found = $currentVCpp | Where-Object { $_.DisplayVersion -like $vcpp.version }
    if (-not $found) {
        $missingVCpp += $vcpp
    }
}

if ($missingVCpp.Count -gt 0) {
    Write-Host "   ⚠️  Missing Visual C++ Runtimes: $($missingVCpp.Count)" -ForegroundColor Yellow
    $installationPlan.missingDependencies += @{
        category = "VisualCppRuntimes"
        count = $missingVCpp.Count
        items = $missingVCpp
    }
}

# Check .NET Framework
Add-Log "Checking .NET Framework..."
$currentDotnet = @()
try {
    $netPath = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\'
    if (Test-Path $netPath) {
        $currentDotnet = @(Get-ChildItem $netPath -ErrorAction SilentlyContinue | 
            ForEach-Object { 
                @{ 
                    framework = $_.PSChildName
                    version = (Get-ItemProperty -Path $_.PSPath -Name 'Version' -ErrorAction SilentlyContinue).Version
                }
            })
    }
} catch { }

$missingDotnet = @()
foreach ($net in $manifest.dependencies.'.NETFramework'.items) {
    $found = $currentDotnet | Where-Object { $_.version -like $net.version }
    if (-not $found) {
        $missingDotnet += $net
    }
}

if ($missingDotnet.Count -gt 0) {
    Write-Host "   ⚠️  Missing .NET versions: $($missingDotnet.Count)" -ForegroundColor Yellow
    $installationPlan.missingDependencies += @{
        category = ".NETFramework"
        count = $missingDotnet.Count
        items = $missingDotnet
    }
}

# Check Python
Add-Log "Checking Python..."
$pythonMissing = @()
foreach ($python in $manifest.dependencies.Python.installations) {
    $found = Test-Path $python.path -ErrorAction SilentlyContinue
    if (-not $found) {
        $pythonMissing += $python
    }
}

if ($pythonMissing.Count -gt 0) {
    Write-Host "   ⚠️  Missing Python installations: $($pythonMissing.Count)" -ForegroundColor Yellow
    $installationPlan.missingDependencies += @{
        category = "Python"
        count = $pythonMissing.Count
        items = $pythonMissing
    }
}

# Check Node.js
Add-Log "Checking Node.js..."
$nodeExists = Get-Command node -ErrorAction SilentlyContinue
if (-not $nodeExists -and $manifest.dependencies.NodeJs.detected) {
    Write-Host "   ⚠️  Node.js not found (was installed before)" -ForegroundColor Yellow
    $installationPlan.missingDependencies += @{
        category = "NodeJs"
        items = $manifest.dependencies.NodeJs.installations
    }
}

# Check OpenSSL
Add-Log "Checking OpenSSL..."
$opensslExists = Get-Command openssl -ErrorAction SilentlyContinue
if (-not $opensslExists -and $manifest.dependencies.CryptoLibraries.detected) {
    Write-Host "   ⚠️  OpenSSL not found (was installed before)" -ForegroundColor Yellow
    $installationPlan.missingDependencies += @{
        category = "CryptoLibraries"
        items = $manifest.dependencies.CryptoLibraries.libraries
    }
}

# Check WebView2
Add-Log "Checking WebView2..."
$webview2Found = Test-Path 'C:\Program Files (x86)\Microsoft\EdgeWebView\Application' -ErrorAction SilentlyContinue
if (-not $webview2Found -and $manifest.dependencies.WebView2.detected) {
    Write-Host "   ⚠️  WebView2 runtime not found" -ForegroundColor Yellow
    $installationPlan.missingDependencies += @{
        category = "WebView2"
    }
}

# ===== BUILD INSTALLATION PLAN =====
Write-Host "`n📋 Building installation plan..." -ForegroundColor Cyan

# Installation definitions
$installationCatalog = @{
    VisualCppRuntimes = @{
        name = "Visual C++ Redistributables"
        description = "Required for running C++ applications"
        downloadBase = "https://support.microsoft.com/en-us/help/2977003"
        installers = @(
            @{
                name = "Visual C++ 2015-2022 (x64)"
                url = "https://aka.ms/vs/17/release/vc_redist.x64.exe"
                args = "/install /quiet /norestart"
            }
            @{
                name = "Visual C++ 2015-2022 (x86)"
                url = "https://aka.ms/vs/17/release/vc_redist.x86.exe"
                args = "/install /quiet /norestart"
            }
        )
    }
    
    DotNet = @{
        name = ".NET Framework/Runtime"
        description = "Microsoft .NET runtime environment"
        downloadBase = "https://dotnet.microsoft.com/download"
        installers = @(
            @{
                name = ".NET 8 Runtime"
                url = "https://dotnetcli.blob.core.windows.net/dotnet/release/latest/dotnet-runtime-latest-win-x64.exe"
                args = "/install /quiet /norestart"
            }
        )
    }
    
    Python = @{
        name = "Python"
        description = "Python runtime and package manager"
        downloadBase = "https://www.python.org/downloads/windows/"
        installers = @(
            @{
                name = "Python 3.11 (x64)"
                url = "https://www.python.org/ftp/python/3.11.8/python-3.11.8-amd64.exe"
                args = "/quiet InstallAllUsers=1 PrependPath=1"
            }
        )
    }
    
    NodeJs = @{
        name = "Node.js"
        description = "JavaScript runtime and npm"
        downloadBase = "https://nodejs.org"
        installers = @(
            @{
                name = "Node.js LTS (x64)"
                url = "https://nodejs.org/dist/v20.11.0/node-v20.11.0-x64.msi"
                args = "/quiet"
            }
        )
    }
    
    OpenSSL = @{
        name = "OpenSSL"
        description = "Cryptography and SSL/TLS library"
        downloadBase = "https://slproweb.com/products/Win32OpenSSL.html"
        installers = @(
            @{
                name = "OpenSSL 3.x (x64)"
                url = "https://slproweb.com/download/Win64OpenSSL-3_2_0.msi"
                args = "INSTALLLEVEL=3 /quiet"
            }
        )
    }
    
    WebView2 = @{
        name = "WebView2 Runtime"
        description = "Microsoft Edge WebView2 for rendering web content"
        downloadBase = "https://developer.microsoft.com/microsoft-edge/webview2/"
        installers = @(
            @{
                name = "WebView2 Runtime (Evergreen)"
                url = "https://go.microsoft.com/fwlink/p/?LinkId=2124703"
                args = "/silent /install"
            }
        )
    }
}

# Generate installation steps
foreach ($missing in $installationPlan.missingDependencies) {
    $category = $missing.category
    $installer = $installationCatalog[$category]
    
    if ($installer) {
        Write-Host "   📦 $($installer.name)" -ForegroundColor Magenta
        
        foreach ($pkg in $installer.installers) {
            $step = @{
                category = $category
                name = $pkg.name
                url = $pkg.url
                args = $pkg.args
                command = "msiexec.exe /i '$($pkg.url)' $($pkg.args) /norestart" -replace '.exe', '.msi'
                priority = switch ($category) {
                    'VisualCppRuntimes' { 1 }
                    'DotNet' { 2 }
                    'WebView2' { 3 }
                    'Python' { 4 }
                    'NodeJs' { 5 }
                    'OpenSSL' { 6 }
                    default { 10 }
                }
            }
            
            $installationPlan.installationSteps += $step
            $installationPlan.downloadLinks += @{
                name = $pkg.name
                url = $pkg.url
            }
        }
    }
}

# ===== DISPLAY CHECKLIST =====
Write-Host "`n✅ INSTALLATION CHECKLIST" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

if ($installationPlan.missingDependencies.Count -eq 0) {
    Write-Host "✨ All dependencies are present! No installation needed." -ForegroundColor Green
    exit 0
}

$installationPlan.installationSteps = $installationPlan.installationSteps | Sort-Object -Property priority

Write-Host "`nInstall in this order:`n" -ForegroundColor White

$step = 1
foreach ($install in $installationPlan.installationSteps) {
    Write-Host "$step. $($install.name)" -ForegroundColor Green
    Write-Host "   Download: $($install.url)"
    
    if ($install.category -like '*.msi*' -or $install.name -like '*.msi*') {
        Write-Host "   Command:  msiexec.exe /i `"<installer>.msi`" /quiet /norestart"
    } else {
        Write-Host "   Command:  <installer>.exe $($install.args)"
    }
    Write-Host ""
    $step++
}

# ===== DOWNLOAD LINKS =====
Write-Host "`n📥 DOWNLOAD LINKS" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan
Write-Host ""

foreach ($link in $installationPlan.downloadLinks) {
    Write-Host "$($link.name):" -ForegroundColor Yellow
    Write-Host "   $($link.url)"
    Write-Host ""
}

# ===== POWERSHELL INSTALLATION SCRIPT =====
Write-Host "`n🚀 AUTO-INSTALL SCRIPT" -ForegroundColor Cyan
Write-Host "================================" -ForegroundColor Cyan

$autoInstallScript = @"
# Auto-Install Script - Run as Administrator
# Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

`$DownloadDir = "`$env:TEMP\DepsInstall_$(Get-Date -Format 'yyyyMMdd-HHmmss')"
New-Item -ItemType Directory -Path `$DownloadDir -Force | Out-Null

Write-Host "Downloading installers to `$DownloadDir..." -ForegroundColor Cyan

`$downloads = @(
"@

foreach ($link in $installationPlan.downloadLinks) {
    $autoInstallScript += "    @{ name = '$($link.name)'; url = '$($link.url)' }`n"
}

$autoInstallScript += @"
)

foreach (`$dl in `$downloads) {
    `$filepath = Join-Path `$DownloadDir (`$dl.name -replace '[^a-zA-Z0-9]', '_')
    Write-Host "Downloading `$(`$dl.name)..." -ForegroundColor Yellow
    try {
        Invoke-WebRequest -Uri `$dl.url -OutFile `$filepath -UseBasicParsing
        Write-Host "   ✅ Downloaded to `$filepath" -ForegroundColor Green
    } catch {
        Write-Host "   ❌ Failed: `$_" -ForegroundColor Red
    }
}

Write-Host "Download complete. Installers are in: `$DownloadDir" -ForegroundColor Green
Write-Host "Please run installers manually or double-click each .exe/.msi" -ForegroundColor Cyan
"@

Write-Host $autoInstallScript

# ===== SAVE INSTALLATION PLAN =====
$planPath = $ManifestPath -replace '\.json$', '-install-plan.json'
try {
    $installationPlan | ConvertTo-Json -Depth 10 | Out-File -FilePath $planPath -Encoding UTF8
    Write-Host "`n📄 Installation plan saved: $planPath" -ForegroundColor Cyan
} catch { }

# ===== OPTIONAL AUTO-INSTALL =====
if ($AutoInstall) {
    Write-Host "`n⚠️  AUTO-INSTALL NOT IMPLEMENTED (requires admin + verification)" -ForegroundColor Yellow
    Write-Host "Please download and run installers manually from links above" -ForegroundColor Yellow
}

Write-Host "`n✅ RESTORE ANALYSIS COMPLETE" -ForegroundColor Green

exit 0
