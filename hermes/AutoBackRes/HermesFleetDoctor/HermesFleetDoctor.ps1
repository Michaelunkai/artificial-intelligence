[CmdletBinding()]
param(
  [int]$Iterations = 3,
  [int]$HealthTimeoutSeconds = 90,
  [int]$SettleSeconds = 12,
  [switch]$NoRepair
)

$ErrorActionPreference = 'Stop'
$AutoBackRes = Split-Path -Parent $PSScriptRoot
$LogDir = Join-Path $PSScriptRoot 'logs'
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null
$RunStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$LogPath = Join-Path $LogDir "HermesFleetDoctor-$RunStamp.log"
$SummaryPath = Join-Path $LogDir "HermesFleetDoctor-$RunStamp.summary.txt"
$Homes = @(
  '/home/ubuntu/.hermes',
  '/home/ubuntu/.hermes-mmmoltbot_bot',
  '/home/ubuntu/.hermes-mmichael_moltbot_bot',
  '/home/ubuntu/.hermes-michaopenclawbot',
  '/home/ubuntu/.hermes-michahermes5bot'
)

function Write-Step {
  param([string]$Message, [string]$Level = 'INFO')
  $line = '[{0}] [{1}] {2}' -f (Get-Date -Format o), $Level, $Message
  Write-Host $line
  Add-Content -LiteralPath $LogPath -Value $line
}

function Invoke-Logged {
  param(
    [string]$Name,
    [string]$FilePath,
    [string[]]$ArgumentList,
    [int]$TimeoutSeconds = 60,
    [switch]$AllowFailure
  )
  Write-Step "START $Name"
  $psi = [System.Diagnostics.ProcessStartInfo]::new()
  $psi.FileName = $FilePath
  $psi.Arguments = (($ArgumentList | ForEach-Object {
    $arg = [string]$_
    if ($arg -match '[\s"]') { '"' + ($arg -replace '"', '\"') + '"' } else { $arg }
  }) -join ' ')
  $psi.UseShellExecute = $false
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $proc = [System.Diagnostics.Process]::new()
  $proc.StartInfo = $psi
  [void]$proc.Start()
  if (-not $proc.WaitForExit($TimeoutSeconds * 1000)) {
    try { $proc.Kill() } catch {}
    Start-Sleep -Milliseconds 250
    $out = ''
    $err = ''
    try { if ($proc.StandardOutput.Peek() -ge 0) { $out = $proc.StandardOutput.ReadToEnd() } } catch {}
    try { if ($proc.StandardError.Peek() -ge 0) { $err = $proc.StandardError.ReadToEnd() } } catch {}
    Add-Content -LiteralPath $LogPath -Value $out
    Add-Content -LiteralPath $LogPath -Value $err
    Write-Step "TIMEOUT $Name after ${TimeoutSeconds}s" 'WARN'
    if (-not $AllowFailure) { throw "$Name timed out" }
    return [pscustomobject]@{ ExitCode = 124; Output = $out; Error = $err }
  }
  $stdout = $proc.StandardOutput.ReadToEnd()
  $stderr = $proc.StandardError.ReadToEnd()
  if ($stdout) { Add-Content -LiteralPath $LogPath -Value $stdout }
  if ($stderr) { Add-Content -LiteralPath $LogPath -Value $stderr }
  Write-Step "END $Name exit=$($proc.ExitCode)"
  if ($proc.ExitCode -ne 0 -and -not $AllowFailure) { throw "$Name failed with exit $($proc.ExitCode)" }
  [pscustomobject]@{ ExitCode = $proc.ExitCode; Output = $stdout; Error = $stderr }
}

