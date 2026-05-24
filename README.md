# T-Orbit Recorder

T-Orbit Recorder is a lightweight native macOS app for automatic audio recording of calls without OBS.

The MVP is a local-first recorder for Vlad, a QA/AQA mentor, who needs reliable recordings of student calls, lead sales calls, interview debriefs, and important or sensitive conversations.

## MVP

- macOS only.
- Target machine: MacBook M4 Pro.
- Target OS: macOS Sequoia.
- Audio-only recording.
- Automatic recording start.
- Auto-start v1 rule engine using active app, microphone activity, system audio activity, allowlist/blocklist, cooldown, and minimum detection duration.
- Microphone recording.
- Deterministic microphone input selection that avoids AirPods/Bluetooth headset mics when a built-in or external microphone is available.
- Full system audio recording.
- Local file storage.
- Local settings stored on the Mac.
- Settings screen for preferred microphone, recording toggles, auto-start rules, storage root, hotkey placeholders, and local privacy controls.
- `metadata.json` stored next to every recording.
- Compact post-call tagging after recording stops.
- MVP tags saved to `metadata.json` and `db/app.sqlite`.
- Tag dialog supports quick tags, custom tags, and status selection without permanent tag controls on the main screen.
- Local recordings list with filters by date, status, source app, title, and tag.
- No Electron.
- No screen recording, cloud upload, T-Orbit sync, AI, or Windows support in MVP.

## Default Storage

```text
~/Recordings/TOrbitRecorder/
  Inbox/
    Unsorted/
    Short/
    Failed/
  Library/
    YYYY/
      MM/
        YYYY-MM-DD_HH-mm_source_audio/
          source/
            mic.m4a
            system.m4a
          export/
            mixed.m4a
          metadata.json
  db/
    app.sqlite
  logs/
```

`db/app.sqlite` stores the local recordings index for list filtering and quick library actions. The recording folder and `metadata.json` remain the canonical record.

## Repository Layout

```text
apps/macos/         Native macOS menu bar app
packages/core/      Testable recording engine and local domain logic
packages/protocol/  Shared storage and metadata contracts
docs/               Product and engineering documentation
samples/scripts/    Local helper scripts and experiments
tests/              Integration fixtures and test assets
```

## Documentation

- `docs/PRODUCT_SPEC.md`: product goal, user, scenarios, and success criteria.
- `docs/MVP_SCOPE.md`: exact MVP boundaries.
- `docs/ARCHITECTURE.md`: client architecture and future integration boundaries.
- `docs/RECORDING_ENGINE.md`: recorder lifecycle and capture rules.
- `docs/AUTOSTART_RULES.md`: automatic start policy.
- `docs/STORAGE_FORMAT.md`: folder layout and metadata schema.
- `docs/SECURITY_PRIVACY.md`: local-first privacy constraints.
- `docs/UI_REDESIGN.md`: MVP UI structure and redesign notes.
- `docs/QA_CHECKLIST.md`: focused manual QA checklist for install, permissions, recording, UI, auto-start, and edge cases.
- `docs/BUG_REPORT_TEMPLATE.md`: copy/paste bug report format for fast handoff back to Codex.
- `docs/DEVELOPMENT_WORKFLOW.md`: branch, PR, validation, and release workflow for post-MVP development.
- `docs/ROADMAP.md`: staged future work.
- `MANUAL_TESTING.md`: manual macOS MVP validation checklist and troubleshooting.

## Development Rules

- Prefer native macOS APIs: Swift, SwiftUI, AVFoundation, ScreenCaptureKit.
- Keep the recording engine testable separately from UI.
- Do not fake working audio capture.
- Add logs for recorder lifecycle events and failures.
- Update docs for every behavior change.
- Validate with `swift test` and `xcodebuild` when the relevant project files exist.

## Build

```sh
./scripts/build_macos.sh
```

The current shell is a SwiftPM-based macOS app target. The build script compiles it and assembles a local app bundle at `apps/macos/.build/app/TOrbitRecorder.app`. This `.build/app` bundle is a development artifact, not the normal launch location.

The build script injects app metadata into the bundle:

- app version: `v0.1.0-mvp`
- build date
- git commit hash

## Package

Create a shareable local package in `dist/`:

```sh
./scripts/package_macos.sh
```

This creates:

```text
dist/TOrbitRecorder.app
dist/TOrbitRecorder-v0.1.0-macOS.zip
dist/INSTALL.md
```

`dist/INSTALL.md` is included in the zip and explains permissions, restart behavior, recordings location, and uninstall steps.

## Install

Install the packaged app into `/Applications` and open it:

```sh
./scripts/install_macos.sh
```

The installer packages the app, asks a running TOrbitRecorder process to quit before replacement, copies the app bundle to `/Applications/TOrbitRecorder.app`, opens it, and prints next steps.

Dry-run the installer without copying or opening the app:

```sh
DRY_RUN=1 ./scripts/install_macos.sh
```

## Run

Use the installed app for normal manual testing:

```sh
open /Applications/TOrbitRecorder.app
```

Use `dist/` for shareable local artifacts and `/Applications/TOrbitRecorder.app` for a normal macOS launch. Do not use `apps/macos/.build/app/TOrbitRecorder.app` except when debugging the build script output directly.

Current recording implementation starts from the menu bar UI or Auto-start Engine v2 and writes `source/mic.m4a`, `source/system.m4a`, and a quick-listen `export/mixed.m4a` preview. System audio uses ScreenCaptureKit audio capture only; no screen video is written. The main window is a compact recorder surface with one primary Start/Stop action; Library and Diagnostics open as separate windows.

