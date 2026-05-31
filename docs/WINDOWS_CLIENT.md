# Windows Client

## Status

Active v0.2 beta scope.

Windows is still outside the shipped macOS v0.1.2 MVP, but the repository now contains a separate experimental Windows client under `apps/windows`. Keep it isolated from the macOS Swift app.

The first Windows beta is manual-recording-first. Auto-start for Zoom/Meet/KTalk is a later Windows milestone after basic audio capture is validated on real student machines.

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
- Records microphone input.
- Records system audio with WASAPI loopback.
- Saves locally without internet.
- Shows simple recording status.
- Provides Diagnostics for support.

Deferred:

- Auto-start on likely calls.
- Browser title/window heuristics.
- Installer/MSIX.
- Cloud upload or T-Orbit sync.

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
  mic.wav
  system.wav
  mic.m4a
  system.m4a
export/
  mixed.wav
  mixed.m4a
metadata.json
```

In Windows v0.2, `.wav` is the reliable canonical recording format. `.m4a` is exported best-effort through Windows Media Foundation when available.

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

Selected for v0.2 beta:

- C#/.NET 8.
- Windows Forms tray app.
- NAudio for microphone and WASAPI loopback capture.

Rejected for this step:

- Rust/Tauri shell only if native audio integration stays clean and lightweight.

C#/.NET is the default because WASAPI, tray behavior, diagnostics, and GitHub Actions Windows packaging are straightforward.

## Risks

- Audio device diversity.
- Bluetooth/headset mode quality.
- Antivirus/security prompts.
- Weak student hardware.
- Bad internet for uploads.
- Privacy/legal expectations for student-side recording.
