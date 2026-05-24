# Windows Client Architecture Design

## Status

Future design only. Windows support is not part of the macOS audio-only local MVP.

The Windows client is intended primarily for student-side recording later. This document describes architecture and product constraints without adding code, dependencies, build scripts, or Windows packaging to the current repository.

## Product Scenario

Primary future flow:

1. Student installs the Windows app.
2. App runs as a lightweight tray recorder.
3. App automatically detects likely interviews or calls.
4. App records microphone and system audio.
5. Recording is saved locally first.
6. Upload queue later sends heavy files to external storage.
7. Metadata sync later sends recording card data to T-Orbit.
8. Mentor sees the recording in T-Orbit with metadata, tags, notes, transcript status, and storage links.

The student UI should be minimal. The product should not feel like an admin panel or a complex recording studio.

## Non-Goals

- Do not add Windows support to the MVP.
- Do not use T-Orbit as storage for heavy audio/video files.
- Do not require cloud upload for local recording.
- Do not expose mentor-level tagging/analysis UI to the student client by default.
- Do not implement AI in the Windows client as a first step.
- Do not build browser extensions for v1 auto-start.

## Core Requirements

### Tray App

The Windows client should live primarily in the system tray.

Expected tray actions:

- Show Window
- Start Recording
- Stop Recording
- Open Latest Recording
- Open Library Folder
- Settings
- Diagnostics
- Quit

Tray state should show:

- idle
- recording
- warning/error
- upload pending/sync pending later

### Auto-Start Recording

The app should detect likely calls and interviews and start recording automatically when enabled.

Rules should stay conservative to avoid recording unrelated desktop activity.

### Microphone + System Audio

The client must capture:

- microphone input
- system audio loopback
- mixed preview/export

The recording pipeline should fail explicitly if one required side cannot be captured and partial recording is not allowed by settings.

### Local Storage

Recordings are local-first. Recording must succeed without internet.

The Windows client should follow the same conceptual storage model as macOS:

```text
source/
  mic.m4a
  system.m4a
export/
  mixed.m4a
metadata.json
```

The exact root path should follow Windows conventions, for example:

```text
%USERPROFILE%\Recordings\TOrbitRecorder\
```

### Upload Queue Later

Upload is a later feature.

The app should eventually maintain a durable queue for:

- upload mixed preview
- upload source tracks if explicitly allowed
- retry failed uploads
- attach storage links to T-Orbit

### T-Orbit Sync Later

T-Orbit sync is later.

The Windows client should eventually sync:

- recording metadata
- student id
- mentor/workspace id
- source app and trigger
- tags/status if available
- external storage links
- transcript/note status

Heavy media stays local or external. T-Orbit receives metadata and links.

### Minimal UI for Student

Student UI should focus on:

- setup
- permission/device check
- recording state
- upload/sync state later
- diagnostics for support

It should not expose advanced mentor analysis, AI prompts, or complex library management unless explicitly needed.

## Windows Audio Architecture

### WASAPI Loopback for System Audio

Use WASAPI loopback capture for system audio.

Expected behavior:

- capture the default render endpoint output
- support common sample rates
- handle device changes
- detect silence/no samples
- recover from endpoint disconnect

Open questions:

- capture default output only vs selected output device
- per-process loopback support if available on target Windows versions
- whether communications-mode audio processing affects capture

### Microphone Input

Capture microphone through native Windows audio APIs.

Requirements:

- select default communications or default input device carefully
- show selected input in UI
- support manual device selection
- detect device disconnect
- avoid switching devices mid-recording
- log device name/id and errors

### Device Selection

Windows device policy should mirror the macOS AirPods protection principle: prefer reliable local/external microphones and avoid low-quality headset profiles when better options exist.

Suggested priority:

1. external USB/audio interface microphones
2. built-in laptop microphone
3. Bluetooth headset microphone as fallback

The app should not change the user's system output device.

## Auto-Start

### Browser Heuristic

Browser detection should be conservative.

Signals:

- active app is a whitelisted browser
- microphone active for detection duration
- system audio active
- active window title suggests a call/interview if available

Call title hints:

- Meet
- Zoom
- Teams
- Interview
- Собеседование
- Call
- KTalk
- SberJazz
- МТС Линк

Browser + YouTube + system audio alone should not start recording.

### Zoom, Teams, Meet

Known call apps can start with higher confidence.

Candidates:

- Zoom desktop
- Microsoft Teams
- browser-based Google Meet
- Discord if used for calls
- Telegram calls later if detectable

For desktop Zoom/Teams:

```text
known_call_app active
AND microphone active
AND cooldown passed
THEN start recording
```

### Whitelist and Blacklist

Defaults should be simpler than mentor/macOS settings.

Student-facing settings:

- Auto-start: Off / Ask first / Auto
- Allowed apps
- Never record these apps
- Detection duration

Advanced whitelist/blacklist editing can be hidden under Diagnostics or Advanced.

### Less Settings for Student

Student settings should avoid over-configuration.

Recommended default:

- Auto-start enabled after setup consent
- conservative browser heuristic
- 3 minute cooldown
- short recording threshold
- upload when available later

## UX

### Setup Wizard

First launch should show a short wizard:

1. What TOrbitRecorder records.
2. Microphone test.
3. System audio test.
4. Storage location.
5. Auto-start preference.
6. T-Orbit sign-in later.

