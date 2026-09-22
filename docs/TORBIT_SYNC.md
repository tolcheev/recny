# T-Orbit Sync

## Status

Future design only. T-Orbit sync is not part of the macOS audio-only MVP.

Do not add backend/client sync code in the MVP.

## Goal

Keep recording reliable and local-first, then sync business metadata to T-Orbit when explicitly enabled.

## Local App Role

The recorder app is responsible for:

- recording microphone and system audio
- creating local folders and `metadata.json`
- keeping a local SQLite index
- acting as local cache
- uploading heavy files later, if configured
- syncing metadata later

Recording must work without network access.

## T-Orbit Role

T-Orbit is the future source of truth for business data:

- users
- mentors
- students
- recording cards
- tags
- transcripts
- Markdown notes
- comments
- permissions
- links to external files

T-Orbit should store metadata and links, not heavy media blobs.

## Heavy Files

Heavy files stay outside T-Orbit:

- local MVP storage
- future external object storage
- future provider-specific upload queue

T-Orbit stores link records with provider, type, size, checksum, permissions, and audit metadata.

## Sync States

Local metadata should support:

- `local_only`: do not sync
- `pending_sync`: queued for upload/sync
- `synced`: remote is up to date
- `sync_failed`: retry needed
- `conflict`: local and remote changed

## API Draft

Draft contract lives in:

```text
packages/protocol/torbit-recordings.openapi.yaml
```

Core future endpoints:

- `POST /recordings`
- `PATCH /recordings/{id}`
- `GET /recordings`
- `GET /recordings/{id}`
- `POST /recordings/{id}/tags`
- `POST /recordings/{id}/storage-links`
- `POST /recordings/{id}/transcripts`
- `POST /recordings/{id}/notes`
- `GET /students/{id}/recordings`

## Recording Payload

Minimum future payload:

- `id`
- `owner_id`
- `workspace_id`
- `mentor_id`
- `student_id`
- `title`
- `started_at`
- `duration`
- `source_app`
- `trigger`
- `tags`
- `status`
- `storage_links`
- `transcript_status`
- `note_status`

## Offline Behavior

- Save locally first.
- Queue sync operations.
- Retry failed operations.
- Never block recording because T-Orbit is unavailable.
- Resolve conflicts in a later phase.

## Security

- Auth token for user/session.
- Device token for recorder client.
- Token revocation.
- Audit log for sync actions.
- No heavy files in T-Orbit application storage.
