# Recording Engine

## Goal

The recording engine must reliably capture call audio without OBS and without pretending capture works when macOS permissions or APIs block it.

The engine is a testable core package, not SwiftUI view logic.

## MVP Capture Requirements

- Capture microphone audio.
- Store microphone audio as `source/mic.m4a`.
- Record microphone audio as AAC in an m4a container at 48 kHz, mono, 128 kbps.
- Save metadata for every session.
- Log lifecycle events and failures.

System audio capture and mixed export are not implemented in the current microphone recording step.

## Preferred Native APIs

- Microphone: AVFoundation.
- System audio: ScreenCaptureKit where available and permitted by macOS.
- Mixing/export: native AVFoundation tooling unless a specific blocker is documented.

Any capture limitation must be represented as a real failure state. Tests may use fixtures for state and storage behavior, but they must not fake a successful production audio capture path.

## Session State Model

Suggested states:

- `idle`
- `preparing`
- `permission_blocked`
- `recording`
- `stopping`
- `mixing`
- `completed`
- `short`
- `failed`

State transitions must be logged with timestamps and session id.

## Start Flow

1. Receive a start request from the autostart controller or UI.
2. Create a stable session id.
3. Resolve the session staging path.
4. Check microphone permission.
5. Check microphone input device availability.
6. Start microphone writer.
7. Emit a lifecycle log event.

If any required permission or capture path fails, the engine must write failure metadata when possible and classify the session under `Inbox/Failed/`.

## Stop Flow

1. Stop accepting new audio buffers.
2. Close source track writers.
3. Compute duration.
4. Classify short sessions when below the configured threshold.
5. Write final `metadata.json`.
6. Move the session into `Library/YYYY/MM/...`, `Inbox/Short/`, or `Inbox/Failed/`.
7. Emit a final lifecycle log event.

## Required Output

```text
source/
  mic.m4a
export/
metadata.json
```

## Audio Track Metadata

Every track in `metadata.json` should include:

- `kind`: `microphone`, `system`, or `mixed`
- `relative_path`
- `codec`
- `container`
- `duration_sec`
- `sample_rate`
- `channels`
- `bitrate`
- `status`
- `error`, when applicable

## Failure Handling

The engine must distinguish:

- microphone permission denied
- system audio permission denied or unavailable
- source app detection failure
- writer creation failure
- disk write failure
- mixing/export failure
- recording shorter than threshold
- unexpected engine crash or cancellation

Failures must be visible in metadata and logs.

## Testability

Package-level tests should cover:

- session id and path generation
- metadata creation and schema defaults
- state transitions
- short-session classification
- failed-session classification
- track status mapping
- log event formatting

Real capture validation remains a manual or device-level integration check because macOS permissions and audio devices are involved.
