# Architecture

## Repository Boundary

This repository contains the standalone Recny desktop client.

The T-Orbit backend is not part of this repository. The MVP does not upload recordings, sync metadata, call cloud AI services, or depend on T-Orbit availability.

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

V1 evaluates the active app and bundle id, running app snapshots, local whitelist/blacklist, microphone activity, system audio activity, Zoom per-process Core Audio input/output activity, browser window-title hints, recording state, cooldown, and minimum detection duration. It does not inspect browser URLs directly and does not use browser extensions. Zoom Web can start from explicit Zoom window titles plus system-audio activity even when the local Zoom microphone is muted; generic browser-call titles still require microphone activity.

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

The local index contains `recordings`, `tags`, and `recording_tags`. The storage layer refreshes it from disk before listing or editing records: it scans `Library/` and `Inbox/` for `metadata.json` files, upserts missing metadata rows, and removes index rows whose session folder or `metadata.json` was deleted outside the app.

### Settings Layer

Owns local user preferences stored on the Mac.

MVP settings include:

- recording indicators: system audio and mixed export are required and always enabled in the MVP
- auto-start rules: enabled flag, whitelist, blacklist, cooldown, minimum detection duration, and short-recording threshold
- storage root folder with open, choose, and reset-to-default actions
- global hotkeys for Show Window and screenshot capture, plus disabled placeholders for editable custom hotkeys
- privacy controls for local-only mode, recording indicator, and Focus Mode reminder

The Settings UI must not expose a working-looking control without backing runtime behavior. Non-MVP controls stay disabled until implemented.

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
6. The app shows a compact post-stop summary with Play, Tag, and Show actions.
7. If the user clicks Tag, saving post-call tags updates `metadata.json` and `db/app.sqlite`.
8. Before showing the recordings list, the app synchronizes the local SQLite index with recording folders on disk.
9. Recordings can be filtered locally by date, status, source app, title, and tag.
10. The recordings list can open a folder, play local audio, share via the macOS share sheet, trim a local clip, capture a still screenshot, run explicit local transcription only after optional Settings preparation is ready, edit title/tags, and delete a local record with confirmation.
11. Settings changes update the local app state and are persisted locally.
12. Logs record lifecycle and failures.

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