The wizard should be skippable only if manual recording still works.

### Test Recording

Student can run a short test recording.

Expected result:

- mic level detected
- system audio detected
- `mixed.m4a` created
- playback works
- clear error if no mic/system audio

### Tray Status

Tray status should show:

- Ready
- Recording
- Recording failed
- Upload pending later
- Sync failed later

Tray tooltip can include:

- selected mic
- system audio readiness
- latest recording status

### Recording Indicator

When recording is active:

- tray icon changes state
- small window/banner can show timer
- stop action is easy to access
- privacy indicator text is clear

The app should not hide active recording state from the student.

### Upload Status

Future upload status should show:

- pending
- uploading
- uploaded
- upload failed
- sync pending
- synced

Upload failure must not delete local files.

## Storage

### Conceptual Model

Same conceptual model as macOS:

```text
RecordingRoot/
  Inbox/
    Unsorted/
    Short/
    Failed/
  Library/
    YYYY/
      MM/
        YYYY-MM-DD_HH-mm_source_audio/
          source/
            mic.m4a
            system.m4a
          export/
            mixed.m4a
          metadata.json
  db/
    app.sqlite
  logs/
```

### Metadata

Windows metadata should remain compatible with macOS/T-Orbit concepts:

- id
- owner_id
- workspace_id
- mentor_id
- student_id
- started_at
- ended_at
- duration_sec
- source app/bundle/process id
- trigger/rule id
- audio tracks
- status
- sync status
- storage links later

### Crash Recovery

Windows client should avoid losing long interviews.

Possible approach:

- write recoverable segments during active recording
- finalize `mic.m4a`, `system.m4a`, and `mixed.m4a` on stop
- preserve partial files on crash
- show recoverable state on next launch

## Stack Options

### C#/.NET + WinUI/WPF

Pros:

- native Windows ecosystem
- mature desktop app tooling
- good tray/background support
- strong access to Windows APIs
- easier enterprise install/signing story
- many audio interop options around WASAPI

Cons:

- separate codebase from Swift/macOS
- native audio capture still needs careful testing
- WinUI packaging can be more involved than WPF

### Rust/Tauri Shell with Native Audio

Pros:

- Rust core can be shared conceptually with cross-platform logic later
- Tauri UI can be lightweight compared with Electron
- native modules can call WASAPI
- smaller footprint than Electron

Cons:

- audio capture still requires Windows-specific native work
- Tauri adds web UI/runtime complexity
- tray/background behavior and installer details need careful validation
- harder fit if the UI should feel fully native Windows

## Recommendation

Use C#/.NET for the first Windows client.

Recommended split:

- WPF or WinUI for minimal tray/settings UI.
- Native WASAPI capture through .NET interop or a focused audio library.
- SQLite for local index.
- A small sync/uploader abstraction matching the macOS architecture.

Reasoning:

- The first Windows requirement is reliable audio capture and student-friendly setup, not cross-platform UI reuse.
- .NET gives direct access to Windows desktop conventions, installers, tray behavior, background startup, and diagnostics.
- Avoid Electron. Avoid a heavy web-style shell unless there is a strong reason to share UI code later.

Tauri/Rust can be revisited if a shared cross-platform core becomes important, but the audio layer remains platform-specific either way.

## Risks

### Audio Devices

Windows audio device setups vary widely:

- USB headsets
- Bluetooth headsets
- virtual audio devices
- HDMI/monitor audio
- default communications device vs default device
- device changes during recording

Mitigation:

- setup wizard
- explicit selected devices
- test recording
- diagnostics
- logs

### Antivirus

Background recording and audio capture may trigger antivirus or corporate policy concerns.

Mitigation:

- code signing
- clear app name and publisher
- transparent recording indicator
- no stealth behavior
- documented install/uninstall

### Permissions

Windows privacy settings can block microphone access.

Mitigation:

- preflight check
- setup wizard
- clear error messages
- link to Windows settings

### Weak Hardware

Some student laptops may have limited CPU, memory, or disk.

Mitigation:

- audio-only by default
- compact bitrate settings
- disk preflight
- avoid AI locally in Windows v1

### Bad Internet

Upload and sync can fail or be slow.

Mitigation:

- local-first storage
- durable upload queue
- retry with backoff
- visible upload/sync status
- never delete local files after failed upload

### Privacy and Legal

Student-side recording can be sensitive.

Mitigation:

- explicit setup consent
- visible recording indicator
- local-only option
- mentor/workspace policy later
- audit log
- no hidden recording

## Future Phases

### Phase 1: Local Student Recorder

- tray app
- manual recording
- mic + system audio
- local storage
- setup wizard
- test recording
- diagnostics

### Phase 2: Auto-Start

- known call app detection
- conservative browser heuristic
- whitelist/blacklist
- cooldown
- short recording handling

### Phase 3: Upload Queue

- external storage upload
- retry queue
- upload status
- storage link metadata

### Phase 4: T-Orbit Sync

- sign-in/device token
- metadata sync
- student-to-mentor recording visibility
- mentor sees recording card
- conflict/sync failure handling

## Open Questions

- Should the Windows client require T-Orbit login before recording, or allow anonymous local recording first?
- Which Windows versions are supported first?
- Should the app capture default output only or allow selected system output devices?
- What install/update mechanism is acceptable for students?
- How much control should mentors have over student auto-start policies?
- What legal consent flow is required for student-side interview recording?
