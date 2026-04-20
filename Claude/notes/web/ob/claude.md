# Claude Rules
## Rule 1

PowerShell v5 syntax - use semicolons (;) not double-ampersand (&&) for command chaining

## Rule 2

always read all md files in the folder!

## Rule 3

100% autonomous operation - background tasks auto-run without prompts, complete tasks fully with test verification

## Rule 4

Fix root causes, not symptoms - trace dependencies before edits, never suppress errors with as any or @ts-ignore

## Rule 5

Prefer editing existing files over creating new ones - never write new files unless explicitly requested

## Rule 6

always create 10-30 todos steps than i can see with ctrl + t !!

## Rule 7

Verify with tests before marking any task complete - ensure all tests pass

## Rule 8

Real-time progress updates - mark [x] on completion of each step

## Rule 9

Log all errors to .claude/learned.md for future reference

## Rule 10

Clean up ONLY when the user explicitly says the task is done - do NOT auto-cleanup or auto-exit mid-work. Never stop working until ALL steps are complete and verified.

## Rule 11

Document all changes and fixes - update/create agents.md or architecture.md on infrastructure changes

## Rule 12

Create clear, descriptive commit messages when explicitly requested

## Rule 13

NEVER exit interactive mode or stop working until the user explicitly tells you to stop. Keep working on the task until fully complete. The Stop hook in settings.json is configured - override with: `New-Item -Path "$env:TEMP\claude_task_complete" -Force`

## Rule 14

NEVER use `run_in_background: true` in Agent tool calls. Background task IDs are session-scoped — they die when the session ends or when multiple sessions are open. Using them across sessions causes "No task found" errors and ENOENT API socket failures. Always use foreground agents (no run_in_background parameter).

## Rule 15

NEVER call TaskOutput or TaskGet with IDs from previous sessions or from other concurrent sessions. Task IDs only live for the duration of the session that created them. If TaskOutput returns "No task found", do NOT retry — the task is permanently gone. Use foreground Agent calls instead.

## Rule 16 — Netlify Auto-Deploy Pipeline (F:\Downloads\ob)

This project auto-deploys to Netlify on every `git push origin main`.

**Pipeline:**
- Pre-push git hook: `F:\Downloads\ob\.git\hooks\pre-push` — triggers deploy automatically
- GitHub Actions disabled for this account; Netlify deploy is webhook-based via pre-push hook
- Live site: `https://ob-autodeploy.netlify.app`
- Netlify account: michaelovsky5@gmail.com (speach2text team)

**Config files:**
- `F:\Downloads\ob\.env` — stores `NETLIFY_SITE_ID` and `NETLIFY_AUTH_TOKEN` (never commit this)
- `F:\Downloads\ob\netlify.toml` — build config (publish dir = root `/`, no build command)
- `.gitignore` — must include `.env`

**To verify a deploy:**
```
netlify status
netlify api listSiteDeploys --data '{"site_id":"<SITE_ID>"}' | ConvertFrom-Json | Select-Object -First 1
curl https://ob-autodeploy.netlify.app
```

**Invariants:**
- NEVER commit `.env` — contains live auth tokens
- NETLIFY_AUTH_TOKEN is also stored as Windows env var `NETLIFY_AUTH_TOKEN`
- Every push to main auto-deploys; no manual `netlify deploy` needed
- GitHub Actions deploy.yml is present but intentionally disabled (account limitation)

