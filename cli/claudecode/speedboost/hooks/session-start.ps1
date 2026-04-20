# SpeedBoost: SessionStart hook
# Pre-caches filesystem map so Claude doesn't waste tokens exploring structure

$input = $null
try { $input = [Console]::In.ReadToEnd() | ConvertFrom-Json } catch {}

$cwd = if ($input.cwd) { $input.cwd } else { Get-Location }
$cacheFile = "$env:TEMP\speedboost_cache.json"

# Build a fast filesystem map of current project (max 2 levels deep)
try {
    $map = Get-ChildItem -Path $cwd -Depth 2 -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -notmatch '(node_modules|\.git|__pycache__|\.venv|dist|build)' } |
        Select-Object Name, FullName, @{n='Type';e={if($_.PSIsContainer){'dir'}else{'file'}}}, Length |
        ConvertTo-Json -Compress

    @{
        cwd = $cwd.ToString()
        map = $map
        built = (Get-Date).ToString('o')
    } | ConvertTo-Json | Set-Content $cacheFile -Encoding UTF8
} catch {
    # Non-fatal — session continues without cache
}

# Output nothing — hook is informational only
exit 0
