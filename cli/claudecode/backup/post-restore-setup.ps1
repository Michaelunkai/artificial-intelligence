#Requires -Version 5.1
<#
.SYNOPSIS
    Post-Restore Setup Script for Claude Code CLI & OpenClaw
    
.DESCRIPTION
    Runs AFTER restore-claudecode.ps1 completes. Handles:
    - NPM package re-registration
    - Credential re-authentication
    - MCP server path verification
    - OpenClaw gateway Windows service registration
    - Scheduled task creation
    - Desktop & startup shortcuts recreation
    - Environment variable validation
    - CLI testing
    
.NOTES
    Source: restore-claudecode.ps1
    Call with: . post-restore-setup.ps1
#>

param(
    [switch]$SkipInteractive,
    [switch]$Verbose
)

# ===== INITIALIZATION =====
$ErrorActionPreference = "Continue"
$WarningPreference = "Continue"
$VerbosePreference = if ($Verbose) { "Continue" } else { "SilentlyContinue" }

$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
$logFile = Join-Path $scriptRoot "post-restore-setup_$timestamp.log"
$errorLog = Join-Path $scriptRoot "post-restore-setup_errors_$timestamp.log"

# Progress tracking
$checks = @()
$passed = 0
$failed = 0
$warnings = 0

function Write-Log {
    param([string]$Message, [ValidateSet("INFO", "WARN", "ERROR", "SUCCESS")][string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logMessage = "[$timestamp] [$Level] $Message"
    Write-Host $logMessage
    Add-Content -Path $logFile -Value $logMessage -ErrorAction SilentlyContinue
    
    if ($Level -eq "ERROR") {
        Add-Content -Path $errorLog -Value $logMessage -ErrorAction SilentlyContinue
    }
}

function Test-IsAdmin {
    $currentPrincipal = [Security.Principal.WindowsPrincipal]::new([Security.Principal.WindowsIdentity]::GetCurrent())
    return $currentPrincipal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Register-Check {
    param([string]$Name, [bool]$Passed, [string]$Details = "")
    $script:checks += @{
        Name = $Name
        Passed = $Passed
        Details = $Details
        Timestamp = Get-Date
    }
    if ($Passed) { $script:passed++ } else { $script:failed++ }
}

Write-Host "`n" + ("=" * 70) -ForegroundColor Cyan
Write-Host "POST-RESTORE SETUP SCRIPT" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Log "Starting post-restore setup..."
Write-Log "Admin mode: $(Test-IsAdmin)"
Write-Host ""

# ===== STEP 1: RE-REGISTER NPM PACKAGES =====
Write-Host "STEP 1: NPM Package Re-Registration" -ForegroundColor Yellow
Write-Log "Step 1: Starting NPM package re-registration"

$npmSuccess = $true
$npmGlobalPackages = @()

try {
    # Check npm is installed
    $npmVersion = npm --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "NPM version: $npmVersion" "INFO"
        
        # List globally installed packages
        $npmList = npm list -g --depth=0 2>$null | Select-Object -Skip 1
        $npmGlobalPackages = $npmList | Where-Object { $_ -match '^\s+├──|^\s+└──' } | 
                            ForEach-Object { ($_ -replace '^\s+[├└]──\s+', '').Split('@')[0].Trim() }
        
        if ($npmGlobalPackages.Count -gt 0) {
            Write-Log "Found $($npmGlobalPackages.Count) global NPM packages"
            
            foreach ($pkg in $npmGlobalPackages) {
                try {
                    Write-Log "Re-registering NPM package: $pkg"
                    npm link $pkg 2>$null | Out-Null
                    if ($LASTEXITCODE -eq 0) {
                        Write-Log "✓ $pkg re-registered" "SUCCESS"
                    } else {
                        Write-Log "⚠ $pkg link attempt (may already be linked)" "WARN"
                        $script:warnings++
                    }
                } catch {
                    Write-Log "✗ Failed to link $pkg : $_" "ERROR"
                    $npmSuccess = $false
                }
            }
        } else {
            Write-Log "No global NPM packages found to re-register" "WARN"
        }
    } else {
        Write-Log "✗ NPM not found or not in PATH" "ERROR"
        $npmSuccess = $false
    }
} catch {
    Write-Log "✗ NPM registration error: $_" "ERROR"
    $npmSuccess = $false
}

Register-Check -Name "NPM Package Re-Registration" -Passed $npmSuccess -Details "$($npmGlobalPackages.Count) packages"

# ===== STEP 2: CREDENTIAL RE-AUTHENTICATION =====
Write-Host "`nSTEP 2: Credential Re-Authentication" -ForegroundColor Yellow
Write-Log "Step 2: Starting credential re-authentication"

$credentialSuccess = $true
$credentialChecks = @()

# GitHub
Write-Log "Checking GitHub credentials..."
$githubConfigPath = "$env:USERPROFILE\.gitconfig"
if (Test-Path $githubConfigPath) {
    $githubEmail = & git config --global user.email 2>$null
    $githubName = & git config --global user.name 2>$null
    if ($githubEmail -and $githubName) {
        Write-Log "✓ GitHub configured: $githubName <$githubEmail>" "SUCCESS"
        $credentialChecks += @{ Service = "GitHub"; Status = "OK" }
    } else {
        Write-Log "⚠ GitHub config incomplete. Run: git config --global user.name 'Your Name'" "WARN"
        $credentialChecks += @{ Service = "GitHub"; Status = "INCOMPLETE" }
        $script:warnings++
    }
} else {
    Write-Log "⚠ Git not configured" "WARN"
    $credentialChecks += @{ Service = "GitHub"; Status = "NOTFOUND" }
}

# Anthropic API
Write-Log "Checking Anthropic API credentials..."
$anthropicApiKeyPath = "$env:USERPROFILE\.anthropic\api_key"
if (Test-Path $anthropicApiKeyPath) {
    $apiKeyLength = (Get-Content $anthropicApiKeyPath | Measure-Object -Character).Characters
    Write-Log "✓ Anthropic API key found ($apiKeyLength chars)" "SUCCESS"
    $credentialChecks += @{ Service = "Anthropic API"; Status = "OK" }
} elseif ($env:ANTHROPIC_API_KEY) {
    Write-Log "✓ Anthropic API key in environment variable" "SUCCESS"
    $credentialChecks += @{ Service = "Anthropic API"; Status = "OK (ENV)" }
} else {
    Write-Log "⚠ Anthropic API key not found. Set ANTHROPIC_API_KEY or create ~/.anthropic/api_key" "WARN"
    $credentialChecks += @{ Service = "Anthropic API"; Status = "NOTFOUND" }
    $script:warnings++
}

# OpenClaw credentials
Write-Log "Checking OpenClaw gateway token..."
$openclaConfigPath = "C:\Users\$env:USERNAME\.openclaw\openclaw.json"
if (Test-Path $openclaConfigPath) {
    Write-Log "✓ OpenClaw config found" "SUCCESS"
    $credentialChecks += @{ Service = "OpenClaw"; Status = "OK" }
} else {
    Write-Log "⚠ OpenClaw config not found at $openclaConfigPath" "WARN"
    $credentialChecks += @{ Service = "OpenClaw"; Status = "NOTFOUND" }
}

if ($credentialChecks | Where-Object { $_.Status -eq "NOTFOUND" }) {
    $credentialSuccess = $false
}

Register-Check -Name "Credential Re-Authentication" -Passed $credentialSuccess -Details "$($credentialChecks.Count) services checked"

# ===== STEP 3: VERIFY MCP SERVER PATHS =====
Write-Host "`nSTEP 3: MCP Server Path Verification" -ForegroundColor Yellow
Write-Log "Step 3: Verifying MCP server paths"

$mcpSuccess = $true
$mcpServers = @()

$mcpConfigPath = "$env:USERPROFILE\AppData\Local\Claude\mcp.json"
if (Test-Path $mcpConfigPath) {
    try {
        $mcpConfig = Get-Content $mcpConfigPath -Raw | ConvertFrom-Json
        $mcpServers = $mcpConfig.servers
        
        if ($mcpServers -and $mcpServers.Count -gt 0) {
            Write-Log "Found $($mcpServers.Count) MCP servers in config"
            
            foreach ($server in $mcpServers.PSObject.Properties) {
                $serverName = $server.Name
                $serverData = $server.Value
                
                if ($serverData.command) {
                    $cmdPath = $serverData.command.Split()[0]
                    $exists = Test-Path $cmdPath
                    
                    if ($exists) {
                        Write-Log "✓ MCP server '$serverName' path exists: $cmdPath" "SUCCESS"
                    } else {
                        Write-Log "✗ MCP server '$serverName' path NOT FOUND: $cmdPath" "ERROR"
                        $mcpSuccess = $false
                    }
                }
            }
        } else {
            Write-Log "ℹ No MCP servers configured" "INFO"
        }
    } catch {
        Write-Log "✗ Error reading MCP config: $_" "ERROR"
        $mcpSuccess = $false
    }
} else {
    Write-Log "ℹ MCP config file not found (may be first-time setup)" "INFO"
}

Register-Check -Name "MCP Server Path Verification" -Passed $mcpSuccess -Details "$($mcpServers.Count) servers verified"

# ===== STEP 4: REGISTER OPENCLAW GATEWAY SERVICE =====
Write-Host "`nSTEP 4: OpenClaw Gateway Windows Service Registration" -ForegroundColor Yellow
Write-Log "Step 4: Registering OpenClaw gateway Windows service"

$serviceSuccess = $true
$isAdmin = Test-IsAdmin

if (-not $isAdmin) {
    Write-Log "⚠ Script not running as admin. Service registration skipped (requires admin)" "WARN"
    $script:warnings++
} else {
    $serviceName = "OpenClawGateway"
    $serviceExists = Get-Service -Name $serviceName -ErrorAction SilentlyContinue
    
    if ($serviceExists) {
        Write-Log "✓ OpenClaw Gateway service already registered" "SUCCESS"
    } else {
        try {
            Write-Log "Attempting to register OpenClaw Gateway service..."
            $openclaExePath = "C:\Users\$env:USERNAME\.openclaw\openclaw.exe"
            
            if (Test-Path $openclaExePath) {
                # Create Windows service using nssm or sc
                Write-Log "Creating service: sc create $serviceName binPath= '$openclaExePath gateway start'"
                & sc create $serviceName binPath= "$openclaExePath gateway start" start= auto 2>&1 | Out-Null
                
                if ($LASTEXITCODE -eq 0 -or $LASTEXITCODE -eq 1072) { # 1072 = already exists
                    Write-Log "✓ OpenClaw Gateway service registered" "SUCCESS"
                    
                    # Try to start it
                    Start-Service -Name $serviceName -ErrorAction SilentlyContinue
                    Write-Log "Service startup attempted"
                } else {
                    Write-Log "✗ Service registration failed (exit code: $LASTEXITCODE)" "WARN"
                    $serviceSuccess = $false
                }
            } else {
                Write-Log "⚠ openclaw.exe not found at $openclaExePath" "WARN"
                $serviceSuccess = $false
            }
        } catch {
            Write-Log "⚠ Service registration error: $_" "WARN"
            $serviceSuccess = $false
        }
    }
}

Register-Check -Name "OpenClaw Gateway Service" -Passed $serviceSuccess -Details "Admin: $isAdmin"

# ===== STEP 5: CREATE SCHEDULED TASKS =====
Write-Host "`nSTEP 5: Create Scheduled Tasks" -ForegroundColor Yellow
Write-Log "Step 5: Creating scheduled tasks"

$taskSuccess = $true
$tasksCreated = @()

if (-not $isAdmin) {
    Write-Log "⚠ Scheduled tasks require admin. Skipped." "WARN"
    $script:warnings++
} else {
    # Task 1: Daily backup at 2 AM
    try {
        $backupScriptPath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\backup\backup-claudecode.ps1"
        $backupTaskName = "ClaudeCodeDailyBackup"
        
        $existingTask = Get-ScheduledTask -TaskName $backupTaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Log "✓ Daily backup task already exists" "SUCCESS"
            $tasksCreated += $backupTaskName
        } else {
            if (Test-Path $backupScriptPath) {
                $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-ExecutionPolicy Bypass -File '$backupScriptPath'"
                $taskTrigger = New-ScheduledTaskTrigger -Daily -At "2:00 AM"
                $taskSettings = New-ScheduledTaskSettingsSet -RunOnlyIfNetworkAvailable
                
                Register-ScheduledTask -TaskName $backupTaskName `
                    -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings `
                    -RunLevel Highest -ErrorAction SilentlyContinue | Out-Null
                
                Write-Log "✓ Daily backup task created (2 AM)" "SUCCESS"
                $tasksCreated += $backupTaskName
            } else {
                Write-Log "⚠ Backup script not found: $backupScriptPath" "WARN"
            }
        }
    } catch {
        Write-Log "⚠ Daily backup task error: $_" "WARN"
        $script:warnings++
    }
    
    # Task 2: OpenClaw startup at login
    try {
        $openclaExePath = "C:\Users\$env:USERNAME\.openclaw\openclaw.exe"
        $startupTaskName = "OpenClawStartup"
        
        $existingTask = Get-ScheduledTask -TaskName $startupTaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Log "✓ OpenClaw startup task already exists" "SUCCESS"
            $tasksCreated += $startupTaskName
        } else {
            if (Test-Path $openclaExePath) {
                $taskAction = New-ScheduledTaskAction -Execute $openclaExePath -Argument "gateway start"
                $taskTrigger = New-ScheduledTaskTrigger -AtLogOn
                $taskSettings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries `
                    -DontStopIfGoingOnBatteries
                
                Register-ScheduledTask -TaskName $startupTaskName `
                    -Action $taskAction -Trigger $taskTrigger -Settings $taskSettings `
                    -RunLevel Highest -ErrorAction SilentlyContinue | Out-Null
                
                Write-Log "✓ OpenClaw startup task created (at login)" "SUCCESS"
                $tasksCreated += $startupTaskName
            } else {
                Write-Log "⚠ openclaw.exe not found: $openclaExePath" "WARN"
            }
        }
    } catch {
        Write-Log "⚠ OpenClaw startup task error: $_" "WARN"
        $script:warnings++
    }
    
    # Task 3: Auto-sync dotfiles every 6 hours
    try {
        $syncScriptPath = "C:\Users\$env:USERNAME\.openclaw\scripts\sync-all-bots.ps1"
        $syncTaskName = "DotfilesAutoSync"
        
        $existingTask = Get-ScheduledTask -TaskName $syncTaskName -ErrorAction SilentlyContinue
        if ($existingTask) {
            Write-Log "✓ Dotfiles auto-sync task already exists" "SUCCESS"
            $tasksCreated += $syncTaskName
        } else {
            if (Test-Path $syncScriptPath) {
                $taskAction = New-ScheduledTaskAction -Execute "powershell.exe" `
                    -Argument "-ExecutionPolicy Bypass -File '$syncScriptPath'"
                $taskTrigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Hours 6) `
                    -Once -At (Get-Date)
                
                Register-ScheduledTask -TaskName $syncTaskName `
                    -Action $taskAction -Trigger $taskTrigger `
                    -RunLevel Highest -ErrorAction SilentlyContinue | Out-Null
                
                Write-Log "✓ Dotfiles auto-sync task created (every 6 hours)" "SUCCESS"
                $tasksCreated += $syncTaskName
            } else {
                Write-Log "⚠ Sync script not found: $syncScriptPath" "WARN"
            }
        }
    } catch {
        Write-Log "⚠ Dotfiles sync task error: $_" "WARN"
        $script:warnings++
    }
}

Register-Check -Name "Scheduled Tasks" -Passed ($tasksCreated.Count -ge 1) -Details "$($tasksCreated.Count) tasks"

# ===== STEP 6: RECREATE DESKTOP SHORTCUTS =====
Write-Host "`nSTEP 6: Recreate Desktop Shortcuts" -ForegroundColor Yellow
Write-Log "Step 6: Recreating desktop shortcuts"

$shortcutSuccess = $true
$shortcutsCreated = @()

$desktopPath = [Environment]::GetFolderPath("Desktop")

try {
    # Claude Code shortcut
    $claudeExePath = "C:\Users\$env:USERNAME\.claude\bin\claude.exe"
    $claudeShortcut = Join-Path $desktopPath "Claude Code.lnk"
    
    if (Test-Path $claudeExePath) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($claudeShortcut)
        $shortcut.TargetPath = $claudeExePath
        $shortcut.WorkingDirectory = $env:USERPROFILE
        $shortcut.Description = "Claude Code CLI"
        $shortcut.Save()
        
        Write-Log "✓ Claude Code shortcut created on desktop" "SUCCESS"
        $shortcutsCreated += "Claude Code"
    }
} catch {
    Write-Log "⚠ Claude Code shortcut error: $_" "WARN"
    $shortcutSuccess = $false
}

try {
    # OpenClaw shortcut
    $openclaExePath = "C:\Users\$env:USERNAME\.openclaw\openclaw.exe"
    $openclaShortcut = Join-Path $desktopPath "OpenClaw.lnk"
    
    if (Test-Path $openclaExePath) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($openclaShortcut)
        $shortcut.TargetPath = $openclaExePath
        $shortcut.Arguments = "gateway start"
        $shortcut.WorkingDirectory = $env:USERPROFILE
        $shortcut.Description = "OpenClaw Gateway"
        $shortcut.Save()
        
        Write-Log "✓ OpenClaw shortcut created on desktop" "SUCCESS"
        $shortcutsCreated += "OpenClaw"
    }
} catch {
    Write-Log "⚠ OpenClaw shortcut error: $_" "WARN"
    $shortcutSuccess = $false
}

Register-Check -Name "Desktop Shortcuts" -Passed $shortcutsCreated.Count -ge 1 -Details "$($shortcutsCreated.Count) shortcuts"

# ===== STEP 7: RECREATE STARTUP SHORTCUTS =====
Write-Host "`nSTEP 7: Recreate Startup Shortcuts" -ForegroundColor Yellow
Write-Log "Step 7: Recreating startup shortcuts"

$startupSuccess = $true
$startupShortcuts = @()

$startupPath = Join-Path $env:APPDATA "Microsoft\Windows\Start Menu\Programs\Startup"

try {
    # Ensure startup directory exists
    if (-not (Test-Path $startupPath)) {
        New-Item -ItemType Directory -Path $startupPath -Force | Out-Null
        Write-Log "Created startup directory: $startupPath"
    }
    
    # OpenClaw startup shortcut
    $openclaExePath = "C:\Users\$env:USERNAME\.openclaw\openclaw.exe"
    $startupShortcut = Join-Path $startupPath "OpenClaw Gateway.lnk"
    
    if (Test-Path $openclaExePath) {
        $shell = New-Object -ComObject WScript.Shell
        $shortcut = $shell.CreateShortcut($startupShortcut)
        $shortcut.TargetPath = $openclaExePath
        $shortcut.Arguments = "gateway start"
        $shortcut.WindowStyle = 7  # Minimized
        $shortcut.WorkingDirectory = $env:USERPROFILE
        $shortcut.Description = "OpenClaw Gateway Auto-Start"
        $shortcut.Save()
        
        Write-Log "✓ OpenClaw startup shortcut created" "SUCCESS"
        $startupShortcuts += "OpenClaw Gateway"
    }
} catch {
    Write-Log "⚠ Startup shortcut error: $_" "WARN"
    $startupSuccess = $false
}

Register-Check -Name "Startup Shortcuts" -Passed $startupShortcuts.Count -ge 1 -Details "$($startupShortcuts.Count) shortcuts"

# ===== STEP 8: VALIDATE ENVIRONMENT VARIABLES =====
Write-Host "`nSTEP 8: Validate Environment Variables" -ForegroundColor Yellow
Write-Log "Step 8: Validating environment variables"

$envSuccess = $true
$envVars = @()

# Critical environment variables
$criticalVars = @(
    @{ Name = "ANTHROPIC_API_KEY"; Type = "User"; Required = $false },
    @{ Name = "PATH"; Type = "User"; Required = $true }
)

foreach ($var in $criticalVars) {
    $value = [Environment]::GetEnvironmentVariable($var.Name, [EnvironmentVariableTarget]::User)
    $sysValue = [Environment]::GetEnvironmentVariable($var.Name, [EnvironmentVariableTarget]::Machine)
    
    if ($value -or $sysValue) {
        Write-Log "✓ $($var.Name) is set" "SUCCESS"
        $envVars += @{ Name = $var.Name; Set = $true }
    } elseif ($var.Required) {
        Write-Log "✗ $($var.Name) is NOT set (required)" "ERROR"
        $envVars += @{ Name = $var.Name; Set = $false }
        $envSuccess = $false
    } else {
        Write-Log "ℹ $($var.Name) is not set (optional)" "INFO"
    }
}

# Check PATH includes important directories
$pathValue = [Environment]::GetEnvironmentVariable("PATH", [EnvironmentVariableTarget]::User)
$pathDirs = @(
    "C:\Users\$env:USERNAME\.claude\bin",
    "C:\Users\$env:USERNAME\AppData\Local\Programs\Python\Python312\Scripts",
    "C:\Users\$env:USERNAME\AppData\Roaming\npm"
)

foreach ($dir in $pathDirs) {
    if ($pathValue -match [regex]::Escape($dir)) {
        Write-Log "✓ $dir in PATH" "SUCCESS"
    } else {
        Write-Log "⚠ $dir NOT in PATH" "WARN"
        $script:warnings++
    }
}

Register-Check -Name "Environment Variables" -Passed $envSuccess -Details "$($envVars.Count) checked"

# ===== STEP 9: TEST CLAUDE CODE CLI =====
Write-Host "`nSTEP 9: Test Claude Code CLI" -ForegroundColor Yellow
Write-Log "Step 9: Testing Claude Code CLI"

$claudeSuccess = $false

try {
    $claudeVersion = & claude --version 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "✓ Claude CLI works: $claudeVersion" "SUCCESS"
        $claudeSuccess = $true
    } else {
        Write-Log "⚠ Claude CLI returned exit code $LASTEXITCODE" "WARN"
        $script:warnings++
    }
} catch {
    Write-Log "✗ Claude CLI error: $_" "ERROR"
}

