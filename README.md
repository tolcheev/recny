# T-Orbit Recorder

T-Orbit Recorder is a lightweight native macOS app for automatic audio recording of calls without OBS.

The MVP is a local-first recorder for Vlad, a QA/AQA mentor, who needs reliable recordings of student calls, lead sales calls, interview debriefs, and important or sensitive conversations.

## MVP

- macOS only.
- Target machine: MacBook M4 Pro.
- Target OS: macOS Sequoia.
- Audio-only recording.
- Automatic recording start.
- Auto-start v2 rule engine using active app, microphone activity, browser call-title heuristics, allowlist/blocklist, cooldown, and minimum detection duration.
- Microphone recording.
- Deterministic microphone input selection that avoids AirPods/Bluetooth headset mics when a built-in or external microphone is available.
- Full system audio recording.
- Local file storage.
- Local settings stored on the Mac.
- Settings screen for preferred microphone, recording toggles, auto-start rules, storage root, hotkey placeholders, and local privacy controls.
- `metadata.json` stored next to every recording.
- Manual Library tagging after recording stops.
- MVP tags saved to `metadata.json` and `db/app.sqlite`.
- Tag dialog supports quick tags, custom tags, and status selection without permanent tag controls on the main screen.
- Local recordings list with filters by date, status, source app, title, and tag.
- No Electron.
- No screen recording, cloud upload, T-Orbit sync, AI, or Windows support in MVP.

## Default Storage

