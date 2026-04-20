# SpeedBoost — Claude Code 5x Speed Project

**Goal:** Make Claude Code run tasks at least 5x faster using every legitimate lever available as of 2025-2026.

## What's in this project

| File | What it does |
|------|-------------|
| `settings.json` | Drop into `~/.claude/settings.json` — enables agent teams, auto-approvals, caching, Haiku routing |
| `hooks/pre-tool-use.ps1` | Blocks wasteful reads, injects pre-built context summaries |
| `hooks/post-compact.ps1` | Re-injects critical context after auto-compaction so Claude doesn't lose focus |
| `hooks/session-start.ps1` | Pre-caches filesystem map at session start |
| `CLAUDE.md` | Ultra-lean template — minimizes context load while maximizing Claude's decision quality |
| `install.ps1` | Installs everything in one shot |

## The 5 Speed Levers

### 1. Agent Teams (parallelism) — **3-5x wall-clock speedup**
Multiple Claude instances work simultaneously. A task that takes 10 minutes sequentially can finish in 2 minutes with 5 parallel teammates.

Enable: `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in settings.json

### 2. Auto-approve safe permissions — **eliminates interruptions**
Claude stops asking permission for read/write ops on your own files. Zero waiting for human clicks.

### 3. Prompt caching — **90% token reduction on repeated context**
CLAUDE.md, system prompts, and file content stay cached across turns. Claude reads faster when it's not re-processing the same context.

### 4. Smart model routing — **3x cost/speed for simple tasks**
Haiku 4.5 for subtasks (file reads, searches, summaries). Sonnet/Opus only for complex reasoning.

### 5. PreToolUse hooks — **skip redundant work**
Hook intercepts file reads for known files and injects cached summaries instead of making Claude re-read large files from disk.

## Install

```powershell
powershell -ExecutionPolicy Bypass -File "F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\cli\claudecode\speedboost\install.ps1"
```

Backs up your existing settings first. Safe to run.
