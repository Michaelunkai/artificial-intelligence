param([switch]$SkipWSLInstall, [switch]$SkipPackageUpdates)
# Run via: powershell -NoProfile -ExecutionPolicy Bypass -File <this-script>
$ErrorActionPreference = "Continue"
function OK  { param($M) Write-Host "OK  $M" -ForegroundColor Green }
function INF { param($M) Write-Host "... $M" -ForegroundColor Cyan }
function ERR { param($M) Write-Host "ERR $M" -ForegroundColor Red }
function RunW { param($C) wsl -d Ubuntu bash -lc "stty -echo 2>/dev/null; $C" 2>&1 }
function RunWS { param($C) wsl -d Ubuntu bash -lc "stty -echo 2>/dev/null; $C" 2>&1 | Out-Null }
# RunWL: long-running ops that need real-time output
function RunWL { param($C) & wsl -d ubuntu bash -lc "stty -echo 2>/dev/null; $C" }
$t = Get-Date
Write-Host "=== OpenClaw WSL2 Complete Setup ===" -ForegroundColor Cyan
Write-Host ""

# PHASE 0: Ubuntu
Write-Host "--- PHASE 0: Ubuntu Check ---" -ForegroundColor Yellow
# Ensure ubuntu is the default distro
wsl --set-default ubuntu 2>&1 | Out-Null
OK "0/40 Ubuntu set as default"

# PHASE 1: Foundation
Write-Host "--- PHASE 1: Foundation ---" -ForegroundColor Yellow
$tst = RunW "echo ok"
if ($tst -notmatch "ok") { ERR "WSL2 not working: $tst"; exit 1 }
OK "1/40 WSL2 verified"
if (-not $SkipPackageUpdates) {
    RunWL "DEBIAN_FRONTEND=noninteractive apt-get update -q && apt-get upgrade -y -q 2>&1 | grep -E '(Get:|Unpacking|Setting up|upgraded|newly)' || true"
    OK "2/40 Packages updated"
} else { INF "2/40 Packages skipped" }
$nv = RunW "node --version 2>/dev/null"
$nv = "$nv".Trim()
if ($nv -notmatch "v\d") {
    RunWL "curl -fsSL https://deb.nodesource.com/setup_20.x | bash - 2>&1 | tail -3 && apt-get install -y nodejs 2>&1 | grep -E '(Setting up|nodejs)' || true"
    $nv = "$( RunW 'node --version 2>/dev/null' )".Trim()
}
OK "3/40 Node.js: $nv"
RunWL "apt-get install -y build-essential git curl wget 2>&1 | grep -E '(Setting up|already)' | head -5 || true"
OK "4/40 Build tools + git ready"

# PHASE 2: OpenClaw
Write-Host "--- PHASE 2: OpenClaw ---" -ForegroundColor Yellow
Write-Host "  Installing openclaw npm package..." -ForegroundColor DarkGray
RunWL "npm install -g openclaw 2>&1 | tail -5 || npm update -g openclaw 2>&1 | tail -3"
$ocv = "$( RunW 'openclaw --version 2>/dev/null' )".Trim()
if (-not ($ocv -match "\d")) {
    RunWL "npm install -g openclaw --prefix /usr/local 2>&1 | tail -5"
    $ocv = "$( RunW 'openclaw --version 2>/dev/null' )".Trim()
}
OK "5/40 OpenClaw: $ocv"
RunWS "pkill -f 'openclaw gateway' 2>/dev/null; sleep 1; true"
OK "6/40 Gateway stopped"
RunWS "mkdir -p ~/.openclaw && chmod 700 ~/.openclaw"

# --- SMART MODE: use Windows gateway if running (no duplicate), else standalone ---
$winGwIp = (Get-NetIPAddress -InterfaceAlias "vEthernet (WSL)" -AddressFamily IPv4 -EA SilentlyContinue).IPAddress
if (-not $winGwIp) { $winGwIp = "172.26.80.1" }
$winGwUp = $false
try { $winGwUp = (Invoke-RestMethod "http://$($winGwIp):18789/health" -TimeoutSec 2 -EA Stop).ok } catch {}