Settings currently cover preferred microphone selection, recording toggles, auto-start rules, storage actions, hotkey placeholders, and local privacy controls. Unimplemented controls are disabled in the UI.

Active settings are persisted locally with `UserDefaults`. MVP defaults keep microphone selection on `Auto, recommended`, Standard audio quality, system audio and mixed preview enabled, auto-start enabled, a 3 minute cooldown, 20 second detection duration, and a 60 second short-recording threshold. Hotkey capture, add marker, local-only mode, and Focus Mode reminder are visible as disabled placeholders until their runtime behavior exists.

Settings also includes an About section with the app version, build date, git commit hash, and local storage path.

## Uninstall

Quit the app and remove the installed bundle:

```sh
osascript -e 'tell application "TOrbitRecorder" to quit' || true
rm -rf /Applications/TOrbitRecorder.app
```

This keeps local recordings. To delete all MVP recording data too:

```sh
rm -rf ~/Recordings/TOrbitRecorder
```

## Troubleshooting

Permissions are tied to the app bundle that macOS sees. For manual testing, install and run the same bundle every time:

```sh
./scripts/install_macos.sh
open /Applications/TOrbitRecorder.app
```

If the Screen & System Audio Recording toggle is enabled but the app still reports missing permission, quit TOrbitRecorder and reopen `/Applications/TOrbitRecorder.app`. macOS often requires a process restart after this permission changes.

Grant permissions in:

- System Settings -> Privacy & Security -> Microphone
- System Settings -> Privacy & Security -> Screen & System Audio Recording

Recordings are stored locally in `~/Recordings/TOrbitRecorder/`.

## Microphone Input Policy

`Auto, recommended` is resolved by the core `DevicePriorityResolver`. It selects only the microphone input device and does not change the macOS output device. Priority is:

1. External microphones such as Shure MV7, Hollyland, USB microphones, and audio interfaces.
2. Built-in MacBook microphone.
3. AirPods and other Bluetooth headset microphones.

AirPods or Bluetooth headset microphones are used only when no other input device is available. If that fallback is used, the UI shows:

```text
Only Bluetooth headset microphone is available. Recording quality may be degraded.
```

## Developer Artifact

From the repository root:

```sh
scripts/build_macos.sh
open -n apps/macos/.build/app/TOrbitRecorder.app
```

The app runs as a menu bar app. Use the menu bar icon for Show Window, Start Recording or Stop Recording, Play Last Recording, Open Last Recording Folder, Open Library, Settings, Diagnostics, and Quit.

For normal dev usage prefer:

```sh
./scripts/install_macos.sh
open /Applications/TOrbitRecorder.app
```

The menu bar app provides Show Window, Start Recording or Stop Recording, Play Last Recording, Open Last Recording Folder, Open Library, Settings, Diagnostics, and Quit.

## Manual MVP End-To-End Check

Detailed manual validation lives in `MANUAL_TESTING.md`.

Before the first recording, grant permissions to `TOrbitRecorder` in macOS System Settings:

- Privacy & Security -> Microphone
- Privacy & Security -> Screen & System Audio Recording

Manual full recording pass:

1. Build and open the app with the commands above.
2. Open Settings and confirm Recording has `Preferred microphone` set to `Auto, recommended`, system audio enabled, and mixed preview enabled.
3. Click Start Recording from the menu bar item or main panel.
4. Speak into the microphone and play audible audio from another macOS app.
5. Record for longer than the short-recording threshold. The MVP default is 60 seconds; use at least 65 seconds for the normal post-call tagging path.
6. Click Stop Recording.
7. Confirm the session folder contains:

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

8. Confirm the post-call tagging panel opens.
9. Add title, participant text, and tags, then save.
10. Open Library and confirm the recording appears in the recent recordings list.
11. Filter by a saved tag.
12. Click Open in Finder on the recording row and confirm the recording folder opens.

Short recording check:

1. Start a new recording.
2. Stop before 60 seconds with default settings.
3. Confirm Last Recording shows `Short recording`, the session is under `Inbox/Short/`, and post-call tagging is not opened automatically.

YouTube plus voice check:

1. Open a YouTube video in a browser and keep the browser audible through the normal Mac output device.
2. Start recording in TOrbit Recorder.
3. Speak into the selected microphone while the YouTube audio is playing.
4. Stop recording and play `export/mixed.m4a`.
5. Confirm the mixed preview contains both your voice and the YouTube audio.

Permission error check:

1. Revoke Microphone or Screen & System Audio Recording permission for `TOrbitRecorder` in System Settings.
2. Quit and reopen the app.
3. Start recording.
4. Confirm the UI shows an error state and the logs explain the blocked permission.

## Smoke Tests

Microphone smoke test for the current terminal process:

```sh
swift run --package-path apps/macos TOrbitRecorderMicSmokeTest --duration 10 --root apps/macos/.build/e2e/mic
```

If this prints `authorization_status=not_determined`, `denied`, or `restricted`, the terminal process does not have microphone permission. Run the app manually and grant permission to `TOrbitRecorder`, or grant microphone access to the terminal process before re-running the CLI smoke test.

System audio smoke test:

```sh
swift run --package-path apps/macos TOrbitRecorderSystemAudioSmokeTest --duration 10 --root apps/macos/.build/e2e/system
```

Play audio from another macOS app while this command runs. The command writes `source/system.m4a` and fails explicitly if ScreenCaptureKit cannot start or if no samples are captured.
