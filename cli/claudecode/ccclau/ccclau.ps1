# ccclau - List and manage Claude Code sessions
$sessions = Get-ChildItem "$env:USERPROFILE\.claude\projects" -Directory -ErrorAction SilentlyContinue
if (-not $sessions) { Write-Host "No Claude sessions found" -ForegroundColor Yellow; return }
Write-Host "=== Claude Code Sessions ===" -ForegroundColor Cyan
foreach ($s in $sessions) {
    $jsonls = Get-ChildItem $s.FullName -Filter "*.jsonl" -ErrorAction SilentlyContinue
    $latest = $jsonls | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    $age = if ($latest) { [math]::Round(((Get-Date) - $latest.LastWriteTime).TotalHours, 1) } else { "N/A" }
    Write-Host "  $($s.Name) | Files: $($jsonls.Count) | Last: ${age}h ago" -ForegroundColor White
}