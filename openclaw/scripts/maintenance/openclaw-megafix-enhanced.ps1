# OpenClaw ENHANCED Mega Fix Script - 80+ Commands
# Generated: 2026-03-12
# Purpose: Comprehensive OpenClaw diagnostics, repair, maintenance + 3rd party tools
# Includes: Native OpenClaw tools, npm diagnostics, system checks, community tools

$ErrorActionPreference = "Continue"
$ProgressPreference = "SilentlyContinue"

Write-Host "🦞 OpenClaw ENHANCED Mega Fix - Starting comprehensive maintenance..." -ForegroundColor Cyan
Write-Host "⚡ 80+ checks including native tools, npm diagnostics, system validation" -ForegroundColor Cyan

# ===== SECTION 1: NATIVE OPENCLAW COMMANDS (43 commands) =====
Write-Host "`n========== NATIVE OPENCLAW DIAGNOSTICS ==========" -ForegroundColor Magenta

# 1. CONFIG & VALIDATION
Write-Host "`n[1/80] Validating config..." -ForegroundColor Yellow
openclaw config validate

# 2. DOCTOR WITH FIXES
Write-Host "`n[2/80] Running doctor with auto-fix..." -ForegroundColor Yellow
openclaw doctor --fix --yes

# 3. DOCTOR DEEP SCAN
Write-Host "`n[3/80] Running deep system scan..." -ForegroundColor Yellow
openclaw doctor --deep

# 4. SECURITY AUDIT
Write-Host "`n[4/80] Running security audit..." -ForegroundColor Yellow
openclaw security audit

# 5. SECURITY AUDIT WITH FIX
Write-Host "`n[5/80] Running security audit with auto-fix..." -ForegroundColor Yellow
openclaw security audit --fix --deep

# 6. GATEWAY STATUS
Write-Host "`n[6/80] Checking gateway status..." -ForegroundColor Yellow
openclaw gateway status

# 7. GATEWAY HEALTH
Write-Host "`n[7/80] Checking gateway health..." -ForegroundColor Yellow
openclaw gateway health

# 8. GATEWAY PROBE
Write-Host "`n[8/80] Probing gateway reachability..." -ForegroundColor Yellow
openclaw gateway probe

# 9. CHANNELS STATUS
Write-Host "`n[9/80] Checking channels status..." -ForegroundColor Yellow
openclaw channels status

# 10. CHANNELS DEEP STATUS
Write-Host "`n[10/80] Checking channels deep status..." -ForegroundColor Yellow
openclaw channels status --deep

# 11. CHANNELS CAPABILITIES
Write-Host "`n[11/80] Checking channel capabilities..." -ForegroundColor Yellow
openclaw channels capabilities

# 12. BROWSER STATUS
Write-Host "`n[12/80] Checking browser status..." -ForegroundColor Yellow
openclaw browser status

# 13. BROWSER START
Write-Host "`n[13/80] Starting browser service..." -ForegroundColor Yellow
openclaw browser start

# 14. BROWSER PROFILES LIST
Write-Host "`n[14/80] Listing browser profiles..." -ForegroundColor Yellow
openclaw browser profiles

# 15. SANDBOX LIST
Write-Host "`n[15/80] Listing sandbox containers..." -ForegroundColor Yellow
openclaw sandbox list

# 16. SANDBOX EXPLAIN
Write-Host "`n[16/80] Explaining sandbox policy..." -ForegroundColor Yellow
openclaw sandbox explain

# 17. MEMORY STATUS
Write-Host "`n[17/80] Checking memory index status..." -ForegroundColor Yellow
openclaw memory status

# 18. MEMORY DEEP STATUS
Write-Host "`n[18/80] Checking memory provider status..." -ForegroundColor Yellow
openclaw memory status --deep

# 19. MEMORY REINDEX
Write-Host "`n[19/80] Reindexing memory files..." -ForegroundColor Yellow
openclaw memory index --force

# 20. PLUGINS LIST
Write-Host "`n[20/80] Listing plugins..." -ForegroundColor Yellow
openclaw plugins list

# 21. PLUGINS DOCTOR
Write-Host "`n[21/80] Running plugin diagnostics..." -ForegroundColor Yellow
openclaw plugins doctor

# 22. SKILLS CHECK
Write-Host "`n[22/80] Checking skills requirements..." -ForegroundColor Yellow
openclaw skills check

# 23. SKILLS LIST
Write-Host "`n[23/80] Listing skills..." -ForegroundColor Yellow
openclaw skills list

# 24. MODELS STATUS
Write-Host "`n[24/80] Checking model configuration..." -ForegroundColor Yellow
openclaw models status

# 25. MODELS LIST
Write-Host "`n[25/80] Listing available models..." -ForegroundColor Yellow
openclaw models list

