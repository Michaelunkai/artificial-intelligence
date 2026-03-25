# OpenRouter CLI Tools

This folder contains scripts for interacting with OpenRouter's AI models via command line.

## Files

- `or.ps1` - Simple command-line wrapper for quick queries
- `run-ai.ps1` - Interactive menu with popular models  
- `openrouter.ps1` - Full-featured browser for all 400+ models
- `openrouter.bat` - Batch file version for Windows CMD

## Usage

### Quick Query
```powershell
.\or.ps1 -Model "deepseek/deepseek-r1:free" -Message "Your question here"
```

### Interactive Menu
```powershell
.\run-ai.ps1
```

### Browse All Models
```powershell
.\openrouter.ps1
```

### Batch File (CMD)
```cmd
openrouter.bat "deepseek/deepseek-r1:free" "Your question"
```

## Popular Free Models

- `deepseek/deepseek-r1:free` - Advanced reasoning model
- `openai/gpt-oss-20b:free` - Open source GPT variant  
- `meta-llama/llama-3.3-70b-instruct:free` - Meta's latest Llama
- `qwen/qwen3-235b-a22b:free` - Large Chinese model
- `google/gemini-2.0-flash-exp:free` - Google's experimental model

## Popular Paid Models

- `anthropic/claude-3.5-sonnet` - Best reasoning capabilities
- `openai/gpt-5` - OpenAI's latest flagship
- `google/gemini-2.5-pro` - Google's premium model  
- `mistralai/codestral-2501` - Optimized for coding
- `x-ai/grok-4` - X.AI's latest model

## Setup

The scripts automatically:
- Add OpenRouter CLI to PATH
- Set UTF-8 encoding for proper Unicode support
- Configure Python environment variables

## Requirements

- OpenRouter CLI installed (`pip install openrouter-cli`)
- Valid OpenRouter API key configured
- PowerShell (for .ps1 files) or Command Prompt (for .bat file)