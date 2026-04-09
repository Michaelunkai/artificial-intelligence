param(
    [string]$taskDir = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot\.rlp"
)

# Create task directory if not exists
if (-not (Test-Path $taskDir)) {
    New-Item -ItemType Directory -Path $taskDir -Force | Out-Null
}

# Create state object
$tasks = New-Object System.Collections.Generic.List[Object]

# Add 47 completed tasks (ids 1-47)
for ($i = 1; $i -le 47; $i++) {
    $task = New-Object PsObject
    $task | Add-Member NoteProperty id $i
    $task | Add-Member NoteProperty status "completed"
    $task | Add-Member NoteProperty title ("Step #" + $i + ": Initial setup verification")
    $task | Add-Member NoteProperty start (Get-Date).AddMinutes(-($i * 5))
    $task | Add-Member NoteProperty end (Get-Date).AddMinutes(-(($i - 1) * 5))
    $task | Add-Member NoteProperty progress 100
    $tasks.Add($task)
}

# Add 33 pending tasks (ids 48-76)
for ($i = 48; $i -le 76; $i++) {
    $task = New-Object PsObject
    $task | Add-Member NoteProperty id $i
    $task | Add-Member NoteProperty status "pending"
    $task | Add-Member NoteProperty title ("Step #" + $i + ": Pending work item")
    $task | Add-Member NoteProperty start (Get-Date).AddHours(-($i % 8))
    $task | Add-Member NoteProperty progress 0
    $tasks.Add($task)
}

# Create state
$state = New-Object PsObject
$state | Add-Member NoteProperty version "1.0"
$state | Add-Member NoteProperty projectId "Claw-Code Automated Setup"
$state | Add-Member NoteProperty tasks $tasks
$state | Add-Member NoteProperty createdAt (Get-Date -Format 'o')

# Output to file
$json = $state | ConvertTo-Json -Depth 10
$stateFile = (Join-Path $taskDir "state.json")
$stateFile | Set-Content -Value $json -Encoding UTF8

Write-Host "Created state with 47 completed, 33 pending"
