# Recny Windows Beta

This is the experimental Windows client for Recny.

## Current Scope

Version: `0.2.5-beta`

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
- Quiet daily background update check from the tray app.
- Tray update badge plus `Update available` menu item with remind-later and skip-this-version behavior.
- `Report Bug` link from the main window and tray menu.

Not implemented in this beta:

- Installer.
- Cloud upload.
- T-Orbit sync.
- AI transcription.

## Storage

Default root:

```text
%USERPROFILE%\Recordings\Recny\
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
dotnet restore apps/windows/Recny.Windows/Recny.Windows.csproj
dotnet build apps/windows/Recny.Windows/Recny.Windows.csproj -c Release --no-restore
dotnet run --project apps/windows/Recny.Windows.Tests/Recny.Windows.Tests.csproj -c Release
dotnet publish apps/windows/Recny.Windows/Recny.Windows.csproj -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

## Test Instructions

1. Run `Recny.exe`.
2. Confirm a Recny icon appears in the Windows tray.
3. Start a Zoom/Meet/KTalk/Teams/Telegram/Discord call and wait at least 10 seconds.
4. Confirm Recny starts recording automatically.
5. Switch to another window/app during the call and confirm Recny keeps recording.
6. End the call and confirm Recny stops after about 10 seconds.
7. Open `Records` and play the latest recording.
8. Open the recording folder and confirm `metadata.json`, `source/mic.wav`, `source/system.wav`, and `export/mixed.wav` exist.

Manual `Start Recording` / `Stop Recording` remains available as a fallback if auto-start misses a call.

If recording fails, open `Diagnostics` and send the storage root, last error, and `logs/app.log`.
