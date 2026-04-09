# claudesize - Show Claude Code disk usage
$paths = @(
    "$env:USERPROFILE\.claude",
    "$env:APPDATA\Claude",
    "$env:LOCALAPPDATA\Claude"
)
Write-Host "=== Claude Code Storage ===" -ForegroundColor Cyan
foreach ($p in $paths) {
    if (Test-Path $p) {
        $size = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
        $sizeMB = [math]::Round($size / 1MB, 2)
        $files = (Get-ChildItem $p -Recurse -Force -ErrorAction SilentlyContinue).Count
        Write-Host "  $p : ${sizeMB}MB ($files files)" -ForegroundColor White
    } else {
        Write-Host "  $p : not found" -ForegroundColor DarkGray
    }
}