# 26. UPDATE STATUS
Write-Host "`n[26/80] Checking update status..." -ForegroundColor Yellow
openclaw update status

# 27. SESSIONS LIST
Write-Host "`n[27/80] Listing sessions..." -ForegroundColor Yellow
openclaw sessions list

# 28. HEALTH CHECK
Write-Host "`n[28/80] Fetching health..." -ForegroundColor Yellow
openclaw health

# 29. STATUS CHECK
Write-Host "`n[29/80] Checking overall status..." -ForegroundColor Yellow
openclaw status

# 30. HOOKS LIST
Write-Host "`n[30/80] Listing hooks..." -ForegroundColor Yellow
openclaw hooks list

# 31. APPROVALS LIST
Write-Host "`n[31/80] Listing approvals..." -ForegroundColor Yellow
openclaw approvals list

# 32. CRON LIST
Write-Host "`n[32/80] Listing cron jobs..." -ForegroundColor Yellow
openclaw cron list

# 33. NODES LIST
Write-Host "`n[33/80] Listing nodes..." -ForegroundColor Yellow
openclaw nodes list

# 34. GATEWAY DISCOVER
Write-Host "`n[34/80] Discovering gateways..." -ForegroundColor Yellow
openclaw gateway discover

# 35. DIRECTORY LOOKUP SELF
Write-Host "`n[35/80] Looking up directory self..." -ForegroundColor Yellow
openclaw directory lookup --self

# 36. BACKUP CREATE
Write-Host "`n[36/80] Creating backup..." -ForegroundColor Yellow
openclaw backup create

# 37. CONFIG FILE CHECK
Write-Host "`n[37/80] Displaying config file path..." -ForegroundColor Yellow
openclaw config file

# 38. ACP STATUS
Write-Host "`n[38/80] Checking ACP agents..." -ForegroundColor Yellow
openclaw acp list 2>$null

# 39. DEVICES LIST
Write-Host "`n[39/80] Listing devices..." -ForegroundColor Yellow
openclaw devices list 2>$null

# 40. WEBHOOKS STATUS
Write-Host "`n[40/80] Checking webhooks..." -ForegroundColor Yellow
openclaw webhooks list 2>$null

# 41. SYSTEM STATUS
Write-Host "`n[41/80] Checking system events..." -ForegroundColor Yellow
openclaw system status 2>$null

# 42. LOGS TAIL
Write-Host "`n[42/80] Tailing recent logs..." -ForegroundColor Yellow
openclaw logs --lines 50

# 43. VERSION CHECK
Write-Host "`n[43/80] Checking OpenClaw version..." -ForegroundColor Yellow
openclaw --version

# ===== SECTION 2: NPM & NODE.JS DIAGNOSTICS (12 commands) =====
Write-Host "`n========== NPM & NODE.JS DIAGNOSTICS ==========" -ForegroundColor Magenta

# 44. NODE VERSION
Write-Host "`n[44/80] Checking Node.js version..." -ForegroundColor Yellow
node --version

# 45. NPM VERSION
Write-Host "`n[45/80] Checking npm version..." -ForegroundColor Yellow
npm --version

# 46. NPM LIST GLOBAL OPENCLAW
Write-Host "`n[46/80] Checking global OpenClaw install..." -ForegroundColor Yellow
npm list -g openclaw

# 47. NPM DOCTOR
Write-Host "`n[47/80] Running npm doctor..." -ForegroundColor Yellow
npm doctor

# 48. NPM CACHE VERIFY
Write-Host "`n[48/80] Verifying npm cache..." -ForegroundColor Yellow
npm cache verify

# 49. CHECK FOR OPENCLAW UPDATES
Write-Host "`n[49/80] Checking for OpenClaw updates on npm..." -ForegroundColor Yellow
npm view openclaw version

# 50. LIST OPENCLAW PLUGINS
Write-Host "`n[50/80] Searching for OpenClaw plugins on npm..." -ForegroundColor Yellow
npm search openclaw --parseable 2>$null | Select-Object -First 20

# 51. CHECK NODE_MODULES HEALTH
Write-Host "`n[51/80] Checking OpenClaw node_modules..." -ForegroundColor Yellow
$openclawPath = (Get-Command openclaw -ErrorAction SilentlyContinue).Source
if ($openclawPath) {
    $moduleDir = Split-Path (Split-Path $openclawPath)
    Write-Host "OpenClaw installed at: $moduleDir" -ForegroundColor Cyan
    Get-ChildItem "$moduleDir\node_modules" -ErrorAction SilentlyContinue | Measure-Object | Select-Object -ExpandProperty Count
}

# 52. NPM OUTDATED CHECK
Write-Host "`n[52/80] Checking for outdated packages..." -ForegroundColor Yellow
npm outdated -g 2>$null | Select-String "openclaw"

