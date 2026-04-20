#!/usr/bin/env pwsh
<#
.SYNOPSIS
    Selective Restore Utility - Restore specific items from backup

.DESCRIPTION
    Allows users to selectively restore components from a backup:
    - .claude directory
    - .openclaw directory
    - npm packages
    - Configuration files
    - Startup items
    - Credentials
    - Browser data
    
    Features:
    - Shows component sizes
    - Previews what will be overwritten
    - Asks for confirmation
    - Restores only selected items
    - Generates detailed report

.PARAMETER BackupPath
    Path to the backup directory containing backed-up components

.PARAMETER Interactive
    Enable interactive mode (prompts for selections and confirmations)

.PARAMETER Components
    Comma-separated list of components to restore (non-interactive mode)

.EXAMPLE
    .\restore-selective.ps1 -BackupPath "D:\backups\claude-2026-03-23" -Interactive

.EXAMPLE
    .\restore-selective.ps1 -BackupPath "D:\backups\claude-2026-03-23" -Components ".claude,.openclaw,npm"
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$BackupPath,
    
    [switch]$Interactive,
    
    [string]$Components = ""
)

# ============================================================================
# CONFIGURATION & COLORS
# ============================================================================

$ErrorActionPreference = "Continue"
$WarningActionPreference = "Continue"

$Colors = @{
    Reset   = "`e[0m"
    Bold    = "`e[1m"
    Green   = "`e[32m"
    Yellow  = "`e[33m"
    Red     = "`e[31m"
    Cyan    = "`e[36m"
    Gray    = "`e[90m"
}

$HomeDir = $env:USERPROFILE
$ReportFile = (Get-ChildItem $BackupPath -ErrorAction SilentlyContinue | Select-Object -First 1).FullName | Split-Path -Parent
if (-not $ReportFile) { $ReportFile = $BackupPath }
$ReportFile = Join-Path $ReportFile "restore-report-$(Get-Date -Format 'yyyy-MM-dd_HHmmss').txt"

# ============================================================================
# UTILITY FUNCTIONS
# ============================================================================

function Write-Color {
    param(
        [string]$Text,
        [string]$Color = "Reset"
    )
    Write-Host "$($Colors[$Color])$Text$($Colors['Reset'])" -NoNewline
}

function Write-Header {
    param([string]$Title)
    Write-Host ""
    Write-Color "═══════════════════════════════════════════════════════════" "Cyan"
    Write-Host ""
    Write-Color "$Title" "Bold"
    Write-Host ""
    Write-Color "═══════════════════════════════════════════════════════════" "Cyan"
    Write-Host ""
}

function Write-Success {
    param([string]$Message)
    Write-Color "✓ " "Green"
    Write-Host $Message
}

function Write-Warning {
    param([string]$Message)
    Write-Color "⚠ " "Yellow"
    Write-Host $Message
}

function Write-Error {
    param([string]$Message)
    Write-Color "✗ " "Red"
    Write-Host $Message
}

function Format-Size {
    param([long]$Bytes)
    if ($Bytes -ge 1GB) {
        return "{0:N2} GB" -f ($Bytes / 1GB)
    } elseif ($Bytes -ge 1MB) {
        return "{0:N2} MB" -f ($Bytes / 1MB)
    } elseif ($Bytes -ge 1KB) {
        return "{0:N2} KB" -f ($Bytes / 1KB)
    } else {
        return "$Bytes B"
    }
}

function Get-DirectorySize {
    param([string]$Path)
    
    if (-not (Test-Path $Path)) {
        return 0
    }
    
    try {
        $items = Get-ChildItem -Path $Path -Recurse -Force -ErrorAction SilentlyContinue
        $size = ($items | Measure-Object -Property Length -Sum).Sum
        return if ($size) { $size } else { 0 }
    } catch {
        return 0
    }
}

function Test-TargetExists {
    param([string]$TargetPath)
    return (Test-Path $TargetPath)
}

# ============================================================================
# COMPONENT DEFINITIONS
# ============================================================================

