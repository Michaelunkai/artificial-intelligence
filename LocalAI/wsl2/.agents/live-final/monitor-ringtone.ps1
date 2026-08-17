param(
    [Parameter(Mandatory = $true)]
    [string]$OutputPath,

    [Parameter(Mandatory = $true)]
    [string]$StopPath
)

$ErrorActionPreference = 'Stop'
$seen = @{}
$utf16 = [System.Text.Encoding]::Unicode
$parent = Split-Path -Parent $OutputPath
if ($parent) {
    [System.IO.Directory]::CreateDirectory($parent) | Out-Null
}
[System.IO.File]::WriteAllText($OutputPath, '', [System.Text.Encoding]::UTF8)

while (-not [System.IO.File]::Exists($StopPath)) {
    $processes = Get-CimInstance Win32_Process -Filter "Name='powershell.exe'"
    foreach ($process in $processes) {
        $pidValue = [int]$process.ProcessId
        if ($seen.ContainsKey($pidValue)) {
            continue
        }
        $seen[$pidValue] = $true
        $commandLine = [string]$process.CommandLine
        $match = [regex]::Match(
            $commandLine,
            '(?i)(?:-EncodedCommand|-enc)\s+"?([A-Za-z0-9+/=]+)"?'
        )
        if (-not $match.Success) {
            continue
        }
        try {
            $decoded = $utf16.GetString(
                [System.Convert]::FromBase64String($match.Groups[1].Value)
            )
        }
        catch {
            continue
        }
        if (
            $decoded -notmatch 'System\.Media\.SoundPlayer' -or
            $decoded -notmatch 'nature-complete\.wav' -or
            $decoded -notmatch 'PlaySync'
        ) {
            continue
        }
        $event = [ordered]@{
            observed_at = [DateTimeOffset]::Now.ToString('o')
            process_id = $pidValue
            command = $decoded
        }
        $line = ($event | ConvertTo-Json -Compress) + [Environment]::NewLine
        [System.IO.File]::AppendAllText(
            $OutputPath,
            $line,
            [System.Text.Encoding]::UTF8
        )
    }
    Start-Sleep -Milliseconds 25
}
