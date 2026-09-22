# Telegram Integration

## Status

Future design only. Telegram is not part of the macOS audio-only MVP.

Do not add bot code, credentials, network calls, or Telegram-dependent behavior until this feature is explicitly scheduled.

## Goal

Use Telegram as a lightweight notification and command surface around recordings, not as the product database or heavy file storage.

## Use Cases

- Notify an allowlisted mentor chat when a new recording is saved.
- Add quick tags from a reply or command.
- Send a short human-readable note or summary link.
- Share links to files stored elsewhere.
- Optionally send a small preview audio file if size and privacy settings allow it.

## Not Primary Storage

Telegram must not be used as primary storage for heavy files:

- `source/mic.m4a`
- `source/system.m4a`
- `export/mixed.m4a`
- future screen video files

Heavy files remain local in MVP and can later be uploaded to external storage. Telegram can receive metadata, status, tags, notes, and links.

## Commands

Future bot commands:

```text
/tag rec_id #tag
/status rec_id reviewed
/note rec_id text
/find query
/upload rec_id provider
```

Command handling should:

- validate chat id against an allowlist
- validate recording id
- normalize tags through the same rules as the desktop app
- update `metadata.json`
- update SQLite index
- write an audit log

## Security

- Allowlisted chat IDs only.
- Unknown chats should not learn whether a recording exists.
- Local-only mode blocks Telegram.
- Do not send sensitive audio by default.
- Do not send raw source tracks by default.
- Log Telegram actions without logging transcript/audio content.

## Data Model Additions

Future local metadata or SQLite fields:

- `telegram_chat_id`
- `telegram_message_id`
- `recording_id`
- `telegram_sync_status`
- `last_telegram_error`

## Implementation Phases

1. Notifications only.
2. Tag/status replies.
3. Notes and external file links.
4. Optional small preview audio.

## Risks

- Wrong chat or leaked notification.
- Telegram file size limits.
- No granular ACL inside Telegram.
- Vendor/API dependency.
- Privacy expectations may differ per call.
