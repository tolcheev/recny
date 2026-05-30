# ToRec macOS App

Native macOS menu bar app for the MVP shell.

## Build

From the repository root:

```sh
scripts/build_macos.sh
```

The script uses SwiftPM because the current MVP shell has no Xcode project yet. It builds the `TOrbitRecorder` executable and assembles a local app bundle at:

```text
apps/macos/.build/app/ToRec.app
```

## Current Scope

- Swift and SwiftUI.
- AppKit status item for menu bar commands.
- `AppState` core state layer.
- `RecordingController` protocol.
- Real microphone recording through AVFoundation into `source/mic.m4a`.
- Real system audio recording through the native macOS audio capture path into `source/system.m4a`.
- System audio capture is audio-only; no screen video stream is written.
- Mixed audio preview through AVFoundation into `export/mixed.m4a`.
- Crash recovery metadata in `recovery.json` and active segment files under `source/segments/`.
- Recoverable interrupted recordings surfaced in the UI with a Recover Recording action.
- Auto-start Engine v2 with active app detection, process-audio signals, browser call-title heuristics, allowlist/blocklist settings, cooldown, and minimum detection duration.
- Settings screen persisted locally with sections for Recording, Auto-start, Storage, Hotkeys, and Privacy.
- `StubRecordingController` that changes state without writing audio.
- Compact post-call tagging panel after Stop.
- MVP tags saved to `metadata.json` and SQLite.
- Local recordings list backed by `~/Recordings/TOrbitRecorder/db/app.sqlite`.
- Recording filters by date, status, source app, title, and tag.
- Local library actions: Open in Finder, Play mixed preview, share through the macOS share sheet, trim a local clip, capture a full-screen still screenshot, optionally transcribe locally after setup, edit title, add tags, and delete with confirmation.
- File-system storage with temporary sessions in `Inbox/Unsorted`, short sessions in `Inbox/Short`, failed sessions in `Inbox/Failed`, and finalized sessions in `Library/YYYY/MM`.
- Basic OSLog logging.
- Permission descriptions for microphone and Screen & System Audio Recording.

Screen video recording, cloud upload, T-Orbit sync, and AI are intentionally not implemented in this step.

## Settings

Active MVP settings:

- Recording: system audio enabled, mixed preview enabled.
- Auto-start: enabled flag, whitelist apps, blacklist apps, detection duration, cooldown minutes, short recording threshold.
- Storage: root folder, choose folder, open folder, reset to default.
- Privacy: show recording indicator.

Disabled placeholders:

- Audio quality preset beyond the current Standard AAC 48 kHz profile.
- Microphone device selection beyond the default system input.
- Editable custom hotkey capture.
- Start/stop global hotkey.
- Add marker hotkey.
- Local-only mode toggle.
- Focus Mode reminder.

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