function Invoke-WslBash {
  param([string]$Name, [string]$Script, [int]$TimeoutSeconds = 60, [switch]$AllowFailure)
  $tmp = Join-Path $env:TEMP ("hermes-doctor-{0}.sh" -f ([guid]::NewGuid().ToString('N')))
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($tmp, (($Script -replace "`r`n","`n") -replace "`r","`n"), $utf8NoBom)
  if ($tmp -notmatch '^([A-Za-z]):(.*)$') { throw "cannot convert temp path for WSL: $tmp" }
  $linuxTmp = ('/mnt/{0}{1}' -f $Matches[1].ToLower(), ($Matches[2] -replace '\\','/'))
  try {
    Invoke-Logged -Name $Name -FilePath 'wsl.exe' -ArgumentList @('-d','Ubuntu','--','bash',$linuxTmp) -TimeoutSeconds $TimeoutSeconds -AllowFailure:$AllowFailure
  } finally {
    Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue
  }
}

function Test-HealthOutputOk {
  param($HealthResult)
  if ($null -eq $HealthResult) { return $false }
  $combined = @($HealthResult.Output, $HealthResult.Error) -join "`n"
  return ($combined -match '(?m)^READY_OK=1\s*$')
}

function Test-HealthMatcherPatch {
  $path = Join-Path $AutoBackRes 'hermes-tray-health.sh'
  $text = Get-Content -LiteralPath $path -Raw
  return ($text -match "hermes_cli/main\.py" -and $text -match "\['-m', 'hermes_cli\.main', 'gateway'\]")
}

function Repair-HealthMatcherPatch {
  if (Test-HealthMatcherPatch) {
    Write-Step 'health matcher already recognizes Python gateway launch forms'
    return
  }
  $path = Join-Path $AutoBackRes 'hermes-tray-health.sh'
  $stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
  Copy-Item -LiteralPath $path -Destination "$path.codex-backup-$stamp"
  $text = Get-Content -LiteralPath $path -Raw
  $needle = @"
        if exe.endswith('/hermes') and argv[i + 1:i + 3] == ['gateway', 'run']:
            return True
"@
  $insert = @"
        if exe.endswith('/hermes') and argv[i + 1:i + 3] == ['gateway', 'run']:
            return True
    for i in range(len(argv) - 3):
        if os.path.basename(argv[i]).startswith('python'):
            if argv[i + 1:i + 4] == ['-m', 'hermes_cli.main', 'gateway'] and len(argv) > i + 4 and argv[i + 4] == 'run':
                return True
    for i in range(len(argv) - 2):
        if argv[i].endswith('/hermes_cli/main.py') and argv[i + 1:i + 3] == ['gateway', 'run']:
            return True
"@
  if (-not $text.Contains($needle)) { throw 'health matcher patch anchor not found' }
  Set-Content -LiteralPath $path -Value $text.Replace($needle, $insert) -Encoding UTF8
  Write-Step "patched health matcher with backup $path.codex-backup-$stamp"
}

function Repair-WslMirrors {
  $pairs = @(
    @((Join-Path $AutoBackRes 'hermes-tray-health.sh'), '/home/ubuntu/.hermes/tray-control/hermes-tray-health.sh'),
    @((Join-Path $AutoBackRes 'hermes-gateway-process-check.sh'), '/home/ubuntu/.hermes/tray-control/hermes-gateway-process-check.sh'),
    @((Join-Path $AutoBackRes 'resume.sh'), '/home/ubuntu/.hermes/tray-control/resume.sh'),
    @((Join-Path $AutoBackRes 'telegram_fleet_progress_watchdog.py'), '/home/ubuntu/.hermes/scripts/telegram_fleet_progress_watchdog.py'),
    @((Join-Path $AutoBackRes 'ensure_telegram_progress_watchdog.sh'), '/home/ubuntu/.hermes/scripts/ensure_telegram_progress_watchdog.sh')
  )
  foreach ($pair in $pairs) {
    $win = $pair[0]
    $linux = $pair[1]
    $wslWin = $win -replace '^F:', '/mnt/f' -replace '\\', '/'
    Invoke-WslBash -Name "mirror $(Split-Path $win -Leaf)" -Script "set -e; install -D -m 755 '$wslWin' '$linux'; chmod +x '$linux'" -TimeoutSeconds 90 | Out-Null
  }
}

