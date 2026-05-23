# Roadmap

## MVP: Local macOS Audio Recorder

Goal: reliable automatic audio recording on Vlad's MacBook M4 Pro without OBS.

Scope:

- macOS Sequoia.
- Audio-only recording.
- Auto-start Engine v1.
- Microphone capture.
- Full system audio capture.
- Local storage.
- Per-session `metadata.json`.
- Post-call tagging.
- Recordings list filtering by date, status, source app, title, and tag.
- Local SQLite index with `recordings`, `tags`, and `recording_tags`.
- Mixed `m4a` export.
- Logs for lifecycle and failures.

## Next: Local Library Polish

Goal: make local recordings easier to browse and manage beyond the MVP list.

Candidate work:

- Search by category and participant.
- Multi-tag filter combinations.
- Bulk edit and delete.
- Editable categories.
- Advanced tag management.
- Better handling for `Inbox/Unsorted/`, `Inbox/Short/`, and `Inbox/Failed/`.

## Next: Better Autostart

Goal: reduce missed recordings and false positives.

Candidate work:

- More precise app detection.
- Better audio activity heuristics.
- Per-app local rules.
- Better cooldowns and duplicate-session detection.
- Manual correction of category and source metadata.

## Future: Screen And External Storage

Goal: support richer evidence and reduce local disk pressure.

Candidate work:

- Optional screen recording.
- External storage upload for heavy files.
- Upload retry queue.
- Local/remote file link tracking.
- Storage health checks.

## Future: T-Orbit Sync

Goal: connect recordings to T-Orbit workflows without moving capture logic into the backend.

Expected split:

- Recorder uploads or references heavy files.
- T-Orbit stores metadata, tags, transcripts, notes, permissions, and links.
- T-Orbit does not become required for local MVP recording.

## Future: AI Module For Mentors

Goal: help mentors review calls faster.

Candidate work:

- Transcription.
- Student call summaries.
- Lead call notes.
- Interview debrief summaries.
- Action items.
- Mentor-facing insights.

AI is not in MVP.

## Future: Windows Client

Goal: support student-side and interview-side recording workflows.

Candidate work:

- Windows client for students.
- Automatic interview recording.
- Cross-platform metadata compatibility.

Windows is not in MVP.
