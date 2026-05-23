# TOrbitRecorder macOS App

Minimal native macOS menu bar app for the MVP shell.

## Build

From the repository root:

```sh
scripts/build_macos.sh
```

The script uses SwiftPM because the current MVP shell has no Xcode project yet. It builds the `TOrbitRecorder` executable and assembles a local app bundle at:

```text
apps/macos/.build/app/TOrbitRecorder.app
```

## Current Scope

- Swift and SwiftUI.
- AppKit status item for menu bar commands.
- `AppState` core state layer.
- `RecordingController` protocol.
- Real microphone recording through AVFoundation into `source/mic.m4a`.
- Real system audio recording through ScreenCaptureKit audio output into `source/system.m4a`.
- ScreenCaptureKit is configured for audio capture only; no screen video stream is written.
- Mixed audio preview through AVFoundation into `export/mixed.m4a`.
- `StubRecordingController` that changes state without writing audio.
- Compact post-call tagging panel after Stop.
- MVP tags saved to `metadata.json` and SQLite.
- Recording list filtering by tag.
- File-system storage with temporary sessions in `Inbox/Unsorted` and finalized sessions in `Library/YYYY/MM`.
- Basic OSLog logging.
- Permission descriptions for microphone and Screen & System Audio Recording.

Autostart, screen video recording, cloud upload, T-Orbit sync, and AI are intentionally not implemented in this step.

## Microphone Smoke Test

If the current macOS user has granted microphone access to the terminal process, run:

```sh
swift run --package-path apps/macos TOrbitRecorderMicSmokeTest --duration 10 --root /tmp/TOrbitRecorderMicSmokeTest
```

If permission is `not_determined`, `denied`, or `restricted`, the smoke test exits before recording and prints the exact authorization status.

## System Audio Smoke Test

Play audible audio from another macOS app, then run:

```sh
swift run --package-path apps/macos TOrbitRecorderSystemAudioSmokeTest --duration 10 --root /tmp/TOrbitRecorderSystemAudioSmokeTest
```

The command writes `/tmp/TOrbitRecorderSystemAudioSmokeTest/source/system.m4a` and fails explicitly if ScreenCaptureKit cannot start or no system audio samples are captured. Grant Screen & System Audio Recording permission to the terminal process if macOS prompts for it, then rerun the command.