function Repair-FleetRuntime {
  $script = @'
set +e
export HERMES_WSL_USER=ubuntu
mkdir -p /home/ubuntu/.hermes/tray-control /home/ubuntu/.hermes/logs /tmp/hermes-tray-ubuntu
chmod 700 /tmp/hermes-tray-ubuntu 2>/dev/null || true
for h in /home/ubuntu/.hermes /home/ubuntu/.hermes-mmmoltbot_bot /home/ubuntu/.hermes-mmichael_moltbot_bot /home/ubuntu/.hermes-michaopenclawbot /home/ubuntu/.hermes-michahermes5bot; do
  echo "DOCTOR_HOME=$h"
  if [ ! -d "$h" ]; then echo "DOCTOR_FAIL=missing_home:$h"; continue; fi
  mkdir -p "$h/logs" "$h/.runtime" "$h/tmp"
  chmod 700 "$h/logs" "$h/.runtime" "$h/tmp" 2>/dev/null || true
  if [ ! -f "$h/config.yaml" ]; then echo "DOCTOR_FAIL=missing_config:$h"; fi
  if [ ! -f "$h/.env" ]; then echo "DOCTOR_FAIL=missing_env:$h"; fi
  if [ -f "$h/.env" ] && ! grep -q '^TELEGRAM_BOT_TOKEN=' "$h/.env"; then echo "DOCTOR_FAIL=missing_token:$h"; fi
done
python3 - <<'PY'
from pathlib import Path
import re, time
homes = [Path(p) for p in [
  "/home/ubuntu/.hermes",
  "/home/ubuntu/.hermes-mmmoltbot_bot",
  "/home/ubuntu/.hermes-mmichael_moltbot_bot",
  "/home/ubuntu/.hermes-michaopenclawbot",
  "/home/ubuntu/.hermes-michahermes5bot",
]]
stamp = time.strftime("%Y%m%d-%H%M%S")
for home in homes:
    path = home / "config.yaml"
    if not path.exists():
        continue
    text = path.read_text(encoding="utf-8")
    new_text, count = re.subn(r"(?m)^(\s*gateway_notify_interval:\s*)\d+\s*$", r"\g<1>0", text, count=1)
    if count and new_text != text:
        backup = path.with_name(f"config.yaml.codex-backup-doctor-{stamp}")
        backup.write_text(text, encoding="utf-8")
        path.write_text(new_text, encoding="utf-8")
        print(f"DOCTOR_CONFIG_REPAIRED=gateway_notify_interval:{home}:backup:{backup}")
    elif count:
        print(f"DOCTOR_CONFIG_OK=gateway_notify_interval:{home}")
    else:
        print(f"DOCTOR_CONFIG_WARN=gateway_notify_interval_missing:{home}")
PY
if [ -x /mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoBackRes/sync-codex-auth-to-hermes.sh ]; then
  bash /mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoBackRes/sync-codex-auth-to-hermes.sh || true
fi
if [ -x /home/ubuntu/.hermes/scripts/ensure_telegram_progress_watchdog.sh ]; then
  bash /home/ubuntu/.hermes/scripts/ensure_telegram_progress_watchdog.sh || true
fi
if python3 - <<'PY'
import os, pathlib, sys, yaml
homes = ["/home/ubuntu/.hermes","/home/ubuntu/.hermes-mmmoltbot_bot","/home/ubuntu/.hermes-mmichael_moltbot_bot","/home/ubuntu/.hermes-michaopenclawbot","/home/ubuntu/.hermes-michahermes5bot"]
counts = {h: 0 for h in homes}
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    try:
        argv = [x.decode("utf-8","ignore") for x in open(f"/proc/{name}/cmdline","rb").read().split(b"\0") if x]
        env_raw = open(f"/proc/{name}/environ","rb").read().decode("utf-8","ignore")
    except Exception:
        continue
    is_gateway = any(argv[i].endswith("/hermes") and argv[i+1:i+3] == ["gateway","run"] for i in range(max(len(argv)-2, 0)))
    is_gateway = is_gateway or any(argv[i].endswith("/hermes_cli/main.py") and argv[i+1:i+3] == ["gateway","run"] for i in range(max(len(argv)-2, 0)))
    if not is_gateway:
        continue
    home = "/home/ubuntu/.hermes"
    for item in env_raw.split("\0"):
        if item.startswith("HERMES_HOME="):
            home = item.split("=", 1)[1]
            break
    if home in counts:
        counts[home] += 1
ok = True
for h in homes:
    if counts[h] != 1:
        print(f"DOCTOR_FAST_PROOF_FAIL=process_count:{h}:{counts[h]}")
        ok = False
    try:
        cfg = yaml.safe_load((pathlib.Path(h) / "config.yaml").read_text(encoding="utf-8"))
        interval = int((cfg.get("agent") or {}).get("gateway_notify_interval") or 0)
    except Exception as exc:
        print(f"DOCTOR_FAST_PROOF_FAIL=config_read:{h}:{type(exc).__name__}")
        ok = False
        continue
    if interval != 0:
        print(f"DOCTOR_FAST_PROOF_FAIL=config_notify_interval:{h}:{interval}")
        ok = False
if os.system("tmux has-session -t '=hermes-telegram-progress-watchdog' >/dev/null 2>&1") != 0:
    print("DOCTOR_FAST_PROOF_FAIL=progress_watchdog_missing")
    ok = False
sys.exit(0 if ok else 1)
PY
then
  echo "DOCTOR_RESUME_SKIPPED=fleet_already_healthy"
else
  bash /home/ubuntu/.hermes/tray-control/resume.sh || true
fi
'@
  Invoke-WslBash -Name 'preserve-first fleet runtime repair/resume' -Script $script -TimeoutSeconds 90 -AllowFailure
}

