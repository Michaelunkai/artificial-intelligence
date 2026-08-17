$ErrorActionPreference = 'Continue'
$Root = 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\hermes\AutoBackRes'
$Exe = Join-Path $Root 'HermesTray.exe'
$TrayLog = Join-Path $Root 'HermesTray.log'
$Log = Join-Path $Root 'wsl-under5-restart-test.log'
function MsNow { [int64](([DateTimeOffset]::UtcNow).ToUnixTimeMilliseconds()) }
function Log($s) { "[$(Get-Date -Format o)] $s" | Add-Content -Path $Log -Encoding utf8 }
function TrayGreenLine {
  if (-not (Test-Path $TrayLog)) { return $null }
  return Get-Content -Path $TrayLog -Tail 200 -ErrorAction SilentlyContinue | Where-Object { $_ -match 'STATUS .*ICON=green' } | Select-Object -Last 1
}
"" | Out-File -FilePath $Log -Encoding utf8
Log 'TEST_START'
$procs = @(Get-CimInstance Win32_Process -Filter "Name='HermesTray.exe'" | Where-Object { $_.ExecutablePath -eq $Exe })
Log "TRAY_BEFORE_COUNT=$($procs.Count) PIDS=$($procs.ProcessId -join ',')"
if ($procs.Count -eq 0) {
  $p = Start-Process -FilePath $Exe -PassThru -WorkingDirectory $Root
  Log "TRAY_STARTED_PID=$($p.Id)"
  Start-Sleep -Milliseconds 700
}
Log 'WSL_SHUTDOWN_BEGIN'
& wsl.exe --shutdown 2>&1 | ForEach-Object { Log "WSL_SHUTDOWN_OUT=$_" }
Log 'WSL_SHUTDOWN_DONE'
Start-Sleep -Milliseconds 800
Log 'WSL_START_BEGIN'
$startOut = & wsl.exe -d Ubuntu --user root -- bash -lc "date +%s%3N > /tmp/wsl_under5_ready_ms; echo WSL_READY_MARKER=$(date +%s%3N)" 2>&1
$readyMs = MsNow
$startOut | ForEach-Object { Log "WSL_START_OUT=$_" }
Log "WSL_SUCCESSFULLY_RESTARTED_MS=$readyMs"
$deadline = $readyMs + 5000
$greenMs = $null
$greenLine = $null
while ((MsNow) -lt $deadline) {
  $line = TrayGreenLine
  if ($line) {
    $greenMs = MsNow
    $greenLine = $line
    break
  }
  Start-Sleep -Milliseconds 100
}
if ($greenMs -eq $null) {
  Log 'TRAY_GREEN_WITHIN_5S=0'
} else {
  Log "TRAY_GREEN_WITHIN_5S=1 elapsed_ms=$($greenMs - $readyMs) line=$greenLine"
}
Log 'HEALTH_AFTER_GREEN_BEGIN'
$healthOut = & wsl.exe -d Ubuntu --user root -- bash -lc "timeout 8s /mnt/f/study/AI_ML/AI_and_Machine_Learning/Artificial_Intelligence/hermes/AutoBackRes/hermes-tray-health.sh | grep -E 'READY_OK=|READY_FAIL|READY_FLEET_ISOLATION_OK=|READY_HOME_OK|READY_PID_COUNT|READY_TMUX|READY_RUNTIME_STATE|READY_POLLING_HEARTBEAT_OK|READY_TELEGRAM_BOT|READY_TELEGRAM_PENDING_OK'" 2>&1
$healthOut | ForEach-Object { Log "HEALTH $_" }
$after = @(Get-CimInstance Win32_Process -Filter "Name='HermesTray.exe'" | Where-Object { $_.ExecutablePath -eq $Exe })
Log "TRAY_AFTER_COUNT=$($after.Count) PIDS=$($after.ProcessId -join ',')"
if ($greenMs -ne $null -and ($greenMs - $readyMs) -le 5000 -and ($healthOut -match 'READY_OK=1') -and ($healthOut -match 'READY_FLEET_ISOLATION_OK=1') -and $after.Count -eq 1) {
  Log 'FINAL_UNDER5_WSL_RESTART_OK=1'
  exit 0
}
Log 'FINAL_UNDER5_WSL_RESTART_OK=0'
exit 2