$Components_Definition = @{
    ".claude" = @{
        Name        = ".claude directory"
        Description = "Claude CLI configuration and data"
        BackupPath  = ".claude"
        TargetPath  = Join-Path $HomeDir ".claude"
        Size        = 0
        Exists      = $false
    }
    ".openclaw" = @{
        Name        = ".openclaw directory"
        Description = "OpenClaw configuration and extensions"
        BackupPath  = ".openclaw"
        TargetPath  = Join-Path $HomeDir ".openclaw"
        Size        = 0
        Exists      = $false
    }
    "npm" = @{
        Name        = "npm packages"
        Description = "Global npm packages and node_modules"
        BackupPath  = "npm"
        TargetPath  = Join-Path $env:APPDATA "npm"
        Size        = 0
        Exists      = $false
    }
    "config" = @{
        Name        = "Configuration files"
        Description = "Various configuration files (.gitconfig, .zshrc, etc.)"
        BackupPath  = "config"
        TargetPath  = $HomeDir
        Size        = 0
        Exists      = $false
    }
    "startup" = @{
        Name        = "Startup items"
        Description = "Startup scripts and scheduled tasks"
        BackupPath  = "startup"
        TargetPath  = "$HomeDir\AppData\Roaming\Microsoft\Windows\Start Menu\Programs\Startup"
        Size        = 0
        Exists      = $false
    }
    "credentials" = @{
        Name        = "Credentials & secrets"
        Description = "SSH keys, API credentials, tokens"
        BackupPath  = "credentials"
        TargetPath  = Join-Path $HomeDir ".credentials"
        Size        = 0
        Exists      = $false
    }
    "browser" = @{
        Name        = "Browser data"
        Description = "Browser profiles, bookmarks, extensions"
        BackupPath  = "browser"
        TargetPath  = "$HomeDir\AppData\Roaming\Chromium"
        Size        = 0
        Exists      = $false
    }
    "documents" = @{
        Name        = "Documents"
        Description = "Personal documents and projects"
        BackupPath  = "documents"
        TargetPath  = "$HomeDir\Documents"
        Size        = 0
        Exists      = $false
    }
}

# ============================================================================
# VALIDATION & INITIALIZATION
# ============================================================================

function Initialize-Components {
    Write-Host "Scanning backup components..."
    
    foreach ($key in $Components_Definition.Keys) {
        $comp = $Components_Definition[$key]
        $backupFullPath = Join-Path $BackupPath $comp.BackupPath
        
        if (Test-Path $backupFullPath) {
            $comp.Size = Get-DirectorySize $backupFullPath
            $comp.Exists = Test-Path $comp.TargetPath
        }
    }
}

function Validate-BackupPath {
    if (-not (Test-Path $BackupPath)) {
        Write-Error "Backup path does not exist: $BackupPath"
        exit 1
    }
    
    $items = Get-ChildItem -Path $BackupPath -ErrorAction SilentlyContinue
    if ($items.Count -eq 0) {
        Write-Error "Backup path is empty: $BackupPath"
        exit 1
    }
    
    Write-Success "Backup path validated: $BackupPath"
}

# ============================================================================
# INTERACTIVE SELECTION
# ============================================================================

function Show-ComponentTable {
    Write-Host ""
    Write-Host "Available components to restore:" | Write-Host
    Write-Host ""
    
    $index = 1
    $validComponents = @()
    
    foreach ($key in $Components_Definition.Keys) {
        $comp = $Components_Definition[$key]
        
        # Only show components that exist in backup
        $backupPath = Join-Path $BackupPath $comp.BackupPath
        if (Test-Path $backupPath) {
            $statusSymbol = if ($comp.Exists) { "⚠" } else { "✓" }
            $statusColor = if ($comp.Exists) { "Yellow" } else { "Green" }
            $sizeStr = Format-Size $comp.Size
            
            Write-Host "  " -NoNewline
            Write-Color "[$index]" "Cyan"
            Write-Host " $($comp.Name)" -NoNewline
            Write-Host " - " -NoNewline
            Write-Color $comp.Description "Gray"
            Write-Host ""
            Write-Host "       Size: " -NoNewline
            Write-Color $sizeStr "Bold"
            Write-Host ", Status: " -NoNewline
            Write-Color "$statusSymbol $(if ($comp.Exists) { 'Will overwrite' } else { 'New' })" $statusColor
            Write-Host ""
            
            $validComponents += $key
            $index++
        }
    }
    
    return $validComponents
}

