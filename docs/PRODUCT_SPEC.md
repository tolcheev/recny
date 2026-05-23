# Product Spec

## Product Goal

T-Orbit Recorder is a lightweight native macOS app for automatic audio recording of calls without OBS.

The MVP must solve one problem: when an important call happens, Vlad should get a reliable local audio recording without manually configuring OBS, routing tools, cloud services, or AI workflows.

## Primary User

Primary MVP user: Vlad, QA/AQA mentor.

Primary scenarios:

- Calls with students.
- Sales calls with leads.
- Interview debriefs and mock interview reviews.
- Conflict, escalation, or otherwise important calls where a factual record matters.

Future users:

- Other mentors.
- Students using a Windows client.
- Teams that need automatic interview recording.

## Target Platform

- macOS only for MVP.
- Target OS: macOS Sequoia.
- Target device: MacBook M4 Pro.
- Apple Silicon first.

## MVP Value Proposition

The app should quietly run as a desktop recorder, detect when a call should be recorded, capture microphone and full system audio, and store the result locally in a predictable folder structure.

The MVP is intentionally not a media studio, meeting bot, cloud recorder, or T-Orbit backend feature.

## MVP Capabilities

- Automatic recording start based on local rules.
- Auto-start Engine v1 using active app, bundle id, microphone activity, system audio activity, whitelist/blacklist, cooldown, and minimum detection duration.
- Microphone audio recording.
- Full system audio recording.
- Separate source tracks for microphone and system audio.
- Mixed audio export for quick playback.
- `metadata.json` saved next to each recording.
- Compact post-call tagging after stop.
- MVP tags saved to `metadata.json` and local SQLite.
- Recording list filtering by date, status, source app, title, and tag.
- Local library actions: Open in Finder, Play mixed preview, edit title, add tags, and delete with confirmation.
- Local storage under `~/Recordings/TOrbitRecorder/`.
- Lifecycle and failure logs.

## Required Session Output

Each valid recording session must create:

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

Short, failed, or unsorted sessions may live in `Inbox/` until the app can classify or promote them into `Library/`.

## Metadata Requirement

MVP metadata must include:

- `id`
- `schema_version`
- `owner_id`
- `workspace_id`
- `mentor_id`
- `title`
- `started_at`
- `ended_at`
- `duration_sec`
- `recording_mode`
- source app name, bundle id, trigger, and rule id
- audio tracks
- participants
- tags
- category
- status
- AI state
- sync state

AI and sync fields exist in the schema even though AI processing and T-Orbit sync are later features.

## Explicit Non-Goals For MVP

- Screen recording.
- Cloud upload.
- T-Orbit sync.
- AI transcription, summaries, scoring, or recommendations.
- Windows support.
- Telegram integration.
- Multi-user administration.
- Retention or autodelete.
- Encryption.

## Success Criteria

- A real call can be recorded as microphone audio plus system audio.
- The app starts recording automatically when a configured local rule matches.
- A completed session has both source tracks, a mixed export, and metadata.
- Stopping a recording opens post-call tagging.
- Closing post-call tagging without saving leaves status as `needs_tagging`.
- Recordings shorter than 60 seconds are stored under `Inbox/Short/` with status `short_recording`.
- Saved recordings are queryable through the local SQLite index.
- Failed capture is visible in `Inbox/Failed/` or logs, not silently ignored.
- Short accidental captures can be separated into `Inbox/Short/`.
- The recording engine can be tested separately from SwiftUI.
- No heavy dependencies or Electron are introduced.
