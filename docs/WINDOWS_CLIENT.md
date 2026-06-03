# Windows Client

## Status

Active v0.2.3 beta scope.

Windows is still outside the shipped macOS v0.1.2 MVP, but the repository now contains a separate experimental Windows client under `apps/windows`. Keep it isolated from the macOS Swift app.

The first useful Windows beta must be auto-recording-first. Manual recording remains available as a fallback, but the core scenario is: launch ToRec once, leave it in the tray, and let it start/stop around likely calls.

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
- Can auto-start on likely calls.
- Can auto-stop auto-started recordings when the active call audio session disappears.
- Can start/stop manually.
- Records microphone input.
- Records system audio with WASAPI loopback.
- Saves locally without internet.
- Shows simple recording status.
- Provides Diagnostics for support.
- Checks the public release manifest for newer builds and opens the GitHub download page.

Deferred:

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

Windows auto-start uses two signals:

- active Windows audio sessions from WASAPI;
- process names and browser window-title hints.

Rules:

- Poll once per second.
- Start after 10 seconds of stable call-like activity.
- Stop only auto-started recordings after 10 seconds without the active call/source audio session.
- Manual recordings never auto-stop.
- Known call apps can trigger from active audio sessions: Zoom, Teams, Telegram, Discord, Slack, Skype, Webex, KTalk.
- Browser apps require call-like title hints: Meet, Google Meet, Zoom, Teams, KTalk, call, huddle, interview, Jitsi, Whereby, Russian call/interview words.
- After auto-start, ToRec keeps recording by the same source process/app audio session. Switching active windows, apps, or tabs must not stop recording.
- Ignore ToRec's own process audio.

No browser extension in the first Windows version.

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
