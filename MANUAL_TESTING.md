# Manual Testing

Manual validation is required for the macOS MVP because microphone capture, Core Audio system audio capture, app focus, and TCC permissions depend on the local Mac session.

## Test Device

Primary target:

- macOS Sequoia
- Apple Silicon
- MacBook M4 Pro

## Build And Launch

From the repository root:

```sh
scripts/build_macos.sh
scripts/package_macos.sh
open -n dist/TOrbitRecorder.app
```

The app runs as a menu bar app. Use the menu bar icon or the main panel for Show Window, Start Recording or Stop Recording, Play Last Recording, Open Recordings, Open Library, Settings, Diagnostics, and Quit.

Settings, Library, and Diagnostics open as separate app windows. If a window is behind other apps, use the menu bar item again; the app should activate and bring that window forward.

## Main Window Smoke Check

The main window should stay recorder-first:

- Header area shows compact auto-start and Ready/Recording/Error state. The app name stays in the window title/menu bar instead of being repeated in the content.
- Idle shows one large `Start Recording` button, then Mic, System audio, and Auto-start summaries.
- Recording shows a large timer, one large `Stop Recording` button, and recording copy.
- Error shows `Recording failed`, a short reason, `Open Diagnostics`, and `Try Again`.
- Recent recordings do not appear on the main window. Use Library for recent recordings, playback, details, and tagging.
- The main window should not show file sizes, folder names, library filters, recoverable sessions, details links, or a full recordings list.

## Menu Bar And Window Behavior

Expected menu items:

- `Show Window`
- `Start Recording` when idle, `Stop Recording` while recording
- `Play Last Recording`
- `Open Recordings`
- `Open Library`
- `Settings`
- `Diagnostics`
- `Quit`

1. Open `dist/TOrbitRecorder.app`.
2. Confirm the menu bar item is visible.
3. Choose menu bar -> Show Window.
4. Confirm the existing main window comes to front and the app becomes active.
5. Close the main window with the red close button.
6. Confirm the app does not quit and the menu bar item remains visible.
7. Choose Show Window again.
8. Confirm the same main window returns without duplicate main windows or extra app instances.

Recording state:

- Idle shows a neutral record icon.
- Recording shows a filled record icon. It is red when `Show recording indicator` is enabled.
- Error shows an orange error icon.
- The recording menu item changes from `Start Recording` to `Stop Recording` while recording.

Quit while recording:

1. Start Recording.
2. Choose menu bar -> Quit, or press Cmd+Q while the app is active.
3. Confirm the app shows `Recording is active. Stop and quit?`.
4. Choose Cancel and confirm recording continues.
5. Choose Quit again, then Stop and Quit.
6. Confirm the recording stops before the app quits.

Dock behavior:

- Settings -> Behavior -> Show Dock icon defaults off for MVP.
- With the Dock icon hidden, the app stays in the macOS menu bar.
- Use the menu bar item or `Option+R` to reopen the main window.

## Keyboard Shortcuts

The Show Window shortcut is global. Other shortcuts are app-active only in the MVP.

Expected shortcuts:

- `Option+R`: Show Window, including when the Dock icon is hidden.
- `Cmd+Shift+R`: Start Recording when idle, Stop Recording when recording.
- `Cmd+Shift+O`: Open Recordings.
- `Cmd+Shift+L`: Open Library.
- `Cmd+Shift+D`: Open Diagnostics.

Manual check:

1. Open TOrbitRecorder from `/Applications` or `dist/`.
2. Confirm Show Dock icon is off in Settings -> Behavior, switch to another app, then press `Option+R`.
3. Confirm T-Orbit Recorder comes to front.
4. Press `Cmd+Shift+L` and confirm Library opens.
5. Press `Cmd+Shift+D` and confirm Diagnostics opens.
6. Press `Cmd+Shift+O` and confirm Finder opens the user-facing `Library/` recordings folder.
7. Press `Cmd+Shift+R` while idle and confirm recording starts.
8. Press `Cmd+Shift+R` while recording and confirm recording stops.
9. Open Settings -> Hotkeys and confirm the same shortcuts are listed.
10. Open a text field in Settings or Tag dialog and confirm normal typing still works.

