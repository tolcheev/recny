# Security And Privacy

## MVP Position

T-Orbit Recorder MVP is local-first.

The app stores recordings, metadata, and logs on the user's Mac and does not upload them to cloud storage, T-Orbit, AI providers, or external services.

## Sensitive Data

Recordings may contain:

- student conversations
- sales conversations with leads
- interview analysis
- conflict or escalation calls
- personal voice data
- business context

The product must treat local audio files as sensitive by default.

## Local Storage

Default root:

```text
~/Recordings/TOrbitRecorder/
```

MVP data stays local:

- source audio
- mixed exports
- metadata
- logs
- local SQLite recordings index

## Permissions

The app should request only permissions required for MVP audio recording.

Required capabilities:

- microphone capture
- system audio capture where macOS allows it

If a permission is missing or macOS blocks capture, the app must show and log the blocked state. It must not mark the session as successfully recorded.

## No Uploads In MVP

The MVP must not:

- upload audio files
- upload metadata
- sync with T-Orbit
- call AI services
- send transcripts, notes, tags, or participant data anywhere

Future upload and sync work must be designed separately and documented before implementation.

## Logs

Logs should help debug recorder lifecycle and failures without storing raw audio.

Allowed log content:

- timestamps
- session ids
- state transitions
- source app and bundle id
- rule id and trigger
- permission status
- failure category and error code

Avoid logging unnecessary participant names, raw transcript text, or long file contents.

## Encryption

Encryption is out of scope for MVP.

Future encryption work must define:

- what is encrypted
- where keys live
- how recovery works
- how T-Orbit sync interacts with encryption

## User Control

The app should make recording state visible in the menu bar UI and provide a local way to stop recording.

Settings include local privacy controls for local-only mode, recording indicator visibility, and Focus Mode reminder. Local-only mode and Focus Mode reminder remain disabled placeholders in the MVP until additional behavior exists; the recording indicator can be toggled locally.

Autostart must be explainable through metadata and logs so the user can understand why a recording started.

## Local Logs

The MVP writes a simple local app log to:

```text
~/Recordings/TOrbitRecorder/logs/app.log
```

Rotation keeps one archive:

```text
~/Recordings/TOrbitRecorder/logs/app.1.log
```

Local file logs are for troubleshooting recorder lifecycle and permission issues. They may include file paths, app names, bundle IDs, device names, selected microphone names, auto-start decisions, and error messages.

Local logs must not include raw transcript text, raw audio content, call content, or screen content.
