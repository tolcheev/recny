# Windows v0.2 Beta Design

## Context

The shipped macOS MVP remains the primary ToRec client. Windows support is now a separate beta client so a student on Windows can test call recording without OBS.

This design intentionally does not port the full macOS feature set in one step. The first Windows artifact must prove reliable local microphone plus system-audio capture and produce a shareable `.exe` package from GitHub Actions.

## Goals

- Build a lightweight native Windows recorder under `apps/windows`.
- Produce a Windows zip artifact that contains a runnable `ToRec.exe`.
- Record microphone input and system audio locally.
- Save source tracks, a mixed export, and metadata per recording.
- Provide a tray-first UI with manual Start/Stop and basic diagnostics.
- Keep macOS code and release artifacts untouched.

## Non-Goals For v0.2 Beta

- No Windows auto-start by Zoom/Meet/KTalk detection.
- No installer/MSIX.
- No cloud upload.
- No T-Orbit backend sync.
- No bundled AI transcription models.
- No browser extension.
- No encryption or retention policy.

## Platform Choice

Use C#/.NET 8 with Windows Forms and NAudio:

- Windows Forms gives a small native tray app without Electron.
- NAudio gives WASAPI loopback and microphone capture.
- GitHub Actions Windows runners can build the `.exe` even though the current development machine is macOS.

## Recording Output

Windows v0.2 stores recordings under:

```text
%USERPROFILE%\Recordings\TOrbitRecorder\Library\YYYY\MM\<session-id>\
  source/
    mic.wav
    system.wav
    mic.m4a        # best effort
    system.m4a     # best effort
  export/
    mixed.wav
    mixed.m4a      # best effort
  metadata.json
```

The macOS MVP contract uses `.m4a`. Windows v0.2 keeps `.wav` source files as the reliable canonical output and writes `.m4a` best-effort through Windows Media Foundation when available. Metadata records exactly which files exist.

## UI

The Windows client has:

- Tray icon.
- Tray menu: Show, Start Recording, Stop Recording, Records, Open Records Folder, Diagnostics, Exit.
- Main window with recording state, elapsed time, Start/Stop, Records, Diagnostics, and Open Folder.
- Records window with local recording list, Play, Open Folder, and Refresh.
- Diagnostics window with OS, storage root, app version, NAudio version, and last recorder error.

## Logging And Failure Rules

- Write lifecycle logs under `%USERPROFILE%\Recordings\TOrbitRecorder\logs\app.log`.
- Log recorder start, stop, file paths, post-processing results, and failures.
- If microphone or WASAPI loopback capture cannot start, fail visibly and leave diagnostics.
- Do not create fake success metadata when capture fails before any usable files are opened.

## Release Plan

GitHub Actions builds on `windows-latest`:

1. Restore .NET dependencies.
2. Build Windows app.
3. Run the lightweight Windows console tests.
4. Publish a self-contained `win-x64` single-file app.
5. Zip the published folder.
6. Upload `ToRec-Windows-v0.2.0-beta.zip` as an Actions artifact.

The zip can then be attached to a prerelease after the build passes.

## Known Risks

- Windows audio devices vary more than the current macOS test machine.
- Bluetooth headset microphone quality can be poor; v0.2 does not implement hard Bluetooth mic blocking.
- Some Windows installations may lack Media Foundation AAC encoder behavior needed for `.m4a`; `.wav` remains the fallback.
- Auto-start is intentionally absent in v0.2, so the student must start recording manually.