Marker shortcuts and marker buttons are hidden from the default UI for now. Existing recordings can still display marker metadata in Library details if metadata contains markers.

## Launch At Login

Launch at Login is on by default. The app first uses the modern macOS login item API through `SMAppService.mainApp`; development/ad-hoc builds can fall back to a local user LaunchAgent if macOS reports that the main login item service is unavailable.

Manual check:

1. Install and open the app from `/Applications`:

```sh
./scripts/install_macos.sh
open /Applications/TOrbitRecorder.app
```

2. Open Settings -> Behavior.
3. Confirm `Launch at Login` is already checked.
4. Confirm the helper text says it is enabled, enabled via local login agent, or says approval is required.
5. If approval is required, open System Settings -> General -> Login Items and enable TOrbitRecorder.
6. Open Diagnostics and confirm Behavior shows:
   - Launch at Login preference
   - macOS login item status
   - running bundle path
   - no Launch at Login error, or a human-readable error if registration failed
7. Quit TOrbitRecorder.
8. Log out and log back in, or restart the Mac.
9. Confirm TOrbitRecorder launches after login and the menu bar item appears.
10. Turn `Launch at Login` off and confirm T-Orbit Recorder is removed or disabled from Login Items. If Diagnostics reported the local login agent fallback, confirm `~/Library/LaunchAgents/com.torbit.recorder.login.plist` is removed.

Known dev-build caveat:

- Test from one stable app bundle path, preferably `/Applications/TOrbitRecorder.app`.
- Switching between `.build/app/TOrbitRecorder.app`, `dist/TOrbitRecorder.app`, and `/Applications/TOrbitRecorder.app` can make macOS treat them as different app bundles.
- If the toggle fails, reinstall to `/Applications`, reopen that exact bundle, and retry.

## Preflight

1. Quit any old `TOrbitRecorder` instance.
2. Build and open the app.
3. Open Settings.
4. Confirm Recording settings:
   - Preferred microphone: Auto, recommended
   - System audio enabled: on
   - Mixed preview enabled: on
5. Confirm Storage root is the intended local folder, normally:

```text
~/Recordings/TOrbitRecorder/
```

6. Confirm there is enough free disk space for local audio files.
7. Confirm Start does not create a recording folder when required preflight checks fail:
   - missing microphone permission
   - missing or denied system audio permission while system audio is enabled
   - no available microphone input
   - output folder not writable
   - free disk space below 2 GB
8. After a preflight failure, confirm `Inbox/Unsorted` does not contain a new empty recoverable session.

## Microphone Selection Policy

1. Open Settings -> Recording.
2. Confirm Preferred microphone defaults to `Auto, recommended`.
3. Confirm the helper copy says Auto prefers external or built-in mics and avoids AirPods mic.
4. Confirm available inputs are labeled as `Recommended`, `Built-in`, `Bluetooth fallback`, or `Available`.
5. Open Diagnostics and confirm it shows:
   - Selected input
   - Recommended input
   - Reason

AirPods check:

1. Connect AirPods.
2. Keep the MacBook microphone available.
3. Click Refresh in Settings or Diagnostics.
4. Confirm Main shows `Mic: MacBook Pro Microphone`, not AirPods.
5. Confirm Diagnostics reason says AirPods microphone was avoided because a built-in microphone is available.

External mic check:

1. Connect Shure MV7, Hollyland, USB microphone, or an audio interface.
2. Keep Preferred microphone on `Auto, recommended`.
3. Click Refresh or wait a few seconds for device refresh.
4. Confirm Main shows the external microphone name.
5. Manually select an external mic, then unplug it.
6. Confirm Main and Diagnostics fall back to MacBook/Built-in microphone instead of AirPods when the built-in mic is available.
7. Start a recording, then connect another microphone.
8. Confirm the active recording input does not change mid-recording; the new best input can be selected for the next recording.

## Permissions

On first launch, the app shows a permissions onboarding panel if anything needed for recording is missing. The panel checks:

- Microphone
- System audio
- Output folder writable

Each row shows one user-facing state:

- `Granted`: ready
- `Missing`: enable it in System Settings
- `Denied`: permission was blocked and must be changed in System Settings
- `Not determined`: click the onboarding action to show the macOS prompt before recording
- `Restart required`: the setting was changed, but the current app process must be restarted
- `Unknown`: the app cannot determine the state

Grant permissions in macOS System Settings:

- Privacy & Security -> Microphone -> `TOrbitRecorder`
- Privacy & Security -> Screen & System Audio Recording -> `TOrbitRecorder`
- If macOS shows a separate `Only System Audio Recording` section, enable `TOrbitRecorder` there too.

If Microphone is `Not determined`, use the onboarding button to trigger the macOS microphone prompt. If it becomes `Denied`, enable it manually in System Settings.

If System audio is `Not determined` or `Missing`, click `Request System Audio Access` or the main `Fix Permissions` button. The app runs a lightweight Core Audio permission probe that should show the macOS system-audio prompt before any recording folder is created. `Start Recording` should remain unavailable until this permission is granted.

After that probe succeeds, the app persists a local "system audio probe succeeded" state for the installed bundle. This is intentional: on macOS Sequoia, the Core Audio system-audio permission can be granted even when the older screen-capture preflight API still reports `false`. If a real recording start later fails with a system-audio permission error, the app clears the persisted state and returns to onboarding.

Expected first-launch flow:

1. Click `Fix Permissions`.
2. Approve the microphone prompt if macOS shows it.
3. Approve the system-audio prompt when macOS shows it.
4. If onboarding shows `Restart required`, restart the same app bundle.
5. Confirm the main button changes back to `Start Recording`.

If system audio is denied or still missing after a failed start:

1. Click `Open System Audio Settings`.
2. Enable `TOrbitRecorder`.
3. Return to the app.
4. If the app shows `Permission is enabled. Restart T-Orbit Recorder to apply it.`, click `Restart App` in onboarding or quit from the menu bar.
5. Reopen the same app bundle shown by onboarding. Normal manual test path:

```sh
open /Applications/TOrbitRecorder.app
```

If the app shows `Restart required`, quit `TOrbitRecorder` completely and reopen the same app bundle:

```sh
osascript -e 'tell application id "com.torbit.recorder" to quit' || true
open /Applications/TOrbitRecorder.app
```

When testing system audio permission, use the same app bundle path after granting permission. Switching between `.build/app/TOrbitRecorder.app`, `dist/TOrbitRecorder.app`, and `/Applications/TOrbitRecorder.app` can make macOS treat the build as a different app until it is approved and restarted. This is why permission can look enabled in System Settings while the currently running process still reports missing access.

Dev packages use the stable bundle identifier `com.torbit.recorder`, but ad-hoc signing still changes the code hash after rebuilds. If you previously approved an older build and the prompt still appears, toggle `TOrbitRecorder` off and on again in Screen & System Audio Recording once, then restart `/Applications/TOrbitRecorder.app`.

For normal manual testing, prefer `/Applications/TOrbitRecorder.app` over `.build/app/TOrbitRecorder.app`.

If the macOS Screen Recording prompt appears even though `TOrbitRecorder` is enabled in System Settings, check for duplicate app copies:

```sh
pgrep -fl TOrbitRecorder
```

There should be one process. If `.build`, `dist`, and `/Applications` copies are all running, quit them all, then reopen only:

```sh
open /Applications/TOrbitRecorder.app
```

The app blocks new duplicate launches, but already-running older copies must still be quit manually before reliable permission testing.

## Full Recording Checklist

Use this path for the normal MVP success case.

1. Start playing audible system audio from another app.
2. Click Start Recording.
3. Speak into the microphone.
4. Keep recording for at least 65 seconds with default settings.
5. Click Stop Recording.
6. Confirm the UI returns to Idle.
7. Confirm the post-call tagging panel opens.
8. Fill:
   - title
   - participant free text
   - at least one MVP tag
9. Save the post-call panel.
10. Open Library and confirm the recording appears in recent recordings.
11. Select the recording and confirm the details panel shows audio analysis and tags.
12. Expand Library filters and filter the list by the saved tag.
13. Click Open in Finder on the recording row.
14. Confirm Finder opens the recording folder.

## Output Files

