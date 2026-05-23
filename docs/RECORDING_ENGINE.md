# Recording Engine

## Goal

The recording engine must reliably capture call audio without OBS and without pretending capture works when macOS permissions or APIs block it.

The engine is a testable core package, not SwiftUI view logic.

## MVP Capture Requirements

- Capture microphone audio.
- Store microphone audio as `source/mic.m4a`.
- Record microphone audio as AAC in an m4a container at 48 kHz, mono, 128 kbps.
- Capture full system audio through ScreenCaptureKit audio output.
- Store system audio as `source/system.m4a`.
- Record system audio as AAC in an m4a container at 48 kHz, stereo, 128 kbps.
- Create quick-listen mixed audio preview as `export/mixed.m4a`.
- Record mixed preview as AAC in an m4a container at 48 kHz, stereo, about 96 kbps.
- Do not add or persist a screen video output in the MVP.
- Save metadata for every session.
- Write `recovery.json` while a session is active.
- Preserve active recording files under `source/segments/`.
- Log lifecycle events and failures.

## Preferred Native APIs

- Microphone: AVFoundation.
- System audio: ScreenCaptureKit where available and permitted by macOS.
- Mixing/export: native AVFoundation tooling unless a specific blocker is documented.

Any capture limitation must be represented as a real failure state. Tests may use fixtures for state and storage behavior, but they must not fake a successful production audio capture path.

## Microphone Input Policy

The recorder selects a microphone input device deterministically before starting the microphone track. It must not change the macOS system output device.

Default selection is `Auto, recommended`:

1. Prefer external microphones: Shure, MV7, Hollyland, USB microphones, audio interfaces, and other non-built-in external microphone devices.
2. Fall back to the built-in MacBook microphone: `MacBook Pro Microphone` or `Built-in Microphone`.
3. Use AirPods, AirPods Pro, AirPods Max, Bluetooth headset, or hands-free profile microphones only when no other input device is available.

If the selected input is the Bluetooth fallback, the app must show:

```text
Only Bluetooth headset microphone is available. Recording quality may be degraded.
```

The selected microphone name is visible in the main recorder UI and can be overridden from Settings > Recording > Preferred microphone. A preferred Bluetooth headset microphone is ignored while a non-Bluetooth microphone is available.

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
- `recoverable`

State transitions must be logged with timestamps and session id.

## Start Flow

1. Receive a start request from the autostart controller or UI.
2. Create a stable session id.
3. Resolve the session staging path.
4. Create `source/`, `source/segments/`, `export/`, and `recovery.json`.
5. Check microphone permission.
6. Resolve the microphone input device using the deterministic input policy and temporarily select only that input device for the microphone writer.
7. Start ScreenCaptureKit system audio writer at `source/segments/system-0001.m4a`.
8. Start microphone writer at `source/segments/mic-0001.m4a`.
9. Emit a lifecycle log event.

If any required permission or capture path fails, the engine must write failure metadata when possible and classify the session under `Inbox/Failed/`.

## Stop Flow

1. Stop accepting new audio buffers.
2. Close segment writers.
3. Copy usable segment files into final source files:
   `source/segments/mic-0001.m4a` -> `source/mic.m4a`;
   `source/segments/system-0001.m4a` -> `source/system.m4a`.
4. Mark `recovery.json` as `completed`.
5. Validate source files with existence and size checks.
6. Create `export/mixed.m4a` from the available source tracks.
7. Compute duration and file sizes where possible.
8. Classify short sessions when below the configured short-recording threshold.
9. Write final `metadata.json`.
10. Move the session into `Library/YYYY/MM/...`, `Inbox/Short/`, or `Inbox/Failed/`.

Recordings shorter than the configured short-recording threshold are finalized with metadata status `short_recording`, moved under `Inbox/Short/`, and kept indexed for review. The MVP default threshold is 60 seconds and can be changed from Settings. Failed finalization uses `failed` and `Inbox/Failed/` when metadata can be written.
11. Emit a final lifecycle log event.

## Crash Recovery

While recording, the canonical in-progress files live in:

```text
source/segments/
  mic-0001.m4a
  system-0001.m4a
recovery.json
```

If the app crashes before normal Stop, the session remains under `Inbox/Unsorted/`.
On next launch, the app scans `Inbox/Unsorted/*/recovery.json`. Any session still marked `recording` is changed to `recoverable` and shown in the UI as `failed / recoverable`.

The Recover Recording action attempts to:

1. Preserve the original segment files.
2. Copy usable segment files into `source/mic.m4a` and `source/system.m4a`.
3. Create `export/mixed.m4a` from whichever source files are readable.
4. Write final `metadata.json`.
5. Move the recovered session into the Library with `status: "needs_review"`.

If no readable source can be recovered, the final recording status is `failed`.
The MVP does not delete interrupted files automatically.

## Required Output

```text
source/
  segments/
    mic-0001.m4a
    system-0001.m4a
  mic.m4a
  system.m4a
export/
  mixed.m4a
metadata.json
recovery.json
```

If one source track is missing, the mixed preview must be created from the available track. If both source tracks are missing or unusable, the session status must be `failed`.

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
- `file_size_bytes`
- `status`
- `error`, when applicable

## Failure Handling

The engine must distinguish:

- microphone permission denied
- no usable microphone input device
- selected microphone input no longer available
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
- microphone device priority resolution
- log event formatting

Real capture validation remains a manual or device-level integration check because macOS permissions and audio devices are involved.