```text
~/Recordings/TOrbitRecorder/
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

`db/app.sqlite` stores the local recordings index for list filtering and quick library actions. The recording folder and `metadata.json` remain the canonical record.

For daily use, use the app `Records` window or the `Library` Finder action. Internal folders under `Inbox/` are workflow buckets:

- `Inbox/Unsorted/`: in-progress staging and crash-recovery candidates.
- `Inbox/Short/`: short recordings below the configured threshold.
- `Inbox/Failed/`: failed sessions kept for diagnostics.

The app should not make you browse these internal folders during normal testing.

## Repository Layout

```text
apps/macos/         Native macOS menu bar app
packages/core/      Testable recording engine and local domain logic
packages/protocol/  Shared storage and metadata contracts
docs/               Product and engineering documentation
samples/scripts/    Local helper scripts and experiments
tests/              Integration fixtures and test assets
```

## Documentation

- `docs/PRODUCT_SPEC.md`: product goal, user, scenarios, and success criteria.
- `docs/MVP_SCOPE.md`: exact MVP boundaries.
- `docs/ARCHITECTURE.md`: client architecture and future integration boundaries.
- `docs/RECORDING_ENGINE.md`: recorder lifecycle and capture rules.
- `docs/AUTOSTART_RULES.md`: automatic start policy.
- `docs/STORAGE_FORMAT.md`: folder layout and metadata schema.
- `docs/SECURITY_PRIVACY.md`: local-first privacy constraints.
- `docs/UI_REDESIGN.md`: MVP UI structure and redesign notes.
- `docs/QA_CHECKLIST.md`: focused manual QA checklist for install, permissions, recording, UI, auto-start, and edge cases.
- `docs/BUG_REPORT_TEMPLATE.md`: copy/paste bug report format for fast handoff back to Codex.
- `docs/DEVELOPMENT_WORKFLOW.md`: branch, PR, validation, and release workflow for post-MVP development.
- `docs/ROADMAP.md`: staged future work.
- `docs/QA_CHECKLIST.md`: manual macOS MVP validation checklist and troubleshooting.

## Development Rules

- Prefer native macOS APIs: Swift, SwiftUI, AVFoundation, ScreenCaptureKit.
- Keep the recording engine testable separately from UI.
- Do not fake working audio capture.
- Add logs for recorder lifecycle events and failures.
- Update docs for every behavior change.
- Validate with `swift test` and `xcodebuild` when the relevant project files exist.

## Build

```sh
./scripts/build_macos.sh
```

The current shell is a SwiftPM-based macOS app target. The build script compiles it and assembles a local app bundle at `apps/macos/.build/app/TOrbitRecorder.app`. This `.build/app` bundle is a development artifact, not the normal launch location.

The build script injects app metadata into the bundle:

- app version: `v0.1.0-mvp`
- build date
- git commit hash

## Package

Create a shareable local package in `dist/`:

```sh
./scripts/package_macos.sh
```

This creates:

```text
dist/TOrbitRecorder.app
dist/TOrbitRecorder-v0.1.0-macOS.zip
dist/INSTALL.md
```

`dist/INSTALL.md` is included in the zip and explains permissions, restart behavior, recordings location, and uninstall steps.

## Install

Install the packaged app into `/Applications` and open it:

```sh
./scripts/install_macos.sh
```

The installer packages the app, asks a running TOrbitRecorder process to quit before replacement, copies the app bundle to `/Applications/TOrbitRecorder.app`, opens it, and prints next steps.

Dry-run the installer without copying or opening the app:

```sh
DRY_RUN=1 ./scripts/install_macos.sh
```

## Run

Use the installed app for normal manual testing:

```sh
open /Applications/TOrbitRecorder.app
```

Use `dist/` for shareable local artifacts and `/Applications/TOrbitRecorder.app` for a normal macOS launch. Do not use `apps/macos/.build/app/TOrbitRecorder.app` except when debugging the build script output directly.

Current recording implementation starts from the menu bar UI or Auto-start Engine v2 and writes `source/mic.m4a`, `source/system.m4a`, and a quick-listen `export/mixed.m4a` preview. When Volume leveling is enabled, it also creates `export/mixed_balanced.m4a` plus `analysis/audio_analysis.json`, and stores `audio.health` warnings in `metadata.json`. System audio uses a Core Audio process tap; no screen video is written. The main window is a compact recorder surface with one primary Start/Stop action; Library and Diagnostics open as separate windows. Marker metadata still exists, but marker controls are hidden from the default recorder UI until the workflow is clearer.

Older recordings can be reprocessed for balanced audio from `Library -> More -> Reprocess Audio`. Batch reprocessing for recordings missing `export/mixed_balanced.m4a` is available in `Diagnostics -> Audio Processing`.

Settings currently cover preferred microphone selection, recording toggles, auto-start rules, storage actions, hotkeys, Dock/menu-bar behavior, and local privacy controls. Unimplemented controls are disabled in the UI.

Active settings are persisted locally with `UserDefaults`. MVP defaults keep microphone selection on `Auto, recommended`, Standard audio quality, system audio and mixed preview enabled, auto-start enabled, Launch at Login enabled, the Dock icon hidden, a 3 minute cooldown, 20 second detection duration, and a 60 second short-recording threshold. T-Orbit Recorder is menu-bar-first by default; use the menu bar icon to show the app window when the Dock icon is hidden. Global Show Window hotkeys are disabled for now to avoid conflicts with other apps. Custom hotkey capture, local-only mode, and Focus Mode reminder are visible as disabled placeholders until their runtime behavior exists.

Settings/About and Diagnostics/App include the app version, build date, git commit hash, and local storage path.

## Launch At Login

Automatic launch is enabled by default. You can review or disable it in:

```text
Settings -> Behavior -> Launch at Login
```

The app first uses the modern macOS `SMAppService.mainApp` login item API. If a development/ad-hoc bundle reports that the main login item service is unavailable, the app falls back to a local user LaunchAgent and Diagnostics labels that state explicitly. The intended test path is still the installed app bundle:

```sh
./scripts/install_macos.sh
open /Applications/TOrbitRecorder.app
```

If macOS reports that approval is required, open System Settings -> General -> Login Items and enable TOrbitRecorder. Diagnostics shows the current login item status, the running bundle path, and the last Launch at Login error if registration fails. For development builds, avoid switching between `.build/app`, `dist/`, and `/Applications` while testing Launch at Login because macOS tracks login items by app bundle identity and path.

## Auto-Start And Auto-Stop

Auto-started Zoom recordings are not tied to Zoom being the foreground window. You can switch to browser, notes, IDE, or slides during a call and the app keeps the recording active.

For Zoom, auto-stop now prefers Zoom window state. A meeting/conference window keeps recording active, while the main Zoom home/workplace window starts the 30 second stop timer. If macOS does not expose Zoom window titles, the Zoom fallback ignores microphone activity from T-Orbit Recorder itself and keeps recording only while system audio is still active. Manual recordings do not auto-stop; they only stop from the Stop button, menu item, or app-active shortcut.

## Uninstall

Quit the app and remove the installed bundle:

```sh
osascript -e 'tell application "TOrbitRecorder" to quit' || true
rm -rf /Applications/TOrbitRecorder.app
```

This keeps local recordings. To delete all MVP recording data too:

```sh
rm -rf ~/Recordings/TOrbitRecorder
```

## Troubleshooting

Permissions are tied to the app bundle and code-signing identity that macOS sees. Dev packages are ad-hoc signed with the stable identifier `com.torbit.recorder`; install and run the same bundle every time:

```sh
./scripts/install_macos.sh
open /Applications/TOrbitRecorder.app
```

Do not keep multiple copies running from `.build`, `dist`, and `/Applications`. macOS permissions are applied to the app bundle, current process, and code-signing requirement, so a second copy or freshly rebuilt ad-hoc binary can trigger a macOS permission prompt even when another `TOrbitRecorder` entry is already enabled.

Check for duplicate running copies:

```sh
pgrep -fl TOrbitRecorder
```

System audio is captured with a Core Audio process tap. It should not require screen video capture. If the app still reports missing system audio permission or shows the macOS prompt again, quit every TOrbitRecorder copy and reopen only the installed app:

```sh
osascript -e 'tell application id "com.torbit.recorder" to quit' || true
open /Applications/TOrbitRecorder.app
```

macOS often requires a process restart after this permission changes. The app now blocks duplicate launches and points you back to the already-running copy.

If you approved an older unsigned/hash-signed dev build before this fix, toggle `TOrbitRecorder` off and on again in the system-audio section once, then restart `/Applications/TOrbitRecorder.app`.

On first launch, use `Fix Permissions` before recording. It requests microphone access and then runs a lightweight Core Audio system-audio permission probe, so the macOS system-audio prompt appears before `Start Recording` is available and before any recording folder is created. After each macOS permission prompt closes, the app requests focus for the existing main window again. This flow stays on the main window when the checks finish and no longer opens Diagnostics automatically.

After the Core Audio probe succeeds, T-Orbit Recorder remembers that system-audio capture is available for the current installed build. The app intentionally does not treat `CGPreflightScreenCaptureAccess()` as proof that Core Audio system capture is ready, because that can make Start Recording available before the system-audio prompt has been shown. Rebuilt ad-hoc packages must probe again so an older approved binary cannot make a new build look granted before macOS accepts it. A real recorder permission failure clears this remembered state and sends the user back to onboarding.

Grant permissions in:

- System Settings -> Privacy & Security -> Microphone
- System Settings -> Privacy & Security -> Screen & System Audio Recording -> `TOrbitRecorder`
- If macOS shows a separate `Only System Audio Recording` section, enable `TOrbitRecorder` there too.

Recordings are stored locally in `~/Recordings/TOrbitRecorder/`.

If Launch at Login fails in a development build, install the app into `/Applications`, reopen that exact bundle, and toggle Launch at Login again. When the local LaunchAgent fallback is used, the plist is stored at `~/Library/LaunchAgents/com.torbit.recorder.login.plist`.

## Microphone Input Policy

`Auto, recommended` is resolved by the core `DevicePriorityResolver`. It selects only the microphone input device and does not change the macOS output device. Priority is:

1. External microphones such as Shure MV7, Hollyland, USB microphones, and audio interfaces.
2. Built-in MacBook microphone.
3. AirPods and other Bluetooth headset microphones.

AirPods or Bluetooth headset microphones are used only when no other input device is available. If that fallback is used, the UI shows:

```text
Only Bluetooth headset microphone is available. Recording quality may be degraded.
```

## Developer Artifact

From the repository root:

```sh
scripts/build_macos.sh
open -n apps/macos/.build/app/TOrbitRecorder.app
```

The app runs as a menu bar app. Use the menu bar icon for Show Window, Start Recording or Stop Recording, Play Last Recording, Open Library, Open Records, Settings, Diagnostics, and Quit. `Open Library` opens the user-facing `Library/` folder, not the internal root with `db`, `logs`, and `Inbox`. `Open Records` opens the in-app searchable records list.

Records shows default untitled recordings as `Recording #N` so the list is scannable before a human title is added. Source app names are normalized for display, so auto-started Zoom calls appear as `Zoom` instead of raw bundle names like `zoom.us`.

