# Quick status check for Universal MCP Dispatcher
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$DispatcherScript = Join-Path $ScriptDir "mcp_dispatcher_universal.py"

Write-Host "=== Universal MCP Dispatcher Status ===" -ForegroundColor Cyan
python "$DispatcherScript" --status | ConvertFrom-Json | Format-List