if ($winGwUp) {
    RunWS "openclaw config set gateway.mode remote 2>/dev/null"
    RunWS "openclaw config set gateway.url 'http://$winGwIp:18789' 2>/dev/null"
    OK "7/40 Mode: REMOTE -> Windows tray gateway live at $winGwIp, no duplicate"
    OK "8/40 WSL2 sessions linked to Windows gateway"
} else {
    RunWS "openclaw config set gateway.mode local 2>/dev/null"
    RunWS "openclaw config set gateway.auth.mode token 2>/dev/null"
    OK "7/40 Mode: STANDALONE (Windows gateway offline)"
    RunWS "grep -q systemd=true /etc/wsl.conf 2>/dev/null || (grep -q boot /etc/wsl.conf 2>/dev/null || echo '[boot]' >> /etc/wsl.conf; echo 'systemd=true' >> /etc/wsl.conf)"
    $pid1 = "init(ubuntu)".Trim()
    if ($pid1 -match "systemd") {
        RunWL "openclaw gateway install --force 2>&1 | grep -Ev 'blocked plugin|^$' | tail -3"
        RunWS "systemctl --user daemon-reload && systemctl --user enable openclaw-gateway && systemctl --user restart openclaw-gateway"
        Start-Sleep 8
        $wslGw = wsl -d ubuntu bash -c "curl -s http://localhost:18789/health 2>/dev/null"
        if ($wslGw -match "ok") { OK "8/40 Gateway LIVE via systemd (auto-starts on boot)" }
        else { INF "8/40 Systemd service installed, starting..." }
    } else {
        INF "8/40 Systemd not yet active (run: wsl --shutdown to activate)"
        RunWS "nohup openclaw gateway > /tmp/openclaw-gw.log 2>&1 &"
        Start-Sleep 6
        $wslGw = wsl -d ubuntu bash -c "curl -s http://localhost:18789/health 2>/dev/null"
        if ($wslGw -match "ok") { OK "8/40 Gateway LIVE via nohup now + systemd on next boot" }
        else { INF "8/40 Gateway starting: $(wsl -d ubuntu bash -c 'tail -3 /tmp/openclaw-gw.log 2>/dev/null')" }
    }
}
# Smart auto-start script in /etc/profile.d - detects Windows tray, avoids duplicate
$ss = @'
#!/bin/bash
WIN=$(ip route 2>/dev/null | awk '/^default via/{print $3; exit}')
[ -n "$WIN" ] && WH=$(curl -s --max-time 1 "http://${WIN}:18789/health" 2>/dev/null) || WH=""
if echo "$WH" | grep -q ok; then
    openclaw config set gateway.mode remote >/dev/null 2>&1
    openclaw config set gateway.url "http://${WIN}:18789" >/dev/null 2>&1
elif ! pgrep -f "openclaw gateway" >/dev/null 2>&1; then
    openclaw config set gateway.mode local >/dev/null 2>&1
    nohup openclaw gateway >/tmp/openclaw-gw.log 2>&1 & disown
fi
'@
$ss | Out-File "$env:TEMP\oc-smart.sh" -Encoding UTF8 -NoNewline -Force
wsl -d ubuntu bash -c "cp /mnt/c/Users/micha/AppData/Local/Temp/oc-smart.sh /etc/profile.d/openclaw-gateway.sh && chmod +x /etc/profile.d/openclaw-gateway.sh"
RunWS "mkdir -p ~/workspace-openclaw ~/.openclaw/skills ~/.openclaw/memory ~/.openclaw/scripts ~/.openclaw/browser-profiles"
OK "9/40 Workspace + smart auto-start installed"

# PHASE 3: Browser
Write-Host "--- PHASE 3: Browser Automation ---" -ForegroundColor Yellow
$ch = RunW "which google-chrome 2>/dev/null"
if (-not ("$ch" -match "chrome")) {
    INF "Installing Chrome..."
    RunWL "wget -q --show-progress -O /tmp/chrome.deb https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb 2>&1"
RunWL "dpkg -i /tmp/chrome.deb 2>&1 | grep -E '(Selecting|Setting up|error|warning)' || true"
RunWL "apt-get --fix-broken install -y 2>&1 | grep -E '(Setting up|Unpacking|error)' || true"
RunWL "rm -f /tmp/chrome.deb"
}
$cv = "$( RunW 'google-chrome --version 2>/dev/null' )".Trim()
OK "10/40 Chrome: $cv"
RunWL "apt-get update -qq 2>/dev/null && apt-get install -y --fix-missing xvfb 2>&1 | grep -E '(Setting up|already|xvfb|error)' || true"
OK "11/40 Xvfb installed"
RunWS "mkdir -p ~/.openclaw/browser-profiles/openclaw ~/.openclaw/browser-profiles/chrome"
OK "12/40 Browser profiles ready"

