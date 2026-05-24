# T-Orbit Sync Technical Design

## Status

Future design only. T-Orbit sync is not part of the macOS audio-only local MVP.

This document defines the intended boundary between the local recorder app and the future T-Orbit platform. It does not implement a backend client, upload pipeline, authentication flow, or T-Orbit backend.

## Goals

T-Orbit sync should let the local recorder create and update business-facing recording cards in T-Orbit while keeping heavy media files out of the T-Orbit application database.

The future T-Orbit platform is expected to own:

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

Heavy audio/video files are not stored in T-Orbit. They remain local in MVP and can later be uploaded to external object storage. T-Orbit stores metadata and links.

## Non-Goals

- Do not store `source/mic.m4a`, `source/system.m4a`, `export/mixed.m4a`, screen video, or other heavy files in T-Orbit.
- Do not make the recorder dependent on network availability.
- Do not block local recording if sync fails.
- Do not add sync to the MVP build.
- Do not implement backend/client code in this repository step.

## Local App Role

### Recorder

The macOS app is the capture client. It owns:

- microphone capture
- system audio capture
- mixed audio preview creation
- local session folder creation
- `metadata.json`
- local SQLite index
- crash recovery files

Recording must remain reliable even when T-Orbit is offline or unreachable.

### Local Cache

The local app keeps a cache of recording metadata for fast Library UX and offline work.

Canonical local artifacts:

- session folder
- `metadata.json`
- `db/app.sqlite`
- logs

The local cache may contain T-Orbit ids and sync state once sync exists.

### Uploader Later

The app can later upload heavy files to external storage, not to T-Orbit. Possible providers:

- T-Orbit-managed object storage
- S3-compatible storage
- another explicitly configured external provider

After upload, the app sends storage links and file metadata to T-Orbit.

### Sync Client

The app acts as a sync client for metadata:

- create recording card in T-Orbit
- patch recording title/status/category/source metadata
- add tags
- attach external storage links
- attach transcript metadata
- attach notes
- read remote recording cards
- reconcile local and remote changes later

## T-Orbit Role

T-Orbit is the source of truth for business entities and collaboration state.

T-Orbit owns:

- users and auth
- mentors
- students
- workspaces
- recording cards
- tag taxonomy and normalized tags
- transcript records and statuses
- Markdown notes
- comments
- permissions and sharing rules
- external storage links
- audit log

T-Orbit does not own heavy media blob storage. It stores link records, metadata, checksums, provider names, and permissions.

## Sync States

Local recording metadata should track sync status.

Allowed states:

- `local_only`: recording is intentionally local and must not sync.
- `pending_sync`: recording has local changes queued for T-Orbit.
- `synced`: local metadata is synced with T-Orbit.
- `sync_failed`: last sync attempt failed; retry is allowed.
- `conflict`: local and remote changes need resolution.

Recommended local metadata extension:

```json
{
  "sync": "pending_sync",
  "torbit": {
    "recording_id": "rec_123",
    "workspace_id": "workspace_123",
    "last_synced_at": "2026-05-24T10:00:00Z",
    "last_sync_error": null,
    "remote_version": 3
  }
}
```

The existing MVP `sync` value remains `local_only` until sync is implemented.

## API Surface

Draft OpenAPI contract:

```text
packages/protocol/torbit-recordings.openapi.yaml
```

Required endpoints:

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

Core recording card fields:

- `id`: recording id. Local app may provide a client-generated id.
- `owner_id`: user who owns the recording.
- `workspace_id`: T-Orbit workspace.
- `mentor_id`: mentor responsible for the call.
- `student_id`: optional student or learner id.
- `title`: human-readable title.
- `started_at`: recording start time.
- `duration`: duration in seconds.
- `source_app`: app that triggered or hosted the call, for example Zoom or browser.
- `trigger`: `manual`, `autostart`, or future trigger type.
- `tags`: normalized tag list.
- `status`: business status.
- `storage_links`: external media file links.
- `transcript_status`: transcript lifecycle state.
- `note_status`: notes lifecycle state.

Example:

```json
{
  "id": "rec_2026-05-24_10-30-00_ab12cd34",
  "owner_id": "user_vlad",
  "workspace_id": "workspace_torbit",
  "mentor_id": "mentor_vlad",
  "student_id": "student_ivan",
  "title": "AQA mentoring call",
  "started_at": "2026-05-24T10:30:00Z",
  "duration": 2538,
  "source_app": "Zoom",
  "trigger": "autostart",
  "tags": ["#ученик", "#разбор"],
  "status": "needs_review",
  "storage_links": [
    {
      "provider": "s3",
      "kind": "mixed_audio",
      "url": "https://storage.example/recordings/rec_123/mixed.m4a",
      "mime_type": "audio/mp4",
      "size_bytes": 30462102,
      "checksum_sha256": "..."
    }
  ],
  "transcript_status": "not_started",
  "note_status": "draft"
}
```

