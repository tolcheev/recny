# Recording Engine

## Goal

The recording engine must reliably capture call audio without OBS and without pretending capture works when macOS permissions or APIs block it.

The engine is a testable core package, not SwiftUI view logic.

## MVP Capture Requirements

- Capture microphone audio.
- Store microphone audio as `source/mic.m4a`.
- Record microphone audio as AAC in an m4a container at 48 kHz, mono, with the selected speech quality preset.
- Capture full system audio through a Core Audio process tap.
- Store system audio as `source/system.m4a`.
- Record system audio as AAC in an m4a container at 48 kHz, stereo, with the selected speech quality preset.
- Create quick-listen mixed audio preview as `export/mixed.m4a`.
- Record mixed preview as AAC in an m4a container at 48 kHz, stereo, with a speech preview bitrate.
- Do not add or persist a screen video output in the MVP.
- Save metadata for every session.
- Write `recovery.json` while a session is active.
- Preserve active recording files under `source/segments/`.
- Log lifecycle events and failures.

## Preferred Native APIs

- Microphone: AVFoundation.
- System audio: Core Audio process tap where available and permitted by macOS.
- Mixing/export: native AVFoundation tooling unless a specific blocker is documented.

The system-audio tap writes AAC with synchronous `ExtAudioFileWrite`. Do not
switch this path back to `ExtAudioFileWriteAsync`: on long calls the async queue
can overflow (`kExtAudioFileError_AsyncWriteBufferOverflow`, OSStatus -66570)
and truncate `source/system.m4a`.

Any capture limitation must be represented as a real failure state. Tests may use fixtures for state and storage behavior, but they must not fake a successful production audio capture path.

## Microphone Input Policy

The recorder selects a microphone input device deterministically before starting the microphone track. This policy lives in `DevicePriorityResolver` in the core package. It must not change the macOS system output device.

Default selection is `Auto, recommended`:

1. Prefer external microphones: Shure, MV7, Hollyland, USB microphones, audio interfaces, and other non-built-in external microphone devices.
2. Fall back to the built-in MacBook microphone: `MacBook Pro Microphone` or `Built-in Microphone`.
3. Fall back to other non-Bluetooth and non-virtual input devices.

AirPods, AirPods Pro, AirPods Max, Bluetooth headset, and hands-free profile microphones are blocked for recording. They must not be selected automatically, must not be honored as a manual preferred input, and must not be used as a restore target after recording. If no non-Bluetooth input is available, recording is blocked and the app must show:

```text
AirPods/Bluetooth microphone is blocked for recording. Connect the MacBook or USB microphone.
```

Virtual meeting inputs are blocked too: `Microsoft Teams Audio`, `Teams Audio`, `ZoomAudioDevice`, and `Zoom Audio Device` must not be selected automatically, must not be honored as a manual preferred input, and must not be used as a restore target after recording. If no non-virtual input is available, recording is blocked and the app must show:

```text
Microsoft Teams/Zoom virtual microphone is blocked for recording. Use the MacBook, USB, or external microphone.
```

The selected microphone name is visible in the main recorder UI and can be overridden from Settings > Recording > Preferred microphone. A preferred Bluetooth headset microphone or virtual meeting microphone is always ignored for recording.

Settings labels each available input as `Recommended`, `Built-in`, `Blocked`, or `Available`. Diagnostics shows the selected input, the recommended Auto input, and the reason for the current selection. Device changes are refreshed while the app runs; Auto can pick a newly connected external microphone for the next recording, but the active recording input is not changed mid-session.

## Speech Quality Presets

Settings > Recording exposes three local AAC presets:

- `Compact`: microphone 96 kbps, system audio 96 kbps, mixed preview 80 kbps.
- `Standard`: microphone 128 kbps, system audio 128 kbps, mixed preview 96 kbps. This is the MVP default.
- `High`: microphone 192 kbps, system audio 192 kbps, mixed preview 128 kbps.

