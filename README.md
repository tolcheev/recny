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
