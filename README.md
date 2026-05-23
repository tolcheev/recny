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
- Full system audio recording.
- Local file storage.
- Local settings stored on the Mac.
- Settings screen for recording toggles, auto-start rules, storage root, hotkey placeholders, and local privacy controls.
- `metadata.json` stored next to every recording.
- Compact post-call tagging after recording stops.
- MVP tags saved to `metadata.json` and `db/app.sqlite`.
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
- `docs/ROADMAP.md`: staged future work.
- `MANUAL_TESTING.md`: manual macOS MVP validation checklist and troubleshooting.

## Development Rules

- Prefer native macOS APIs: Swift, SwiftUI, AVFoundation, ScreenCaptureKit.
- Keep the recording engine testable separately from UI.
- Do not fake working audio capture.
- Add logs for recorder lifecycle events and failures.
- Update docs for every behavior change.
- Validate with `swift test` and `xcodebuild` when the relevant project files exist.

## Build macOS MVP Shell

```sh
scripts/build_macos.sh
```

The current shell is a SwiftPM-based macOS app target. The build script compiles it and assembles a local app bundle at `apps/macos/.build/app/TOrbitRecorder.app`.

Current recording implementation starts from the menu bar UI or Auto-start Engine v1 and writes `source/mic.m4a`, `source/system.m4a`, and a quick-listen `export/mixed.m4a` preview. System audio uses ScreenCaptureKit audio capture only; no screen video is written. The app shows a local recordings list backed by SQLite and can open folders, play mixed previews, edit titles/tags, and delete local records with confirmation.

Settings currently cover recording toggles, auto-start rules, storage actions, hotkey placeholders, and local privacy controls. Unimplemented controls are disabled in the UI.

Active settings are persisted locally with `UserDefaults`. MVP defaults keep system audio and mixed preview enabled, auto-start enabled, a 3 minute cooldown, 20 second detection duration, and a 60 second short-recording threshold. Audio quality, microphone device selection, hotkey capture, add marker, local-only mode, and Focus Mode reminder are visible as disabled placeholders until their runtime behavior exists.

## Run The App

From the repository root:

```sh
scripts/build_macos.sh
open -n apps/macos/.build/app/TOrbitRecorder.app
```

The app runs as a menu bar app. Use the menu bar icon for Start Recording, Stop Recording, Open Recordings Folder, Settings, and Quit.

## Manual MVP End-To-End Check

Detailed manual validation lives in `MANUAL_TESTING.md`.

Before the first recording, grant permissions to `TOrbitRecorder` in macOS System Settings:

- Privacy & Security -> Microphone
- Privacy & Security -> Screen & System Audio Recording

Manual full recording pass:

1. Build and open the app with the commands above.
2. Open Settings and confirm Recording has system audio and mixed preview enabled.
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
9. Add title, category, participant text, tags, and status, then save.
10. Confirm the recording appears in Recordings List.
11. Filter by a saved tag.
12. Click Open in Finder on the recording row and confirm the recording folder opens.

Short recording check:

1. Start a new recording.
2. Stop before 60 seconds with default settings.
3. Confirm status is `short_recording`, the session is under `Inbox/Short/`, and post-call tagging is not opened automatically.

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