For normal dev usage prefer:

```sh
./scripts/install_macos.sh
open /Applications/TOrbitRecorder.app
```

The menu bar app provides Show Window, Start Recording or Stop Recording, Play Last Recording, Open Library, Open Records, Settings, Diagnostics, and Quit.

## Manual MVP End-To-End Check

Detailed manual validation lives in `docs/QA_CHECKLIST.md`.

Before the first recording, click `Fix Permissions` in the app. The onboarding flow should request all required permissions before recording starts and stays on the main window when checks finish:

- Microphone
- Screen & System Audio Recording
- If shown separately: Screen & System Audio Recording -> Only System Audio Recording

If a permission is already denied, the app opens the matching System Settings pane so you can enable `TOrbitRecorder`, then restart the same app bundle if the UI shows `Restart required`.

Manual full recording pass:

1. Build and open the app with the commands above.
2. Open Settings and confirm Recording has `Preferred microphone` set to `Auto, recommended`, system audio enabled, and mixed preview enabled.
3. Click Start Recording from the menu bar item or main panel.
4. Speak into the microphone and play audible audio from another macOS app.
5. Record for longer than the short-recording threshold. The MVP default is 60 seconds; use at least 65 seconds for a normal saved recording.
6. Click Stop Recording.
7. Confirm the session folder contains:

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

