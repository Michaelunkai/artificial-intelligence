#Requires -Version 5.1
<#
.SYNOPSIS
    System Dependencies Backup Script
    Backs up all critical system dependencies: C++ runtimes, .NET, Python, Node.js, OpenSSL, WebView2, fonts, Windows features

.DESCRIPTION
    Creates a comprehensive manifest of installed system dependencies.
    Output: Dependencies manifest JSON file with versions, paths, and installation info.

.EXAMPLE
    .\backup-system-deps.ps1 -OutputPath "C:\backups\deps"
#>

param(
    [string]$OutputPath = "$env:USERPROFILE\AppData\Local\Claude\backups",
    [switch]$Verbose
)

$ErrorActionPreference = 'Continue'
$WarningPreference = 'SilentlyContinue'

# Ensure output directory exists
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

$manifest = @{
    timestamp = (Get-Date -Format 'yyyy-MM-dd HH:mm:ss')
    computerName = $env:COMPUTERNAME
    osVersion = (Get-WmiObject Win32_OperatingSystem).Caption
    architecture = [Environment]::Is64BitOperatingSystem ? "x64" : "x86"
    dependencies = @{}
}

function Add-Log {
    param([string]$message)
    if ($Verbose) { Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $message" -ForegroundColor Gray }
}

function Get-RegistryVersions {
    param([string]$path, [string]$versionProperty = 'DisplayVersion')
    $versions = @()
    try {
        $reg = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
        if ($reg) {
            $versions += $reg | Select-Object -ExpandProperty $versionProperty -ErrorAction SilentlyContinue
        }
    } catch { }
    return $versions
}

# ===== VISUAL C++ RUNTIMES =====
Add-Log "Scanning Visual C++ Runtimes..."
$vcppRuntimes = @()
$regPaths = @(
    'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
    'HKLM:\Software\Wow6432Node\Windows\CurrentVersion\Uninstall\*'
)

foreach ($regPath in $regPaths) {
    try {
        $items = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue | 
            Where-Object { $_.DisplayName -like '*Visual C++*' -or $_.DisplayName -like '*Microsoft Visual*' }
        foreach ($item in $items) {
            $vcppRuntimes += @{
                name = $item.DisplayName
                version = $item.DisplayVersion
                installDate = $item.InstallDate
                publisherUrl = $item.URLInfoAbout
                uninstallString = $item.UninstallString
            }
        }
    } catch { }
}

$manifest.dependencies['VisualCppRuntimes'] = @{
    detected = $vcppRuntimes.Count -gt 0
    count = $vcppRuntimes.Count
    items = $vcppRuntimes
    registryLocations = $regPaths
}

# ===== .NET FRAMEWORK =====
Add-Log "Scanning .NET Framework versions..."
$dotnetVersions = @()
try {
    # Check .NET Framework registry
    $netPath = 'HKLM:\SOFTWARE\Microsoft\NET Framework Setup\NDP\'
    if (Test-Path $netPath) {
        $netItems = Get-ChildItem $netPath -ErrorAction SilentlyContinue
        foreach ($item in $netItems) {
            $version = (Get-ItemProperty -Path $item.PSPath -Name 'Version' -ErrorAction SilentlyContinue).Version
            if ($version) {
                $dotnetVersions += @{
                    framework = $item.PSChildName
                    version = $version
                    path = $item.PSPath
                }
            }
        }
    }

    # Check .NET Core/5+
    $dotnetCore = & dotnet --version 2>$null
    if ($dotnetCore) {
        $dotnetVersions += @{
            framework = ".NET Runtime"
            version = $dotnetCore
            path = (Get-Command dotnet -ErrorAction SilentlyContinue).Source
        }
    }

    # Check global .NET installs
    $dotnetGlobalPath = 'C:\Program Files\dotnet'
    if (Test-Path $dotnetGlobalPath) {
        $dotnetVersions += @{
            framework = ".NET Global"
            version = "Installed"
            path = $dotnetGlobalPath
            installSize = (Get-ChildItem $dotnetGlobalPath -Recurse -ErrorAction SilentlyContinue | Measure-Object -Property Length -Sum).Sum / 1MB
        }
    }
} catch { }

$manifest.dependencies['.NETFramework'] = @{
    detected = $dotnetVersions.Count -gt 0
    count = $dotnetVersions.Count
    items = $dotnetVersions
}

# ===== PYTHON =====
Add-Log "Scanning Python installations..."
$pythonInstalls = @()
$pythonPaths = @(
    'HKCU:\Software\Python\PythonCore\*',
    'HKLM:\Software\Python\PythonCore\*',
    'HKLM:\Software\Wow6432Node\Python\PythonCore\*'
)

foreach ($path in $pythonPaths) {
    try {
        $pythonKeys = Get-ChildItem -Path $path -ErrorAction SilentlyContinue
        foreach ($key in $pythonKeys) {
            $installPath = (Get-ItemProperty -Path "$($key.PSPath)\InstallPath" -Name '(Default)' -ErrorAction SilentlyContinue).'(Default)'
            if ($installPath) {
                $pythonInstalls += @{
                    version = $key.PSChildName
                    path = $installPath
                }
            }
        }
    } catch { }
}

# Try direct python command
try {
    $pyVersion = & python --version 2>&1
    $pyPath = (Get-Command python -ErrorAction SilentlyContinue).Source
    if ($pyPath) {
        $pythonInstalls += @{
            version = $pyVersion -replace 'Python '
            path = $pyPath
            isActive = $true
        }
    }
} catch { }

# Get pip packages if Python is available
$pipPackages = @()
if ($pythonInstalls) {
    try {
        $pipList = & pip list --format json 2>$null | ConvertFrom-Json
        $pipPackages = @($pipList | ForEach-Object { @{ name = $_.name; version = $_.version } })
    } catch { }
}

$manifest.dependencies['Python'] = @{
    detected = $pythonInstalls.Count -gt 0
    count = $pythonInstalls.Count
    installations = $pythonInstalls
    packages = @{
        count = $pipPackages.Count
        packages = $pipPackages | Select-Object -First 50  # Limit to prevent huge JSON
    }
}

# ===== NODE.JS =====
Add-Log "Scanning Node.js installation..."
$nodejsInfo = @()
try {
    $nodeVersion = & node --version 2>$null
    $nodePath = (Get-Command node -ErrorAction SilentlyContinue).Source
    if ($nodePath) {
        $nodejsInfo += @{
            version = $nodeVersion
            path = $nodePath
        }
    }
} catch { }

# Get npm packages
$npmPackages = @()
try {
    $npmList = & npm list -g --depth=0 --json 2>$null | ConvertFrom-Json
    if ($npmList.dependencies) {
        $npmPackages = @($npmList.dependencies.PSObject.Properties | ForEach-Object { 
            @{ name = $_.Name; version = $_.Value.version } 
        })
    }
} catch { }

# Check Node installation directory
$nodeGlobalPath = 'C:\Program Files\nodejs'
if (Test-Path $nodeGlobalPath) {
    $nodejsInfo += @{
        type = "Global Installation"
        path = $nodeGlobalPath
    }
}

$manifest.dependencies['NodeJs'] = @{
    detected = $nodejsInfo.Count -gt 0
    installations = $nodejsInfo
    globalPackages = @{
        count = $npmPackages.Count
        packages = $npmPackages
    }
}

# ===== OPENSSL / CRYPTO LIBRARIES =====
Add-Log "Scanning OpenSSL and crypto libraries..."
$cryptoLibraries = @()

$cryptoPaths = @(
    'C:\Program Files\OpenSSL',
    'C:\Program Files (x86)\OpenSSL',
    'C:\OpenSSL',
    "$env:USERPROFILE\AppData\Local\Programs\OpenSSL"
)

foreach ($path in $cryptoPaths) {
    if (Test-Path $path) {
        $cryptoLibraries += @{
            name = "OpenSSL"
            path = $path
            exists = $true
        }
    }
}

# Check via environment
$opensslPath = $env:OPENSSL_DIR
if ($opensslPath) {
    $cryptoLibraries += @{
        name = "OpenSSL (env)"
        path = $opensslPath
    }
}

# Try openssl command
try {
    $opensslVersion = & openssl version 2>$null
    if ($opensslVersion) {
        $cryptoLibraries += @{
            name = "OpenSSL CLI"
            version = $opensslVersion
            path = (Get-Command openssl -ErrorAction SilentlyContinue).Source
        }
    }
} catch { }

$manifest.dependencies['CryptoLibraries'] = @{
    detected = $cryptoLibraries.Count -gt 0
    libraries = $cryptoLibraries
}

# ===== WEBVIEW2 RUNTIME =====
Add-Log "Scanning WebView2 runtime..."
$webview2Info = @()

$webview2Paths = @(
    'HKCU:\Software\Microsoft\Edge\User Data\Default\Preferences',
    'HKLM:\Software\Microsoft\EdgeUpdate\Clients\{F3017226-FE2A-4295-8BDF-00C3A9A7E4C5}',
    'C:\Program Files (x86)\Microsoft\Edge\Application'
)

foreach ($path in $webview2Paths) {
    if (Test-Path $path) {
        $webview2Info += @{
            location = $path
            exists = $true
        }
    }
}

# Check registry for WebView2 Runtime
try {
    $wv2Reg = Get-ItemProperty 'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*' -ErrorAction SilentlyContinue | 
        Where-Object { $_.DisplayName -like '*WebView2*' }
    if ($wv2Reg) {
        $webview2Info += @{
            name = $wv2Reg.DisplayName
            version = $wv2Reg.DisplayVersion
            installDate = $wv2Reg.InstallDate
        }
    }
} catch { }

$manifest.dependencies['WebView2'] = @{
    detected = $webview2Info.Count -gt 0
    info = $webview2Info
}

# ===== SYSTEM FONTS =====
Add-Log "Scanning system fonts..."
$fontPath = 'C:\Windows\Fonts'
$fontRegistry = 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Fonts'

$systemFonts = @()
if (Test-Path $fontPath) {
    try {
        $fontFiles = Get-ChildItem $fontPath -Include *.ttf, *.otf -ErrorAction SilentlyContinue
        $systemFonts = @($fontFiles | Select-Object Name, FullName, Length, LastWriteTime -First 100)
    } catch { }
}

$manifest.dependencies['SystemFonts'] = @{
    detected = $systemFonts.Count -gt 0
    count = $systemFonts.Count
    installedFonts = $systemFonts | Select-Object -First 50  # Limit large list
}

# ===== WINDOWS FEATURES & ROLES =====
Add-Log "Scanning Windows features..."
$features = @()
try {
    $features = @(Get-WindowsOptionalFeature -Online -ErrorAction SilentlyContinue | 
        Where-Object { $_.State -eq 'Enabled' } | 
        Select-Object FeatureName, State, Description)
} catch { }

$manifest.dependencies['WindowsFeatures'] = @{
    detected = $features.Count -gt 0
    count = $features.Count
    enabled = $features
}

# ===== SAVE MANIFEST =====
$outputFile = Join-Path $OutputPath "dependencies-manifest-$(Get-Date -Format 'yyyyMMdd-HHmmss').json"

try {
    $manifest | ConvertTo-Json -Depth 10 | Out-File -FilePath $outputFile -Encoding UTF8
    Write-Host "✅ Backup complete: $outputFile" -ForegroundColor Green
    Write-Host "📊 Summary:" -ForegroundColor Cyan
    Write-Host "   - Visual C++ Runtimes: $($manifest.dependencies['VisualCppRuntimes'].count)"
    Write-Host "   - .NET Framework: $($manifest.dependencies['.NETFramework'].count)"
    Write-Host "   - Python installations: $($manifest.dependencies['Python'].count)"
    Write-Host "   - Python packages: $($manifest.dependencies['Python'].packages.count)"
    Write-Host "   - Node.js: $($manifest.dependencies['NodeJs'].detected)"
    Write-Host "   - npm packages: $($manifest.dependencies['NodeJs'].globalPackages.count)"
    Write-Host "   - Crypto libraries: $($manifest.dependencies['CryptoLibraries'].libraries.Count)"
    Write-Host "   - WebView2: $($manifest.dependencies['WebView2'].detected)"
    Write-Host "   - System fonts: $($manifest.dependencies['SystemFonts'].count)"
    Write-Host "   - Windows features: $($manifest.dependencies['WindowsFeatures'].count)"
} catch {
    Write-Error "Failed to save manifest: $_"
    exit 1
}

exit 0
