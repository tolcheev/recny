# ToRec Windows Beta

This is the experimental Windows client for ToRec.

## Current Scope

Version: `0.2.3-beta`

Implemented:

- Tray app.
- Automatic start for likely Zoom/Meet/KTalk/Teams/Telegram/Discord calls.
- Automatic stop for auto-started recordings after the active call audio session disappears.
- Window/app switching does not stop an active auto-started recording.
- Manual Start/Stop recording.
- Microphone capture.
- System audio capture through WASAPI loopback.
- Local recordings folder.
- `metadata.json` per recording.
- Records window with Play and Open Folder.
- Diagnostics window and local file log.
- Manual `Check for Updates` action from the main window and tray menu.

Not implemented in this beta:

- Installer.
- Cloud upload.
- T-Orbit sync.
- AI transcription.

## Storage

Default root:

```text
%USERPROFILE%\Recordings\TOrbitRecorder\
```

Each recording creates:

```text
Library/YYYY/MM/<session-id>/
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

The `.wav` files are the reliable local output. `.m4a` files are best-effort exports using Windows Media Foundation.

## Build Locally On Windows

```powershell
dotnet restore apps/windows/ToRec.Windows/ToRec.Windows.csproj
dotnet build apps/windows/ToRec.Windows/ToRec.Windows.csproj -c Release --no-restore
dotnet run --project apps/windows/ToRec.Windows.Tests/ToRec.Windows.Tests.csproj -c Release
dotnet publish apps/windows/ToRec.Windows/ToRec.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## Test Instructions

1. Run `ToRec.exe`.
2. Confirm a ToRec icon appears in the Windows tray.
3. Start a Zoom/Meet/KTalk/Teams/Telegram/Discord call and wait at least 10 seconds.
4. Confirm ToRec starts recording automatically.
5. Switch to another window/app during the call and confirm ToRec keeps recording.
6. End the call and confirm ToRec stops after about 10 seconds.
7. Open `Records` and play the latest recording.
8. Open the recording folder and confirm `metadata.json`, `source/mic.wav`, `source/system.wav`, and `export/mixed.wav` exist.

Manual `Start Recording` / `Stop Recording` remains available as a fallback if auto-start misses a call.

If recording fails, open `Diagnostics` and send the storage root, last error, and `logs/app.log`.
