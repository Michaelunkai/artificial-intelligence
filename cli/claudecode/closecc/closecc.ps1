<#
.SYNOPSIS
    closecc - Kill ALL Claude Code related processes and report real count
#>
$killed = 0
$killedNames = @()

# 1. Kill processes named claude/anthropic directly
$namedProcs = Get-Process -Name 'claude','AnthropicClaude','anthropic*' -ErrorAction SilentlyContinue
foreach ($p in $namedProcs) {
    Stop-Process -Id $p.Id -Force -ErrorAction SilentlyContinue
    $killedNames += "$($p.Name)[$($p.Id)]"
    $killed++
}

# 2. Kill node.exe processes whose CommandLine contains claude-code or anthropic
$nodeProcs = Get-WmiObject Win32_Process -Filter "Name = 'node.exe'" -ErrorAction SilentlyContinue
foreach ($n in $nodeProcs) {
    $cl = $n.CommandLine
    if ($cl -match 'claude-code|anthropic-ai|claude\\cli|@anthropic') {
        if ($killedNames -notcontains "node[$($n.ProcessId)]") {
            Stop-Process -Id $n.ProcessId -Force -ErrorAction SilentlyContinue
            $killedNames += "node[$($n.ProcessId)]"
            $killed++
        }
    }
}

# 3. Kill any process whose Path contains claude or anthropic
Get-Process -ErrorAction SilentlyContinue | Where-Object {
    try { $_.Path -and $_.Path -match 'claude|anthropic' } catch { $false }
} | ForEach-Object {
    $key = "$($_.Name)[$($_.Id)]"
    if ($killedNames -notcontains $key) {
        Stop-Process -Id $_.Id -Force -ErrorAction SilentlyContinue
        $killedNames += $key
        $killed++
    }
}

# 4. Kill bun/cmd processes running claude scripts
Get-WmiObject Win32_Process -Filter "Name = 'bun.exe' OR Name = 'cmd.exe'" -ErrorAction SilentlyContinue | Where-Object {
    $_.CommandLine -match 'claude'
} | ForEach-Object {
    $key = "$($_.Name)[$($_.ProcessId)]"
    if ($killedNames -notcontains $key) {
        Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue
        $killedNames += $key
        $killed++
    }
}

if ($killed -gt 0) {
    Write-Host "Killed $killed Claude process(es): $($killedNames -join ', ')" -ForegroundColor Green
} else {
    Write-Host "No Claude processes found" -ForegroundColor Yellow
}
