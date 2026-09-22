# Recny

Recny is a local-first desktop app that records calls automatically. It captures microphone and system audio into separate files, creates a mixed copy, and keeps everything on the computer.

[Download Recny](https://tolcheev.github.io/recny/) · [Report a bug](https://github.com/tolcheev/recny/issues/new?template=bug_report.yml) · [Read the architecture](docs/ARCHITECTURE.md)

## Platform status

### macOS

- Current release: `v0.1.8`
- Apple Silicon, macOS Sequoia
- Native Swift and SwiftUI menu bar app
- Ad-hoc signed and not Apple-notarized

### Windows

- Current release: `v0.2.5-beta`
- Windows x64
- Native .NET 8 tray app
- Experimental beta distributed as a self-contained ZIP without an installer

## What Recny records

- microphone audio;
- system audio;
- a mixed listening copy;
- local metadata, tags, logs, and diagnostics.

Recny can watch supported call apps and start recording after stable call activity. Manual Start and Stop remain available when automatic detection misses a call.

## Install

### macOS

1. Download `Recny-v0.1.8-macOS.dmg` from the [Recny website](https://tolcheev.github.io/recny/).
2. Open the DMG and drag `Recny.app` into Applications.
3. In Finder, open Applications, right-click Recny, and choose Open.
4. If macOS still blocks the app, open System Settings > Privacy & Security and choose Open Anyway.
5. Grant Microphone and Screen & System Audio Recording permissions when Recny asks.

Do not disable Gatekeeper globally. The current free build is ad-hoc signed, so the first-launch warning is expected.

### Windows

1. Download `Recny-Windows-v0.2.5-beta.zip` from the [Recny website](https://tolcheev.github.io/recny/).
2. Extract the ZIP into a permanent folder.
3. Run `Recny.exe`.
4. If Microsoft Defender SmartScreen appears, choose More info, verify that the file came from this repository, and choose Run anyway.
5. Open Recny from the system tray.

The Windows build is a beta. It has no installer and does not yet match every macOS feature.

## Local storage

macOS keeps recordings under:

```text
~/Recordings/TOrbitRecorder/
```

The historical folder name remains unchanged so existing recordings and macOS permissions continue to work.

Windows keeps recordings under:

```text
%USERPROFILE%\Recordings\Recny\
```

Each completed recording contains separate source tracks, a mixed export, and `metadata.json`. See [Storage format](docs/STORAGE_FORMAT.md) for the detailed contract.

## Privacy

Recording, metadata, tags, diagnostics, and optional local transcription stay on the computer. Recny does not upload calls, sync with T-Orbit, or run cloud AI. Read [Security and privacy](docs/SECURITY_PRIVACY.md) before using Recny for sensitive calls.

## Build and test

### macOS

Requirements: macOS, Xcode Command Line Tools, Swift 6.

```sh
swift test --package-path apps/macos
./scripts/build_macos.sh
./scripts/package_macos.sh
```

The package script creates the app bundle, ZIP, DMG, SHA-256 files, and update manifest under `dist/`. The DMG contains `Recny.app` and an Applications shortcut; it does not automate Finder to apply a custom window layout.

### Windows

Requirements: Windows x64 and .NET 8 SDK.

```powershell
dotnet restore apps/windows/Recny.Windows/Recny.Windows.csproj
dotnet build apps/windows/Recny.Windows/Recny.Windows.csproj -c Release --no-restore
dotnet run --project apps/windows/Recny.Windows.Tests/Recny.Windows.Tests.csproj -c Release
dotnet publish apps/windows/Recny.Windows/Recny.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## Repository layout

```text
apps/macos/         Swift and SwiftUI macOS client
apps/windows/       .NET 8 Windows client and tests
packages/protocol/  Shared recording metadata contract
docs/               Product and engineering documentation
scripts/            macOS build and release scripts
site/               GitHub Pages website
```

Read [CONTRIBUTING.md](CONTRIBUTING.md) before opening a pull request. Report security problems through the process in [SECURITY.md](SECURITY.md).

## License

Recny is available under the [MIT License](LICENSE).
