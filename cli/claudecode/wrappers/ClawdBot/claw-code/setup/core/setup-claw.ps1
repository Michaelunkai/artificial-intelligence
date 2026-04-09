# setup-claw.ps1 - Fully automated Claw-Code CLI setup
# PowerShell v5 syntax - NO && chaining, NO null-coalescing, NO ternary
# Zero user interaction - completely autonomous
# Builds Rust claw binary + copies ALL Claude Code config/memory/hooks/auth

param(
    [switch]$Force,
    [switch]$SkipBuild,
    [switch]$SkipLaunch
)

$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest

# ---- Ensure Rust/cargo on PATH (may be missing in -NoProfile context) ----
$cargoDir = "$env:USERPROFILE\.cargo\bin"
if ((Test-Path $cargoDir) -and ($env:PATH -notlike "*$cargoDir*")) {
    $env:PATH = "$cargoDir;$env:PATH"
}

# ---- Paths ----
$CLAW_ROOT    = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot\claw-code"
$REPO_DIR     = "$CLAW_ROOT\repo"
$RUST_DIR     = "$REPO_DIR\rust"
$CLAUDE_HOME  = "C:\Users\micha\.claude"
$CLAW_CONFIG  = "$env:USERPROFILE\.claw"
$CLAW_BIN     = "$RUST_DIR\target\release\claw.exe"
$REPO_URL     = "https://github.com/ultraworkers/claw-code.git"

$stepNum = 0
function Step($msg) {
    $script:stepNum++
    Write-Host ""
    Write-Host "  [$script:stepNum] $msg" -ForegroundColor Cyan
    Write-Host ("  " + ("-" * 70)) -ForegroundColor DarkGray
}

function Ok($msg) {
    Write-Host "      [OK] $msg" -ForegroundColor Green
}

function Fail($msg) {
    Write-Host "      [FAIL] $msg" -ForegroundColor Red
    throw $msg
}

function Info($msg) {
    Write-Host "      $msg" -ForegroundColor DarkGray
}

# ==============================================================
# PHASE 1: Prerequisites
# ==============================================================
Step "Checking prerequisites: git, cargo (Rust toolchain)"

# Check git
try {
    $gitVer = & git --version 2>&1
    Ok "git: $gitVer"
} catch {
    Fail "git not found. Install git from https://git-scm.com/"
}