function Get-FleetProcesses {
  $script = @'
python3 - <<'PY'
import os
homes = ["/home/ubuntu/.hermes","/home/ubuntu/.hermes-mmmoltbot_bot","/home/ubuntu/.hermes-mmichael_moltbot_bot","/home/ubuntu/.hermes-michaopenclawbot","/home/ubuntu/.hermes-michahermes5bot"]
counts = {h: 0 for h in homes}
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    try:
        argv = [x.decode("utf-8","ignore") for x in open(f"/proc/{name}/cmdline","rb").read().split(b"\0") if x]
        env = open(f"/proc/{name}/environ","rb").read().decode("utf-8","ignore")
    except Exception:
        continue
    is_gateway = False
    for i in range(len(argv)-2):
        if argv[i].endswith("/hermes") and argv[i+1:i+3] == ["gateway","run"]:
            is_gateway = True
        if argv[i].endswith("/hermes_cli/main.py") and argv[i+1:i+3] == ["gateway","run"]:
            is_gateway = True
    if not is_gateway:
        continue
    hermes_home = "/home/ubuntu/.hermes"
    for part in env.split("\0"):
        if part.startswith("HERMES_HOME="):
            hermes_home = part.split("=", 1)[1]
            break
    if hermes_home in counts:
        counts[hermes_home] += 1
        print(f"DOCTOR_PROCESS={hermes_home}:{name}:{' '.join(argv[:3])}")
for h in homes:
    print(f"DOCTOR_PROCESS_COUNT={h}:{counts[h]}")
PY
'@
  Invoke-WslBash -Name 'fleet process inventory' -Script $script -TimeoutSeconds 45 -AllowFailure
}

function Invoke-Health {
  Invoke-WslBash -Name 'tray health' -Script 'export HERMES_WSL_USER=ubuntu HERMES_TRAY_PROCESS_WAIT_SECONDS=8 HERMES_TRAY_NETWORK_TIMEOUT=8; /home/ubuntu/.hermes/tray-control/hermes-tray-health.sh' -TimeoutSeconds $HealthTimeoutSeconds -AllowFailure
}

