# OpenRouter CLI Interactive Script
# Usage: .\openrouter.ps1

param(
    [string]$Message = "",
    [string]$Model = ""
)

# Add OpenRouter CLI to PATH for this session
$env:PATH += ";C:\Users\micha\AppData\Local\Packages\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\LocalCache\local-packages\Python313\Scripts"

# Function to get available models
function Get-Models {
    Write-Host "Fetching available models..." -ForegroundColor Yellow
    $models = & openrouter-cli models 2>$null | Where-Object { $_ -match "^-" } | ForEach-Object {
        if ($_ -match "^- (.+?)\s+@") {
            $matches[1]
        }
    }
    return $models
}

# Function to show popular models
function Show-PopularModels {
    Write-Host "`n=== POPULAR MODELS ===" -ForegroundColor Green
    $popular = @(
        "openai/gpt-5",
        "openai/gpt-4.1", 
        "openai/o3",
        "openai/o1",
        "anthropic/claude-sonnet-4",
        "anthropic/claude-opus-4.1",
        "anthropic/claude-3.5-sonnet",
        "google/gemini-2.5-pro",
        "google/gemini-2.5-flash",
        "mistralai/mistral-large-2411",
        "mistralai/codestral-2501",
        "deepseek/deepseek-r1",
        "deepseek/deepseek-chat",
        "meta-llama/llama-4-maverick",
        "x-ai/grok-4",
        "x-ai/grok-3",
        "qwen/qwen3-235b-a22b"
    )
    
    for ($i = 0; $i -lt $popular.Count; $i++) {
        Write-Host "$($i + 1). $($popular[$i])" -ForegroundColor Cyan
    }
    Write-Host "$($popular.Count + 1). Browse all models" -ForegroundColor White
    Write-Host "$($popular.Count + 2). Free models only" -ForegroundColor Green
    
    return $popular
}

# Function to show free models
function Show-FreeModels {
    Write-Host "`n=== FREE MODELS ===" -ForegroundColor Green
    $free = @(
        "openai/gpt-oss-20b:free",
        "z-ai/glm-4.5-air:free",
        "qwen/qwen3-coder:free",
        "moonshotai/kimi-k2:free",
        "google/gemma-3n-e2b-it:free",
        "tencent/hunyuan-a13b-instruct:free",
        "mistralai/mistral-small-3.2-24b-instruct:free",
        "moonshotai/kimi-dev-72b:free",
        "deepseek/deepseek-r1-0528:free",
        "deepseek/deepseek-r1:free",
        "qwen/qwen3-235b-a22b:free",
        "meta-llama/llama-3.3-70b-instruct:free",
        "google/gemini-2.0-flash-exp:free",
        "qwen/qwen-2.5-coder-32b-instruct:free",
        "meta-llama/llama-3.2-3b-instruct:free"
    )
    
    for ($i = 0; $i -lt $free.Count; $i++) {
        Write-Host "$($i + 1). $($free[$i])" -ForegroundColor Green
    }
    
    return $free
}

# Function to browse all models with search
function Browse-AllModels {
    Write-Host "`nFetching all models..." -ForegroundColor Yellow
    $allModels = Get-Models
    
    Write-Host "`nSearch models (enter part of name, or press Enter to see all): " -ForegroundColor Yellow -NoNewline
    $search = Read-Host
    
    if ($search) {
        $filtered = $allModels | Where-Object { $_ -like "*$search*" }
        if ($filtered.Count -eq 0) {
            Write-Host "No models found matching '$search'" -ForegroundColor Red
            return $null
        }
        $models = $filtered
        Write-Host "`nModels matching '$search':" -ForegroundColor Green
    } else {
        $models = $allModels
        Write-Host "`nAll available models:" -ForegroundColor Green
    }
    
    # Show in pages of 20
    $pageSize = 20
    $currentPage = 0
    $totalPages = [Math]::Ceiling($models.Count / $pageSize)
    
    while ($true) {
        $start = $currentPage * $pageSize
        $end = [Math]::Min($start + $pageSize - 1, $models.Count - 1)
        
        Write-Host "`n--- Page $($currentPage + 1) of $totalPages ---" -ForegroundColor Yellow
        for ($i = $start; $i -le $end; $i++) {
            Write-Host "$($i + 1). $($models[$i])" -ForegroundColor Cyan
        }
        
        if ($totalPages -gt 1) {
            Write-Host "`n[N]ext page, [P]revious page, [S]elect number, [Q]uit: " -ForegroundColor White -NoNewline
            $choice = Read-Host
            
            switch ($choice.ToUpper()) {
                "N" { 
                    if ($currentPage -lt $totalPages - 1) { $currentPage++ }
                    continue
                }
                "P" { 
                    if ($currentPage -gt 0) { $currentPage-- }
                    continue
                }
                "Q" { return $null }
                default {
                    if ($choice -match '^\d+$') {
                        $selection = [int]$choice
                        if ($selection -ge 1 -and $selection -le $models.Count) {
                            return $models[$selection - 1]
                        }
                    }
                    Write-Host "Invalid choice!" -ForegroundColor Red
                    Start-Sleep 1
                }
            }
        } else {
            Write-Host "`nSelect model number (1-$($models.Count)): " -ForegroundColor White -NoNewline
            $choice = Read-Host
            if ($choice -match '^\d+$') {
                $selection = [int]$choice
                if ($selection -ge 1 -and $selection -le $models.Count) {
                    return $models[$selection - 1]
                }
            }
            Write-Host "Invalid selection!" -ForegroundColor Red
            return $null
        }
    }
}