## Storage Links

Storage links point to external files. T-Orbit records enough metadata to display, authorize, and audit access.

Recommended fields:

- `provider`
- `kind`: `microphone_audio`, `system_audio`, `mixed_audio`, `screen_video`, or future media kind.
- `url`
- `mime_type`
- `size_bytes`
- `duration_sec`
- `checksum_sha256`
- `created_at`
- `expires_at`

Raw source tracks should be more restricted than mixed preview links.

## Transcripts

Transcript endpoint stores transcript metadata and optional text payloads. AI generation is future work and not part of MVP.

Possible transcript states:

- `not_started`
- `queued`
- `processing`
- `completed`
- `failed`

The transcript record can include:

- language
- provider
- status
- text or external text link
- segments later
- error message

## Notes

Notes are Markdown-oriented business notes for mentors.

Possible note states:

- `none`
- `draft`
- `published`

Notes should support:

- author id
- Markdown body
- source: manual, import, AI later
- timestamps
- audit trail

## Comments

Comments are not in the required first OpenAPI endpoint list, but T-Orbit should own them later because comments depend on users, permissions, and notification rules.

Future endpoint shape:

```text
POST /recordings/{id}/comments
GET /recordings/{id}/comments
```

## Offline Behavior

### Local First

Recording and tagging must work without network access. Local writes happen first:

1. write audio files
2. write `metadata.json`
3. update SQLite
4. enqueue sync operation if sync is enabled

### Retry Queue

The app should maintain a durable retry queue for future sync:

- operation id
- recording id
- operation type
- payload
- attempt count
- next retry time
- last error

Retries should use exponential backoff and stop when local-only mode is enabled.

### Conflict Resolution Later

Initial sync can be last-writer-wins for simple fields if versioning exists, but conflict state must be available.

Potential conflict cases:

- local title changed while remote title changed
- local tags changed while remote tags changed
- local status changed after remote review
- remote recording deleted or access revoked

Conflict resolution is a later product task. The MVP future sync client can mark `conflict` and keep local data intact.

## Security

### Auth Token

T-Orbit API calls require a user/workspace scoped auth token.

Requirements:

- scoped access
- expiry
- refresh or re-login flow
- secure local storage in Keychain
- no token in logs

### Device Token

The recorder should identify the device/client installation.

Use cases:

- audit which device created a recording
- revoke a lost device
- debug sync failures
- rate-limit or isolate a client

### Revocation

T-Orbit must be able to revoke:

- user session token
- device token
- workspace access
- recording access
- storage link access

The local app must handle revocation by stopping sync and keeping local recordings local unless the user deletes them.

### Audit Log

T-Orbit should audit:

- recording created
- recording patched
- tags changed
- storage link attached
- transcript attached
- note attached
- permission changes
- sync failures caused by auth/permission issues

The local app should also log sync attempts and failures locally without recording sensitive content.

### No Heavy Files in T-Orbit

T-Orbit API must reject direct heavy media uploads. APIs accept metadata and external storage links only.

## Privacy Rules

- Local-only mode blocks all sync.
- Sync should be opt-in until product readiness.
- Sensitive source tracks should not be uploaded by default.
- Storage links should be permissioned, revocable, and auditable.
- T-Orbit should avoid storing raw transcript or note content unless the workspace explicitly enables those features.

## Implementation Phases

### Phase 1: Metadata Sync

- create recording cards
- patch title/status/category/source
- sync tags
- preserve local-first behavior
- implement retry queue

### Phase 2: Storage Links

- upload media to external storage
- attach storage links to T-Orbit
- link mixed preview first
- restrict source tracks

### Phase 3: Transcripts and Notes

- attach transcripts
- attach Markdown notes
- support note and transcript status
- prepare comments/permissions UX

### Phase 4: Conflict Handling

- remote version checks
- conflict state in UI
- user-guided resolution
- audit history

## Open Questions

- Should the local recording id become the T-Orbit recording id, or should T-Orbit issue canonical ids?
- Should local-only recordings be visible to T-Orbit as redacted placeholders, or completely absent?
- Which external storage provider is the default?
- Are transcripts stored directly in T-Orbit or as external text links?
- What permission model applies to mentor/student recording visibility?
- What data must be deleted locally when remote access is revoked?