function Invoke-FocusedProof {
  $script = @'
set +e
python3 - <<'PY'
import os, pathlib, sys, time, yaml
homes = ["/home/ubuntu/.hermes","/home/ubuntu/.hermes-mmmoltbot_bot","/home/ubuntu/.hermes-mmichael_moltbot_bot","/home/ubuntu/.hermes-michaopenclawbot","/home/ubuntu/.hermes-michahermes5bot"]
counts = {h: 0 for h in homes}
for name in os.listdir("/proc"):
    if not name.isdigit():
        continue
    try:
        argv = [x.decode("utf-8","ignore") for x in open(f"/proc/{name}/cmdline","rb").read().split(b"\0") if x]
        env_raw = open(f"/proc/{name}/environ","rb").read().decode("utf-8","ignore")
    except Exception:
        continue
    ok = False
    for i in range(len(argv)-2):
        if argv[i].endswith("/hermes") and argv[i+1:i+3] == ["gateway","run"]:
            ok = True
        if argv[i].endswith("/hermes_cli/main.py") and argv[i+1:i+3] == ["gateway","run"]:
            ok = True
    if not ok:
        continue
    home = "/home/ubuntu/.hermes"
    for item in env_raw.split("\0"):
        if item.startswith("HERMES_HOME="):
            home = item.split("=", 1)[1]
            break
    if home in counts:
        counts[home] += 1
for h in homes:
    print(f"DOCTOR_FOCUSED_PROCESS_COUNT={h}:{counts[h]}")
    if counts[h] != 1:
        print(f"DOCTOR_FOCUSED_FAIL=process_count:{h}:{counts[h]}")
for h in homes:
    p = pathlib.Path(h) / "config.yaml"
    try:
        cfg = yaml.safe_load(p.read_text(encoding="utf-8"))
        interval = int((cfg.get("agent") or {}).get("gateway_notify_interval") or 0)
    except Exception as exc:
        print(f"DOCTOR_FOCUSED_FAIL=config_read:{h}:{type(exc).__name__}")
        continue
    print(f"DOCTOR_FOCUSED_CONFIG_NOTIFY_INTERVAL={h}:{interval}")
    if interval != 0:
        print(f"DOCTOR_FOCUSED_FAIL=config_notify_interval:{h}:{interval}")
PY
tmux has-session -t '=hermes-telegram-progress-watchdog' >/dev/null 2>&1 && echo DOCTOR_FOCUSED_PROGRESS_WATCHDOG=1 || echo DOCTOR_FOCUSED_FAIL=progress_watchdog_missing
'@
  Invoke-WslBash -Name 'focused fleet proof' -Script $script -TimeoutSeconds 80 -AllowFailure
}

function Test-FocusedProofOk {
  param($ProofResult)
  if ($null -eq $ProofResult) { return $false }
  $combined = @($ProofResult.Output, $ProofResult.Error) -join "`n"
  $allHomes = $true
  foreach ($fleetHome in $Homes) {
    if ($combined -notmatch [regex]::Escape("DOCTOR_FOCUSED_PROCESS_COUNT=${fleetHome}:1")) { $allHomes = $false }
    if ($combined -notmatch [regex]::Escape("DOCTOR_FOCUSED_CONFIG_NOTIFY_INTERVAL=${fleetHome}:0")) { $allHomes = $false }
  }
  return ($ProofResult.ExitCode -eq 0 -and $allHomes -and $combined -match 'DOCTOR_FOCUSED_PROGRESS_WATCHDOG=1' -and $combined -notmatch 'DOCTOR_FOCUSED_FAIL=')
}

function Test-RecentTrayReadyOk {
  $trayLog = Join-Path $AutoBackRes 'HermesTray.log'
  if (-not (Test-Path -LiteralPath $trayLog)) { return $false }
  $tail = Get-Content -LiteralPath $trayLog -Tail 120 -ErrorAction SilentlyContinue
  return (($tail -join "`n") -match 'Status exit=0 .*READY_OK=1' -and ($tail -join "`n") -match 'STATUS healthy ICON=green')
}

