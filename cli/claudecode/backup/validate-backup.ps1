param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath
)

# ============================================================================
# QUICK VALIDATE BACKUP UTILITY
# Validates complete backup integrity of ClaudeCode ecosystem
# ============================================================================

$ErrorActionPreference = "Stop"
$WarningPreference = "SilentlyContinue"

# Colors
$colors = @{
    Success = "Green"
    Error = "Red"
    Warning = "Yellow"
    Info = "Cyan"
    Section = "Magenta"
}

function Write-Header {
    param([string]$Text)
    Write-Host "`n" -NoNewline
    Write-Host "╔" + ("═" * 70) + "╗" -ForegroundColor $colors.Section
    Write-Host "║ $Text".PadRight(72) + "║" -ForegroundColor $colors.Section
    Write-Host "╚" + ("═" * 70) + "╝" -ForegroundColor $colors.Section
}

function Write-CheckItem {
    param(
        [string]$Name,
        [bool]$Exists,
        [string]$Path = ""
    )
    $status = if ($Exists) { "✓" } else { "✗" }
    $color = if ($Exists) { $colors.Success } else { $colors.Error }
    $display = if ($Path) { "$Name ($Path)" } else { $Name }
    Write-Host "  $status $display" -ForegroundColor $color
    return $Exists
}

# Track results
$results = @{
    Categories = @{}
    Missing = @()
    Total = 0
    Found = 0
}

# Validate backup path
if (-not (Test-Path $BackupPath)) {
    Write-Host "✗ FATAL: Backup path not found: $BackupPath" -ForegroundColor $colors.Error
    exit 1
}

Write-Header "BACKUP VALIDATION REPORT"
Write-Host "Backup Path: $BackupPath" -ForegroundColor $colors.Info
Write-Host "Started: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor $colors.Info

# ============================================================================
# SECTION 1: CRITICAL CLAUDE DIRECTORY
# ============================================================================
Write-Header "1. CLAUDE DIRECTORY (.claude)"
$claudeDir = Join-Path $BackupPath ".claude"
$claudeFound = Test-Path $claudeDir

if ($claudeFound) {
    $claudeItems = @(
        @{Name=".claude/scripts"; File="scripts" },
        @{Name=".claude/extensions"; File="extensions" },
        @{Name=".claude/workspaces"; File="workspaces" },
        @{Name=".claude/gateway"; File="gateway" },
        @{Name=".claude/config"; File="config" }
    )
    
    $claudeCount = 0
    foreach ($item in $claudeItems) {
        $itemPath = Join-Path $claudeDir $item.File
        $exists = Test-Path $itemPath
        Write-CheckItem $item.Name $exists $itemPath
        $results.Total++
        if ($exists) { $claudeCount++; $results.Found++ }
        else { $results.Missing += $item.Name }
    }
    Write-Host "  Result: $claudeCount / $($claudeItems.Count) subdirs found" -ForegroundColor $colors.Info
} else {
    Write-Host "  ✗ CRITICAL: .claude directory missing!" -ForegroundColor $colors.Error
    $results.Missing += ".claude directory"
}

# ============================================================================
# SECTION 2: CONFIGURATION FILES
# ============================================================================
Write-Header "2. CONFIGURATION FILES"
$configFiles = @(
    @{Name=".claude.json"; Path=".claude.json" },
    @{Name=".claude.json.backup"; Path=".claude.json.backup" },
    @{Name="claude-config.json"; Path="claude-config.json" }
)

$configCount = 0
foreach ($file in $configFiles) {
    $filePath = Join-Path $BackupPath $file.Path
    $exists = Test-Path $filePath
    Write-CheckItem $file.Name $exists $file.Path
    $results.Total++
    if ($exists) { $configCount++; $results.Found++ }
    else { $results.Missing += $file.Name }
}
Write-Host "  Result: $configCount / $($configFiles.Count) config files found" -ForegroundColor $colors.Info

# ============================================================================
# SECTION 3: OPENCLAW WORKSPACES
# ============================================================================
Write-Header "3. OPENCLAW WORKSPACES"
$workspaces = @(
    "workspace",
    "workspace-main",
    "workspace-session2",
    "workspace-openclaw",
    "workspace-openclaw4",
    "workspace-moltbot",
    "workspace-moltbot2",
    "workspace-openclaw-main"
)

$workspaceCount = 0
foreach ($ws in $workspaces) {
    $wsPath = Join-Path $BackupPath $ws
    $exists = Test-Path $wsPath
    Write-CheckItem "Workspace: $ws" $exists $ws
    $results.Total++
    if ($exists) { $workspaceCount++; $results.Found++ }
    else { $results.Missing += $ws }
}
Write-Host "  Result: $workspaceCount / $($workspaces.Count) workspaces found" -ForegroundColor $colors.Info

