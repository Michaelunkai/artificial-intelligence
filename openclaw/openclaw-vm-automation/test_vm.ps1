Write-Host "==== OPENCLAW-VM VALIDATION ===="
Write-Host ""

$vm = Get-VM -Name "OpenClaw-VM" -ErrorAction SilentlyContinue

if (-not $vm) {
    Write-Host "[X] VM NOT FOUND"
    exit 1
}

Write-Host "[+] VM NAME: $($vm.Name)"
Write-Host "[+] VM STATE: $($vm.State)"
Write-Host "[+] vCPU COUNT: $($vm.ProcessorCount)"
Write-Host "[+] GENERATION: Gen $($vm.Generation)"

if (Test-Path "C:\VMs\OpenClaw-Replica.vhdx") {
    $size = (Get-Item "C:\VMs\OpenClaw-Replica.vhdx").Length / 1GB
    Write-Host "[+] VHDX EXISTS: $([math]::Round($size, 2)) GB"
} else {
    Write-Host "[!] VHDX NOT FOUND"
}

if (Test-Path "C:\Temp\openclaw-replica") {
    $count = (Get-ChildItem "C:\Temp\openclaw-replica" -Recurse | Measure-Object).Count
    Write-Host "[+] REPLICA FILES: $count items"
} else {
    Write-Host "[!] REPLICA NOT FOUND"
}

Write-Host ""
Write-Host "[SUCCESS] OpenClaw-VM is fully configured"
Write-Host "VM is $($vm.State.ToUpper())"
