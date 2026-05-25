# Storage Format

## Default Root

```text
~/Recordings/TOrbitRecorder/
```

The MVP stores all recordings locally. The recording folder plus `metadata.json` is the canonical record.

The default root can be changed from Settings and is persisted locally. Reset to default returns the app to `~/Recordings/TOrbitRecorder/`.

The root contains both user recordings and app internals. In normal use, the app opens `Library/` from the `Open Recordings` button so the user does not need to browse `db/`, `logs/`, or internal `Inbox/` staging folders.

## Directory Layout

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

During an active or recoverable recording the session can also contain crash-recovery artifacts:

```text
source/segments/
  mic-0001.m4a
  system-0001.m4a
recovery.json
```

On a normal Stop, finalized non-failed recordings remove these recovery artifacts after `source/mic.m4a`, `source/system.m4a`, and export files have been created. Failed and interrupted sessions keep them for diagnostics and recovery.

## Inbox

`Inbox/` is an internal workflow area for recordings that are not ready for the main library. It is intentionally visible on disk for recovery and debugging, but it is not the normal user-facing folder.

- `Inbox/Unsorted/`: in-progress staging and crash-recovery candidates.
- `Inbox/Short/`: recordings below the short-session threshold. These are not errors.
- `Inbox/Failed/`: sessions where required capture, writing, or export failed.

## Library

`Library/YYYY/MM/` is the user-facing recordings folder and stores completed normal recordings.

Session directory format:

```text
YYYY-MM-DD_HH-mm_source_audio/
```

Examples of `source`:

- `zoom`
- `google-meet`
- `facetime`
- `manual`
- `unknown`

If two sessions would produce the same folder name, append a short stable id suffix.

## Required Session Files

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

Failed sessions may have missing final audio files, but `metadata.json` should be written whenever possible. Interrupted and failed sessions keep `recovery.json` and any files under `source/segments/`.

## SQLite Index

`db/app.sqlite` stores the MVP local index for the recordings list, post-call tags, and local library actions.

MVP rules:

- The app must not require SQLite to recover a recording.
- `metadata.json` remains the source of truth for a session.
- SQLite mirrors local recording metadata needed for list filtering by date, status, source app, title, and tags.
- If the SQLite database is empty, the app may rebuild the index by scanning `Library/` and `Inbox/` for `metadata.json`.

MVP tables:

```text
recordings
  id TEXT PRIMARY KEY
  title TEXT
  category TEXT
  participant TEXT
  status TEXT
  source_app TEXT
  started_at TEXT
  ended_at TEXT
  duration_sec REAL
  metadata_path TEXT
  folder_path TEXT

tags
  tag TEXT PRIMARY KEY

recording_tags
  recording_id TEXT
  tag TEXT
```

Deleting a local record removes the session folder and the SQLite index row. It does not call T-Orbit, cloud storage, or AI services.

## Metadata Schema

`metadata.json` MVP fields:

