# Architecture

## Repository Boundary

This repository contains the standalone T-Orbit Recorder desktop client.

The T-Orbit backend is not part of this repository. The MVP does not upload recordings, sync metadata, call AI services, or depend on T-Orbit availability.

## Target Runtime

- macOS Sequoia.
- Apple Silicon.
- Primary validation device: MacBook M4 Pro.
- Native app stack: Swift, SwiftUI, AVFoundation, ScreenCaptureKit.
- No Electron.

## Project Layout

```text
apps/macos/         Native macOS menu bar app
packages/core/      Recording engine, storage, permissions, logging
packages/protocol/  Metadata schema and shared protocol types
docs/               Product and engineering documentation
samples/scripts/    Local helper scripts and experiments
tests/              Integration fixtures and test assets
```

## Runtime Components

### Menu Bar App

Owns visible app lifecycle:

- launch and quit
- recording status
- permission prompts and blocked-state messaging
- manual stop when needed
- links to local recording folder and logs

The UI must not own capture mechanics.

### Autostart Controller

Evaluates local rules and decides when to request a recording start.

It produces source metadata:

- source app
- bundle id
- trigger
- rule id

V1 evaluates the active app and bundle id, local whitelist/blacklist, microphone activity, system audio activity, recording state, cooldown, and minimum detection duration. It does not inspect browser URLs and does not use browser extensions.

### Recording Engine

Owns capture work:

- microphone capture
- system audio capture
- source file writing
- mixed export creation
- state transitions
- failure mapping
- lifecycle logs

### Storage Layer

Owns local paths:

```text
~/Recordings/TOrbitRecorder/
  Inbox/
  Library/
  db/
  logs/
```

The MVP canonical record is the session folder plus `metadata.json`.

SQLite at `db/app.sqlite` mirrors local recording metadata for the MVP recording list, filters, and edit/delete actions. It must not become required for MVP playback or file recovery.

The local index contains `recordings`, `tags`, and `recording_tags`. When the database is empty, the storage layer can rebuild it by scanning `Library/` and `Inbox/` for `metadata.json`.

### Protocol Layer

Owns stable data contracts:

- metadata schema
- recording status values
- MVP tag values
- AI state values
- sync state values
- audio track descriptors

The protocol package should allow future T-Orbit sync without forcing backend code into the desktop app.

## Data Flow

1. Autostart rule matches a local call signal, or the user starts recording manually.
2. App checks required permissions.
3. Recording engine creates a session id and staging folder.
4. Microphone and system audio are written as separate source tracks.
5. On stop, the storage layer writes `metadata.json` with `status: "needs_tagging"`, `short_recording`, or `failed` depending on duration and recorder result.
6. The app opens compact post-call tagging.
7. Saving post-call tags updates `metadata.json` and `db/app.sqlite`.
8. Recordings can be filtered locally by date, status, source app, title, and tag.
9. The recordings list can open a folder, play `export/mixed.m4a`, edit title/tags, and delete a local record with confirmation.
10. Logs record lifecycle and failures.

## Future Integration Boundary

Later versions may upload heavy files to external storage and sync metadata to T-Orbit.

The intended split:

- External storage: heavy audio and future video files.
- T-Orbit: metadata, tags, transcripts, notes, permissions, links, AI outputs.
- Recorder: capture, local durability, upload/sync clients when enabled.

## Dependency Policy

- Prefer native Apple APIs.
- Keep third-party dependencies small and justified.
- Do not introduce Electron.
- Do not add media frameworks that duplicate native capture without a clear blocker.

## Testing Strategy

- Unit-test metadata, path generation, state transitions, and failure mapping.
- Integration-test local storage layout.
- Manually validate real microphone and system audio capture on macOS.
- Keep UI tests separate from recording engine tests.
