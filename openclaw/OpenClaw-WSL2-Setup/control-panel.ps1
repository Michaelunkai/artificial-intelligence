try { Invoke-RestMethod http://localhost:18789/health -TimeoutSec 3 | Out-Null; Write-Host "Gateway: ONLINE" -ForegroundColor Green } catch { Write-Host "Gateway: OFFLINE" -ForegroundColor Red }
$v = wsl -d Ubuntu bash -lc "openclaw --version 2>/dev/null"
Write-Host "OpenClaw WSL2: $v"
$sk = wsl -d Ubuntu bash -lc "ls ~/.openclaw/skills 2>/dev/null | wc -l"
Write-Host "Skills: $sk"
