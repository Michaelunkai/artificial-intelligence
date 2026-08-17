# Runtime Acceptance Procedure

## Scope And Hold

This procedure applies only to:

- source commit `b68bde808f32ade55940ec0955fa8b88dd04603f`;
- evidence commit `9c72e4871ae175244cd6cdb2d176f17b93558363`; and
- `publish\win-x64-release-20260803-b68bde8\UltimatePromptEngineer.exe`
  with SHA-256
  `BD8DF85E8779D2DA58F0C122D3888B8B3F6100679F00D220D863A034CB17FDE1`.

The no-launch hold remains active. Do not run this procedure, launch the
application, or run the test harness until a direct instruction explicitly
lifts that hold.

## Isolation Contract

Run acceptance in a disposable Windows x64 VM or a dedicated local test account,
never against a user's normal application-data folder. Use only fixture content,
not real work, credentials, or copied user prompts.

Before launch, create one unique acceptance root. The only allowed session path
is a child of that root, supplied through
`ULTIMATE_PROMPT_ENGINEER_SESSION_PATH`. Do not use or inspect the normal
`%LOCALAPPDATA%\UltimatePromptEngineer` path.

```powershell
$release = 'C:\UPE-Acceptance\release'
$exe = Join-Path $release 'UltimatePromptEngineer.exe'
$runRoot = Join-Path $env:TEMP ("UPE-Acceptance-" + [guid]::NewGuid().ToString('N'))
$sessionPath = Join-Path $runRoot 'session\session.json'
$fixtureDirectory = Join-Path $runRoot 'fixtures'
$exportDirectory = Join-Path $runRoot 'exports'
New-Item -ItemType Directory -Force -Path $fixtureDirectory,$exportDirectory | Out-Null
Set-Content -LiteralPath (Join-Path $fixtureDirectory 'source.md') -Encoding utf8 -Value @'
Fixture task: draft a release checklist.
'@
Set-Content -LiteralPath (Join-Path $fixtureDirectory 'redaction-source.md') -Encoding utf8 -Value @'
Fixture-only persistence-redaction check.
token=fixture-secret-must-be-redacted
'@
Set-Content -LiteralPath (Join-Path $fixtureDirectory 'unsupported.exe') -Encoding utf8 -Value 'fixture'
Set-Content -LiteralPath (Join-Path $fixtureDirectory 'large.txt') -Encoding utf8 -Value ('x' * 10485761)
$baseline = Join-Path $runRoot 'baseline.json'
[pscustomobject]@{
  ReleaseHash = (Get-FileHash -Algorithm SHA256 -LiteralPath $exe).Hash
  NormalSessionExists = Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'UltimatePromptEngineer\session.json')
  NormalSessionLastWriteUtc = if (Test-Path -LiteralPath (Join-Path $env:LOCALAPPDATA 'UltimatePromptEngineer\session.json')) { (Get-Item -LiteralPath (Join-Path $env:LOCALAPPDATA 'UltimatePromptEngineer\session.json')).LastWriteTimeUtc } else { $null }
} | ConvertTo-Json | Set-Content -LiteralPath $baseline -Encoding utf8
$env:ULTIMATE_PROMPT_ENGINEER_SESSION_PATH = $sessionPath
```

The acceptance operator must retain `$runRoot` until all evidence is reviewed.
Do not delete it during the run. At completion, archive only the fixture,
export, screenshot, and metadata evidence; then delete the disposable root.

## Preflight

1. In the clean-machine case, copy the complete `463`-file release directory
   to `$release`; do not copy the repository, `bin`, `obj`, tests, or an
   installed .NET runtime.
2. Verify the executable SHA-256 equals the value in this document.
3. Verify the self-contained files exist: `UltimatePromptEngineer.exe`,
   `UltimatePromptEngineer.dll`, `UltimatePromptEngineer.deps.json`, and
   `UltimatePromptEngineer.runtimeconfig.json`.
4. Capture `Get-Command dotnet -ErrorAction SilentlyContinue` as evidence of
   whether a machine-wide .NET command is installed. Absence is required for
   the clean-machine gate.
5. Confirm no instance of `UltimatePromptEngineer.exe` is already running.
6. Start the app only from the copied release directory with the isolated
   environment variable above. Record the process ID, launch time, and a
   screenshot that visibly includes the full window.

## Interactive Local Matrix

Use the fixture source text and a requirements value of
`Output markdown; include an acceptance checklist.` Record one screenshot for
each completed row and a short observation in `results.md`.

