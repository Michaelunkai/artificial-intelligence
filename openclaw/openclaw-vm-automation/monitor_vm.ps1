# Real-time monitoring dashboard for OpenClaw-VM
# Shows VM status, resource usage, and gateway health

param(
    [int]$RefreshSeconds = 5
)

function Show-Dashboard {
    Clear-Host
    Write-Host "╔════════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║         OPENCLAW-VM MONITORING DASHBOARD                      ║" -ForegroundColor Cyan
    Write-Host "╚════════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Write-Host "Timestamp: $timestamp`n" -ForegroundColor Gray
    
    # VM Status
    Write-Host "┌─ VM STATUS ────────────────────────────────────────────────────┐" -ForegroundColor White
    $vm = Get-VM -Name "OpenClaw-VM" -ErrorAction SilentlyContinue
    
    if ($vm) {
        $state_color = if ($vm.State -eq "Running") { "Green" } else { "Yellow" }
        Write-Host "  Name:          OpenClaw-VM" -ForegroundColor White
        Write-Host "  State:         $($vm.State)" -ForegroundColor $state_color
        Write-Host "  vCPU:          $($vm.ProcessorCount) cores"
        Write-Host "  Memory:        $([math]::Round($vm.MemoryMaximum/1GB, 2)) GB (dynamic)"
        Write-Host "  Generation:    Gen $($vm.Generation)"
        Write-Host "  Uptime:        $(if ($vm.State -eq 'Running') { 'Running' } else { 'Offline' })"
    } else {
        Write-Host "  [ERROR] OpenClaw-VM not found!" -ForegroundColor Red
    }
    Write-Host "└────────────────────────────────────────────────────────────────┘" -ForegroundColor White
    
    # Disk Space
    Write-Host "`n┌─ STORAGE ──────────────────────────────────────────────────────┐" -ForegroundColor White
    
    $vhdx = Get-Item "C:\VMs\OpenClaw-Replica.vhdx" -ErrorAction SilentlyContinue
    if ($vhdx) {
        $size_gb = [math]::Round($vhdx.Length / 1GB, 2)
        Write-Host "  VHDX Path:     C:\VMs\OpenClaw-Replica.vhdx"
        Write-Host "  Current Size:  $size_gb GB"
        Write-Host "  Allocated:     100 GB (dynamic)"
        Write-Host "  Status:        Created and ready"
    }
    
    if (Test-Path "C:\Temp\openclaw-replica") {
        $replica_count = (Get-ChildItem "C:\Temp\openclaw-replica" -Recurse -ErrorAction SilentlyContinue | Measure-Object).Count
        Write-Host "`n  Replica Files: $replica_count items"
        Write-Host "  Replica Path:  C:\Temp\openclaw-replica"
        Write-Host "  Status:        Complete"
    }
    
    Write-Host "└────────────────────────────────────────────────────────────────┘" -ForegroundColor White
    
    # Network
    Write-Host "`n┌─ NETWORK ──────────────────────────────────────────────────────┐" -ForegroundColor White
    
    if ($vm) {
        $adapters = Get-VMNetworkAdapter -VMName "OpenClaw-VM" -ErrorAction SilentlyContinue
        if ($adapters) {
            Write-Host "  Adapters:      $($adapters.Count)"
            foreach ($adapter in $adapters) {
                Write-Host "    - $($adapter.Name)"
                Write-Host "      Switch: $($adapter.SwitchName)"
            }
        } else {
            Write-Host "  Adapters:      None configured"
        }
    }
    
    Write-Host "└────────────────────────────────────────────────────────────────┘" -ForegroundColor White
    
    # Gateway Health
    Write-Host "`n┌─ GATEWAY HEALTH ───────────────────────────────────────────────┐" -ForegroundColor White
    
    $gateway_port = 18792
    $sock = New-Object System.Net.Sockets.TcpClient
    try {
        $sock.Connect("127.0.0.1", $gateway_port)
        if ($sock.Connected) {
            Write-Host "  Port $gateway_port:     OPEN (gateway reachable)" -ForegroundColor Green
            Write-Host "  Access URL:    http://127.0.0.1:$gateway_port" -ForegroundColor Green
        }
        $sock.Close()
    } catch {
        Write-Host "  Port $gateway_port:     CLOSED (gateway not running)" -ForegroundColor Yellow
    }
    
    Write-Host "└────────────────────────────────────────────────────────────────┘" -ForegroundColor White
    
    # Quick Commands
    Write-Host "`n┌─ QUICK COMMANDS ───────────────────────────────────────────────┐" -ForegroundColor White
    Write-Host "  python F:\Downloads\a.py          Create/recreate VM" -ForegroundColor Cyan
    Write-Host "  python F:\Downloads\b.py          Start VM and gateway" -ForegroundColor Cyan
    Write-Host "  Get-VM -Name 'OpenClaw-VM'        Check VM status" -ForegroundColor Cyan
    Write-Host "  Stop-VM -Name 'OpenClaw-VM'       Stop VM" -ForegroundColor Cyan
    Write-Host "  Start-VM -Name 'OpenClaw-VM'      Start VM" -ForegroundColor Cyan
    Write-Host "└────────────────────────────────────────────────────────────────┘" -ForegroundColor White
    
    Write-Host "`nPress Ctrl+C to exit. Refreshing every $RefreshSeconds seconds..." -ForegroundColor Gray
}

# Main loop
while ($true) {
    Show-Dashboard
    Start-Sleep -Seconds $RefreshSeconds
}