```json
{
  "id": "rec_2026-05-23_14-30-00_ab12cd",
  "schema_version": 1,
  "owner_id": "local:vlad",
  "workspace_id": "local:t-orbit-recorder",
  "mentor_id": "local:vlad",
  "title": "Student call",
  "started_at": "2026-05-23T14:30:00Z",
  "ended_at": "2026-05-23T15:12:18Z",
  "duration_sec": 2538,
  "recording_mode": "audio_only",
  "source": {
    "app_name": "Zoom",
    "bundle_id": "us.zoom.xos",
    "trigger": "autostart",
    "rule_id": "autostart.v2.zoom",
    "confidence": "high",
    "reason": "Zoom active with microphone activity."
  },
  "audio_tracks": [
    {
      "bitrate": 128000,
      "channels": 1,
      "codec": "aac",
      "container": "m4a",
      "duration_sec": 2538,
      "error": null,
      "file_size_bytes": 30212231,
      "kind": "microphone",
      "relative_path": "source/mic.m4a",
      "sample_rate": 48000,
      "signal": {
        "had_signal": true,
        "approximate_silence_ratio": 0.18,
        "clipping_detected": false
      },
      "status": "completed"
    },
    {
      "bitrate": 128000,
      "channels": 2,
      "codec": "aac",
      "container": "m4a",
      "duration_sec": 2538,
      "error": null,
      "file_size_bytes": 40155312,
      "kind": "system",
      "relative_path": "source/system.m4a",
      "sample_rate": 48000,
      "signal": {
        "had_signal": true,
        "approximate_silence_ratio": 0.24,
        "clipping_detected": false
      },
      "status": "completed"
    },
    {
      "bitrate": 96000,
      "channels": 2,
      "codec": "aac",
      "container": "m4a",
      "duration_sec": 2538,
      "error": null,
      "file_size_bytes": 30462102,
      "kind": "mixed",
      "relative_path": "export/mixed.m4a",
      "sample_rate": 48000,
      "signal": {
        "had_signal": true,
        "approximate_silence_ratio": 0.15,
        "clipping_detected": false
      },
      "status": "completed"
    },
    {
      "bitrate": 96000,
      "channels": 2,
      "codec": "aac",
      "container": "m4a",
      "duration_sec": 2538,
      "error": null,
      "file_size_bytes": 29877120,
      "kind": "mixed_balanced",
      "relative_path": "export/mixed_balanced.m4a",
      "sample_rate": 48000,
      "signal": {
        "had_signal": true,
        "approximate_silence_ratio": 0.15,
        "clipping_detected": false
      },
      "status": "completed"
    }
  ],
  "audio": {
    "health": {
      "status": "good",
      "warnings": []
    },
    "processing": {
      "balanced_mix_status": "done",
      "balanced_mix_path": "export/mixed_balanced.m4a",
      "analysis_path": "analysis/audio_analysis.json",
      "mic_gain_db": 3,
      "system_gain_db": -2,
      "warnings": []
    }
  },
  "markers": [
    {
      "id": "marker_important_001",
      "time_sec": 732,
      "label": "Important",
      "tags": ["important"],
      "created_at": "2026-05-23T14:42:12.000Z"
    },
    {
      "id": "marker_objection_001",
      "time_sec": 1724,
      "label": "Objection",
      "tags": ["objection"],
      "created_at": "2026-05-23T14:58:44.000Z"
    }
  ],
  "quality_warnings": [],
  "participants": [],
  "tags": [],
  "category": "student_call",
  "status": "needs_tagging",
  "ai": "not_started",
  "sync": "local_only"
}
```

## Field Notes

- `owner_id`, `workspace_id`, and `mentor_id` may use local placeholder ids in MVP.
- `participants` is an array because future versions may attach leads, students, or interview participants.
- `tags` stores the MVP post-call tag selection.
- `markers` stores manual in-call markers with elapsed recording seconds, a human-readable label, quick tags, and creation time.
- `file_size_bytes` is written for audio tracks that pass the integrity check.
- `signal` stores lightweight quality diagnostics for completed audio tracks.
- `quality_warnings` stores legacy user-facing warnings derived from signal metadata.
- `audio.health.status` is the current UI-facing audio state: `good`, `warning`, or `failed`.
- `audio.health.warnings` stores compact warning codes such as `mic_silent`, `system_silent`, `mic_too_quiet`, `system_too_quiet`, `clipping_detected`, `balanced_mix_failed`, and `only_one_track_available`.
- `audio.processing` stores derived audio export state for `export/mixed_balanced.m4a` and `analysis/audio_analysis.json`.
- `ai` exists now but AI is later.
- `sync` exists now but T-Orbit sync is later.

## MVP Tags

```text
#лид
#скрининг
#интервью
#важное
```

## Suggested Status Values

Recording `status`:

- `needs_tagging`
- `saved`
- `needs_review`
- `reviewed`
- `failed`
- `short_recording`

AI `ai`:

- `not_started`
- `queued`
- `processing`
- `completed`
- `failed`

For MVP, use `not_started`.

Sync `sync`:

- `local_only`
- `pending`
- `synced`
- `failed`

For MVP, use `local_only`.