Register-Check -Name "Claude Code CLI Test" -Passed $claudeSuccess -Details "Version: $(if ($claudeSuccess) { $claudeVersion } else { 'ERROR' })"

# ===== STEP 10: TEST OPENCLAW =====
Write-Host "`nSTEP 10: Test OpenClaw" -ForegroundColor Yellow
Write-Log "Step 10: Testing OpenClaw"

$openclaSuccess = $false

try {
    $openclaStatus = & openclaw status 2>$null
    if ($LASTEXITCODE -eq 0) {
        Write-Log "✓ OpenClaw CLI works" "SUCCESS"
        Write-Log "Status: $openclaStatus"
        $openclaSuccess = $true
    } else {
        Write-Log "⚠ OpenClaw status returned exit code $LASTEXITCODE" "WARN"
        Write-Log "Details: $openclaStatus"
        $script:warnings++
    }
} catch {
    Write-Log "✗ OpenClaw error: $_" "ERROR"
}

Register-Check -Name "OpenClaw Test" -Passed $openclaSuccess -Details "CLI accessible"

# ===== STEP 11: FINAL CHECKLIST =====
Write-Host "`n" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan
Write-Host "FINAL RESTORATION CHECKLIST" -ForegroundColor Cyan
Write-Host "=" * 70 -ForegroundColor Cyan