In the recording folder, confirm these files exist and are non-empty:

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
export/mixed_balanced.m4a
analysis/audio_analysis.json
metadata.json
```

Useful local checks:

```sh
stat -f "%z %N" source/mic.m4a source/system.m4a export/mixed.m4a export/mixed_balanced.m4a analysis/audio_analysis.json metadata.json
afinfo source/mic.m4a
afinfo source/system.m4a
afinfo export/mixed.m4a
afinfo export/mixed_balanced.m4a
plutil -p metadata.json
plutil -p analysis/audio_analysis.json
```

Expected metadata:

- `status` is `needs_tagging`, `saved`, `needs_review`, or `reviewed` after a normal recording.
- `audio_tracks` includes `microphone`, `system`, `mixed`, and `mixed_balanced` when Volume leveling is enabled.
- Completed audio tracks have `file_size_bytes` greater than 0.
- Completed audio tracks include `signal.had_signal`, `signal.approximate_silence_ratio`, and `signal.clipping_detected`.
- `audio.processing.balanced_mix_status` is `done` when `mixed_balanced.m4a` was created.
- `audio.processing.balanced_mix_path` is `export/mixed_balanced.m4a`.
- `audio.processing.analysis_path` is `analysis/audio_analysis.json`.
- `audio.processing.mic_gain_db` and `audio.processing.system_gain_db` show the applied balancing plan.
- `audio.health.status` is `good`, `warning`, or `failed`.
- `audio.health.warnings` contains compact warning codes such as `mic_too_quiet`, `system_silent`, `clipping_detected`, or `balanced_mix_failed`.
- `quality_warnings` is empty for normal speech recordings.
- `source.trigger` is `manual` for manual starts.
- `sync` remains `local_only`.
- `ai` remains `not_started`.
- `markers` is present. It may be empty because marker controls are hidden from the default UI.

Marker metadata example:

```json
"markers": [
  {
    "id": "A1B2",
    "time_sec": 12,
    "label": "Important",
    "tags": ["important"],
    "created_at": "2026-05-24T01:00:12.000Z"
  }
]
```

## Audio Leveling

Audio Leveling v1 creates a balanced playback preview after Stop Recording.

Expected behavior:

- Raw files are not modified:
  - `source/mic.m4a`
  - `source/system.m4a`
- Original simple mix remains:
  - `export/mixed.m4a`
- Balanced playback preview is created:
  - `export/mixed_balanced.m4a`
- Analysis is saved:
  - `analysis/audio_analysis.json`
- Library rows show `Balanced` plus `Audio OK`, `Audio warning`, or `Audio failed`.
- Play opens the built-in T-Orbit Recorder player and uses `mixed_balanced.m4a` by default when it exists.
- Diagnostics -> Audio Processing can play Current and Original.
- Library row -> More can play Balanced, play Original, open the folder, reveal `audio_analysis.json`, reprocess audio, or edit note/tags.
- Library details show audio health when audio health is warning/failed.
- Library rows show a compact `Balanced` badge when balanced playback is ready, or `Audio warning` when leveling failed.
- Library rows also show a compact audio warning badge for problematic recordings.
- Library details show original mixed size, balanced mixed size, mic gain, system gain, audio health, and audio warnings.

Reprocess one old recording:

1. Open Library.
2. Pick a recording that has `export/mixed.m4a` but no `export/mixed_balanced.m4a`.
3. Open row `More`.
4. Click `Reprocess Audio`.
5. Confirm `export/mixed_balanced.m4a` and `analysis/audio_analysis.json` are created.
6. Confirm `metadata.json` now has `audio.processing.balanced_mix_status` and `audio.health.status`.
7. Confirm the Library row updates to show balanced/audio health state.

Overwrite existing balanced audio:

1. Open Library on a recording that already has `export/mixed_balanced.m4a`.
2. Open row `More`.
3. Click `Reprocess Audio`.
4. Confirm the overwrite/skip prompt appears.
5. Choose `Skip` and confirm the existing file remains.
6. Repeat and choose `Overwrite Balanced Audio`.
7. Confirm only `export/mixed_balanced.m4a`, `analysis/audio_analysis.json`, and `metadata.json` changed.

Reprocess all old recordings:

1. Open Diagnostics.
2. In `Audio Processing`, click `Reprocess Missing Balanced Audio`.
3. Confirm progress text shows the current recording and total count.
4. Confirm the final summary shows processed/skipped/failed counts.
5. Open Library and verify old recordings now have balanced playback where source files were usable.

Manual balance check: loud YouTube + quiet voice

1. Open Settings -> Recording.
2. Confirm Volume leveling is on and mode is `Balanced`.
3. Play YouTube or another loud system audio source.
4. Speak quietly into the microphone.
5. Record for 20-30 seconds.
6. Stop recording.
7. Open the recording folder.
8. Compare:
   - `export/mixed.m4a`
   - `export/mixed_balanced.m4a`
9. Confirm the balanced file makes the quiet microphone easier to hear without obvious clipping.
10. Open `analysis/audio_analysis.json` and confirm mic/system gain values are recorded.

Manual balance check: quiet YouTube + loud voice

1. Play quiet system audio.
2. Speak loudly into the microphone.
3. Record for 20-30 seconds.
4. Stop recording.
5. Compare Original vs Balanced from Diagnostics:
   - `Play Original` should use `export/mixed.m4a`.
   - `Play Current` should use `export/mixed_balanced.m4a` when available.
6. Confirm the balanced file does not make the microphone painfully loud.
7. Use Library -> More -> Reveal Audio Analysis and confirm Finder selects `analysis/audio_analysis.json`.

Limits:

- Maximum gain boost: `+12 dB`.
- Maximum attenuation: `-12 dB`.
- Limiter/safe peak ceiling: `-1 dBFS`.
- Mostly silent tracks are not aggressively boosted.
- If balanced processing fails, `export/mixed.m4a` remains available and metadata records `balanced_mix_status = failed`.

## Audio Health Warnings

Silent microphone check:

1. Start a short manual recording with the microphone muted or without speaking.
2. Stop the recording.
3. Confirm the Library row shows `Audio warning`.
4. Open Library details and confirm the copy includes `Microphone track is silent`.
5. Open `metadata.json` and confirm `audio.health.warnings` contains `mic_silent`.
6. Confirm the microphone track has `signal.had_signal: false` or a high `approximate_silence_ratio`.

Silent system audio check:

1. Start a short manual recording with no system audio playing.
2. Stop the recording.
3. Confirm the Library row shows `Audio warning`.
4. Open Library details and confirm the copy includes `System audio track is silent`.
5. Open `metadata.json` and confirm `audio.health.warnings` contains `system_silent`.
6. Confirm the system track has `signal.had_signal: false` or a high `approximate_silence_ratio`.

Clipping check:

1. Record very loud microphone input.
2. Confirm `metadata.json` sets microphone `signal.clipping_detected: true`.
3. Confirm `metadata.json` includes `audio.health.warnings: ["clipping_detected"]` or contains that code among other warnings.
4. Confirm Library details show `Clipping detected`.

Balanced mix failure check:

1. Temporarily disable Volume leveling or simulate a missing/failed balanced export during development.
2. Confirm Play still falls back to `export/mixed.m4a`.
3. Confirm `metadata.json` records `audio.health.warnings` with `balanced_mix_failed` when leveling fails.
4. Confirm UI copy says `Balanced mix failed, original audio is available`.

## Post-Call Tagging

1. Stop a recording longer than the short threshold.
2. Confirm the post-call tagging panel appears.
3. Close the panel without saving.
4. Confirm the metadata status remains `needs_tagging`.
5. Open Library.
6. Click More -> Tag on the recording row and edit title, participant, quick tags, custom tags, and status.
7. Confirm Enter saves from text fields, Cmd+Enter saves, and Escape closes without saving.
8. Save edits.
9. Confirm `metadata.json` and the SQLite list reflect the changed title/tags/status.

## Library

Open Library from the main footer or menu bar. Confirm it opens as a separate window with a recent recordings list and a details panel for the selected recording.

Check search:

- title
- participant
- tags
- source app

Check collapsed filters:

- status
- date range
- source app
- tags
- audio health

Check actions:

- Open recording folder
- Play mixed preview in the built-in T-Orbit Recorder player
- Edit title/participant/context note/tags through `More -> Edit Note / Tags` or the details `Edit / Tag` action
- Add/remove tags and context notes in the tag dialog
- Reveal Audio Analysis from details when `analysis/audio_analysis.json` exists
- Delete local record with confirmation

Delete confirmation should say `This removes audio files and metadata.` Delete should remove the local session folder and the SQLite index row.

## Short Recording

With default settings, the short recording threshold is 60 seconds.

1. Start Recording.
2. Record for less than 60 seconds.
3. Stop Recording.
4. Confirm the session status is `short_recording`.
5. Confirm the session is stored under:

```text
~/Recordings/TOrbitRecorder/Inbox/Short/
```

6. Confirm post-call tagging does not open automatically.
7. Open Library and confirm the row shows `Short recording`, Play/Open/Edit work, and metadata still exists for false-positive review.

## Auto-Start: Zoom

1. Open Settings -> Auto-start.
2. Set Mode to `Auto`.
3. Confirm Zoom or `us.zoom.xos` is in the whitelist.
4. Confirm Zoom is not in the blacklist.
5. Open Zoom and join or start a call.
6. Speak into the microphone.
7. Wait for the configured detection duration, default 20 seconds.
8. Confirm recording starts automatically.
9. Switch to another app during the call and confirm the recording continues.
10. End the Zoom call or close Zoom.
11. Wait up to 35 seconds after microphone and system-audio activity stop.
12. Confirm the app stops recording automatically and the row appears in Library.
13. Confirm metadata:

```text
source.app_name = Zoom
source.bundle_id = us.zoom.xos
source.trigger = autostart
source.rule_id = autostart.v2.zoom
source.confidence = high
source.reason = Zoom active with microphone activity.
```

Known caveat: V2 treats Zoom as a known call app, so system audio activity is not required for the direct-call-app shortcut.

Auto-stop caveat: auto-stop only applies to recordings that started from auto-start. Manual recordings must still be stopped manually.

## Auto-Start: Browser Heuristic

1. Open Settings -> Auto-start.
2. Set Mode to `Auto`.
3. Confirm the browser is in the whitelist: Google Chrome, Safari, Firefox, Yandex Browser, or Microsoft Edge.
4. Confirm the browser is not in the blacklist.
5. Open a browser-based call whose window title includes a call-like word, such as Meet, Zoom, Teams, Interview, Call, or Встреча.
6. Speak into the microphone.
7. Ensure system audio is active in the browser or another app.
8. Keep the browser active in the foreground.
9. Wait for the configured detection duration.
10. Confirm recording starts automatically.
11. Stop recording.
12. Confirm metadata has `source.trigger = autostart` and `source.rule_id = autostart.v2.browser_title`.

False positive check:

1. Open a YouTube/video page in a whitelisted browser.
2. Play system audio without microphone activity.
3. Confirm recording does not start.
4. If microphone activity is present and the title is available but does not look call-like, confirm recording still does not start.

Known caveat: V2 does not inspect URLs or meeting rooms. If the active browser window title is unavailable, browser fallback can still start from microphone + system audio activity with medium confidence.

## Auto-Start: Ask First

1. Open Settings -> Auto-start.
2. Set Mode to `Ask first`.
3. Trigger a Zoom or browser-call signal.
4. Wait for the configured detection duration.
5. Confirm the app notifies that a call was detected but does not start recording automatically.
6. Start recording manually from the main window or menu bar if the call should be recorded.

## Permission Error Check

Microphone:

1. Revoke Microphone permission for `TOrbitRecorder`.
2. Quit and reopen the app.
3. Click Start Recording.
4. Confirm the UI shows Error and microphone permission denied.
5. Confirm the app does not mark the session as a successful recording.

System audio:

1. Revoke system audio permission for `TOrbitRecorder`.
2. Quit and reopen the app.
3. Click Start Recording.
4. Confirm the UI shows Error or system audio permission denied.
5. Confirm logs explain the Core Audio process tap permission or setup failure.

## Troubleshooting

### Microphone Permission Is `not_determined`

Symptom:

- CLI smoke test prints `authorization_status=not_determined`.
- App start triggers a microphone permission prompt or fails before recording.

Fix:

1. Run the app bundle, not only the CLI smoke test.
2. Grant Microphone permission to `TOrbitRecorder`.
3. Quit and reopen the app.
4. Retry Start Recording.

The CLI smoke test uses the current terminal process. It needs separate microphone permission for that terminal/Codex process.

CLI smoke tests write logs under their `--root` folder. Regular unit tests write file logs under the system temporary directory, so test runs should not pollute `~/Recordings/TOrbitRecorder/logs/app.log`.

### System Audio Permission

Symptom:

- `source/system.m4a` is missing or empty.
- Core Audio process tap start fails.
- System audio status shows permission denied or error.

Fix:

1. Open System Settings -> Privacy & Security -> Screen & System Audio Recording.
2. Enable `TOrbitRecorder`. If macOS shows `Only System Audio Recording`, enable it there too.
3. Quit and reopen the exact same `TOrbitRecorder.app` bundle you are testing.
4. Play audible audio from another app.
5. Retry recording.

If System Settings already shows `TOrbitRecorder` enabled but the app still reports a system audio permission error, click `Request System Audio Access` once in onboarding. If the probe succeeds, the app should switch to `Granted` immediately and stay granted after restart. If it fails, quit the app completely, reopen the same `/Applications/TOrbitRecorder.app` bundle, and approve that bundle in System Settings.

Developer reset if TCC gets stuck:

```sh
tccutil reset Microphone com.torbit.recorder
tccutil reset ScreenCapture com.torbit.recorder
tccutil reset AudioCapture com.torbit.recorder
```

After reset, reopen the same app bundle and grant permissions again.

### No System Audio

Symptom:

- `source/system.m4a` exists but has very small size or no audible content.
- System audio smoke test has zero samples or fails.

Fix:

1. Make sure another app is producing audible output during the test.
2. Check the current macOS output device and volume.
3. Keep system audio enabled in Settings.
4. Re-run the system audio smoke test:

```sh
swift run --package-path apps/macos TOrbitRecorderSystemAudioSmokeTest --duration 10 --root apps/macos/.build/e2e/system
```

### No Mic Audio

Symptom:

- `source/mic.m4a` is missing, empty, or silent.
- Mic status shows permission denied or no input device.

Fix:

1. Check Microphone permission for `TOrbitRecorder`.
2. Check macOS Sound input device.
3. Open Settings -> Recording -> Preferred microphone and confirm Auto selects an external or built-in microphone before AirPods.
4. Confirm the microphone input level moves in System Settings.
5. Reopen the app and retry.

### AirPods Selected As Microphone

Symptom:

- The selected mic is AirPods or another Bluetooth headset.
- Incoming system audio quality degrades during recording.

Expected behavior:

- Auto microphone selection should choose Shure/MV7/Hollyland/USB/audio interface devices first.
- If no external mic exists, it should choose `MacBook Pro Microphone` or `Built-in Microphone`.
- AirPods/Bluetooth headset microphones should be used only when no other input device is available.

Fix:

1. Open Settings -> Recording -> Preferred microphone.
2. Keep `Auto, recommended` unless you need a specific external microphone.
3. Confirm AirPods is labeled `Bluetooth fallback`.
4. Click Refresh.
5. Confirm the main window shows `Mic: MacBook Pro Microphone` or the external mic name while AirPods remain connected for output.
6. If AirPods is the only available input, confirm the main window shows `Bluetooth microphone is used. Audio quality may be degraded.`

### Mixed File Missing One Side

Symptom:

- `export/mixed.m4a` exists but contains only mic or only system audio.

Expected behavior:

- MVP mixed preview may be created from available source tracks for diagnostics.
- A recording should not be shown as Saved unless required source tracks and `mixed.m4a` exist and are non-empty.
- If a required source track or `mixed.m4a` is missing, failed, or empty, status should be `failed`.
- Empty files should produce a human-readable reason: `Empty audio file`.

Fix:

1. Check `metadata.json` `audio_tracks` for the failed side.
2. Validate source files with `stat` and `afinfo`.
3. Fix the missing source track permission/device issue.
4. Retry recording.