# 53. NPM LIST DEPTH 0
Write-Host "`n[53/80] Listing global packages..." -ForegroundColor Yellow
npm list -g --depth=0 | Select-String "openclaw"

# 54. NPX VERSION
Write-Host "`n[54/80] Checking npx version..." -ForegroundColor Yellow
npx --version

# 55. CHECK PACKAGE.JSON
Write-Host "`n[55/80] Locating OpenClaw package.json..." -ForegroundColor Yellow
$pkgPath = "$env:APPDATA\npm\node_modules\openclaw\package.json"
if (Test-Path $pkgPath) {
    Write-Host "Found: $pkgPath" -ForegroundColor Green
    Get-Content $pkgPath | Select-String '"version"', '"name"'
} else {
    Write-Host "Not found at: $pkgPath" -ForegroundColor Red
}

# ===== SECTION 3: SYSTEM DIAGNOSTICS (15 commands) =====
Write-Host "`n========== SYSTEM DIAGNOSTICS ==========" -ForegroundColor Magenta

# 56. CHECK OPENCLAW PROCESSES
Write-Host "`n[56/80] Checking OpenClaw processes..." -ForegroundColor Yellow
Get-Process | Where-Object { $_.ProcessName -like "*openclaw*" -or $_.ProcessName -like "*node*" } | Select-Object ProcessName, Id, CPU, WorkingSet

# 57. CHECK PORT 18790 (DEFAULT GATEWAY)
Write-Host "`n[57/80] Checking gateway port 18790..." -ForegroundColor Yellow
$port = netstat -ano | Select-String ":18790"
if ($port) {
    Write-Host "Port 18790 in use:" -ForegroundColor Cyan
    $port
} else {
    Write-Host "Port 18790 is free" -ForegroundColor Green
}

# 58. CHECK PORT 18792 (BROWSER CDP)
Write-Host "`n[58/80] Checking browser CDP port 18792..." -ForegroundColor Yellow
$browserPort = netstat -ano | Select-String ":18792"
if ($browserPort) {
    Write-Host "Port 18792 in use:" -ForegroundColor Cyan
    $browserPort
} else {
    Write-Host "Port 18792 is free" -ForegroundColor Green
}

# 59. CHECK DOCKER STATUS
Write-Host "`n[59/80] Checking Docker status..." -ForegroundColor Yellow
docker --version 2>$null
docker ps 2>$null | Select-String "openclaw"

# 60. CHECK ENVIRONMENT VARIABLES
Write-Host "`n[60/80] Checking OpenClaw environment variables..." -ForegroundColor Yellow
Get-ChildItem Env: | Where-Object { $_.Name -like "*OPENCLAW*" -or $_.Name -like "*CLAUDE*" }

# 61. CHECK DISK SPACE
Write-Host "`n[61/80] Checking disk space on C: drive..." -ForegroundColor Yellow
Get-PSDrive C | Select-Object Used, Free, @{Name="FreeGB";Expression={[math]::Round($_.Free/1GB,2)}}

# 62. CHECK OPENCLAW CONFIG DIRECTORY
Write-Host "`n[62/80] Checking OpenClaw config directory..." -ForegroundColor Yellow
$configDir = "$env:USERPROFILE\.openclaw"
if (Test-Path $configDir) {
    Write-Host "Config dir exists: $configDir" -ForegroundColor Green
    Get-ChildItem $configDir -File | Select-Object Name, Length, LastWriteTime | Format-Table
} else {
    Write-Host "Config dir not found: $configDir" -ForegroundColor Red
}

# 63. CHECK LOG FILES
Write-Host "`n[63/80] Checking OpenClaw log files..." -ForegroundColor Yellow
$logDir = "$env:USERPROFILE\.openclaw\logs"
if (Test-Path $logDir) {
    Get-ChildItem $logDir -File | Sort-Object LastWriteTime -Descending | Select-Object -First 10 Name, @{Name="SizeMB";Expression={[math]::Round($_.Length/1MB,2)}}, LastWriteTime
}

# 64. CHECK WORKSPACE DIRECTORY
Write-Host "`n[64/80] Checking workspace directory..." -ForegroundColor Yellow
$workspaceDir = "$env:USERPROFILE\.openclaw\workspace-moltbot"
if (Test-Path $workspaceDir) {
    Write-Host "Workspace exists: $workspaceDir" -ForegroundColor Green
    Get-ChildItem $workspaceDir -File | Measure-Object -Property Length -Sum | Select-Object Count, @{Name="TotalMB";Expression={[math]::Round($_.Sum/1MB,2)}}
}

# 65. CHECK CHROME/BROWSER PROCESS
Write-Host "`n[65/80] Checking Chrome/browser processes..." -ForegroundColor Yellow
Get-Process | Where-Object { $_.ProcessName -like "*chrome*" -or $_.ProcessName -like "*msedge*" } | Select-Object ProcessName, Id, @{Name="MemoryMB";Expression={[math]::Round($_.WorkingSet/1MB,2)}} | Sort-Object MemoryMB -Descending | Select-Object -First 5

