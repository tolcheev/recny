# ToRec Windows Beta

This is the experimental Windows client for ToRec.

## Current Scope

Version: `0.2.0-beta`

Implemented:

- Tray app.
- Manual Start/Stop recording.
- Microphone capture.
- System audio capture through WASAPI loopback.
- Local recordings folder.
- `metadata.json` per recording.
- Records window with Play and Open Folder.
- Diagnostics window and local file log.

Not implemented in this beta:

- Automatic Zoom/Meet/KTalk start.
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
3. Open ToRec and click `Start Recording` before a call.
4. Speak and play some system audio.
5. Click `Stop Recording`.
6. Open `Records` and play the latest recording.
7. Open the recording folder and confirm `metadata.json`, `source/mic.wav`, `source/system.wav`, and `export/mixed.wav` exist.

If recording fails, open `Diagnostics` and send the storage root, last error, and `logs/app.log`.