Write-Host ""
Write-Host "Post-Restore Setup Summary:" -ForegroundColor Cyan
Write-Host "━" * 70

Write-Host ("`n[RESULTS] {0:P0} Success Rate ({1} passed, {2} failed, {3} warnings)" -f 
    ($passed / ($passed + $failed)), $passed, $failed, $warnings) -ForegroundColor Cyan

foreach ($check in $checks) {
    $statusIcon = if ($check.Passed) { "✓" } else { "✗" }
    $color = if ($check.Passed) { "Green" } else { "Red" }
    $details = if ($check.Details) { " | $($check.Details)" } else { "" }
    
    Write-Host "$statusIcon $($check.Name)$details" -ForegroundColor $color
}

Write-Host "`n" + ("=" * 70)
Write-Host "RESTORATION ITEMS" -ForegroundColor Cyan
Write-Host ("=" * 70) -ForegroundColor Cyan
Write-Host ""

$checklist = @(
    @{ Item = "NPM packages re-registered"; Status = if ($npmSuccess) { "✓" } else { "⚠" } },
    @{ Item = "Credentials validated"; Status = if ($credentialSuccess) { "✓" } else { "⚠" } },
    @{ Item = "MCP server paths verified"; Status = if ($mcpSuccess) { "✓" } else { "⚠" } },
    @{ Item = "OpenClaw gateway service"; Status = if ($serviceSuccess) { "✓" } else { "⚠" } },
    @{ Item = "Scheduled tasks created"; Status = if ($tasksCreated.Count -gt 0) { "✓" } else { "⚠" } },
    @{ Item = "Desktop shortcuts recreated"; Status = if ($shortcutsCreated.Count -gt 0) { "✓" } else { "⚠" } },
    @{ Item = "Startup shortcuts recreated"; Status = if ($startupShortcuts.Count -gt 0) { "✓" } else { "⚠" } },
    @{ Item = "Environment variables set"; Status = if ($envSuccess) { "✓" } else { "⚠" } },
    @{ Item = "Claude Code CLI functional"; Status = if ($claudeSuccess) { "✓" } else { "⚠" } },
    @{ Item = "OpenClaw functional"; Status = if ($openclaSuccess) { "✓" } else { "⚠" } }
)

