<#
.SYNOPSIS
    gbeads
#>
if (!(Get-Command go -ErrorAction SilentlyContinue)) { winget install GoLang.Go --accept-source-agreements --accept-package-agreements }; $env:PATH = [Environment]::GetEnvironmentVariable('PATH', 'Machine') + ';' + [Environment]::GetEnvironmentVariable('PATH', 'User'); go install github.com/beads-ai/beads-cli/cmd/bd@latest; [Environment]::SetEnvironmentVariable('PATH', "C:\Users\micha\go\bin;" + [Environment]::GetEnvironmentVariable('PATH', 'User'), 'User'); $env:PATH = "C:\Users\micha\go\bin;" + $env:PATH; bd version
