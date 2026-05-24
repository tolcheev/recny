# Telegram Integration Technical Design

## Status

Future design only. Telegram integration is not part of the macOS audio-only local MVP.

This document defines a possible integration path without adding runtime code, bot credentials, network calls, cloud upload, or Telegram-dependent behavior to the MVP.

## Goals

Telegram can become a lightweight notification and command surface around local recordings. It should help a mentor quickly know that a recording exists, add lightweight metadata, and share links or notes when explicitly enabled.

Telegram must not become the primary storage for heavy audio files. The canonical MVP record remains the local recording folder plus `metadata.json`; future T-Orbit sync can store metadata, permissions, transcripts, notes, and external storage links.

## Non-Goals

- Do not use Telegram as the primary storage for `mic.m4a`, `system.m4a`, or `mixed.m4a`.
- Do not send sensitive audio by default.
- Do not bypass local-only mode.
- Do not implement granular access control inside Telegram.
- Do not add AI summaries or transcription as part of this integration.
- Do not add Telegram integration to the MVP build.

## Use Cases

### New Recording Notification

When a recording finishes, the app can send an allowlisted Telegram chat a short notification:

- recording title or fallback `Untitled recording`
- status: `needs_tagging`, `saved`, `needs_review`, `reviewed`, `failed`, or `short_recording`
- duration
- source app
- local or external link availability
- quick command hints

Example:

```text
New recording saved
rec_2026-05-24_10-30-00_ab12cd34
Zoom · 42:18 · Needs tag

/tag rec_2026-05-24_10-30-00_ab12cd34 #разбор
/status rec_2026-05-24_10-30-00_ab12cd34 needs_review
```

### Quick Tags via Reply

A mentor can reply to the notification or send a command to add tags without opening the desktop UI.

Expected behavior:

- validate chat id against allowlist
- validate `recording_id`
- normalize tags with the same rules as the desktop app
- update `metadata.json`
- update local SQLite index
- append an audit log entry
- send a short confirmation

### Summary or Markdown Note

Telegram can receive or store a human-written note attached to a recording. This is not AI transcription.

Possible inputs:

- `/note rec_id text`
- reply to a recording notification with a note prefix
- future Markdown summary generated outside MVP and explicitly sent

The note should be persisted as metadata or a future notes file/index record, then mirrored to T-Orbit when T-Orbit sync exists.

### File Links

Telegram messages can carry links to files stored outside Telegram, for example future external object storage.

Rules:

- local file paths should not be sent to Telegram unless explicitly configured for local-only debugging
- external links must be permissioned and revocable
- links should be recorded in metadata or a future sync table
- T-Orbit should own durable metadata and permissions

### Small Preview Audio

If explicitly enabled and if size limits allow, the integration can send a small `export/mixed.m4a` preview.

Rules:

- disabled by default
- never send `source/mic.m4a` or `source/system.m4a` by default
- check file size before upload
- prefer short previews or compressed excerpts in future versions
- log every upload attempt and result

## Telegram Is Not Heavy File Storage

Telegram file upload is useful for convenience, not for durable recording storage. Heavy audio files should remain local in MVP and can later move to external storage designed for:

- durable retention
- access control
- revocation
- auditability
- predictable file size limits
- T-Orbit metadata references

Telegram should store notifications, commands, optional notes, and maybe small previews. It should not be treated as the source of truth.

## Bot Commands

### `/tag rec_id #tag`

Adds one or more tags to a recording.

Examples:

```text
/tag rec_2026-05-24_10-30-00_ab12cd34 #разбор
/tag rec_2026-05-24_10-30-00_ab12cd34 #лид #важное
```

Validation:

- chat id is allowlisted
- recording exists
- tags normalize successfully
- local storage is writable

Result:

- update `metadata.json`
- update SQLite tags index
- respond with current tag list

### `/status rec_id reviewed`

Updates recording status.

Allowed status values should match the app model:

- `needs_tagging`
- `saved`
- `needs_review`
- `reviewed`
- `failed`
- `short_recording`

Result:

- update `metadata.json`
- update SQLite index
- audit status change

### `/note rec_id text`

Adds or replaces a human-written note.

The command should preserve Markdown-safe text, but the implementation must avoid executing or rendering untrusted content inside the app.

Result:

- persist note locally
- associate note with `recording_id`
- acknowledge the write

### `/find query`

Searches local or synced metadata.

MVP future scope:

- title
- participant
- tags
- source app
- status
- date text

The desktop app is local-first, so a pure bot implementation cannot query local-only data unless a local bridge is running and explicitly authorized.

### `/upload rec_id provider`

Requests upload of a recording to an external provider.

Examples:

```text
/upload rec_2026-05-24_10-30-00_ab12cd34 s3
/upload rec_2026-05-24_10-30-00_ab12cd34 torbit-storage
```

Rules:

- disabled unless upload provider is configured
- blocked by local-only mode
- never uploads raw source tracks unless explicitly allowed
- stores returned links in metadata/sync tables
- sends Telegram confirmation with link state, not credentials

