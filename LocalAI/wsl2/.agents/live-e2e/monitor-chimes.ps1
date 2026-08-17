$ErrorActionPreference = "SilentlyContinue"

$root = Split-Path -Parent $MyInvocation.MyCommand.Path
$stopFile = Join-Path $root "exit-code.txt"
$outputFile = Join-Path $root "chime-processes.jsonl"
$seen = @{}

Remove-Item -LiteralPath $outputFile -Force -ErrorAction SilentlyContinue

while (-not (Test-Path -LiteralPath $stopFile)) {
    Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
        Where-Object {
            $_.CommandLine -like "*-EncodedCommand*" -and
            $_.CommandLine -notlike "*monitor-chimes.ps1*"
        } |
        ForEach-Object {
            $key = "$($_.ProcessId)|$($_.CreationDate)"
            if (-not $seen.ContainsKey($key)) {
                $seen[$key] = $true
                [pscustomobject]@{
                    process_id = $_.ProcessId
                    creation_date = $_.CreationDate
                    command_line = $_.CommandLine
                    observed_at = (Get-Date).ToString("o")
                } | ConvertTo-Json -Compress |
                    Add-Content -LiteralPath $outputFile -Encoding UTF8
            }
        }
    Start-Sleep -Milliseconds 200
}

Start-Sleep -Seconds 2
Get-CimInstance Win32_Process -Filter "Name = 'powershell.exe'" |
    Where-Object {
        $_.CommandLine -like "*-EncodedCommand*" -and
        $_.CommandLine -notlike "*monitor-chimes.ps1*"
    } |
    ForEach-Object {
        $key = "$($_.ProcessId)|$($_.CreationDate)"
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            [pscustomobject]@{
                process_id = $_.ProcessId
                creation_date = $_.CreationDate
                command_line = $_.CommandLine
                observed_at = (Get-Date).ToString("o")
            } | ConvertTo-Json -Compress |
                Add-Content -LiteralPath $outputFile -Encoding UTF8
        }
    }
