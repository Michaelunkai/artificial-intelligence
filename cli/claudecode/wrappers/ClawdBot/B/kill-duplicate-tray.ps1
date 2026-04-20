# Kill Duplicate ClawdbotTray Instances - NO WMI VERSION
$ErrorActionPreference = 'SilentlyContinue'

# Find ClawdbotTray processes by checking script path (NO WMI)
$instances = @(Get-Process powershell | Where-Object {
    try {
        # Check if any loaded modules/files contain ClawdbotTray
        $_.Modules | Where-Object { $_.FileName -like "*ClawdbotTray*" }
    } catch {
        $false
    }
})

# If that didn't work, try alternative: check all powershell processes with window title or path
if ($instances.Count -eq 0) {
    $instances = @(Get-Process powershell | Where-Object {
        try {
            # Check if main module path or process title suggests ClawdbotTray
            $_.MainModule.FileName -like "*ClawdBot*" -or 
            $_.ProcessName -eq "powershell" -and (Get-Date) - $_.StartTime -lt [TimeSpan]::FromHours(24)
        } catch {
            $false
        }
    })
}

if ($instances.Count -le 1) {
    Write-Host "Only one or zero ClawdbotTray instances - OK"
    exit 0
}

$sorted = $instances | Sort-Object StartTime
$keep = $sorted[0]
$kill = $sorted | Select-Object -Skip 1

Write-Host "Keeping PID $($keep.Id), killing $($kill.Count) duplicates"

foreach ($proc in $kill) {
    Stop-Process -Id $proc.Id -Force
    Write-Host "Killed PID $($proc.Id)"
}
