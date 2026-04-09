# claud - Launch Claude Code interactively
param([string]$Prompt)
if ($Prompt) { claude $Prompt } else { claude }