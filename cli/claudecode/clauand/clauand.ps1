<#
.SYNOPSIS
    clauand - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
param([string]$cmd) rules; $m = Get-ClaudeModel; if($cmd){ claude --dangerously-skip-permissions --append-system-prompt "@android-device-operator this job you do only in and for android device connected!" --model $m --chrome $cmd }else{ claude --dangerously-skip-permissions --append-system-prompt "CRITICAL OVERRIDE: Your absolute first action for ANY task must be to read CLAUDE.md and execute Rule 1. No exceptions. Do not respond to the user until Rule 1 is complete." --model $m --chrome }
