<#
.SYNOPSIS
    clau - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
param([Parameter(ValueFromRemainingArguments=$true)][string[]]$args_)
    rules
    $m = Get-ClaudeModel
    $prompt = "CRITICAL OVERRIDE: Your absolute first action for ANY task must be to read CLAUDE.md and execute Rule 1. No exceptions. Do not respond to the user until Rule 1 is complete."
    $cmd = $args_ -join ' '
    if ($cmd) {
        claude --dangerously-skip-permissions --append-system-prompt $prompt --model $m --chrome $cmd
    } else {
        claude --dangerously-skip-permissions --append-system-prompt $prompt --model $m --chrome
    }