# ============================================================================
# SECTION 4: NPM PACKAGES & NODE_MODULES
# ============================================================================
Write-Header "4. NPM PACKAGES"
$npmPackages = @(
    "node_modules/claude-code",
    "node_modules/@anthropic-ai",
    "node_modules/openclaw",
    "node_modules/moltbot",
    "node_modules/clawdbot",
    "node_modules/opencode"
)

$npmCount = 0
foreach ($pkg in $npmPackages) {
    $pkgPath = Join-Path $BackupPath $pkg
    $exists = Test-Path $pkgPath
    $displayName = $pkg -replace 'node_modules/', ''
    Write-CheckItem "Package: $displayName" $exists $pkg
    $results.Total++
    if ($exists) { $npmCount++; $results.Found++ }
    else { $results.Missing += $pkg }
}
Write-Host "  Result: $npmCount / $($npmPackages.Count) packages found" -ForegroundColor $colors.Info

# ============================================================================
# SECTION 5: MCP CONFIGURATION
# ============================================================================
Write-Header "5. MCP CONFIGURATION"
$mcpFiles = @(
    @{Name="mcp.json"; Path="mcp.json" },
    @{Name="mcp-servers.json"; Path="mcp-servers.json" },
    @{Name="mcp-config"; Path="mcp-config" }
)

$mcpCount = 0
foreach ($file in $mcpFiles) {
    $filePath = Join-Path $BackupPath $file.Path
    $exists = Test-Path $filePath
    Write-CheckItem $file.Name $exists $file.Path
    $results.Total++
    if ($exists) { $mcpCount++; $results.Found++ }
    else { $results.Missing += $file.Name }
}
Write-Host "  Result: $mcpCount / $($mcpFiles.Count) MCP configs found" -ForegroundColor $colors.Info

# ============================================================================
# SECTION 6: POWERSHELL PROFILES
# ============================================================================
Write-Header "6. POWERSHELL PROFILES"
$psProfiles = @(
    "PowerShell/profile.ps1",
    "PowerShell/Microsoft.PowerShell_profile.ps1",
    "PowerShell/profile-main.ps1"
)

$psCount = 0
foreach ($profile in $psProfiles) {
    $profilePath = Join-Path $BackupPath $profile
    $exists = Test-Path $profilePath
    Write-CheckItem $profile $exists
    $results.Total++
    if ($exists) { $psCount++; $results.Found++ }
    else { $results.Missing += $profile }
}
Write-Host "  Result: $psCount / $($psProfiles.Count) profiles found" -ForegroundColor $colors.Info

# ============================================================================
# SECTION 7: REGISTRY EXPORTS & VBS FILES
# ============================================================================
Write-Header "7. REGISTRY EXPORTS & VBS STARTUP FILES"
$regFiles = @(
    "Registry/startup.vbs",
    "Registry/claude-startup.vbs",
    "Registry/system-registry.reg",
    "Registry/user-registry.reg"
)

$regCount = 0
foreach ($file in $regFiles) {
    $filePath = Join-Path $BackupPath $file
    $exists = Test-Path $filePath
    Write-CheckItem $file $exists
    $results.Total++
    if ($exists) { $regCount++; $results.Found++ }
    else { $results.Missing += $file }
}
Write-Host "  Result: $regCount / $($regFiles.Count) registry files found" -ForegroundColor $colors.Info

# ============================================================================
# SECTION 8: SHORTCUTS & LINKS
# ============================================================================
Write-Header "8. SHORTCUTS & LINKS"
$shortcuts = @(
    "Shortcuts/ClaudeCode.lnk",
    "Shortcuts/OpenClaw.lnk",
    "Shortcuts/MoltBot.lnk",
    "Shortcuts/Terminal-ClaudeCode.lnk"
)

$shortcutCount = 0
foreach ($shortcut in $shortcuts) {
    $shortcutPath = Join-Path $BackupPath $shortcut
    $exists = Test-Path $shortcutPath
    Write-CheckItem $shortcut $exists
    $results.Total++
    if ($exists) { $shortcutCount++; $results.Found++ }
    else { $results.Missing += $shortcut }
}
Write-Host "  Result: $shortcutCount / $($shortcuts.Count) shortcuts found" -ForegroundColor $colors.Info

# ============================================================================
# SECTION 9: METADATA & MANIFEST
# ============================================================================
Write-Header "9. METADATA & MANIFEST"
$metaFiles = @(
    "backup-manifest.json",
    "backup-metadata.json",
    "manifest.json",
    "BACKUP_INFO.txt"
)