Write-Step "HermesFleetDoctor start Iterations=$Iterations HealthTimeoutSeconds=$HealthTimeoutSeconds NoRepair=$NoRepair"
Write-Step "AutoBackRes=$AutoBackRes"
Write-Step 'online/current implementation note: uses bounded external process execution and explicit timeouts so progress cannot hang indefinitely'

if (-not $NoRepair) {
  Repair-HealthMatcherPatch
  Repair-WslMirrors
}

$lastHealth = $null
$healthPassed = $false
$lastFocusedProof = $null
for ($i = 1; $i -le $Iterations; $i++) {
  Write-Progress -Activity 'Hermes Fleet Doctor' -Status "Iteration $i of $Iterations" -PercentComplete ([int](($i - 1) * 100 / [Math]::Max($Iterations,1)))
  Write-Step "ITERATION $i"
  Get-FleetProcesses | Out-Null
  if (-not $NoRepair) { Repair-FleetRuntime | Out-Null }
  Start-Sleep -Seconds $SettleSeconds
  $lastFocusedProof = Invoke-FocusedProof
  if ((Test-FocusedProofOk $lastFocusedProof) -and (Test-RecentTrayReadyOk)) {
    Write-Step "focused proof and recent tray readiness passed on iteration $i"
    $healthPassed = $true
    break
  }
  $lastHealth = Invoke-Health
  if ($lastHealth.ExitCode -eq 0 -or (Test-HealthOutputOk $lastHealth)) {
    Write-Step "health passed on iteration $i"
    $healthPassed = $true
    break
  }
  Write-Step "health not clean on iteration $i exit=$($lastHealth.ExitCode); continuing bounded loop" 'WARN'
}

Write-Progress -Activity 'Hermes Fleet Doctor' -Completed
$processes = Get-FleetProcesses
$focusedProof = if ($null -ne $lastFocusedProof) { $lastFocusedProof } else { Invoke-FocusedProof }
$tray = Get-Process -Name HermesTray -ErrorAction SilentlyContinue | Select-Object -First 1 Id,Path,StartTime
if ($tray) {
  Write-Step "HermesTray process id=$($tray.Id) path=$($tray.Path) start=$($tray.StartTime)"
} else {
  Write-Step 'HermesTray process not running; launch existing tray wrapper instead of killing sessions' 'WARN'
  $runTray = Join-Path $AutoBackRes 'run-HermesTray.ps1'
  if ((Test-Path -LiteralPath $runTray) -and -not $NoRepair) {
    Invoke-Logged -Name 'launch HermesTray wrapper' -FilePath 'powershell.exe' -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',$runTray) -TimeoutSeconds 30 -AllowFailure | Out-Null
  }
}

$focusedOk = Test-FocusedProofOk $focusedProof
$recentTrayOk = Test-RecentTrayReadyOk
$finalHealth = if (($healthPassed -and $null -ne $lastHealth) -or ($focusedOk -and $recentTrayOk)) { $lastHealth } else { Invoke-Health }
$healthExitText = if ($null -eq $finalHealth) { 'skipped_focused_proof' } else { $finalHealth.ExitCode }
$ok = $finalHealth.ExitCode -eq 0 -or (Test-HealthOutputOk $finalHealth) -or ($focusedOk -and $recentTrayOk)
$summary = @(
  "HermesFleetDoctor log: $LogPath",
  "health_exit=$healthExitText",
  "health_ready_ok=$(Test-HealthOutputOk $finalHealth)",
  "focused_proof_ok=$focusedOk",
  "recent_tray_ready_ok=$recentTrayOk",
  "health_matcher_patch=$(Test-HealthMatcherPatch)",
  "tray_running=$([bool](Get-Process -Name HermesTray -ErrorAction SilentlyContinue))",
  "preserve_first=true",
  "forced_close_healthy_sessions=false"
)
$summary | Set-Content -LiteralPath $SummaryPath -Encoding UTF8
Write-Step "summary=$SummaryPath"
if (-not $ok) {
  Write-Step 'final health still reports a problem; see log for exact READY_FAIL markers' 'WARN'
  exit 2
}
Write-Step 'HermesFleetDoctor complete'
exit 0
