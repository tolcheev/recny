# Windows Client

## Status

Future design only. Windows support is not part of the macOS audio-only MVP.

Do not add Windows code, packaging, CI, or dependencies in the MVP repo step.

## Goal

Provide a lightweight student-side recorder for Windows:

- tray app
- automatic call/interview recording
- microphone + system audio
- local-first storage
- upload queue later
- T-Orbit metadata sync later

## Core Requirements

- Lives in the Windows tray.
- Can start/stop manually.
- Can auto-start on likely calls.
- Records microphone input.
- Records system audio with WASAPI loopback.
- Saves locally without internet.
- Shows simple recording status.
- Provides Diagnostics for support.

## Audio Architecture

### Microphone

- Native Windows audio input.
- Manual device selection.
- Avoid switching input during active recording.
- Prefer external/built-in microphones over Bluetooth headset mics where possible.

### System Audio

- WASAPI loopback capture.
- Capture default output device first.
- Detect silence and device disconnect.
- Log clear errors.

## Auto-Start

Future rules should mirror macOS v2:

- whitelist/blacklist apps
- cooldown
- minimum detection duration
- browser title hints for calls/interviews
- known call apps like Zoom/Teams
- avoid browser + YouTube false positives where possible

No browser extension in first Windows version.

## Storage

Same conceptual model as macOS:

```text
source/
  mic.m4a
  system.m4a
export/
  mixed.m4a
metadata.json
```

Suggested root:

```text
%USERPROFILE%\Recordings\TOrbitRecorder\
```

## Upload and T-Orbit Later

Upload queue later:

- upload mixed preview
- upload source tracks only if explicitly allowed
- retry failures
- store external links

T-Orbit sync later:

- recording metadata
- student/mentor/workspace ids
- tags/status
- transcript/note status
- external storage links

Heavy files stay local or external. T-Orbit stores metadata and links.

## UX

Student UI should be minimal:

- setup wizard
- test recording
- tray status
- recording indicator
- local recording folder
- upload/sync status later

Avoid mentor/admin features in the student app.

## Stack Options

Recommended first evaluation:

- C#/.NET with WinUI or WPF for native Windows UX.
- Rust/Tauri shell only if native audio integration stays clean and lightweight.

Default recommendation: C#/.NET first because WASAPI, tray behavior, installer tooling, and Windows diagnostics are straightforward.

## Risks

- Audio device diversity.
- Bluetooth/headset mode quality.
- Antivirus/security prompts.
- Weak student hardware.
- Bad internet for uploads.
- Privacy/legal expectations for student-side recording.
