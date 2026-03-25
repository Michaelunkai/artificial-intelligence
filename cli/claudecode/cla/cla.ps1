<#
.SYNOPSIS
    cla - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
& -Command "Start-Process 'F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\RunClaudeYoloWithGemini.ahk'; Start-Sleep 2; Add-Type -AssemblyName System.Windows.Forms; [System.Windows.Forms.SendKeys]::SendWait('{F1}'); Start-Sleep 8; Get-Process AutoHotkey* | Stop-Process -Force"
