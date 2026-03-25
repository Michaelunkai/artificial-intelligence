<#
.SYNOPSIS
    cclau - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
wsl -d Ubuntu -u ubuntu -e bash -c "cd ~ && claude && exec bash"
