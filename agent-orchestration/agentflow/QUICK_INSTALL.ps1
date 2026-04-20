# AgentFlow Quick Install - Bypasses compilation issues

Write-Host "Installing AgentFlow..." -ForegroundColor Cyan

# Remove better-sqlite3, use sqlite3 instead (no compilation needed)
$package = Get-Content "package.json" | ConvertFrom-Json
$package.dependencies.PSObject.Properties.Remove('better-sqlite3')
$package.dependencies | Add-Member -MemberType NoteProperty -Name 'sqlite3' -Value '^5.1.6' -Force
$package | ConvertTo-Json -Depth 10 | Set-Content "package_temp.json"
Move-Item "package_temp.json" "package.json" -Force

# Install dependencies
npm install --no-optional

# Copy to OpenClaw extensions
$target = "C:\Users\micha\.openclaw\extensions\agentflow"
if (Test-Path $target) {
    Remove-Item $target -Recurse -Force
}
Copy-Item -Path . -Destination $target -Recurse -Force -Exclude node_modules,data,logs

# Install deps in target location
Push-Location $target
npm install --no-optional --silent
Pop-Location

Write-Host "Done! Run: openclaw gateway restart" -ForegroundColor Green
