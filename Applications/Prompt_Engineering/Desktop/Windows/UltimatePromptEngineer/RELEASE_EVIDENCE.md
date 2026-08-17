# Release Evidence

This record covers the fresh, self-contained artifact built from source commit
`b68bde808f32ade55940ec0955fa8b88dd04603f` on August 3, 2026. The release
evidence is committed separately after the package hash is known. The explicit
no-launch hold is active: neither the desktop application nor the test harness
was launched for this record.

This artifact is evidence only for source commit `b68bde8`. It does not cover
uncommitted changes, a different commit, or a package written to another
directory. The `publish` directory is ignored by Git and remains mutable; the
directory, file name, and checksum below identify the package that was audited.

## Toolchain

- SDK: `C:\Program Files\dotnet\dotnet.exe`
- Pinned SDK: `11.0.100-preview.6.26359.118`
- Pin file: `global.json`
- Target framework: `net8.0-windows`
- Runtime: `win-x64`
- Publish mode: self-contained
- Release symbols: disabled
- Release version: `1.0.0.0`
- Informational version source: `1.0.0-local-first`

## Source, Build, And Package Evidence

The following completed from the repository root without launching the
application or test harness:

```powershell
& 'C:\Program Files\dotnet\dotnet.exe' restore '.\UltimatePromptEngineer.csproj' --runtime win-x64
& 'C:\Program Files\dotnet\dotnet.exe' restore '.\UltimatePromptEngineer.Tests\UltimatePromptEngineer.Tests.csproj' --runtime win-x64
& 'C:\Program Files\dotnet\dotnet.exe' build '.\UltimatePromptEngineer.csproj' --configuration Release --runtime win-x64 --no-restore
& 'C:\Program Files\dotnet\dotnet.exe' publish '.\UltimatePromptEngineer.csproj' --configuration Release --runtime win-x64 --self-contained true --no-restore --output '.\publish\win-x64-release-20260803-b68bde8'
```

Results:

- Both restores completed with all projects up to date.
- Release build: `0` warnings, `0` errors, exit code `0`.
- Self-contained publish: exit code `0`.
- The only emitted build message was the expected `NETSDK1057`
  preview-SDK informational message.
- The test command was deliberately withheld and is not represented as passed.

## Recorded Artifact

Executable:

`F:\study\AI_ML\AI_and_Machine_Learning\Artificial_Intelligence\Applications\Prompt_Engineering\Desktop\Windows\UltimatePromptEngineer\publish\win-x64-release-20260803-b68bde8\UltimatePromptEngineer.exe`

- SHA-256: `BD8DF85E8779D2DA58F0C122D3888B8B3F6100679F00D220D863A034CB17FDE1`
- Package files: `463`
- Package bytes: `167,555,437`
- PDB files: `0`
- Test-file leakage: `0`
- Apphost, runtimeconfig, and dependency manifest: present
- `UltimatePromptEngineer.runtimeconfig.json` SHA-256:
  `530B9BC1576203237A32DB45BFDFCA9E87EFC133089517CD15C51F18B4D2659A`
- `UltimatePromptEngineer.deps.json` SHA-256:
  `855A0D3A142686BBA545CECDFE87B136AD7C67552ACBE9FD645EA785B1278561`
- Runtime frameworks: `Microsoft.NETCore.App 8.0.28` and
  `Microsoft.WindowsDesktop.App 8.0.28`
- Authenticode status: `NotSigned`

## Static Verification

The following checks were performed without launching an executable:

- The release directory exists and contains `463` files totaling
  `167,555,437` bytes.
- The executable hash matches the recorded SHA-256, and the apphost,
  runtimeconfig, and dependency manifest are present.
- Generated directories (`bin`, `obj`, `publish`, `verification-bin*`, and
  `work`) are ignored, and no generated release binaries are tracked by Git.
- A credential-pattern scan of tracked source and documentation files found no
  API key, GitHub token, OpenAI-style key, or private-key pattern.
- `git fsck --no-reflogs --no-dangling` completed without repository-object
  errors.

Recheck this recorded package without launching it:

```powershell
$releaseDirectory = Resolve-Path '.\publish\win-x64-release-20260803-b68bde8'
Get-FileHash -Algorithm SHA256 -LiteralPath (Join-Path $releaseDirectory 'UltimatePromptEngineer.exe')
Get-AuthenticodeSignature -FilePath (Join-Path $releaseDirectory 'UltimatePromptEngineer.exe')
```

## GitHub Hygiene

- Remote: `https://github.com/Michaelunkai/UltimatePromptEngineer.git`
- Source branch: `main`, tracking `origin/main`.
- The local repository has no Git tag, GitHub Actions workflow, signed artifact,
  installer bundle, archive, checksum sidecar, or release metadata.
- `HEAD` and `origin/main` both resolve to `f9f38f26f4352de1a5baf0615f5dd8173e29448e`.
- External GitHub release state and branch-protection configuration were not
  inspected.

## Exact Withheld Runtime Gates

- Desktop interactive acceptance: clean first use, local generation, copy,
  import/export dialogs, reset, keyboard shortcuts, error recovery,
  persistence/reopen, window resizing, and high-DPI behavior.
- Runtime test-harness execution, including deterministic local composition,
  file-safety, persistence/recovery, provider error normalization, and
  no-credential local behavior.
- Clean-machine launch without repository files and without a preinstalled
  .NET runtime.
- Optional remote Gemini success, quota, credential, timeout, cancellation,
  and malformed-response behavior. No provider key was used for this release
  record.

## Distribution Gates

- The pinned SDK is a preview build; release policy must approve that toolchain
  or provide an approved installed SDK before distribution.
- A release tag, GitHub release asset, and published checksum are required.
- Code-signing policy must be approved and completed. The recorded executable
  is explicitly unsigned.
- The no-launch hold must be explicitly lifted before runtime evidence can be
  added.

## Signing And Distribution Readiness

Read-only verification performed on August 3, 2026:

- `Get-AuthenticodeSignature` reports `NotSigned` for the recorded executable;
  no signing command was run.
- Windows SDK `signtool.exe` is available at
  `C:\Program Files (x86)\Windows Kits\10\bin\10.0.26100.0\x64\signtool.exe`,
  file version `4.00 (WinBuild.160101.0800)`. Tool availability is not evidence
  of an authorized certificate, approved publisher identity, or signing policy.
- The published directory is a self-contained loose-file directory. No MSI,
  MSIX, APPX, archive, checksum sidecar, or signature sidecar was found.
- The local source repository contains no installer or signing configuration and
  no release workflow. The remote branch was read only; no tag or release
  operation was performed.

Readiness decision: `NOT READY FOR DISTRIBUTION`.

Blocking evidence:

1. Approved code-signing identity, certificate custody, timestamp policy, and
   signing procedure are not provided. Do not sign this artifact without direct
   authorization.
2. Distribution packaging is not defined beyond the self-contained publish
   directory; an approved package format and release checksum publication are
   required.
3. The pinned SDK is a preview build and requires an explicit policy exception
   or an approved replacement toolchain.
4. Runtime acceptance, clean-machine proof, and the no-launch hold remain
   unresolved as documented above.