8. Confirm `metadata.json` contains audio health and processing fields.
9. Open Records and confirm the recording appears in the recent recordings list.
10. Use More -> Tag or details -> Edit / Tag to add title, participant text, and tags, then save.
11. Select the recording and confirm its details panel shows Markers.
12. Filter by a saved tag.
13. Click Open in Finder on the recording row and confirm the recording folder opens.

Short recording check:

1. Start a new recording.
2. Stop before 60 seconds with default settings.
3. Confirm Records shows `Short recording`. Internally, the session is under `Inbox/Short/`, and post-call tagging is not opened automatically.

YouTube plus voice check:

1. Open a YouTube video in a browser and keep the browser audible through the normal Mac output device.
2. Start recording in T-Orbit Recorder.
3. Speak into the selected microphone while the YouTube audio is playing.
4. Stop recording, open Records, and use Play on the new row.
5. Confirm playback expands the inline Records player and prefers `export/mixed_balanced.m4a` when it exists, otherwise falls back to `export/mixed.m4a`.
6. Confirm the mixed preview contains both your voice and the YouTube audio.

Permission error check:

1. Revoke Microphone or system audio permission for `TOrbitRecorder` in System Settings.
2. Quit and reopen the app.
3. Confirm Start is blocked and the app shows `Fix Permissions`.
4. Click `Fix Permissions`.
5. Confirm the UI shows the missing permission state and the logs explain the blocked permission.

## Smoke Tests

Microphone smoke test for the current terminal process:

```sh
swift run --package-path apps/macos TOrbitRecorderMicSmokeTest --duration 10 --root apps/macos/.build/e2e/mic
```

If this prints `authorization_status=not_determined`, `denied`, or `restricted`, the terminal process does not have microphone permission. Run the app manually and grant permission to `TOrbitRecorder`, or grant microphone access to the terminal process before re-running the CLI smoke test.

System audio smoke test:

```sh
swift run --package-path apps/macos TOrbitRecorderSystemAudioSmokeTest --duration 10 --root apps/macos/.build/e2e/system
```

Play audio from another macOS app while this command runs. The command writes `source/system.m4a` and fails explicitly if the Core Audio process tap cannot start or if no samples are captured.

CLI smoke tests write their file logs under the provided `--root` folder. Unit tests write file logs under the system temporary directory, so running tests should not add test-only entries to `~/Recordings/TOrbitRecorder/logs/app.log`.