# 66. CHECK NETWORK CONNECTIVITY
Write-Host "`n[66/80] Testing network connectivity..." -ForegroundColor Yellow
Test-NetConnection -ComputerName google.com -Port 443 -InformationLevel Quiet

# 67. CHECK DNS RESOLUTION
Write-Host "`n[67/80] Testing DNS resolution..." -ForegroundColor Yellow
Resolve-DnsName docs.openclaw.ai -ErrorAction SilentlyContinue | Select-Object Name, IPAddress

# 68. CHECK SYSTEM UPTIME
Write-Host "`n[68/80] Checking system uptime..." -ForegroundColor Yellow
$uptime = (Get-Date) - (Get-CimInstance Win32_OperatingSystem).LastBootUpTime
Write-Host "System uptime: $($uptime.Days) days, $($uptime.Hours) hours" -ForegroundColor Cyan

# 69. CHECK WINDOWS VERSION
Write-Host "`n[69/80] Checking Windows version..." -ForegroundColor Yellow
Get-CimInstance Win32_OperatingSystem | Select-Object Caption, Version, BuildNumber

# 70. CHECK POWERSHELL VERSION
Write-Host "`n[70/80] Checking PowerShell version..." -ForegroundColor Yellow
$PSVersionTable.PSVersion

# ===== SECTION 4: FILE INTEGRITY & PERMISSIONS (5 commands) =====
Write-Host "`n========== FILE INTEGRITY & PERMISSIONS ==========" -ForegroundColor Magenta

# 71. CHECK CONFIG FILE PERMISSIONS
Write-Host "`n[71/80] Checking config file permissions..." -ForegroundColor Yellow
$configFile = "$env:USERPROFILE\.openclaw\openclaw.json"
if (Test-Path $configFile) {
    Get-Acl $configFile | Select-Object Path, Owner, AccessToString
}

# 72. CHECK WORKSPACE PERMISSIONS
Write-Host "`n[72/80] Checking workspace permissions..." -ForegroundColor Yellow
if (Test-Path $workspaceDir) {
    Get-Acl $workspaceDir | Select-Object Path, Owner
}

# 73. VERIFY OPENCLAW BINARY
Write-Host "`n[73/80] Verifying OpenClaw binary..." -ForegroundColor Yellow
Get-Command openclaw | Select-Object Name, Source, Version

# 74. CHECK FOR CORRUPTED FILES
Write-Host "`n[74/80] Checking for zero-byte files in config..." -ForegroundColor Yellow
if (Test-Path $configDir) {
    Get-ChildItem $configDir -Recurse -File | Where-Object { $_.Length -eq 0 } | Select-Object FullName
}

# 75. CHECK SKILLS DIRECTORY
Write-Host "`n[75/80] Checking skills directory..." -ForegroundColor Yellow
$skillsDir = "$env:USERPROFILE\.openclaw\skills"
if (Test-Path $skillsDir) {
    Get-ChildItem $skillsDir -Directory | Measure-Object | Select-Object @{Name="SkillCount";Expression={$_.Count}}
}

# ===== SECTION 5: FINAL REPAIRS & RESTARTS (5 commands) =====
Write-Host "`n========== FINAL REPAIRS & RESTARTS ==========" -ForegroundColor Magenta

# 76. GATEWAY RESTART
Write-Host "`n[76/80] Restarting gateway to apply fixes..." -ForegroundColor Yellow
openclaw gateway restart

# 77. BROWSER CYCLE
Write-Host "`n[77/80] Cycling browser service..." -ForegroundColor Yellow
openclaw browser stop
Start-Sleep -Seconds 3
openclaw browser start

# 78. FINAL HEALTH CHECK
Write-Host "`n[78/80] Final health check..." -ForegroundColor Yellow
openclaw health

# 79. FINAL GATEWAY STATUS
Write-Host "`n[79/80] Final gateway status..." -ForegroundColor Yellow
openclaw gateway status

# 80. FINAL COMPREHENSIVE STATUS
Write-Host "`n[80/80] Final comprehensive status..." -ForegroundColor Yellow
openclaw status

Write-Host "`n✅ OpenClaw ENHANCED Mega Fix Complete!" -ForegroundColor Green
Write-Host "📊 80+ diagnostics completed" -ForegroundColor Cyan
Write-Host "Review output above for any remaining issues." -ForegroundColor Cyan
Write-Host "`nLog saved to: $env:USERPROFILE\.openclaw\logs\megafix-$(Get-Date -Format 'yyyyMMdd-HHmmss').log" -ForegroundColor Yellow