All presets keep 48 kHz sample rate. Microphone remains mono; system and mixed tracks remain stereo.

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
2. Run preflight before creating any recording session folder:
   - microphone permission granted
   - system audio capture available when system audio is enabled
   - deterministic microphone selection resolves to an available input device
   - output root exists and is writable
   - free disk space is at least 2 GB
   - no active recording session is already running
3. Create a stable session id.
4. Resolve the session staging path.
5. Create `source/`, `source/segments/`, `export/`, and `recovery.json`.
6. Resolve the microphone input device using the deterministic input policy and temporarily select only that input device for the microphone writer.
7. Start the Core Audio process tap system audio writer at `source/segments/system-0001.m4a`.
8. Start microphone writer at `source/segments/mic-0001.m4a`.
9. Emit a lifecycle log event and switch UI state to `recording`.

If preflight fails, the app must not create a recording folder or recoverable session. If writer startup fails after staging has begun, empty staged folders are discarded; only staged sessions with usable audio files or segments are left for recovery.

## System Audio Permission Probe

System audio permission is proven exclusively by the Core Audio process-tap capture probe; the legacy ScreenCaptureKit preflight is not consulted.

The probe:

1. Marks `AppState.isSystemAudioPermissionRequestInProgress = true` and clears any in-run verified flag so the snapshot cannot report `.granted` while the macOS TCC prompt is on screen.
2. Starts a short Core Audio process tap into a temporary file in `NSTemporaryDirectory()`.
3. Polls `frameCountSnapshot()` every 200 ms for up to 8 s.
4. Returns success only after the recorder reports at least one written audio frame — proof that macOS is actually delivering bytes after the user clicked Allow.
5. On timeout or capture error, marks the request failed and surfaces `systemAudioPermissionDenied`.

While `isSystemAudioPermissionRequestInProgress` is set:

- `permissionSnapshot.screenSystemAudio` cannot be promoted to `.granted`, even if a previous run cached a successful probe in `UserDefaults`.
- `isRecordingStartAllowed` returns `false`.
- `shouldShowPermissionsOnboarding` stays `true`.
- The status summary renders `System audio: Checking permission`.
- The header renders `Error`-toned `Permissions needed`, not `Ready`.

Only after the probe verifies real audio frames are `noteSystemAudioPermissionRequestSucceeded()` and the persisted `systemAudioPermissionProbeSucceeded` flag set. The Ready state is therefore impossible to reach while the system-audio TCC prompt is still visible.

The persisted system-audio probe cache is keyed by app version, build date, git commit, and probe implementation version. Development/ad-hoc rebuilds can keep the same version and commit while changing the code-signing requirement, so build date is part of the key. A new local build must run the Core Audio probe again instead of reusing an older `Ready` state.

## Auto-Started Stop Guard

Auto-started recordings are allowed to continue while the user switches away from Zoom or another call app. Foreground app changes are not a reliable signal that the call ended.

The app stops an auto-started recording only after the call signal has been absent for the configured grace period. The default grace period is 10 seconds, and auto-start monitoring polls once per second so the real stop time stays close to that target. For Zoom, Core Audio process activity from `us.zoom.xos` is the preferred signal: active Zoom input or output keeps recording alive while the user works in another app. Meeting/home window titles are used when macOS exposes them. If both Zoom window titles and per-process audio activity are unavailable, global system-audio activity is the last fallback and microphone activity is ignored because the recorder can keep input devices marked as running. For Yandex Telemost, process input activity or a call-like meeting window is required; output-only process activity and global microphone/system activity do not start or keep a Telemost recording alive. Telegram and Discord are not in the default auto-start whitelist; if explicitly allowlisted, their keep-alive signal must come from the same app using both Core Audio input and output. Playback-only output or unrelated microphone activity does not keep the recording alive. Manual recordings do not use this guard and must be stopped by the user.

The guard logs:

- signal loss start
- signal restored
- auto-stop execution
- auto-stop failure, if finalization fails

## Stop Flow

When Stop is requested from the main window, menu bar, shortcut, or auto-stop guard, the UI immediately enters a `Stopping...` state and disables duplicate stop requests. The app writes a local file log before awaiting recorder finalization so Diagnostics can distinguish a missed click from a slow or failed stop transaction.

