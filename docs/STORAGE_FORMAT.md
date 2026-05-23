# Storage Format

## Default Root

```text
~/Recordings/TOrbitRecorder/
```

The MVP stores all recordings locally. The recording folder plus `metadata.json` is the canonical record.

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
export/mixed.m4a
metadata.json
```

Failed sessions may have missing audio files, but `metadata.json` should be written whenever possible.

## SQLite Index

`db/app.sqlite` stores the MVP local index for post-call tags and recording list filtering.

MVP rules:

- The app must not require SQLite to recover a recording.
- `metadata.json` remains the source of truth for a session.
- SQLite mirrors local recording metadata needed for list and tag filtering.

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
    "app": "Zoom",
    "bundle_id": "us.zoom.xos",
    "trigger": "app_active",
    "rule_id": "local.enabled_app.zoom"
  },
  "audio_tracks": [
    {
      "kind": "microphone",
      "relative_path": "source/mic.m4a",
      "codec": "aac",
      "container": "m4a",
      "duration_sec": 2538,
      "sample_rate": 48000,
      "channels": 1,
      "status": "completed",
      "error": null
    },
    {
      "kind": "system",
      "relative_path": "source/system.m4a",
      "codec": "aac",
      "container": "m4a",
      "duration_sec": 2538,
      "sample_rate": 48000,
      "channels": 2,
      "status": "completed",
      "error": null
    },
    {
      "kind": "mixed",
      "relative_path": "export/mixed.m4a",
      "codec": "aac",
      "container": "m4a",
      "duration_sec": 2538,
      "sample_rate": 48000,
      "channels": 2,
      "status": "completed",
      "error": null
    }
  ],
  "participants": [],
  "tags": [],
  "category": "student_call",
  "status": "needs_tagging",
  "ai_status": "not_started",
  "sync_status": "local_only"
}
```

## Field Notes

- `owner_id`, `workspace_id`, and `mentor_id` may use local placeholder ids in MVP.
- `participants` is an array because future versions may attach leads, students, or interview participants.
- `tags` stores the MVP post-call tag selection.
- `ai_status` exists now but AI is later.
- `sync_status` exists now but T-Orbit sync is later.

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

AI `ai_status`:

- `not_started`
- `queued`
- `processing`
- `completed`
- `failed`

For MVP, use `not_started`.

Sync `sync_status`:

- `local_only`
- `pending`
- `synced`
- `failed`

For MVP, use `local_only`.
