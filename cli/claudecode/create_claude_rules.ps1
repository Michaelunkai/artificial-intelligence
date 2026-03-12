
# Script to create claude.md with rules from F:\backup\claudecode\rules\a.txt
# Will create claude.md in the current directory, except if in excluded directories

$rulesSourcePath = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\rules\a.txt"
$excludedDirectories = @("F:\cv-matcher", "F:\study\shells\powershell\scripts\Win11Fixer\new3", " F:\study\Platforms\windows\snipping\SnipToClipBoard", "F:\backup\windowsapps\installed\myapps\compiled_python\myg\kk\k")
$currentDir = (Get-Location).Path

# Normalize current path
$normalizedCurrent = $currentDir.TrimEnd('\', '/').ToLower()

# Check if we're in any excluded directory
foreach ($excludedDir in $excludedDirectories) {
    $normalizedExcluded = $excludedDir.TrimEnd('\', '/').ToLower()
    if ($normalizedCurrent -eq $normalizedExcluded) {
        Write-Host "Cannot create claude.md in $excludedDir - this directory is excluded." -ForegroundColor Yellow
        exit 1
    }
}

# Check if rules source file exists
if (-not (Test-Path $rulesSourcePath)) {
    Write-Host "Rules source file not found: $rulesSourcePath" -ForegroundColor Red
    exit 1
}

# Read the rules file
$rulesContent = Get-Content $rulesSourcePath -Raw

# Parse rules (lines starting with "- ")
$rules = @()
$lines = $rulesContent -split "`r?`n"

foreach ($line in $lines) {
    $trimmedLine = $line.Trim()
    if ($trimmedLine -match "^-\s+(.+)$") {
        $rules += $Matches[1]
    }
}

if ($rules.Count -eq 0) {
    Write-Host "No rules found in source file (rules should start with '- ')" -ForegroundColor Yellow
    exit 1
}

# Build claude.md content
$claudeContent = @"
# Claude Rules

"@

$ruleNumber = 1
foreach ($rule in $rules) {
    $claudeContent += "## Rule $ruleNumber`n`n$rule`n`n"
    $ruleNumber++
}

# Write claude.md in current directory
$outputPath = Join-Path $currentDir "claude.md"
$claudeContent | Out-File -FilePath $outputPath -Encoding UTF8

Write-Host "Created: $outputPath" -ForegroundColor Green
Write-Host "Total rules: $($rules.Count)" -ForegroundColor Cyan
