# ToRec Windows v0.2.0 Beta

This is the first experimental Windows build of ToRec.

## What Works

- Manual microphone plus system-audio recording.
- Windows tray app.
- Records window with local playback/open-folder actions.
- Local diagnostics and logs.
- Local-only storage under `%USERPROFILE%\Recordings\TOrbitRecorder\`.

## What Does Not Work Yet

- No automatic Zoom/Google Meet/KTalk start in this beta.
- No installer; run `ToRec.exe` directly from the extracted folder.
- No cloud upload or T-Orbit sync.
- No AI transcription.

## How To Install

1. Download `ToRec-Windows-v0.2.0-beta.zip`.
2. Extract the zip to a normal folder, for example `Downloads\ToRec`.
3. Run `ToRec.exe`.
4. If Windows SmartScreen appears, choose `More info` -> `Run anyway` only if you trust this internal test build.

## How To Test

1. Open ToRec from the tray.
2. Press `Start Recording` before the call.
3. Speak and play call/system audio.
4. Press `Stop Recording`.
5. Open `Records` and play the latest recording.
6. Open the folder and confirm `metadata.json`, `source\mic.wav`, `source\system.wav`, and `export\mixed.wav` exist.

## Known Risks

- Windows audio device behavior varies by laptop/headset.
- Bluetooth headset microphones may sound bad. Prefer built-in or wired microphones for this beta.
- `.m4a` export is best-effort; `.wav` files are the reliable fallback.
- Auto-start will be added only after manual recording is validated.