$metaCount = 0
foreach ($file in $metaFiles) {
    $filePath = Join-Path $BackupPath $file
    $exists = Test-Path $filePath
    Write-CheckItem $file $exists
    $results.Total++
    if ($exists) { $metaCount++; $results.Found++ }
    else { $results.Missing += $file }
}
Write-Host "  Result: $metaCount / $($metaFiles.Count) metadata files found" -ForegroundColor $colors.Info

# ============================================================================
# VALIDATION SUMMARY
# ============================================================================
Write-Header "VALIDATION SUMMARY"

$completeness = [int](($results.Found / $results.Total) * 100)
Write-Host "Items Found: $($results.Found) / $($results.Total)" -ForegroundColor $colors.Info
Write-Host "Completeness: $completeness%" -ForegroundColor $colors.Info

# ============================================================================
# FILE HASH VALIDATION (WHERE APPLICABLE)
# ============================================================================
Write-Header "10. FILE HASH VALIDATION"

$hashTarget = Join-Path $BackupPath ".claude.json"
if (Test-Path $hashTarget) {
    try {
        $hash = Get-FileHash $hashTarget -Algorithm SHA256
        Write-Host "✓ .claude.json SHA256: $($hash.Hash.Substring(0,16))..." -ForegroundColor $colors.Success
        $claudeJsonSize = (Get-Item $hashTarget).Length
        Write-Host "  Size: $([math]::Round($claudeJsonSize / 1MB, 2)) MB" -ForegroundColor $colors.Info
    } catch {
        Write-Host "✗ Failed to hash .claude.json: $_" -ForegroundColor $colors.Error
    }
}

# Validate manifest if present
$manifestPath = Join-Path $BackupPath "backup-manifest.json"
if (Test-Path $manifestPath) {
    try {
        $manifest = Get-Content $manifestPath | ConvertFrom-Json
        Write-Host "✓ Backup manifest valid" -ForegroundColor $colors.Success
        if ($manifest.timestamp) {
            Write-Host "  Created: $($manifest.timestamp)" -ForegroundColor $colors.Info
        }
        if ($manifest.version) {
            Write-Host "  Version: $($manifest.version)" -ForegroundColor $colors.Info
        }
    } catch {
        Write-Host "✗ Invalid manifest JSON: $_" -ForegroundColor $colors.Warning
    }
}

# ============================================================================
# REMEDIATION SUGGESTIONS
# ============================================================================
if ($results.Missing.Count -gt 0) {
    Write-Header "REMEDIATION SUGGESTIONS"
    Write-Host "Missing $($results.Missing.Count) item(s). Suggested actions:" -ForegroundColor $colors.Warning
    Write-Host ""
    
    foreach ($item in $results.Missing) {
        $remediation = switch -Wildcard ($item) {
            ".claude*" {
                "► Restore .claude directory from source: Copy-Item -Recurse -Force"
            }
            "workspace*" {
                "► Recover workspace from OpenClaw config or re-clone from source repo"
            }
            "node_modules/*" {
                "► Run 'npm install' to restore packages"
            }
            "*.vbs" {
                "► Re-export VBS startup scripts from Windows Task Scheduler / Startup folder"
            }
            "*.ps1" {
                "► Restore PowerShell profiles from source or reload from $PROFILE location"
            }
            "*.reg" {
                "► Export registry again using 'regedit /e filename.reg [KEY_PATH]'"
            }
            "*.lnk" {
                "► Recreate shortcuts using New-Item -ItemType SymbolicLink"
            }
            default {
                "► Restore from source or recreate this item"
            }
        }
        Write-Host "  • $item" -ForegroundColor $colors.Error
        Write-Host "    $remediation" -ForegroundColor $colors.Info
    }
    Write-Host ""
}

# ============================================================================
# FINAL VERDICT
# ============================================================================
Write-Header "FINAL VERDICT"

if ($results.Missing.Count -eq 0) {
    Write-Host "✓ BACKUP OK" -ForegroundColor $colors.Success
    Write-Host ""
    Write-Host "All critical files present. Backup integrity verified." -ForegroundColor $colors.Success
    Write-Host "Backup can be safely restored or archived." -ForegroundColor $colors.Success
    exit 0
} else {
    Write-Host "✗ BACKUP INCOMPLETE" -ForegroundColor $colors.Error
    Write-Host ""
    Write-Host "Missing Items: $($results.Missing.Count)" -ForegroundColor $colors.Error
    Write-Host "Completeness: $completeness%" -ForegroundColor $colors.Warning
    Write-Host ""
    Write-Host "Missing:" -ForegroundColor $colors.Error
    foreach ($item in $results.Missing) {
        Write-Host "  - $item" -ForegroundColor $colors.Error
    }
    Write-Host ""
    Write-Host "⚠️  Do NOT restore this backup until missing items are recovered." -ForegroundColor $colors.Warning
    exit 1
}
