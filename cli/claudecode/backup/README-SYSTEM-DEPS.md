# System Dependencies Backup & Restore

Two-script solution for backing up and restoring all critical system dependencies used by Claude/OpenClaw.

## Files

- **backup-system-deps.ps1** (11.5 KB) - Creates comprehensive dependency manifest
- **restore-system-deps.ps1** (13.3 KB) - Analyzes manifest and generates installation checklist
- **README-SYSTEM-DEPS.md** - This file

## What Gets Backed Up

### 1. **Visual C++ Runtimes**
   - All installed versions from registry
   - Installation dates, publishers, uninstall info

### 2. **.NET Framework**
   - .NET Framework versions (3.5, 4.x)
   - .NET Runtime versions (5+)
   - Installation paths

### 3. **Python**
   - All Python installations (registry + PATH)
   - Current Python version
   - Complete pip package list (all packages)

### 4. **Node.js**
   - Node version and installation path
   - Global npm packages list
   - Node installation directory

### 5. **OpenSSL & Crypto Libraries**
   - OpenSSL paths and environment variables
   - Crypto library installations
   - OpenSSL CLI version

### 6. **WebView2 Runtime**
   - Registry entries
   - Installation status
   - Version information

### 7. **System Fonts**
   - All .ttf and .otf fonts in C:\Windows\Fonts
   - Font metadata (size, modified date)

### 8. **Windows Features**
   - Enabled Windows optional features
   - Feature names and descriptions

## Usage

### Step 1: Create a Backup

```powershell
# Basic backup (default location: %APPDATA%\Local\Claude\backups)
.\backup-system-deps.ps1

# Custom output location
.\backup-system-deps.ps1 -OutputPath "C:\MyBackups"

# Verbose output
.\backup-system-deps.ps1 -Verbose
```

**Output:** Creates a `dependencies-manifest-yyyyMMdd-HHmmss.json` file containing all system dependency information.

### Step 2: Analyze Dependencies Before Restore

```powershell
# Read manifest and generate installation plan
.\restore-system-deps.ps1 -ManifestPath "C:\path\to\dependencies-manifest-*.json"

# Dry-run mode (show what would happen, don't install)
.\restore-system-deps.ps1 -ManifestPath "C:\path\to\dependencies-manifest-*.json" -DryRun
```

**Output:**
- Console display showing missing dependencies
- Installation checklist with:
  - Priority order
  - Download URLs
  - Installation commands
  - PowerShell auto-download script
- `dependencies-manifest-*-install-plan.json` (detailed plan for future reference)

## Manifest Structure

### dependencies-manifest-20250323-123456.json
```json
{
  "timestamp": "2025-03-23 12:34:56",
  "computerName": "MYPC",
  "osVersion": "Windows 10 Pro",
  "architecture": "x64",
  "dependencies": {
    "VisualCppRuntimes": {
      "detected": true,
      "count": 3,
      "items": [
        {
          "name": "Microsoft Visual C++ 2015-2022 Redistributable",
          "version": "14.38.33135",
          "installDate": "20250101",
          "publisherUrl": "https://support.microsoft.com",
          "uninstallString": "..."
        }
      ]
    },
    ".NETFramework": { ... },
    "Python": {
      "detected": true,
      "count": 1,
      "installations": [
        {
          "version": "3.11.8",
          "path": "C:\\Python311",
          "isActive": true
        }
      ],
      "packages": {
        "count": 125,
        "packages": [
          { "name": "pip", "version": "23.3.1" },
          { "name": "requests", "version": "2.31.0" },
          ...
        ]
      }
    },
    "NodeJs": { ... },
    "CryptoLibraries": { ... },
    "WebView2": { ... },
    "SystemFonts": { ... },
    "WindowsFeatures": { ... }
  }
}
```

## Installation Plan Example

When you run restore, you get:

