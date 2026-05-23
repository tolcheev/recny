# Security And Privacy

## MVP Position

The MVP stores recordings locally and does not upload audio, metadata, transcripts, notes, or tags to a cloud service.

## Permissions

The app must request only permissions required for audio capture. If microphone or system audio capture permissions are missing, the app must report the blocked capability instead of pretending capture works.

## Data Handling

- Store audio files under `~/Recordings/TOrbitRecorder/` by default.
- Do not upload recordings in MVP.
- Do not sync with T-Orbit in MVP.
- Do not run AI transcription in MVP.
- Do not implement retention or autodelete in MVP.

## Encryption

Encryption is explicitly out of scope for MVP. Future encryption work must be designed and documented before implementation.
