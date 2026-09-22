# Contributing to Recny

Recny has native clients for macOS and Windows. Keep changes small, update documentation when behavior changes, and never commit real recordings or call metadata.

## Before opening an issue

Search existing issues. For a bug, include the Recny version, operating-system version, call app, reproduction steps, expected result, and actual result. Sanitize logs and screenshots. Do not attach recordings, transcripts, credentials, names of call participants, or private call content.

Use the process in [SECURITY.md](SECURITY.md) for vulnerabilities.

## macOS development

Requirements: macOS, Xcode Command Line Tools, Swift 6.

```sh
swift test --package-path apps/macos
./scripts/build_macos.sh
```

ScreenCaptureKit and microphone behavior require real macOS permissions and cannot be validated by a stub. Use the smoke tests documented in [apps/macos/README.md](apps/macos/README.md) when changing audio capture.

## Windows development

Requirements: Windows x64 and .NET 8 SDK.

```powershell
dotnet restore apps/windows/Recny.Windows/Recny.Windows.csproj
dotnet build apps/windows/Recny.Windows/Recny.Windows.csproj -c Release --no-restore
dotnet run --project apps/windows/Recny.Windows.Tests/Recny.Windows.Tests.csproj -c Release
```

WASAPI capture needs a real Windows audio device. Passing unit tests does not replace manual microphone and loopback checks.

## Pull requests

- Keep one product change per pull request.
- Add lifecycle and failure logs for recorder changes.
- Preserve local-first behavior.
- Add focused tests for behavior that can be tested without OS audio permissions.
- Update the relevant files under `docs/`.
- Do not add cloud upload, background telemetry, or recording analytics without a separate product decision.

By contributing, you agree that your contribution is licensed under the MIT License.
