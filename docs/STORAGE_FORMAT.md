# Storage Format

## Default Root

```text
~/Recordings/TOrbitRecorder/
```

The MVP stores all recordings locally. The recording folder plus `metadata.json` is the canonical record.

The default root can be changed from Settings and is persisted locally. Reset to default returns the app to `~/Recordings/TOrbitRecorder/`.

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
            segments/
              mic-0001.m4a
              system-0001.m4a
            mic.m4a
            system.m4a
          export/
            mixed.m4a
          metadata.json
          recovery.json
  db/
    app.sqlite
  logs/
```

## Inbox

`Inbox/` is for recordings that are not ready for the main library.

- `Inbox/Unsorted/`: valid recordings without a final category.
- `Inbox/Short/`: recordings below the short-session threshold.
- `Inbox/Failed/`: sessions where required capture, writing, or export failed.

## Library

`Library/YYYY/MM/` stores completed recordings.

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
source/segments/
export/mixed.m4a
metadata.json
recovery.json
```

Failed sessions may have missing final audio files, but `metadata.json` should be written whenever possible. Interrupted sessions keep `recovery.json` and any files under `source/segments/`.

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
    "trigger": "app_active",
    "rule_id": "local.enabled_app.zoom"
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
      "status": "completed"
    }
  ],
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
- `file_size_bytes` is written for audio tracks that pass the integrity check.
- `ai` exists now but AI is later.
- `sync` exists now but T-Orbit sync is later.

## MVP Tags

```text
#ученик
#лид
#клиент
#мок
#собес
#разбор
#продажа
#конфликт
#важное
#разобрать
#плохой_звук
#сильный_созвон
#просадка_продажи
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
