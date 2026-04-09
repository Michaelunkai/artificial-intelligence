# claumcp - Launch Claude Code with MCP servers enabled
param([string]$Prompt)
$env:MCP_ENABLED = "true"
if ($Prompt) { claude $Prompt } else { claude }