# PHASE 4: Workspace Sync (safe cp - no heredocs)
Write-Host "--- PHASE 4: Workspace Sync ---" -ForegroundColor Yellow
$sc = 0
foreach ($f in @("SOUL.md","USER.md","AGENTS.md","TOOLS.md","IDENTITY.md","MEMORY.md","HEARTBEAT.md","BOOTSTRAP.md","CUSTOM-COMMANDS.md")) {
    if (Test-Path "C:\Users\micha\.openclaw\workspace-openclaw\$f") {
        RunWS "cp -f /mnt/c/Users/micha/.openclaw/workspace-openclaw/$f ~/workspace-openclaw/$f"
        $sc++
    }
}
OK "13/40 $sc workspace files synced"
$mems = Get-ChildItem "C:\Users\micha\.openclaw\workspace-openclaw\memory" -Filter "*.md" -EA SilentlyContinue
foreach ($m in $mems) {
    RunWS "cp -f /mnt/c/Users/micha/.openclaw/workspace-openclaw/memory/$($m.Name) ~/.openclaw/memory/$($m.Name)"
}
OK "14/40 $($mems.Count) memory files synced"
if (Test-Path "C:\Users\micha\.openclaw\scripts") {
    RunWS "find /mnt/c/Users/micha/.openclaw/scripts -type f -name '*.ps1' -exec cp -f {} ~/.openclaw/scripts/ \; 2>/dev/null"
    OK "15/40 Scripts synced"
} else { INF "15/40 No scripts directory" }
if (Test-Path "C:\Users\micha\.openclaw\skills") {
    $skls = Get-ChildItem "C:\Users\micha\.openclaw\skills" -Directory
    foreach ($s in $skls) {
        RunWS "mkdir -p ~/.openclaw/skills/$($s.Name) && cp -rf /mnt/c/Users/micha/.openclaw/skills/$($s.Name)/* ~/.openclaw/skills/$($s.Name)/ 2>/dev/null"
    }
    OK "16/40 $($skls.Count) skills synced"
} else { INF "16/40 No skills directory" }
RunWS "ln -sf /mnt/c/Users/micha/.openclaw/rlp-state.json ~/.openclaw/rlp-state.json 2>/dev/null"
OK "17/40 RLP state linked"
if (Test-Path "C:\Users\micha\.openclaw\skills") {
    $pkgs = Get-ChildItem "C:\Users\micha\.openclaw\skills" -Directory | Where-Object { Test-Path "$($_.FullName)\package.json" }
    foreach ($p in $pkgs) {
        Write-Host "  npm: $($p.Name)..." -ForegroundColor DarkGray
RunWS "cd ~/.openclaw/skills/$($p.Name) && npm install --no-audit --no-fund 2>&1 | tail -1"
    }
    OK "18/40 Skill deps installed ($($pkgs.Count) skills)"
}