function Get-UserSelections {
    param([array]$ValidComponents)
    
    Write-Host ""
    Write-Color "Select components to restore (space-separated numbers, e.g., '1 3 5'): " "Bold"
    $input = Read-Host
    
    $selections = @()
    if ($input -ne "") {
        $numbers = $input -split '\s+' | Where-Object { $_ -match '^\d+$' }
        
        foreach ($num in $numbers) {
            $idx = [int]$num - 1
            if ($idx -ge 0 -and $idx -lt $ValidComponents.Count) {
                $selections += $ValidComponents[$idx]
            }
        }
    }
    
    return $selections
}

function Show-PreviewAndConfirm {
    param([array]$SelectedComponents)
    
    Write-Header "Restore Preview"
    
    $totalSize = 0
    $willOverwrite = 0
    
    Write-Host "The following will be restored:" ""
    Write-Host ""
    
    foreach ($key in $SelectedComponents) {
        $comp = $Components_Definition[$key]
        $backupPath = Join-Path $BackupPath $comp.BackupPath
        $size = Get-DirectorySize $backupPath
        $totalSize += $size
        
        Write-Host "  • " -NoNewline
        Write-Color $comp.Name "Green"
        Write-Host " - " -NoNewline
        Write-Color (Format-Size $size) "Bold"
        
        if ($comp.Exists) {
            Write-Host " " -NoNewline
            Write-Color "[WILL OVERWRITE]" "Red"
            $willOverwrite++
        }
        
        Write-Host ""
    }
    
    Write-Host ""
    Write-Color "Total size: " "Bold"
    Write-Color (Format-Size $totalSize) "Bold"
    Write-Host ""
    
    if ($willOverwrite -gt 0) {
        Write-Warning "$willOverwrite component(s) will overwrite existing data"
    }
    
    Write-Host ""
    Write-Color "Proceed with restore? (yes/no): " "Bold"
    $confirm = Read-Host
    
    return ($confirm -eq "yes" -or $confirm -eq "y")
}

# ============================================================================
# RESTORATION LOGIC
# ============================================================================

function Restore-Component {
    param(
        [string]$ComponentKey,
        [ref]$Report
    )
    
    $comp = $Components_Definition[$ComponentKey]
    $backupPath = Join-Path $BackupPath $comp.BackupPath
    
    try {
        $Report.Value += "`n[RESTORING] $($comp.Name)`n"
        
        if (-not (Test-Path $backupPath)) {
            $Report.Value += "  Status: SKIPPED (not found in backup)`n"
            return $false
        }
        
        # Create parent directory if needed
        if ($comp.TargetPath -and -not (Test-Path (Split-Path $comp.TargetPath))) {
            New-Item -ItemType Directory -Path (Split-Path $comp.TargetPath) -Force | Out-Null
        }
        
        # Remove existing target if it exists
        if (Test-Path $comp.TargetPath) {
            Write-Warning "Removing existing: $($comp.TargetPath)"
            Remove-Item -Path $comp.TargetPath -Recurse -Force -ErrorAction SilentlyContinue
        }
        
        # Copy from backup
        Copy-Item -Path $backupPath -Destination $comp.TargetPath -Recurse -Force -ErrorAction Stop
        
        $size = Get-DirectorySize $comp.TargetPath
        $Report.Value += "  Status: RESTORED`n"
        $Report.Value += "  Location: $($comp.TargetPath)`n"
        $Report.Value += "  Size: $(Format-Size $size)`n"
        $Report.Value += "  Timestamp: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
        
        Write-Success "Restored: $($comp.Name)"
        return $true
    } catch {
        $Report.Value += "  Status: FAILED`n"
        $Report.Value += "  Error: $($_.Exception.Message)`n"
        Write-Error "Failed to restore $($comp.Name): $($_.Exception.Message)"
        return $false
    }
}

# ============================================================================
# REPORT GENERATION
# ============================================================================

