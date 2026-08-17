#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
REL="$ROOT/release"
TMP="$ROOT/tmp"
mkdir -p "$REL" "$TMP" "$ROOT/iso-root"
KEYFILE="$ROOT/PRIVATE_RECOVERY_KEY_DO_NOT_UPLOAD.txt"
if [ ! -f "$KEYFILE" ]; then
  umask 077
  openssl rand -base64 48 > "$KEYFILE"
fi
BACKUP_SRC=(/home/ubuntu/.hermes /home/ubuntu/.hermes-michahermes5bot /home/ubuntu/.hermes-michaopenclawbot /home/ubuntu/.hermes-mmichael_moltbot_bot /home/ubuntu/.hermes-mmmoltbot_bot)
rm -f "$REL"/hermes-backup.enc.part-* "$REL"/hermes-private-recovery.iso "$REL"/SHA256SUMS "$REL"/manifest.txt "$TMP"/hermes-backup.tar.gz "$TMP"/hermes-backup.enc
printf 'Creating Hermes encrypted backup...\n'
tar --warning=no-file-changed -C /home/ubuntu -czf "$TMP/hermes-backup.tar.gz" .hermes .hermes-michahermes5bot .hermes-michaopenclawbot .hermes-mmichael_moltbot_bot .hermes-mmmoltbot_bot || true
openssl enc -aes-256-cbc -pbkdf2 -salt -in "$TMP/hermes-backup.tar.gz" -out "$TMP/hermes-backup.enc" -pass "file:$KEYFILE"
split -b 1900M -d -a 3 "$TMP/hermes-backup.enc" "$REL/hermes-backup.enc.part-"
cat > "$ROOT/iso-root/README.txt" <<'EOF'
Hermes Private Encrypted Recovery ISO
Run install-private.ps1 from elevated/non-elevated PowerShell after mounting.
This ISO downloads encrypted backup parts from the latest private GitHub release and restores them after you enter the recovery key.
EOF
cat > "$ROOT/iso-root/install-private.ps1" <<'PS1'
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
PS1
genisoimage -quiet -J -R -V HERMES_PRIV -o "$REL/hermes-private-recovery.iso" "$ROOT/iso-root"
( cd "$REL" && sha256sum hermes-private-recovery.iso hermes-backup.enc.part-* > SHA256SUMS )
{
  echo "Built: $(date -Is)"
  echo "Homes:"
  for d in "${BACKUP_SRC[@]}"; do du -sh "$d"; done
  echo "Release files:"
  ls -lh "$REL"
} > "$REL/manifest.txt"
printf 'Private release built at %s\n' "$REL"
