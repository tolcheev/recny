# Windows v0.2 Beta Implementation Plan

## Objective

Create a separate Windows beta client that builds a shareable `ToRec.exe` zip on GitHub Actions.

## Steps

1. Update Windows documentation to mark v0.2 beta as active scope.
2. Add `apps/windows/ToRec.Windows.Core` with recording, storage, metadata, diagnostics, and post-processing code.
3. Add `apps/windows/ToRec.Windows` Windows Forms tray app.
4. Add `apps/windows/ToRec.Windows.Tests` as a package-light console test runner.
5. Add `.github/workflows/windows-build.yml` to build, test, publish, zip, and upload the Windows artifact.
6. Update README with Windows beta install and use instructions.
7. Push the branch and use GitHub Actions to validate on a real Windows runner.
8. If the workflow passes, download the artifact locally and attach it to a prerelease.

## Acceptance Criteria

- Windows app source lives under `apps/windows`.
- macOS app source is unchanged by the Windows implementation.
- The Windows app has manual Start/Stop for microphone plus system audio.
- A recording creates `source/`, `export/`, and `metadata.json`.
- Diagnostics exposes storage path and last error.
- Local tests verify path layout, metadata writing, and metadata scanning.
- GitHub Actions produces a zip containing `ToRec.exe`.

## Validation Commands

Local macOS validation is limited because .NET is not installed on this machine:

```sh
git diff --check
```

Windows runner validation:

```sh
dotnet restore apps/windows/ToRec.Windows/ToRec.Windows.csproj
dotnet build apps/windows/ToRec.Windows/ToRec.Windows.csproj -c Release --no-restore
dotnet run --project apps/windows/ToRec.Windows.Tests/ToRec.Windows.Tests.csproj -c Release
dotnet publish apps/windows/ToRec.Windows/ToRec.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## Rollback

Remove `apps/windows`, the Windows workflow, and the Windows-specific README/docs changes. Existing macOS release artifacts and source are not modified by this plan.