# Main script logic
Clear-Host
Write-Host "🤖 OpenRouter CLI Interactive Tool" -ForegroundColor Magenta
Write-Host "=================================" -ForegroundColor Magenta

# If model is specified via parameter, use it directly
if ($Model) {
    $selectedModel = $Model
    Write-Host "Using specified model: $selectedModel" -ForegroundColor Green
} else {
    # Show model selection menu
    $popularModels = Show-PopularModels
    
    Write-Host "`nSelect an option: " -ForegroundColor White -NoNewline
    $choice = Read-Host
    
    if ($choice -match '^\d+$') {
        $selection = [int]$choice
        
        if ($selection -ge 1 -and $selection -le $popularModels.Count) {
            $selectedModel = $popularModels[$selection - 1]
        }
        elseif ($selection -eq ($popularModels.Count + 1)) {
            $selectedModel = Browse-AllModels
            if (-not $selectedModel) {
                Write-Host "No model selected. Exiting." -ForegroundColor Red
                exit 1
            }
        }
        elseif ($selection -eq ($popularModels.Count + 2)) {
            $freeModels = Show-FreeModels
            Write-Host "`nSelect free model (1-$($freeModels.Count)): " -ForegroundColor White -NoNewline
            $freeChoice = Read-Host
            if ($freeChoice -match '^\d+$') {
                $freeSelection = [int]$freeChoice
                if ($freeSelection -ge 1 -and $freeSelection -le $freeModels.Count) {
                    $selectedModel = $freeModels[$freeSelection - 1]
                }
            }
        }
    }
    
    if (-not $selectedModel) {
        Write-Host "Invalid selection. Exiting." -ForegroundColor Red
        exit 1
    }
}

Write-Host "`nUsing model: $selectedModel" -ForegroundColor Green

# Get message if not provided
if (-not $Message) {
    Write-Host "`nEnter your message (or type 'interactive' for chat mode): " -ForegroundColor Yellow -NoNewline
    $Message = Read-Host
}

# Handle interactive mode
if ($Message -eq "interactive") {
    Write-Host "`n🗨️  Interactive Chat Mode - Type 'exit' to quit" -ForegroundColor Magenta
    Write-Host "Model: $selectedModel" -ForegroundColor Green
    Write-Host "----------------------------------------" -ForegroundColor Gray
    
    while ($true) {
        Write-Host "`nYou: " -ForegroundColor Cyan -NoNewline
        $userInput = Read-Host
        
        if ($userInput -eq "exit") {
            Write-Host "Goodbye! 👋" -ForegroundColor Magenta
            break
        }
        
        if ($userInput.Trim() -eq "") {
            continue
        }
        
        Write-Host "`nAI: " -ForegroundColor Yellow
        try {
            $userInput | & openrouter-cli run $selectedModel
        }
        catch {
            Write-Host "Error: $_" -ForegroundColor Red
        }
    }
} else {
    # Single message mode
    Write-Host "`n🤖 Response:" -ForegroundColor Yellow
    Write-Host "Model: $selectedModel" -ForegroundColor Green
    Write-Host "----------------------------------------" -ForegroundColor Gray
    
    try {
        $Message | & openrouter-cli run $selectedModel
    }
    catch {
        Write-Host "Error: $_" -ForegroundColor Red
        exit 1
    }
}

Write-Host "`n✅ Done!" -ForegroundColor Green