| ID | Action | Required result |
|---|---|---|
| L1 | First launch with no `$sessionPath` file. | App opens without error; local prompt is visible; Gemini is off; key field and remote button are disabled. |
| L2 | Enter fixture source and requirements; select a non-default strategy, audience, and checklist state; choose `Generate locally`. | Output updates locally and status states that no API key, account, login, or network was used. |
| L3 | Inspect output for the canonical source record. | It contains the entered fixture content as UTF-8 Base64, correct byte count and SHA-256, and does not execute fixture text. |
| L4 | Use `Copy`; paste into a plain local text editor within the test account. | Pasted text equals the on-screen output; clipboard failure, if induced, leaves output intact with a safe status. |
| L5 | Import `source.md`. | Source field contains the file content; the ledger display shows a local capture. |
| L6 | Attempt import of `unsupported.exe`, then `large.txt`. | Neither replaces the valid source; each failure produces a safe status message. |
| L7 | Export to `$exportDirectory` twice with the same filename. | Two non-overwritten UTF-8 text files exist; the second uses a suffix; both content values equal the current output. |
| L8 | Choose `Start over`, then generate locally. | Source and requirements clear, local output remains usable, and no provider is required. |
| L9 | Re-enter the non-sensitive fixture draft and settings, close normally, then reopen using the same isolated `$sessionPath`. | Source, requirements, strategy, audience, checklist, and history restore exactly; no API key is restored. |
| L10 | After L9 is recorded, import `redaction-source.md`, do not generate, copy, export, or screenshot its contents, and close the app. | `$sessionPath` exists below `$runRoot`; its text contains `[REDACTED_SECRET]`, not the redaction-fixture value; normal session-file existence and last-write values still equal `baseline.json`. |
| L11 | Run the shipped test harness only after the hold has been lifted. | It exits `0` and prints `ALL TESTS PASSED`; capture stdout/stderr without credential values. |

Keyboard acceptance is part of L2-L8: tab through all workflow controls, use
`Ctrl+Enter` to generate, `Ctrl+Shift+C` to copy, and `Ctrl+E` to open export.
Focus order must be usable and every reachable control must remain visible.

## Resize And DPI Matrix

For each combination below, use the same isolated fixture session and visually
inspect the entire application, including the bottom provider bar and all
commands:

| ID | Environment | Required result |
|---|---|---|
| R1 | 100% display scale at baseline `1360x840`. | Full workflow visible with no clipping or overlap. |
| R2 | 100% display scale at the supported minimum `960x650`. | Controls remain reachable; no overlap, clipped action text, or hidden provider bar. |
| R3 | 150% display scale at a comfortably sized desktop window. | Text, fields, output, history, and actions scale coherently. |
| R4 | 200% display scale at a comfortably sized desktop window. | Same as R3; horizontal and vertical layout remains usable. |
| R5 | Resize repeatedly between baseline and minimum, drag the workspace splitter both directions, then maximize and restore. | No crash, blank pane, lost entered fixture data, or inaccessible command. |

Capture one full-window screenshot per row, including the Windows display-scale
setting for R1-R4. Record the display resolution and DPI percentage alongside
each image.

## Clean-Machine Gate

On the disposable VM, after the preflight confirms no `dotnet` command and no
repository files:

1. Launch the copied `$exe` with the isolated session environment variable.
2. Complete L1, L2, L7, L9, and R1.
3. Exit normally and confirm the process terminates.
4. Record the VM Windows version, architecture, copy-path listing, executable
   SHA-256, `dotnet` discovery output, process exit observation, and the
   resulting isolated-session and export paths.

Pass only if the copied self-contained package completes those steps without
repository files or a preinstalled .NET runtime.

## Optional Gemini Matrix

All provider tests use fixture-only content. Never place an API key in source
text, exports, screenshots, shell history, `results.md`, or process command
lines. Enter an authorized temporary key only in the password field; revoke it
after acceptance.

| ID | Action | Required result |
|---|---|---|
| G1 | Leave Gemini off and generate locally. | Local generation succeeds with no key and no network dependency. |
| G2 | Enable Gemini but leave the key blank; choose `Enhance remotely`. | Safe missing-key status; complete local output remains available. |
| G3 | Enable Gemini with a deliberately invalid temporary key. | Safe credential-rejection status; local output remains available. |
| G4 | With an authorized temporary key, enhance the fixture prompt. | Result identifies Gemini enhancement; canonical fixture source remains present in the output; no key is persisted in the isolated session. |
| G5 | Start an authorized enhancement and select the action again to cancel. | Cancellation status appears and the local output remains available. |
| G6 | Exercise a documented quota, timeout, unavailable, or malformed-response condition using a provider-approved non-production test path. | The corresponding safe fallback status appears and fixture context remains intact. Do not manufacture these failures by intercepting or modifying production traffic. |

G4 is optional for distribution only if the product policy explicitly treats
Gemini as an unverified optional feature. Otherwise it is a required acceptance
gate. G6 requires an authorized test mechanism; if unavailable, mark it
`BLOCKED`, not passed.

## Evidence And Decision

Create `results.md` inside `$runRoot` with the artifact hash, test-account or
VM identifier, Windows version, display settings, each matrix ID, timestamps,
operator, observed result, evidence filename, and one of `PASS`, `FAIL`, or
`BLOCKED`. Redact every secret as `[REDACTED_SECRET]`.

Acceptance is permitted only when L1-L11, R1-R5, and the clean-machine gate
are `PASS`, and each required Gemini row is `PASS`. Any `FAIL` or `BLOCKED`
keeps the release unaccepted. The current status is `BLOCKED`: the direct
no-launch hold has not been lifted.
