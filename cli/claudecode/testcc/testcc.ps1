<#
.SYNOPSIS
    testcc - PowerShell script
.NOTES
    Extracted: 2026-02-19
#>
Write-Host "=== Network ===" -ForegroundColor Cyan; Test-NetConnection api.anthropic.com -Port 443 -WarningAction SilentlyContinue | Select-Object ComputerName,TcpTestSucceeded,PingSucceeded; Write-Host "`n=== DNS ===" -ForegroundColor Cyan; Resolve-DnsName api.anthropic.com -Type A | Select-Object Name,IPAddress; Write-Host "`n=== TLS ===" -ForegroundColor Cyan; try{$t=[System.Net.Sockets.TcpClient]::new('api.anthropic.com',443);$s=[System.Net.Security.SslStream]::new($t.GetStream());$s.AuthenticateAsClient('api.anthropic.com');Write-Host "TLS OK: $($s.SslProtocol)" -ForegroundColor Green;$s.Dispose();$t.Dispose()}catch{Write-Host "TLS FAIL: $_" -ForegroundColor Red}; Write-Host "`n=== Proxy/ENV ===" -ForegroundColor Cyan; @('HTTP_PROXY','HTTPS_PROXY','NO_PROXY') | ForEach-Object {$v=[Environment]::GetEnvironmentVariable($_); Write-Host "$($_): $(if($v){$v}else{'NOT SET'})"}; Write-Host "ANTHROPIC_API_KEY: $(if($env:ANTHROPIC_API_KEY){'SET (hidden)'}else{'NOT SET'})"