## Security Model

### Allowlisted Chat IDs

Only configured Telegram chat IDs can interact with the bot.

Configuration should support:

- one or more mentor private chats
- optional mentor team/group chats later
- explicit deny behavior for unknown chats

Unknown chat behavior:

- do not reveal whether a recording exists
- respond with a generic unauthorized message or ignore
- write audit log with chat id and command type

### Sensitive Audio Defaults

By default, Telegram notifications should not include audio files. The safest default is text-only notifications with recording metadata and command hints.

Audio sending requires explicit settings:

- send small mixed preview
- maximum file size
- allowed chats
- allowed statuses/categories

### Local-Only Mode

If local-only mode is enabled, Telegram integration must be fully blocked:

- no notifications
- no commands
- no file uploads
- no metadata sync through Telegram

The app should explain that Telegram requires leaving local-only mode.

### Audit Log

Every Telegram action should append an audit log entry:

- timestamp
- chat id
- Telegram user id, if available
- command
- recording id
- result
- error code, if failed

Do not log raw audio content, transcripts, or sensitive note contents unless the user explicitly enables verbose debugging.

## Data Model

Future local tables or metadata extension can track Telegram linkage.

### Recording Telegram Link

```text
telegram_recording_links
  id TEXT PRIMARY KEY
  recording_id TEXT NOT NULL
  telegram_chat_id TEXT NOT NULL
  telegram_message_id TEXT NOT NULL
  sync_status TEXT NOT NULL
  created_at TEXT NOT NULL
  updated_at TEXT NOT NULL
```

Required fields:

- `telegram_chat_id`: destination chat id for the message or command.
- `telegram_message_id`: Telegram message id for notification, note, or preview.
- `recording_id`: local recording id.
- `sync_status`: current state, for example `pending`, `sent`, `failed`, `blocked_local_only`, `unauthorized`, or `deleted`.

### Metadata Extension

`metadata.json` can include a future optional section:

```json
{
  "telegram": {
    "sync_status": "sent",
    "messages": [
      {
        "telegram_chat_id": "123456",
        "telegram_message_id": "789",
        "type": "notification",
        "created_at": "2026-05-24T10:31:00Z"
      }
    ]
  }
}
```

The SQLite table is better for local querying and retries. Metadata extension is useful for portability and human inspection.

## Architecture

Recommended future components:

- `TelegramSettings`: bot enabled flag, allowlisted chat ids, notification preferences, preview policy.
- `TelegramBotClient`: small wrapper over Telegram Bot API.
- `TelegramCommandParser`: validates command syntax and extracts action.
- `TelegramCommandHandler`: applies authorized commands to local storage/index.
- `TelegramNotificationService`: sends post-recording notifications.
- `TelegramAuditLogger`: writes local audit events.
- `TelegramSyncIndex`: maps local recordings to Telegram messages and sync state.

The recording engine should not depend on Telegram. Integration should subscribe to recording lifecycle events after metadata is written.

## Future Implementation Plan

### Phase 1: Notifications Only

Scope:

- settings for bot token and allowlisted chat ids
- local-only mode gate
- post-recording text notification
- sync status persistence
- audit log
- retry failed notifications manually

No command handling. No audio upload.

### Phase 2: Tag Replies and Commands

Scope:

- receive Telegram updates
- parse `/tag`, `/status`, and `/note`
- support reply-to-message mapping by `telegram_message_id`
- update `metadata.json`
- update SQLite index
- audit all writes

No heavy file upload.

### Phase 3: Links and Notes

Scope:

- `/find query`
- `/upload rec_id provider`
- external storage link persistence
- optional small mixed preview upload
- note rendering in Telegram
- T-Orbit sync compatibility for metadata and links

## Risks

### API Limits

Telegram Bot API limits can affect notification bursts, uploads, and polling/webhook behavior. The app needs retry and backoff.

### Privacy

Recording metadata can be sensitive even without audio. Notifications should be explicit, minimal, and disabled by local-only mode.

### Wrong Chat

Misconfigured chat ids can leak recording metadata. Use allowlists, confirmation UI, and audit logs.

### No Granular ACL

Telegram chats do not provide the same recording-level ACL expected from T-Orbit. Avoid treating Telegram as an authorization layer.

### File Size Limits

Telegram file size limits make long call recordings unreliable as attachments. Prefer external storage links and only optional small previews.

### Vendor Dependency

Telegram availability, API behavior, and policy can change. The app should treat Telegram as optional and non-critical.

## Open Questions

- Should Telegram settings live in the macOS app only, or later in T-Orbit workspace settings?
- Should command processing use long polling from the desktop app or a server-side webhook?
- Should notes be stored in `metadata.json`, SQLite, or a future `notes.md` beside the recording?
- Should previews be generated as excerpts instead of sending full `mixed.m4a`?
- What is the minimum acceptable audit log for compliance-sensitive calls?