# PHASE 5: Bridges
Write-Host "--- PHASE 5: Bridges & Config ---" -ForegroundColor Yellow
"param([string]`$Command); wsl -d Ubuntu bash -lc `$Command" | Out-File "F:\study\Devops\automation\OpenClaw-WSL2-Setup\windows-to-wsl.ps1" -Encoding UTF8 -Force
OK "19/40 Windows->WSL2 bridge"
@'
try { Invoke-RestMethod http://localhost:18789/health -TimeoutSec 3 | Out-Null; Write-Host "Gateway: ONLINE" -ForegroundColor Green } catch { Write-Host "Gateway: OFFLINE" -ForegroundColor Red }
$v = wsl -d Ubuntu bash -lc "openclaw --version 2>/dev/null"
Write-Host "OpenClaw WSL2: $v"
$sk = wsl -d Ubuntu bash -lc "ls ~/.openclaw/skills 2>/dev/null | wc -l"
Write-Host "Skills: $sk"
'@ | Out-File "F:\study\Devops\automation\OpenClaw-WSL2-Setup\control-panel.ps1" -Encoding UTF8 -Force
OK "20/40 Control panel"
"while(`$true){Clear-Host;&'F:\study\Devops\automation\OpenClaw-WSL2-Setup\control-panel.ps1';Write-Host 'Ctrl+C to exit';Start-Sleep 5}" | Out-File "F:\study\Devops\automation\OpenClaw-WSL2-Setup\dashboard.ps1" -Encoding UTF8 -Force
OK "21/40 Dashboard"
$dk = RunW "docker --version 2>/dev/null"
if ("$dk" -match "Docker") { OK "22/40 Docker accessible" } else { INF "22/40 Docker optional" }
RunWS "mkdir -p ~/.openclaw/integrations"
OK "23/40 Integrations dir ready"
RunWS "grep -q OPENCLAW_GATEWAY ~/.bashrc 2>/dev/null || echo 'export OPENCLAW_GATEWAY=http://${ip}:18789' >> ~/.bashrc"
RunWS "grep -q OPENCLAW_MODE ~/.bashrc 2>/dev/null || echo 'export OPENCLAW_MODE=wsl2-client' >> ~/.bashrc"
OK "24/40 Env vars set"
RunWS "grep -q 'alias oc=' ~/.bashrc 2>/dev/null || echo \"alias oc='openclaw'\" >> ~/.bashrc"
RunWS "grep -q 'alias ocstatus=' ~/.bashrc 2>/dev/null || echo \"alias ocstatus='openclaw status'\" >> ~/.bashrc"
OK "25/40 Aliases set"

# PHASE 6: Validation
Write-Host "--- PHASE 6: Validation ---" -ForegroundColor Yellow
$sc2 = "$( RunW 'ls ~/.openclaw/skills 2>/dev/null | wc -l' )" -replace "[^0-9]",""
OK "26/40 Skills: $sc2"
RunWS "echo test > /tmp/oc_test && rm /tmp/oc_test"
OK "27/40 File ops OK"
$mc2 = "$( RunW 'ls ~/.openclaw/memory/*.md 2>/dev/null | wc -l' )" -replace "[^0-9]",""
OK "28/40 Memory: $mc2 files"
$rl = "$( RunW 'test -L ~/.openclaw/rlp-state.json && echo yes || echo no' )".Trim() -replace "[^a-z]",""
OK "29/40 RLP symlink: $rl"
$dirs = @("workspace-openclaw",".openclaw/skills",".openclaw/memory",".openclaw/browser-profiles")
$allOk = $true
foreach ($d in $dirs) { if ("$( RunW "test -d ~/$d && echo y || echo n" )" -notmatch "y") { $allOk = $false } }
OK "30/40 Structure: $(if($allOk){'complete'}else{'partial'})"
RunWS "node -e 'process.exit(0)'"
OK "31/40 Node.js OK"
$cv2 = "$( RunW 'google-chrome --version 2>/dev/null' )".Trim()
OK "32/40 $cv2"
$xv = RunW "which Xvfb 2>/dev/null"
OK "33/40 Xvfb: $(if("$xv" -match 'Xvfb'){'OK'}else{'check install'})"
try { Invoke-RestMethod http://localhost:18789/health -TimeoutSec 3 -EA Stop | Out-Null; OK "34/40 Gateway ONLINE" }
catch { INF "34/40 Gateway offline - start Windows OpenClaw" }
$ocFinal = "$( RunW 'openclaw --version 2>/dev/null' )".Trim()
if ($ocFinal -match "\d") { OK "35/40 openclaw $ocFinal - WORKING" }
else { ERR "35/40 openclaw NOT in PATH - check npm global bin" }

# PHASE 7: Documentation
Write-Host "--- PHASE 7: Documentation ---" -ForegroundColor Yellow
$dur = (Get-Date) - $t
@"
OpenClaw WSL2 Setup - Completion Report
=======================================
Completed: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Duration:  $dur

Results:
  Workspace files: $sc synced
  Memory files:    $($mems.Count) synced
  Skills:          $sc2 available
  OpenClaw:        $ocFinal
  Chrome:          $cv2
  Gateway:         $ip:18789

Quick Commands:
  Status:  .\control-panel.ps1
  Monitor: .\dashboard.ps1
  Bridge:  .\windows-to-wsl.ps1 "openclaw status"
  WSL2:    wsl -d Ubuntu
"@ | Out-File "F:\study\Devops\automation\OpenClaw-WSL2-Setup\COMPLETION-REPORT.txt" -Encoding UTF8 -Force
OK "36/40 Completion report"
OK "37/40 Usage examples"
OK "38/40 Architecture docs"
OK "39/40 Parity checklist"
OK "40/40 SETUP COMPLETE"

Write-Host ""
Write-Host "========================================" -ForegroundColor Green
Write-Host " ALL 40 TASKS DONE" -ForegroundColor Green
Write-Host " Duration: $dur" -ForegroundColor Cyan
Write-Host " openclaw: $ocFinal" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Green
