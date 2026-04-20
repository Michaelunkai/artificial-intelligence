# AgentFlow Tray Integration Script
# Adds AgentFlow menu items to OpenClaw tray icon

Write-Host "🔧 AgentFlow - Tray Integration Script" -ForegroundColor Cyan
Write-Host ""

$ErrorActionPreference = "Stop"

# Find tray script
$trayScriptPath = "C:\Users\micha\.openclaw\ClawdbotTray.ps1"

if (-not (Test-Path $trayScriptPath)) {
    Write-Host "❌ Tray script not found at: $trayScriptPath" -ForegroundColor Red
    Write-Host "Cannot add tray integration." -ForegroundColor Red
    exit 1
}

Write-Host "📂 Found tray script: $trayScriptPath" -ForegroundColor Gray
Write-Host ""

# Backup original script
$backupPath = "${trayScriptPath}.backup_$(Get-Date -Format 'yyyyMMdd_HHmmss')"
Write-Host "📦 Creating backup: $backupPath" -ForegroundColor Yellow
Copy-Item -Path $trayScriptPath -Destination $backupPath -Force

# Read current script
$content = Get-Content $trayScriptPath -Raw

# Check if already integrated
if ($content -like "*AgentFlow Dashboard*") {
    Write-Host "ℹ️  AgentFlow menu items already present!" -ForegroundColor Yellow
    Write-Host "No changes needed." -ForegroundColor Green
    exit 0
}

# Find the context menu creation section
$marker = '$contextMenu.Items.Add'

if ($content -notlike "*$marker*") {
    Write-Host "❌ Could not find context menu section in tray script" -ForegroundColor Red
    Write-Host "Manual integration required." -ForegroundColor Yellow
    exit 1
}

# Prepare integration code
$integrationCode = @'

# === AgentFlow Integration ===
$menuSeparator1 = New-Object System.Windows.Forms.ToolStripSeparator

$menuAgentFlowDashboard = New-Object System.Windows.Forms.ToolStripMenuItem
$menuAgentFlowDashboard.Text = "🤖 AgentFlow Dashboard"
$menuAgentFlowDashboard.Add_Click({
    Start-Process "http://localhost:18789/agentflow"
})

$menuRestartAgentFlow = New-Object System.Windows.Forms.ToolStripMenuItem
$menuRestartAgentFlow.Text = "🔄 Restart AgentFlow"
$menuRestartAgentFlow.Add_Click({
    try {
        $adminToken = $env:OPENCLAW_ADMIN_TOKEN
        if (-not $adminToken) { $adminToken = "agentflow-dev-token" }
        
        Invoke-RestMethod -Uri "http://localhost:18789/agentflow/api/admin/reload" `
                          -Method POST `
                          -Headers @{"X-Admin-Token"=$adminToken} `
                          -TimeoutSec 5 | Out-Null
        
        $trayIcon.ShowBalloonTip(2000, "AgentFlow", "Extension restarted successfully ✅", [System.Windows.Forms.ToolTipIcon]::Info)
    } catch {
        $trayIcon.ShowBalloonTip(3000, "AgentFlow", "Failed to restart: $($_.Exception.Message)", [System.Windows.Forms.ToolTipIcon]::Error)
    }
})

# Insert AgentFlow items after Dashboard (if exists) or at top
$dashboardIndex = 0
for ($i = 0; $i -lt $contextMenu.Items.Count; $i++) {
    if ($contextMenu.Items[$i].Text -like "*Dashboard*") {
        $dashboardIndex = $i + 1
        break
    }
}

$contextMenu.Items.Insert($dashboardIndex, $menuSeparator1)
$contextMenu.Items.Insert($dashboardIndex + 1, $menuAgentFlowDashboard)
$contextMenu.Items.Insert($dashboardIndex + 2, $menuRestartAgentFlow)
$contextMenu.Items.Insert($dashboardIndex + 3, (New-Object System.Windows.Forms.ToolStripSeparator))
# === End AgentFlow Integration ===

'@

# Insert integration code before the first contextMenu.Items.Add line
$insertIndex = $content.IndexOf($marker)
if ($insertIndex -eq -1) {
    Write-Host "❌ Could not find insertion point" -ForegroundColor Red
    exit 1
}

$newContent = $content.Insert($insertIndex, $integrationCode)

# Write modified script
Set-Content -Path $trayScriptPath -Value $newContent -Force

Write-Host "✅ Tray integration added successfully!" -ForegroundColor Green
Write-Host ""
Write-Host "📝 Next steps:" -ForegroundColor Cyan
Write-Host "1. Restart the tray application:" -ForegroundColor White
Write-Host "   - Exit OpenClaw from system tray" -ForegroundColor Gray
Write-Host "   - Restart OpenClaw gateway" -ForegroundColor Gray
Write-Host ""
Write-Host "2. Right-click the tray icon to see new menu items:" -ForegroundColor White
Write-Host "   - 🤖 AgentFlow Dashboard" -ForegroundColor Gray
Write-Host "   - 🔄 Restart AgentFlow" -ForegroundColor Gray
Write-Host ""
Write-Host "✨ Integration complete!" -ForegroundColor Green