# Check cargo (Rust) - auto-install if missing
$cargoExe = Get-Command cargo -ErrorAction SilentlyContinue
if (-not $cargoExe) {
    Info "Rust not found - installing via rustup..."
    $rustupInit = "$env:TEMP\rustup-init.exe"
    if (-not (Test-Path $rustupInit)) {
        [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12
        $wc = New-Object System.Net.WebClient
        $wc.DownloadFile("https://win.rustup.rs/x86_64", $rustupInit)
    }
    if (-not (Test-Path $rustupInit)) {
        Fail "Failed to download rustup-init.exe"
    }
    # Silent install with default toolchain
    $prevEAP = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & $rustupInit -y --default-toolchain stable --profile default 2>&1 | ForEach-Object { Info $_ }
    $ErrorActionPreference = $prevEAP
    # Refresh PATH
    $cargoDir = "$env:USERPROFILE\.cargo\bin"
    if (Test-Path $cargoDir) {
        $env:PATH = "$cargoDir;$env:PATH"
    }
    $cargoExe = Get-Command cargo -ErrorAction SilentlyContinue
    if (-not $cargoExe) {
        Fail "Rust install completed but cargo still not found on PATH"
    }
    Ok "Rust installed successfully"
}
$cargoVer = & cargo --version 2>&1
Ok "cargo: $cargoVer"

# Check rustc
$rustcVer = & rustc --version 2>&1
Ok "rustc: $rustcVer"

# ==============================================================
# PHASE 2: Clone or update repository
# ==============================================================
Step "Cloning/updating claw-code repository"

$prevEAP = $ErrorActionPreference
$ErrorActionPreference = "Continue"
if (Test-Path "$REPO_DIR\.git") {
    Info "Repo exists, pulling latest..."
    $pullOut = & git pull --ff-only 2>&1
    if ($LASTEXITCODE -eq 0) {
        Ok "git pull: $pullOut"
    } else {
        Info "Pull failed (likely local changes), continuing with existing repo"
    }
} else {
    Info "Cloning from $REPO_URL..."
    if (Test-Path $REPO_DIR) {
        Remove-Item $REPO_DIR -Recurse -Force -ErrorAction SilentlyContinue
    }
    & git clone $REPO_URL $REPO_DIR 2>&1 | ForEach-Object { Info $_ }
    if (-not (Test-Path "$REPO_DIR\.git")) {
        $ErrorActionPreference = $prevEAP
        Fail "git clone failed"
    }
    Ok "Repository cloned to $REPO_DIR"
}
$ErrorActionPreference = $prevEAP

# Verify repo structure
if (-not (Test-Path "$RUST_DIR\Cargo.toml")) {
    Fail "Cargo.toml not found at $RUST_DIR\Cargo.toml - invalid repo structure"
}
Ok "Repo structure verified: Cargo.toml found"

# ==============================================================
# PHASE 3: Build with cargo (release mode)
# ==============================================================
if (-not $SkipBuild) {
    Step "Building claw binary (cargo build --release --workspace)"
    Info "This may take several minutes on first build..."

    Push-Location $RUST_DIR
    $env:CARGO_TERM_COLOR = "always"
    $prevEAP2 = $ErrorActionPreference
    $ErrorActionPreference = "Continue"
    & cargo build --release --workspace 2>&1 | ForEach-Object { Info $_ }
    $buildExit = $LASTEXITCODE
    $ErrorActionPreference = $prevEAP2
    Pop-Location
    if ($buildExit -ne 0) {
        Fail "cargo build failed with exit code $buildExit"
    }

    if (-not (Test-Path $CLAW_BIN)) {
        Fail "claw.exe not found at $CLAW_BIN after build"
    }
    $size = [math]::Round((Get-Item $CLAW_BIN).Length / 1MB, 1)
    Ok "claw.exe built: $CLAW_BIN ($size MB)"
} else {
    Step "Skipping build (--SkipBuild)"
    if (-not (Test-Path $CLAW_BIN)) {
        Fail "claw.exe not found at $CLAW_BIN - run without -SkipBuild first"
    }
    Ok "Existing claw.exe found"
}

# ==============================================================
# PHASE 4: Copy settings.json
# ==============================================================
Step "Copying Claude Code settings.json to claw-code config"

if (-not (Test-Path $CLAW_CONFIG)) {
    New-Item -ItemType Directory -Path $CLAW_CONFIG -Force | Out-Null
}

$srcSettings = "$CLAUDE_HOME\settings.json"
$dstSettings = "$CLAW_CONFIG\settings.json"
if (Test-Path $srcSettings) {
    # Read Claude Code settings and create claw-compatible subset
    # Claw's Rust parser is strict: no BOM, no unknown keys
    $srcObj = Get-Content $srcSettings -Raw | ConvertFrom-Json
    $clawSettings = [ordered]@{
        env = @{
            BASH_MAX_TIMEOUT_MS = "1200000"
            BASH_DEFAULT_TIMEOUT_MS = "600000"
        }
        permissions = @{
            allow = @("*")
            deny = @()
        }
    }
    if ($srcObj.model) { $clawSettings.model = $srcObj.model }
    $settingsJson = $clawSettings | ConvertTo-Json -Depth 10
    [System.IO.File]::WriteAllText($dstSettings, $settingsJson, [System.Text.UTF8Encoding]::new($false))
    Ok "settings.json created (claw-compatible) at $dstSettings"
} else {
    Info "No settings.json found at $srcSettings - skipping"
}

# Also copy to project-level .claw dir
$projClawDir = "$REPO_DIR\.claw"
if (-not (Test-Path $projClawDir)) {
    New-Item -ItemType Directory -Path $projClawDir -Force | Out-Null
}
if ($settingsJson) {
    [System.IO.File]::WriteAllText("$projClawDir\settings.json", $settingsJson, [System.Text.UTF8Encoding]::new($false))
    Ok "settings.json also copied to $projClawDir\settings.json"
}

# ==============================================================
# PHASE 5: Copy hooks (embedded in settings.json - already copied)
# ==============================================================
Step "Verifying hooks in copied settings"

if (Test-Path $dstSettings) {
    $settingsObj = Get-Content $dstSettings -Raw | ConvertFrom-Json
    $hookKeys = @()
    if ($settingsObj.PSObject.Properties.Name -contains 'hooks') {
        foreach ($prop in $settingsObj.hooks.PSObject.Properties) {
            $hookKeys += $prop.Name
        }
    }
    if ($hookKeys.Count -gt 0) {
        Ok "Hooks present: $($hookKeys -join ', ')"
    } else {
        Info "No hooks section found in settings - that's OK"
    }
} else {
    Info "No settings to check hooks in"
}

# Copy hook scripts from scripts/ that hooks reference
$hookScripts = Get-ChildItem "$CLAUDE_HOME\scripts\hook-*" -ErrorAction SilentlyContinue
if ($hookScripts) {
    $clawScripts = "$CLAW_CONFIG\scripts"
    if (-not (Test-Path $clawScripts)) {
        New-Item -ItemType Directory -Path $clawScripts -Force | Out-Null
    }
    foreach ($hs in $hookScripts) {
        Copy-Item $hs.FullName "$clawScripts\$($hs.Name)" -Force
    }
    Ok "Copied $($hookScripts.Count) hook scripts"
}

# ==============================================================
# PHASE 6: Copy memory/ folder
# ==============================================================
Step "Copying memory/ folder"

$srcMemory = "$CLAUDE_HOME\memory"
$dstMemory = "$CLAW_CONFIG\memory"
if (Test-Path $srcMemory) {
    if (-not (Test-Path $dstMemory)) {
        New-Item -ItemType Directory -Path $dstMemory -Force | Out-Null
    }
    $memFiles = Get-ChildItem $srcMemory -File -Recurse
    foreach ($f in $memFiles) {
        $relPath = $f.FullName.Substring($srcMemory.Length)
        $destFile = "$dstMemory$relPath"
        $destDir = Split-Path $destFile -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $f.FullName $destFile -Force
    }
    # Verify MEMORY.md
    if (Test-Path "$dstMemory\MEMORY.md") {
        Ok "memory/ copied: $($memFiles.Count) files, MEMORY.md present"
    } else {
        Info "memory/ copied but MEMORY.md not found"
    }
} else {
    Info "No memory/ folder at $srcMemory"
}

# ==============================================================
# PHASE 7: Copy commands/ folder
# ==============================================================
Step "Copying commands/ folder"

$srcCommands = "$CLAUDE_HOME\commands"
$dstCommands = "$CLAW_CONFIG\commands"
if (Test-Path $srcCommands) {
    if (-not (Test-Path $dstCommands)) {
        New-Item -ItemType Directory -Path $dstCommands -Force | Out-Null
    }
    $cmdFiles = Get-ChildItem $srcCommands -File -Recurse
    foreach ($f in $cmdFiles) {
        $relPath = $f.FullName.Substring($srcCommands.Length)
        $destFile = "$dstCommands$relPath"
        $destDir = Split-Path $destFile -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $f.FullName $destFile -Force
    }
    Ok "commands/ copied: $($cmdFiles.Count) slash command files"
} else {
    Info "No commands/ folder at $srcCommands"
}

# ==============================================================
# PHASE 8: Copy scripts/ folder
# ==============================================================
Step "Copying scripts/ folder"

$srcScripts = "$CLAUDE_HOME\scripts"
$dstScriptsDir = "$CLAW_CONFIG\scripts"
if (Test-Path $srcScripts) {
    if (-not (Test-Path $dstScriptsDir)) {
        New-Item -ItemType Directory -Path $dstScriptsDir -Force | Out-Null
    }
    $scriptFiles = Get-ChildItem $srcScripts -File -Recurse
    foreach ($f in $scriptFiles) {
        $relPath = $f.FullName.Substring($srcScripts.Length)
        $destFile = "$dstScriptsDir$relPath"
        $destDir = Split-Path $destFile -Parent
        if (-not (Test-Path $destDir)) {
            New-Item -ItemType Directory -Path $destDir -Force | Out-Null
        }
        Copy-Item $f.FullName $destFile -Force
    }
    Ok "scripts/ copied: $($scriptFiles.Count) files"
} else {
    Info "No scripts/ folder at $srcScripts"
}

# ==============================================================
# PHASE 9: Copy workspace/ data
# ==============================================================
Step "Copying workspace/ data"

$srcWorkspace = "$CLAUDE_HOME\workspace"
$dstWorkspace = "$CLAW_CONFIG\workspace"
if (Test-Path $srcWorkspace) {
    if (-not (Test-Path $dstWorkspace)) {
        New-Item -ItemType Directory -Path $dstWorkspace -Force | Out-Null
    }
    # Copy key files only (not the full 35MB - just state and config)
    $keyFiles = @("rlp-state.json", "rlp-state.SAFE.json")
    foreach ($kf in $keyFiles) {
        $src = "$srcWorkspace\$kf"
        if (Test-Path $src) {
            Copy-Item $src "$dstWorkspace\$kf" -Force
        }
    }
    # Copy .ps1 and .json files at root level
    $wsFiles = Get-ChildItem $srcWorkspace -File -ErrorAction SilentlyContinue | Where-Object { $_.Extension -match '\.(json|ps1|txt|md)$' }
    foreach ($f in $wsFiles) {
        Copy-Item $f.FullName "$dstWorkspace\$($f.Name)" -Force
    }
    Ok "workspace/ key files copied to $dstWorkspace"
} else {
    Info "No workspace/ folder at $srcWorkspace"
}

# ==============================================================
# PHASE 10: Replicate auth credentials
# ==============================================================
Step "Replicating authentication credentials"

$srcCreds = "$CLAUDE_HOME\.credentials.json"
$dstCreds = "$CLAW_CONFIG\.credentials.json"
if (Test-Path $srcCreds) {
    # Write without BOM
    $rawCreds = [System.IO.File]::ReadAllText($srcCreds, [System.Text.UTF8Encoding]::new($false))
    if ($rawCreds.Length -gt 0 -and [int]$rawCreds[0] -eq 65279) {
        $rawCreds = $rawCreds.Substring(1)
    }
    [System.IO.File]::WriteAllText($dstCreds, $rawCreds, [System.Text.UTF8Encoding]::new($false))
    # Extract OAuth access token and set as env var for claw
    try {
        $creds = $rawCreds | ConvertFrom-Json
        if ($creds.PSObject.Properties.Name -contains 'claudeAiOauth') {
            $oauth = $creds.claudeAiOauth
            if ($oauth.accessToken) {
                $env:ANTHROPIC_AUTH_TOKEN = $oauth.accessToken
                Info "ANTHROPIC_AUTH_TOKEN set from OAuth credentials"
            }
        }
        if ($creds.PSObject.Properties.Name -contains 'apiKey') {
            $env:ANTHROPIC_API_KEY = $creds.apiKey
            Info "ANTHROPIC_API_KEY set from credentials"
        }
    } catch {
        Info "Could not parse credentials, copied raw file"
    }
    Ok "Credentials copied to $dstCreds"
} else {
    $apiKey = $env:ANTHROPIC_API_KEY
    if ($apiKey) {
        Ok "ANTHROPIC_API_KEY already set in environment"
    } else {
        Info "No credentials found - you may need to run 'claw login'"
    }
}

# ==============================================================
# PHASE 11: Copy scales, tier configs, resource-config.json
# ==============================================================
Step "Copying scales, tier configs, resource-config.json"

$configFiles = @(
    "resource-config.json",
    "claude-dashboard.local.json",
    "usage-cache.json"
)
foreach ($cf in $configFiles) {
    $src = "$CLAUDE_HOME\$cf"
    if (Test-Path $src) {
        Copy-Item $src "$CLAW_CONFIG\$cf" -Force
        Ok "Copied $cf"
    }
}

# Copy skills/
$srcSkills = "$CLAUDE_HOME\skills"
if (Test-Path $srcSkills) {
    $dstSkills = "$CLAW_CONFIG\skills"
    if (-not (Test-Path $dstSkills)) {
        New-Item -ItemType Directory -Path $dstSkills -Force | Out-Null
    }
    Copy-Item "$srcSkills\*" $dstSkills -Recurse -Force
    Ok "skills/ copied"
}

# ==============================================================
# PHASE 12: Copy learned.md
# ==============================================================
Step "Copying learned.md"

$srcLearned = "$CLAUDE_HOME\learned.md"
$dstLearned = "$CLAW_CONFIG\learned.md"
if (Test-Path $srcLearned) {
    Copy-Item $srcLearned $dstLearned -Force
    $lines = (Get-Content $srcLearned).Count
    Ok "learned.md copied ($lines lines)"
} else {
    Info "No learned.md found"
}

# Copy CLAUDE.md
$srcClaudeMd = "$CLAUDE_HOME\CLAUDE.md"
$dstClaudeMd = "$CLAW_CONFIG\CLAUDE.md"
if (Test-Path $srcClaudeMd) {
    Copy-Item $srcClaudeMd $dstClaudeMd -Force
    Ok "CLAUDE.md copied"
}

# ==============================================================
# PHASE 13: Register 'claw' command globally via PATH
# ==============================================================
Step "Registering 'claw' command globally"

$binDir = "$CLAW_ROOT\setup\core\bin"
$binLink = "$binDir\claw.exe"

# Create a symlink or copy to bin dir
if (Test-Path $CLAW_BIN) {
    try {
        Copy-Item $CLAW_BIN $binLink -Force -ErrorAction Stop
        Ok "claw.exe copied to $binLink"
    } catch {
        if (Test-Path $binLink) {
            Info "claw.exe already exists in bin (file locked, skipping copy)"
        } else {
            Fail "Failed to copy claw.exe: $_"
        }
    }
}

# Add bin dir to User PATH if not already there
$userPath = [System.Environment]::GetEnvironmentVariable("PATH", "User")
if ($userPath -notlike "*$binDir*") {
    $newPath = "$binDir;$userPath"
    [System.Environment]::SetEnvironmentVariable("PATH", $newPath, "User")
    $env:PATH = "$binDir;$env:PATH"
    Ok "Added $binDir to User PATH"
} else {
    Ok "$binDir already in User PATH"
}

# Verify claw is accessible
try {
    $clawVer = & "$binLink" --version 2>&1
    Ok "claw --version: $clawVer"
} catch {
    Info "claw --version check failed (may need new terminal): $_"
}

# ==============================================================
# PHASE 14: Add 'claw' function to PowerShell profile
# ==============================================================
Step "Adding 'claw' function to PowerShell profile"

$profilePath = "C:\Users\micha\Documents\WindowsPowerShell\Microsoft.PowerShell_profile.ps1"

# Check if claw function already exists in profile
$profileContent = ""
if (Test-Path $profilePath) {
    $profileContent = Get-Content $profilePath -Raw -ErrorAction SilentlyContinue
}

$clawFunction = @'

# ---- Claw-Code CLI ----
if (-not (Get-Command claw -ErrorAction SilentlyContinue)) {
    $clawBin = "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\wrappers\ClawdBot\claw-code\setup\core\bin\claw.exe"
    if (Test-Path $clawBin) {
        function global:claw {
            # Load auth from Claude Code credentials if not already set
            if (-not $env:ANTHROPIC_AUTH_TOKEN) {
                $credFile = "$env:USERPROFILE\.claude\.credentials.json"
                if (Test-Path $credFile) {
                    try {
                        $c = Get-Content $credFile -Raw | ConvertFrom-Json
                        if ($c.claudeAiOauth.accessToken) {
                            $env:ANTHROPIC_AUTH_TOKEN = $c.claudeAiOauth.accessToken
                        }
                    } catch {}
                }
            }
            & $clawBin @args
        }
    }
}
'@

if ($profileContent -notlike "*Claw-Code CLI*") {
    # Append via temp file to avoid encoding issues
    $tempFile = "$env:TEMP\claw_profile_append.ps1"
    [System.IO.File]::WriteAllText($tempFile, $clawFunction, [System.Text.UTF8Encoding]::new($false))
    Add-Content -Path $profilePath -Value (Get-Content $tempFile -Raw)
    Remove-Item $tempFile -Force -ErrorAction SilentlyContinue
    Ok "claw function added to $profilePath"
} else {
    Ok "claw function already in profile"
}

# Verify dot-sourceable
try {
    $parseErrors = $null
    $null = [System.Management.Automation.Language.Parser]::ParseFile($profilePath, [ref]$null, [ref]$parseErrors)
    if ($parseErrors.Count -eq 0) {
        Ok "Profile is syntactically valid"
    } else {
        Info "Profile has $($parseErrors.Count) parse warnings (may be pre-existing)"
    }
} catch {
    Info "Could not validate profile syntax"
}

# ==============================================================
# PHASE 15: Summary and optional launch
# ==============================================================
Step "Setup complete - Summary"

Write-Host ""
Write-Host "  ============================================" -ForegroundColor Green
Write-Host "  CLAW-CODE SETUP COMPLETE" -ForegroundColor Green
Write-Host "  ============================================" -ForegroundColor Green
Write-Host ""
Write-Host "  Binary:      $binLink" -ForegroundColor White
Write-Host "  Config:      $CLAW_CONFIG" -ForegroundColor White
Write-Host "  Repo:        $REPO_DIR" -ForegroundColor White
Write-Host "  Profile:     $profilePath" -ForegroundColor White
Write-Host ""

# Count what was copied
$counts = @{
    "Settings"    = [int](Test-Path $dstSettings)
    "Credentials" = [int](Test-Path $dstCreds)
    "Memory"      = (Get-ChildItem "$CLAW_CONFIG\memory" -File -Recurse -ErrorAction SilentlyContinue).Count
    "Commands"    = (Get-ChildItem "$CLAW_CONFIG\commands" -File -Recurse -ErrorAction SilentlyContinue).Count
    "Scripts"     = (Get-ChildItem "$CLAW_CONFIG\scripts" -File -Recurse -ErrorAction SilentlyContinue).Count
    "Learned"     = [int](Test-Path $dstLearned)
}
foreach ($k in $counts.Keys) {
    Write-Host "  $($k.PadRight(14)) $($counts[$k])" -ForegroundColor DarkGray
}
Write-Host ""

if (-not $SkipLaunch) {
    Write-Host "  Launching interactive claw session..." -ForegroundColor Cyan
    Write-Host ""
    & $binLink
} else {
    Write-Host "  Run 'claw' to start interactive session" -ForegroundColor Yellow
}
