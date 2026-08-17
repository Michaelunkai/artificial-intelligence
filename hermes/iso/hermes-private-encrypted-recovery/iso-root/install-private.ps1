param([string]$Repo='Michaelunkai/hermes-private-encrypted-recovery',[string]$GitHubToken)
$ErrorActionPreference='Stop'
if(-not $GitHubToken){ $GitHubToken=Read-Host 'GitHub token with repo read access' }
$recoveryKey=Read-Host 'Paste recovery key'
$work=Join-Path $env:TEMP ('hermes-private-restore-'+[guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Force -Path $work | Out-Null
$headers=@{Authorization='Bearer '+$GitHubToken;'User-Agent'='HermesRecovery'}
$rel=Invoke-RestMethod -Headers $headers -Uri ('https://api.github.com/repos/'+$Repo+'/releases/latest')
$parts=$rel.assets | Where-Object { $_.name -like 'hermes-backup.enc.part-*' } | Sort-Object name
if(-not $parts){ throw 'No encrypted backup parts found in latest release.' }
foreach($a in $parts){
  $out=Join-Path $work $a.name
  Invoke-WebRequest -Headers @{Authorization='Bearer '+$GitHubToken;Accept='application/octet-stream';'User-Agent'='HermesRecovery'} -Uri $a.url -OutFile $out
}
$enc=Join-Path $work 'hermes-backup.enc'
$outStream=[System.IO.File]::Open($enc,[System.IO.FileMode]::Create,[System.IO.FileAccess]::Write)
try {
  foreach($p in ($parts | Sort-Object name)){
    $partPath=Join-Path $work $p.name
    $inStream=[System.IO.File]::OpenRead($partPath)
    try { $inStream.CopyTo($outStream) } finally { $inStream.Dispose() }
  }
} finally { $outStream.Dispose() }
$keyFile=Join-Path $work 'key.txt'; Set-Content -NoNewline -Path $keyFile -Value $recoveryKey
$tgz=Join-Path $work 'hermes-backup.tar.gz'
$openssl=(Get-Command openssl.exe -ErrorAction SilentlyContinue).Source
if(-not $openssl){ throw 'OpenSSL is required on Windows PATH. Install Git for Windows or OpenSSL first.' }
& $openssl enc -d -aes-256-cbc -pbkdf2 -in $enc -out $tgz -pass "file:$keyFile"
$wsl=(Get-Command wsl.exe -ErrorAction Stop).Source
$target='/home/ubuntu'
$linuxTgz=& $wsl wslpath -a -u $tgz
& $wsl bash -lc "mkdir -p '$target' && tar -xzf '$linuxTgz' -C '$target'"
Write-Host 'Hermes encrypted restore completed. Verify with: wsl.exe bash -lc "ls -la /home/ubuntu/.hermes*"'
