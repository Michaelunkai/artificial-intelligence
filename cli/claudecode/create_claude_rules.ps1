# create_claude_rules - Generate CLAUDE.md in current directory
param([string]$Dir = (Get-Location).Path)
$target = Join-Path $Dir "CLAUDE.md"
if (Test-Path $target) { Write-Host "CLAUDE.md already exists at $target" -ForegroundColor Yellow; return }
$template = Get-Content "$env:USERPROFILE\Documents\WindowsPowerShell\CLAUDE.md" -Raw -ErrorAction SilentlyContinue
if ($template) { $template | Set-Content $target -Encoding UTF8 }
else { "# Claude Rules`n" | Set-Content $target -Encoding UTF8 }
Write-Host "Created $target" -ForegroundColor Green