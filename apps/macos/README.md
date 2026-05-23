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
- `StubRecordingController` that changes state without writing audio.
- Compact post-call tagging panel after Stop.
- MVP tags saved to `metadata.json` and SQLite.
- Recording list filtering by tag.
- File-system storage with temporary sessions in `Inbox/Unsorted` and finalized sessions in `Library/YYYY/MM`.
- Basic OSLog logging.
- Permission descriptions for microphone and future system audio capture.

Real recording, autostart, screen capture, cloud upload, T-Orbit sync, and AI are intentionally not implemented in this step.