foreach ($item in $checklist) {
    $color = if ($item.Status -eq "✓") { "Green" } else { "Yellow" }
    Write-Host "$($item.Status) $($item.Item)" -ForegroundColor $color
}

Write-Host ""
Write-Host ("=" * 70)
Write-Host "NEXT STEPS:" -ForegroundColor Cyan
Write-Host ("=" * 70)

$nextSteps = @(
    "1. Review log file: $logFile"
    "2. If errors found, check: $errorLog"
    "3. For credentials not set: Follow the login prompts in applications"
    "4. Verify Windows services: Get-Service OpenClawGateway"
    "5. Test connections: claude --version && openclaw status"
    "6. Check Task Scheduler for registered tasks"
    "7. Restart system for all changes to take effect"
)

$nextSteps | ForEach-Object { Write-Host $_ -ForegroundColor Cyan }

Write-Host ""
Write-Host "=" * 70 -ForegroundColor Green
Write-Host "POST-RESTORE SETUP COMPLETE" -ForegroundColor Green
Write-Host "=" * 70 -ForegroundColor Green
Write-Host ""

Write-Log "Post-restore setup completed."
Write-Log "Passed: $passed | Failed: $failed | Warnings: $warnings"
Write-Host "Logs saved to: $logFile" -ForegroundColor Gray

# Optional: Keep errors in memory for debugging
if (Test-Path $errorLog) {
    Write-Host "Errors logged to: $errorLog" -ForegroundColor Gray
}

Write-Host ""