```
✅ INSTALLATION CHECKLIST
================================

Install in this order:

1. Visual C++ 2015-2022 (x64)
   Download: https://aka.ms/vs/17/release/vc_redist.x64.exe
   Command:  <installer>.exe /install /quiet /norestart

2. Visual C++ 2015-2022 (x86)
   Download: https://aka.ms/vs/17/release/vc_redist.x86.exe
   Command:  <installer>.exe /install /quiet /norestart

3. .NET 8 Runtime
   Download: https://dotnetcli.blob.core.windows.net/dotnet/...
   Command:  msiexec.exe /i "<installer>.msi" /quiet /norestart

...

📥 DOWNLOAD LINKS
================================
```

## Installation Methods

### Method 1: Manual Download & Install (Safest)
1. Run restore script to get checklist
2. Download each .exe/.msi from provided URLs
3. Double-click each installer or run commands from checklist
4. Restart if needed after Visual C++ installs

### Method 2: Bulk Download Script
The restore script generates a PowerShell snippet to download all installers to a temp folder:

```powershell
# Run this script (copy from restore output) to download all at once
$downloads = @(
    @{ name = 'Visual C++ 2015-2022 (x64)'; url = 'https://...' }
    @{ name = 'Python 3.11'; url = 'https://...' }
    ...
)

foreach ($dl in $downloads) {
    $filepath = Join-Path $env:TEMP ($dl.name -replace '[^a-zA-Z0-9]', '_')
    Invoke-WebRequest -Uri $dl.url -OutFile $filepath -UseBasicParsing
}
```

### Method 3: Silent Install (Admin + Verification Required)
After downloading, run installers with /quiet flag:

```powershell
# Run as Administrator
cd C:\Path\To\Installers

msiexec.exe /i "vcredist_2022_x64.exe" /quiet /norestart
msiexec.exe /i "dotnet-runtime-8.exe" /quiet /norestart
python-3.11.exe /quiet InstallAllUsers=1 PrependPath=1
```

## Important Notes

### Permissions
- **Backup:** Requires read access to registry and Program Files
- **Restore:** Requires admin privileges to install software
- Run as Administrator for best results

### Network Requirements
- Restore process requires internet access to download installers
- All download URLs are to official Microsoft/vendor repositories
- No third-party mirrors or sketchy sources

### Font Backup Limitations
- Font files are very large and only filenames are backed up
- On restore, fonts are detected by scanning C:\Windows\Fonts
- To fully restore fonts, manually copy font files from backup

### Python Packages
- Only first 50 packages shown in manifest (due to size)
- All packages ARE backed up; use `pip freeze > requirements.txt` for complete list
- To restore packages: `pip install -r requirements.txt`

### Customization
Feel free to edit the scripts to:
- Add/remove specific dependencies
- Change installer URLs (to match your versions)
- Modify installation arguments
- Add post-install verification steps

## Troubleshooting

### "Manifest not found"
Ensure path exists or use wildcard:
```powershell
.\restore-system-deps.ps1 -ManifestPath "C:\backups\deps\dependencies-manifest-*.json"
```

### Installation hangs
Press Ctrl+C and try again. Some installers need to be run one at a time.

### PowerShell execution policy error
```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Missing dependencies after restore
Re-run backup script to check what was actually installed vs. what the manifest expected.

## File Locations

Default locations:
- **Backup output:** `%APPDATA%\Local\Claude\backups\dependencies-manifest-*.json`
- **Install plan:** Same folder as manifest with `-install-plan.json` suffix
- **Scripts:** `F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\`

## Version Info

- **Created:** 2025-03-23
- **PowerShell:** Requires v5.1+
- **Windows:** Windows 10/11
- **Admin rights:** Recommended for restore operations

## Future Enhancements

Potential improvements:
- Cloud storage upload for manifests
- Compression of font backups
- Automated version checking against latest releases
- Parallel installation for faster setup
- Integration with chocolatey/winget for additional packages
- Docker export for environment reproducibility
