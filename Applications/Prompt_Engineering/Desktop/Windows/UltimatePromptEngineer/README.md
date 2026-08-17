# Ultimate Prompt Engineer

A local-first Windows desktop app that turns arbitrary captured context into a durable, ready-to-send prompt for any AI agent.

## Guarantees

- Local prompt generation is available immediately, without an API key, account, login, network, or manual setup.
- Source context and explicit requirements are separate inputs. A selectable strategy, intent, audience, and optional completion checklist shape the generated specification.
- Committed local captures are retained for the active session by default. The prompt payload is deterministic for the same captures and does not include capture timestamps.
- The offline prompt includes a canonical UTF-8 Base64 record with byte count and SHA-256 data. This keeps hostile-looking source text inside an explicit untrusted-data boundary.
- Copy and text export work without a provider. Import and export failures are reported as user-safe status messages.
- Gemini Developer API is an opt-in enhancement only. The session-only key is never persisted, and local output remains the fallback for quota, credential, network, cancellation, or malformed-response failures.
- Use local-only mode for sensitive content. A provider may process submitted content under its own terms.

## Runtime Gate

The explicit no-launch hold is active. Do not launch the application or the
test harness until that hold is explicitly lifted.

The freshly packaged, unlaunched executable is:

`publish\win-x64-release-20260803-b68bde8\UltimatePromptEngineer.exe`

Its commit provenance, SHA-256, static package checks, and exact withheld
runtime gates are documented in [RELEASE_EVIDENCE.md](RELEASE_EVIDENCE.md).
The `publish` directory is ignored by Git, so do not treat an arbitrary or
mutable directory below it as a verified release.

## Test

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' run --project '.\UltimatePromptEngineer.Tests\UltimatePromptEngineer.Tests.csproj' --configuration Release --runtime win-x64 --no-restore
```

This command was intentionally not executed for the August 3, 2026 release
record because the no-launch hold also withholds runtime test execution.

## Publish

```powershell
$sourceCommit = (& 'C:\Program Files\Git\cmd\git.exe' rev-parse --short=8 HEAD).Trim()
$releaseDirectory = Join-Path $PWD ("publish\win-x64-release-{0}-{1}" -f (Get-Date -Format 'yyyyMMdd'), $sourceCommit)
& 'C:\Program Files\dotnet\dotnet.exe' restore '.\UltimatePromptEngineer.csproj' --runtime win-x64
& 'C:\Program Files\dotnet\dotnet.exe' restore '.\UltimatePromptEngineer.Tests\UltimatePromptEngineer.Tests.csproj' --runtime win-x64
& 'C:\Program Files\dotnet\dotnet.exe' build '.\UltimatePromptEngineer.csproj' --configuration Release --runtime win-x64 --no-restore
& 'C:\Program Files\dotnet\dotnet.exe' publish '.\UltimatePromptEngineer.csproj' --configuration Release --runtime win-x64 --self-contained true --no-restore --output $releaseDirectory
Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $releaseDirectory 'UltimatePromptEngineer.exe')
```

The published executable is self-contained for 64-bit Windows. The optional
Gemini API key is entered at runtime, is never stored in this repository, and is
not needed for local generation. Each publish uses a new commit-stamped
directory so a recorded artifact is not overwritten.
