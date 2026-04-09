# listclau - List backup folders in F:\backup\claudecode (parallel C# size calc)
$backupPath = 'F:\backup\claudecode'
if (-not (Test-Path $backupPath)) { Write-Host "Not found: $backupPath" -ForegroundColor Red; return }

Add-Type @"
using System;
using System.IO;
using System.Threading;
using System.Threading.Tasks;

public class FastDirSize {
    public static long[] GetSizes(string[] dirs) {
        long[] sizes = new long[dirs.Length];
        Parallel.For(0, dirs.Length, i => {
            long total = 0;
            try {
                foreach (var f in Directory.EnumerateFiles(dirs[i], "*", SearchOption.AllDirectories)) {
                    try { total += new FileInfo(f).Length; } catch { }
                }
            } catch { }
            sizes[i] = total;
        });
        return sizes;
    }
}
"@

$dirs = [System.IO.Directory]::GetDirectories($backupPath) |
    ForEach-Object { [System.IO.DirectoryInfo]::new($_) } |
    Where-Object { $_.Name -match '^backup_\d{4}' } |
    Sort-Object Name -Descending

if (-not $dirs) { Write-Host "No backups found in $backupPath" -ForegroundColor Yellow; return }

Write-Host "=== F:\backup\claudecode (latest first) ===" -ForegroundColor Cyan
Write-Host ""

$paths = [string[]]($dirs | ForEach-Object { $_.FullName })
$sizes = [FastDirSize]::GetSizes($paths)

for ($i = 0; $i -lt $dirs.Count; $i++) {
    $d = $dirs[$i]
    $sizeMB = [math]::Round($sizes[$i] / 1MB, 2)
    $sizeGB = [math]::Round($sizes[$i] / 1GB, 3)
    Write-Host ("[DIR]  {0,-45} {1,10} MB  ({2,8} GB)  Created: {3}" -f $d.Name, $sizeMB, $sizeGB, $d.CreationTime.ToString('yyyy-MM-dd HH:mm:ss')) -ForegroundColor Yellow
}

# Show latest dir if it exists (internal incremental cache)
$latestDir = Join-Path $backupPath "latest"
if (Test-Path $latestDir) {
    $latestSize = 0L
    try {
        foreach ($f in [System.IO.Directory]::EnumerateFiles($latestDir, '*', [System.IO.SearchOption]::AllDirectories)) {
            try { $latestSize += ([System.IO.FileInfo]::new($f)).Length } catch {}
        }
    } catch {}
    $lMB = [math]::Round($latestSize / 1MB, 2)
    $lGB = [math]::Round($latestSize / 1GB, 3)
    Write-Host ""
    Write-Host ("[INC]  {0,-45} {1,10} MB  ({2,8} GB)  (incremental cache)" -f "latest", $lMB, $lGB) -ForegroundColor DarkGray
}
