# ToRec Windows v0.2.2 Beta

This Windows beta includes automatic call recording start and a safer auto-stop policy.

## What Works

- Automatic start for likely Zoom/Meet/KTalk/Teams/Telegram/Discord calls.
- Automatic stop for auto-started recordings after the active call audio session disappears.
- Window/app switching does not stop an active auto-started recording.
- Manual microphone plus system-audio recording as a fallback.
- Windows tray app.
- Records window with local playback/open-folder actions.
- Local diagnostics and logs.
- Local-only storage under `%USERPROFILE%\Recordings\TOrbitRecorder\`.

## What Does Not Work Yet

- No installer; run `ToRec.exe` directly from the extracted folder.
- No cloud upload or T-Orbit sync.
- No AI transcription.

## How To Install

1. Download `ToRec-Windows-v0.2.2-beta.zip`.
2. Extract the zip to a normal folder, for example `Downloads\ToRec`.
3. Run `ToRec.exe`.
4. If Windows SmartScreen appears, choose `More info` -> `Run anyway` only if you trust this internal test build.

## How To Test

1. Open ToRec once and leave it in the tray.
2. Join a Zoom/Meet/KTalk/Teams/Telegram/Discord call.
3. Wait at least 10 seconds.
4. Confirm ToRec starts recording automatically.
5. Switch to another window/app during the call and confirm recording continues.
6. End the call.
7. Confirm ToRec stops after about 10 seconds.
8. If auto-start misses a call, use manual `Start Recording` / `Stop Recording` and report the app/window name.
9. Open `Records` and play the latest recording.
10. Open the folder and confirm `metadata.json`, `source\mic.wav`, `source\system.wav`, and `export\mixed.wav` exist.

## Known Risks

- Windows audio device behavior varies by laptop/headset.
- Bluetooth headset microphones may sound bad. Prefer built-in or wired microphones for this beta.
- `.m4a` export is best-effort; `.wav` files are the reliable fallback.
- Browser auto-start depends on the browser window title at start time. Once recording has started, ToRec holds the recording by the active audio session instead of the active window.
