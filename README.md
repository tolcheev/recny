# Recny

Recny is a local-first desktop app that records calls automatically. It captures microphone and system audio into separate files, creates a mixed copy, and keeps everything on the computer. On Apple Silicon, optional local models can transcribe a completed recording and generate editable notes.

[Download Recny](https://tolcheev.github.io/recny/) · [Инструкция на русском](https://tolcheev.github.io/recny/guide.html) · [Release 0.1.9](docs/RELEASE_NOTES_V0_1_9.md) · [Report a bug](https://github.com/tolcheev/recny/issues/new?template=bug_report.yml) · [Read the architecture](docs/ARCHITECTURE.md)

## Platform status

### macOS

- Current release: `v0.1.9`
- Apple Silicon, macOS 15 or newer
- Native Swift and SwiftUI menu bar app
- Ad-hoc signed and not Apple-notarized
- Optional local Parakeet transcription and Qwen3 4B notes, started manually after a recording

### Windows

- Current release: `v0.2.5-beta`
- Windows x64
- Native .NET 8 tray app
- Experimental beta distributed as a self-contained ZIP without an installer
- No local transcription or AI notes in this Windows build

## What Recny records

- microphone audio;
- system audio;
- a mixed listening copy;
- local metadata, tags, logs, and diagnostics.

Recny can watch supported call apps and start recording after stable call activity. Manual Start and Stop remain available when automatic detection misses a call.

## Install

### macOS

1. Download `Recny-v0.1.9-macOS.dmg` from the [Recny website](https://tolcheev.github.io/recny/).
2. Open the DMG and drag `Recny.app` into Applications.
3. Launch Recny from Applications.
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

## Local transcripts and notes on macOS

Open **Records → Transcript & Notes** to search a transcript, play verified timestamps, or generate notes with the **Meeting**, **Interview**, or **Mentoring** preset. **Process Locally** runs both steps; **More → Transcribe Only** recognizes speech, and **More → Regenerate Notes** reuses an existing verified transcript. Notes support source references, Markdown editing, copying, export, and local version history. Jobs are queued and can be cancelled or retried.

Models are not bundled with the app. Prepare Parakeet in **Settings → Local transcription**. For notes, use **Settings → Local Notes → Copy Runtime Install Command**, run the command, select **Check Setup**, then **Download & Prepare Model**. The isolated Python 3.11 runtime uses `mlx-lm==0.32.2` and `lm-format-enforcer==0.11.3`; the notes model is `mlx-community/Qwen3-4B-Instruct-2507-4bit`. Allow at least 10 GiB free for setup and processing, plus space for recordings. Downloads require internet; prepared processing runs offline without API keys or a cloud fallback.

Processing starts only on request. Recognition and generated notes may contain semantic errors or repeated facts; review them against the audio. **Interview** produces structured notes, not a complete expert evaluation. Mixed system audio has no individual speaker identification.

See the [full Russian user guide](https://tolcheev.github.io/recny/guide.html), [local setup and verification](docs/LOCAL_AI.md), and [dated validation report](docs/LOCAL_AI_VALIDATION.md).

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

Recording, metadata, tags, diagnostics, optional local transcription, and generated notes stay on the computer. Dependency installation and model preparation download files from external repositories. Recny does not upload calls, sync with T-Orbit, or run cloud AI. Read [Security and privacy](docs/SECURITY_PRIVACY.md) before using Recny for sensitive calls.

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
