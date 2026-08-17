# LocalAI Ultimate Agent Research

Date: 2026-08-12
Target: `a.sh` and mirrored `local-ai-setup.sh`

## Objective

Maximize the practical capability, speed, reliability, observability, and
terminal usability of the local Nature agent while preserving honest runtime
boundaries and durable recovery.

## Evidence Reviewed

- The current 5,000+ line installer and embedded Python agent.
- The complete installation/runtime transcript in `F:\downloads\local.md`.
- Current official documentation for llama.cpp server features, OpenAI agent
  tools, MCP, prompt_toolkit, Rich, Chrome extension/native messaging,
  Playwright, WSLg, uv, Git, ShellCheck, Bats, Tree-sitter, Hugging Face, and
  agent security guidance.
- Current official command sets and interaction patterns from Codex, Claude
  Code, Gemini CLI, GitHub Copilot CLI, and Aider.
- The local Chrome Profile 2 extension installation and its native-host
  manifest, plus the bundled browser client contract.

## Confirmed Failure Modes

1. Unbounded whole-file tool arguments can spend minutes streaming before any
   write begins.
2. Installing Python libraries into the externally managed system interpreter
   causes avoidable failures and `--break-system-packages` fallbacks.
3. Linux Tk under WSL is the wrong default for a requested Windows desktop app
   and fails without a display.
4. A downloaded `mmproj` is not proof that image input works end to end.
5. A downloaded draft model is not proof of a fixed speedup.
6. Opening Chrome is not equivalent to controlling the approved signed-in
   Profile 2 tab.
7. Sending every tool schema on every model turn wastes context and can reduce
   tool-call reliability.
8. Fixed generic plan rows can be marked complete by unrelated successful
   actions.
9. Disabled server logging makes failures harder to explain in real time.
10. Broad process kills and fixed test ports can disturb unrelated work.
11. Persistent prompt storage exists, but Up/Down behavior lacks explicit
    bindings and an automated cross-session acceptance test.

## Design Decisions

### Agent Editing

- Add bounded `write_file`, `append_file`, and structured `apply_patch` tools.
- Reject oversized whole-file writes with a precise recovery instruction.
- Validate patches before mutation and report exact results.
- Route only task-relevant tools to each model turn.

### Progress And Evidence

- Emit immediate English start events and one useful status update per second.
- Preserve readable newline output for non-interactive logs.
- Add durable JSONL events for task, tool, duration, status, and evidence.
- Show exact task requirements and mark only the matching verified item done.

### Terminal Experience

- Use Rich Markdown, tables, panels, and status colors when available.
- Keep a clean ANSI fallback.
- Bind Up and Down explicitly to older/newer history with `FileHistory`.
- Add reverse search and test history across separate PromptSession instances.

### Capabilities

- Add high-value built-ins and workflows for tools, capabilities, profiles,
  sessions, checkpoints, retries, files, search, patches, vision, browser,
  MCP, skills, hooks, permissions, metrics, benchmarks, models, config,
  themes, background jobs, recap, and repository context.
- Keep custom slash commands persistent.
- Add trusted MCP configuration and bounded stdio discovery/calls.
- Distinguish available, installed-but-unverified, setup-required, and
  unavailable capabilities.

### Browser

- Preserve generic URL opening through the Windows helper.
- Verify the exact Chrome binary, Profile 2, Person 1 metadata, extension ID,
  native-host manifest, and extension files.
- Fail closed for signed-in interactive control unless a supported privileged
  bridge session can actually enumerate and claim the exact open tab.
- Label isolated Playwright as web testing, never as the user's signed-in
  browser profile.

### Model Runtime

- Feature-detect llama-server flags from the installed binary.
- Add fast, balanced, and quality profiles.
- Prefer measured settings over fixed speed claims.
- Keep logs enabled and expose metrics/slots when supported.
- Treat vision and speculative decoding as verified only after live probes.

### Installer And Tests

- Use an isolated virtual environment or uv instead of modifying system Python.
- Keep TLS verification enabled.
- Validate model files before accepting them.
- Use dynamic test ports and stop only the exact process started by the test.
- Run shell syntax, extracted-Python compilation, mirror identity, routing,
  bounded-write, patch, non-TTY progress, slash catalog, and prompt-history
  behavior checks.

## Acceptance Standard

The implementation may claim a feature only when the exact relevant test or
runtime probe passes. No local script can guarantee every future task or remove
external permissions, hardware, authentication, network, policy, or model
limits; the correct target is maximal practical capability with explicit,
recoverable boundaries and no false success.
