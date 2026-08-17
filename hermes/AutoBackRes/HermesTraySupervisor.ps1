param(
    [string] $Root = $PSScriptRoot,
    [int] $PollSeconds = 15,
    [switch] $EnableRelaunch
)

$ErrorActionPreference = 'Continue'
$log = Join-Path $Root 'HermesTraySupervisor.log'
function Write-SupervisorLog {
    param([string] $Message)
    try {
        $stamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ssK'
        Add-Content -LiteralPath $log -Value "[$stamp] $Message" -Encoding UTF8
    } catch {
    }
}

if (-not $EnableRelaunch) {
    Write-SupervisorLog 'HermesTray supervisor relaunch loop is disabled by default; start HermesTray.exe directly unless explicit -EnableRelaunch is requested.'
    return
}

$mutex = New-Object System.Threading.Mutex($false, 'Global\HermesTraySupervisorAutoBackRes')
$hasMutex = $false

try {
    $hasMutex = $mutex.WaitOne(0)
    if (-not $hasMutex) { return }

    $exe = Join-Path $Root 'HermesTray.exe'

    Write-SupervisorLog "HermesTray supervisor started root=$Root poll_seconds=$PollSeconds"
    $lastStartedProcess = $null
    $lastSeenPid = $null
    $lastExitLoggedPid = $null

    while ($true) {
        try {
            if ($lastStartedProcess -and $lastStartedProcess.HasExited -and $lastExitLoggedPid -ne $lastStartedProcess.Id) {
                Write-SupervisorLog "HermesTray exited pid=$($lastStartedProcess.Id) exit_code=$($lastStartedProcess.ExitCode)"
                $lastExitLoggedPid = $lastStartedProcess.Id
            }

            if (-not (Test-Path -LiteralPath $exe -PathType Leaf)) {
                Write-SupervisorLog "HermesTray.exe missing: $exe"
            } else {
                $existing = Get-CimInstance Win32_Process -Filter "Name = 'HermesTray.exe'" -ErrorAction SilentlyContinue |
                    Where-Object { $_.ExecutablePath -eq $exe } |
                    Select-Object -First 1

                if (-not $existing) {
                    if ($lastSeenPid -and $lastExitLoggedPid -ne $lastSeenPid) {
                        Write-SupervisorLog "HermesTray disappeared before supervisor could read exit code pid=$lastSeenPid"
                        $lastExitLoggedPid = $lastSeenPid
                    }
                    $process = Start-Process -FilePath $exe -WindowStyle Hidden -PassThru
                    $lastStartedProcess = $process
                    $lastSeenPid = $process.Id
                    $lastExitLoggedPid = $null
                    Write-SupervisorLog "HermesTray relaunched pid=$($process.Id)"
                } else {
                    if ($lastSeenPid -ne $existing.ProcessId) {
                        Write-SupervisorLog "HermesTray observed pid=$($existing.ProcessId)"
                        $lastSeenPid = $existing.ProcessId
                    }
                    if (-not $lastStartedProcess -or $lastStartedProcess.Id -ne $existing.ProcessId) {
                        try {
                            $lastStartedProcess = Get-Process -Id $existing.ProcessId -ErrorAction Stop
                        } catch {
                            $lastStartedProcess = $null
                        }
                    }
                }
            }
        } catch {
            Write-SupervisorLog "Supervisor loop error: $($_.Exception.Message)"
        }

        Start-Sleep -Seconds ([Math]::Max(5, $PollSeconds))
    }
} finally {
    if ($hasMutex) {
        try { $mutex.ReleaseMutex() | Out-Null } catch { }
    }
    try { $mutex.Dispose() } catch { }
}