1. Log `recording stop requested`.
2. Stop accepting new audio buffers.
3. Close segment writers.
4. Copy present segment files into final source files:
   `source/segments/mic-0001.m4a` -> `source/mic.m4a`;
   `source/segments/system-0001.m4a` -> `source/system.m4a`.
5. Mark `recovery.json` as `completed`.
6. Validate source files with existence and size checks.
7. Create `export/mixed.m4a` from the available source tracks.
8. Create `export/mixed_balanced.m4a` when Audio Leveling is enabled.
9. Compute duration and file sizes where possible.
10. Analyze completed source tracks for basic signal metadata: signal presence, approximate silence ratio, and clipping.
11. Validate required outputs. A required source or mixed file that is missing, failed, or 0 bytes makes the recording status `failed` with reason `Empty audio file` or `Missing audio file`.
    If a required track is non-empty but finished with a late writer warning, keep the recording usable and mark the track `completed_with_warnings`.
    If `source/system.m4a` is much shorter than the recording duration, surface an `Audio warning` instead of silently reporting `Audio OK`.
12. Classify short sessions when below the configured short-recording threshold.
13. Write final `metadata.json`.
14. Update the SQLite index.
15. Move the session into `Library/YYYY/MM/...`, `Inbox/Short/`, or `Inbox/Failed/`.

Recordings shorter than the configured short-recording threshold are finalized with metadata status `short_recording`, moved under `Inbox/Short/`, and kept indexed for review. The MVP default threshold is 60 seconds and can be changed from Settings. Failed finalization uses `failed` and `Inbox/Failed/` when metadata can be written.
16. Emit a final lifecycle log event.

Stop finalization logs each major phase:

- stop pipeline begin
- microphone writer stopped
- system audio stop begin/finished
- segment finalization begin/finished
- mixed preview begin/finished
- audio leveling begin/finished
- metadata finalization begin/finished
- recording stop request finished

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

The mixed preview can still be created from whichever readable source tracks are available, but the recording is not shown as saved unless all required MVP outputs pass integrity checks. If a required source track or `mixed.m4a` is missing, failed, or empty, the session status is `failed`.

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
- `signal`, for completed tracks when analysis succeeds:
  - `had_signal`
  - `approximate_silence_ratio`
  - `clipping_detected`
- `status`
- `error`, when applicable

Top-level `quality_warnings` contains legacy post-stop warnings derived from signal metadata.
Current UI-facing audio health is stored in `audio.health`:

- `status`: `good`, `warning`, or `failed`
- `warnings`: compact codes for display and filtering

Supported health warning codes:

- `mic_silent`
- `system_silent`
- `mic_too_quiet`
- `system_too_quiet`
- `clipping_detected`
- `balanced_mix_failed`
- `only_one_track_available`

The mixed preview uses conservative gain during two-track mixing so mic + system playback is less likely to overload. If only one source track is available, the preview is created from that track with near-unity gain.

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

## Stop finalization and stalled exports (September 2026)

A stop request freezes the displayed elapsed time, clears the audio meters, and
shows `Saving` while files are finalized. The recording end timestamp is captured
before stopping the devices, so shutdown and export time do not extend its duration.

Both original and balanced mixing use a shared callback watchdog. Each accepted
sample resets the deadline; starting `finishWriting` resets it once more. Sixty
seconds without progress fails that export and queues reader/writer cancellation.
A progressing long recording is not subject to a total export time limit. Late
callbacks cannot resume the awaiting operation twice. Cancellation uses the same
serial queue as sample appends to avoid concurrent writer mutations.

Exports write to a unique hidden `.pending.m4a` file. Only a completed writer
publishes the final mix; failed or timed-out attempts remove the pending path and
preserve any previously completed mix. The source microphone and system tracks
remain available for recovery. Existing finalization records a failed export in
metadata; the timeout is not a claim that a mix was saved successfully. Logs include
`finishWriting` entry, publication, and stalled export paths.

The watchdog bounds the writer stage, not every AVFoundation operation or audio
analysis stage. Live capture and the original long-recording incident require
manual validation on the affected installed build.