function Generate-Report {
    param(
        [array]$SelectedComponents,
        [ref]$Report,
        [array]$RestoreResults
    )
    
    $Report.Value = "SELECTIVE RESTORE REPORT`n"
    $Report.Value += "=" * 70 + "`n"
    $Report.Value += "Generated: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')`n"
    $Report.Value += "Backup Source: $BackupPath`n"
    $Report.Value += "User: $env:USERNAME`n"
    $Report.Value += "Computer: $env:COMPUTERNAME`n"
    $Report.Value += "`n"
    
    $successCount = ($RestoreResults | Where-Object { $_ -eq $true }).Count
    $failureCount = ($RestoreResults | Where-Object { $_ -eq $false }).Count
    
    $Report.Value += "SUMMARY`n"
    $Report.Value += "-" * 70 + "`n"
    $Report.Value += "Total Components: $($SelectedComponents.Count)`n"
    $Report.Value += "Successfully Restored: $successCount`n"
    $Report.Value += "Failed: $failureCount`n"
    $Report.Value += "`n"
    
    foreach ($key in $SelectedComponents) {
        $comp = $Components_Definition[$key]
        $backupPath = Join-Path $BackupPath $comp.BackupPath
        $size = Get-DirectorySize $backupPath
        
        $Report.Value += "`n[COMPONENT] $($comp.Name)`n"
        $Report.Value += "  Description: $($comp.Description)`n"
        $Report.Value += "  Source: $backupPath`n"
        $Report.Value += "  Target: $($comp.TargetPath)`n"
        $Report.Value += "  Size: $(Format-Size $size)`n"
    }
    
    $Report.Value += "`n" + ("=" * 70) + "`n"
    $Report.Value += "End of Report`n"
}

function Save-Report {
    param([string]$ReportContent)
    
    try {
        Set-Content -Path $ReportFile -Value $ReportContent -Force
        Write-Success "Report saved: $ReportFile"
        return $ReportFile
    } catch {
        Write-Error "Failed to save report: $($_.Exception.Message)"
        return $null
    }
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================

function Main {
    Clear-Host
    Write-Header "SELECTIVE RESTORE UTILITY"
    
    # Validate backup path
    Validate-BackupPath
    
    # Initialize components
    Initialize-Components
    
    # Get valid components
    $validComponents = Show-ComponentTable
    
    if ($validComponents.Count -eq 0) {
        Write-Error "No components found in backup"
        exit 1
    }
    
    # Determine selections
    [array]$selectedComponents = @()
    
    if ($Interactive) {
        # Interactive mode
        $selectedComponents = Get-UserSelections $validComponents
        
        if ($selectedComponents.Count -eq 0) {
            Write-Warning "No components selected"
            exit 0
        }
        
        # Show preview and get confirmation
        if (-not (Show-PreviewAndConfirm $selectedComponents)) {
            Write-Warning "Restore cancelled by user"
            exit 0
        }
    } else {
        # Non-interactive mode: use Components parameter
        if ($Components -ne "") {
            $requested = $Components -split ',' | ForEach-Object { $_.Trim() }
            foreach ($comp in $requested) {
                if ($validComponents -contains $comp) {
                    $selectedComponents += $comp
                }
            }
        }
        
        if ($selectedComponents.Count -eq 0) {
            Write-Error "No valid components specified"
            exit 1
        }
    }
    
    # Perform restore
    Write-Header "RESTORING COMPONENTS"
    
    $report = ""
    $results = @()
    
    foreach ($key in $selectedComponents) {
        $result = Restore-Component -ComponentKey $key -Report ([ref]$report)
        $results += $result
    }
    
    # Generate and save report
    Write-Header "RESTORE COMPLETE"
    
    $report = ""
    Generate-Report -SelectedComponents $selectedComponents -Report ([ref]$report) -RestoreResults $results
    Save-Report $report
    
    # Summary
    $successCount = ($results | Where-Object { $_ -eq $true }).Count
    $failureCount = ($results | Where-Object { $_ -eq $false }).Count
    
    Write-Host ""
    Write-Color "Successfully restored: " "Green"
    Write-Host "$successCount/$($selectedComponents.Count)"
    
    if ($failureCount -gt 0) {
        Write-Color "Failed: " "Red"
        Write-Host $failureCount
    }
    
    Write-Host ""
    Write-Success "Selective restore completed"
    Write-Host "Report: $ReportFile"
}

# Run main
Main
