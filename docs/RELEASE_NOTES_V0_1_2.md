# ToRec v0.1.2 macOS MVP

Internal Apple Silicon macOS build for local-first call recording.

## What Changed Since v0.1.1

- User-facing app name changed from T-Orbit Recorder to ToRec.
- Packaged app bundle is now `ToRec.app`.
- Release archive is now `ToRec-v0.1.2-macOS.zip`.
- The bundle identifier remains `com.torbit.recorder` for permission continuity.
- The executable name remains `TOrbitRecorder` internally to avoid risky SwiftPM target churn before testing.
- Installer removes the legacy `/Applications/TOrbitRecorder.app` while installing `/Applications/ToRec.app`.
- Local storage remains `~/Recordings/TOrbitRecorder/` so existing recordings continue to load.

## What Works

- Native Swift/SwiftUI menu bar app with no Electron.
- Manual and automatic audio-only recording.
- Microphone plus system audio capture.
- Required local outputs per recording:
  - `source/mic.m4a`
  - `source/system.m4a`
  - `export/mixed.m4a`
  - `metadata.json`
- Optional balanced mix:
  - `export/mixed_balanced.m4a`
  - `analysis/audio_analysis.json`
- Local recordings list with search, filters, details, playback, Finder open, share sheet, copy audio path, non-destructive trim, screenshot capture, local optional transcription, tags, and delete.
- Zoom auto-start/auto-stop v2:
  - tracks Zoom process audio when available;
  - keeps recording active when the Zoom call continues in the background;
  - stops close to 10 seconds after the call signal disappears.
- AirPods/Bluetooth headset microphones are blocked for recording; built-in or external microphones are preferred.
- Menu bar status item:
  - red question mark when recording permissions are missing;
  - play-style icon when ready/recording;
  - global `Ctrl+Option+R` to show the app window;
  - global `Ctrl+Option+S` for full-screen screenshot capture.
- Local-first storage under `~/Recordings/TOrbitRecorder/`.
- No macOS Notifications permission request.

## Local-Only Boundaries

- No cloud upload.
- No T-Orbit backend sync.
- No Telegram bot/API integration.
- No screen video recording.
- No automatic AI processing.
- Optional transcription is local-only and user-triggered after explicit setup in Settings.

## Install

1. Download `ToRec-v0.1.2-macOS.zip`.
2. Unzip it.
3. Move `ToRec.app` to `/Applications`.
4. Open `/Applications/ToRec.app`.
5. Grant:
   - Microphone;
   - Screen & System Audio Recording / Only System Audio Recording.
6. Quit and reopen the same `/Applications/ToRec.app` after changing permissions.

This is an internal ad-hoc signed build, not a notarized public macOS release. If Gatekeeper blocks it, use Finder -> Applications -> right-click `ToRec` -> Open. For trusted internal testing only:

```sh
xattr -dr com.apple.quarantine /Applications/ToRec.app
open /Applications/ToRec.app
```

## Known Limitations

- Focused on macOS Sequoia and Apple Silicon.
- Ad-hoc signed; not notarized with Developer ID yet.
- Auto-start uses native macOS signals and heuristics; Zoom is the most tested path.
- Optional local transcription requires `uv`, `ffmpeg`, and Parakeet setup from Settings.
- No DMG installer yet.

## Validation

- `swift test --package-path apps/macos`
- `scripts/package_macos.sh`
- `codesign --verify --deep --strict --verbose=2 dist/ToRec.app`
- `spctl` Gatekeeper check is expected to reject this internal ad-hoc build until Developer ID notarization is added.
