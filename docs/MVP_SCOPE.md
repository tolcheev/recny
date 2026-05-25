# MVP Scope

## In Scope

- Native macOS desktop app.
- Menu bar first user experience.
- macOS Sequoia support.
- Apple Silicon support, with MacBook M4 Pro as the primary validation machine.
- Audio-only recording.
- Automatic recording start.
- Auto-start Engine v2 with active app detection, bundle id detection, browser call-title heuristics, whitelist/blacklist settings, cooldown, and minimum detection duration.
- Microphone capture.
- Full system audio capture.
- Separate microphone and system source files.
- Mixed `m4a` export.
- `metadata.json` next to every session.
- Manual tagging from Library after stop.
- MVP tags.
- Status values: `needs_tagging`, `saved`, `needs_review`, `reviewed`, `failed`, `short_recording`.
- SQLite recordings index for local filters and library actions.
- Recordings list filters: date, status, source app, title, and tags.
- Local recording actions: Open in Finder, Play mixed preview, edit title, add tags, delete with confirmation.
- Settings screen with preferred microphone selection, recording toggles, auto-start rules, storage root actions, disabled hotkey placeholders, and local privacy controls.
- Local storage under `~/Recordings/TOrbitRecorder/`.
- Local logs for lifecycle events and failures.
- Basic failure classification into `Inbox/Failed/`.
- Basic short recording classification into `Inbox/Short/`.

## Out Of Scope For MVP

- Screen recording.
- Cloud upload.
- T-Orbit backend sync.
- AI transcription, summaries, insights, or recommendations.
- Windows support.
- Telegram integration.
- External storage integration.
- Encryption.
- Retention or autodelete.
- Team permissions.

## Later But Planned

- Rich local library management beyond the MVP list/actions.
- Advanced tag management beyond the MVP fixed tag set.
- Screen recording.
- Uploading heavy files to external storage.
- T-Orbit metadata sync.
- AI module for mentor workflows.
- Windows client for students.
- Automatic interview recording workflows.

## MVP Constraints

- Do not use Electron.
- Do not add heavy dependencies.
- Prefer Swift, SwiftUI, AVFoundation, ScreenCaptureKit, SQLite.
- Keep the recording engine separate from UI.
- Do not fake audio capture.
- Stop and document macOS permission or API blockers.
- Keep all heavy files local in MVP.

## Acceptance Checklist

- Starting a supported call can start recording automatically.
- Microphone audio is written to `source/mic.m4a`.
- System audio is written to `source/system.m4a`.
- Mixed audio is written to `export/mixed.m4a`.
- `metadata.json` is created with the MVP schema.
- Stop does not open tagging automatically; the recording remains `needs_tagging` until edited from Library.
- Recordings shorter than the configured short-recording threshold are classified as `short_recording` and placed under `Inbox/Short/`; the MVP default is 60 seconds.
- Tags persist to `metadata.json` and `db/app.sqlite`.
- Recordings can be filtered by date, status, source app, title, and tag in the app.
- Local records can be opened, played, retitled, retagged, and deleted with confirmation.
- Settings persist locally and keep unimplemented controls disabled.
- Preferred microphone defaults to `Auto, recommended`, avoids AirPods/Bluetooth headset microphones when a built-in or external microphone is available, and never changes the macOS output device.
- Logs explain start, stop, success, short recording, and failure cases.
- The app can run without T-Orbit backend availability.

## Validation

When implementation exists:

- Run `swift test` for packages.
- Run `xcodebuild` for the macOS app when a full Xcode installation is active.
- Manually validate microphone and system audio capture on the target MacBook M4 Pro.
