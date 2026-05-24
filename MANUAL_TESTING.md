# Manual Testing

Manual validation is required for the macOS MVP because microphone capture, ScreenCaptureKit system audio capture, app focus, and TCC permissions depend on the local Mac session.

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

The app runs as a menu bar app. Use the menu bar icon or the main panel for Show Window, Start Recording or Stop Recording, Play Last Recording, Open Last Recording Folder, Open Library, Settings, Diagnostics, and Quit.

Settings, Library, and Diagnostics open as separate app windows. If a window is behind other apps, use the menu bar item again; the app should activate and bring that window forward.

## Main Window Smoke Check

The main window should stay recorder-first:

- Header shows `TOrbit Recorder`, auto-start state, and a small Ready/Recording/Error status dot.
- Idle shows one large `Start Recording` button, then Mic, System audio, and Auto-start summaries.
- Recording shows a large timer, one large `Stop Recording` button, and recording copy.
- Error shows `Recording failed`, a short reason, `Open Diagnostics`, and `Try Again`.
- If a latest recording exists, it appears as one compact row: `Last: ...` with Play, Open, and Tag.
- The main window should not show file sizes, folder names, library filters, recoverable sessions, or a full recordings list.

## Menu Bar And Window Behavior

1. Open `dist/TOrbitRecorder.app`.
2. Confirm the menu bar item is visible.
3. Choose menu bar -> Show Window.
4. Confirm the existing main window comes to front and the app becomes active.
5. Close the main window with the red close button.
6. Confirm the app does not quit and the menu bar item remains visible.
7. Choose Show Window again.
8. Confirm the same main window returns without duplicate main windows.

Recording state:

- Idle shows a neutral record icon.
- Recording shows a filled red record icon when `Show recording indicator` is enabled.
- Error shows an orange error icon.

Quit while recording:

1. Start Recording.
2. Choose menu bar -> Quit, or press Cmd+Q while the app is active.
3. Confirm the app shows `Recording is active. Stop and quit?`.
4. Choose Cancel and confirm recording continues.
5. Choose Quit again, then Stop and Quit.
6. Confirm the recording stops before the app quits.

Dock behavior:

- Settings -> Privacy / Behavior -> Show Dock icon defaults on for MVP.
- Turning it off switches the app to menu-bar-only accessory behavior.
- If the Dock icon is hidden, use the menu bar item to reopen the main window.

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
5. Start a recording, then connect another microphone.
6. Confirm the active recording input does not change mid-recording; the new best input can be selected for the next recording.

## Permissions

On first launch, the app shows a permissions onboarding panel if anything needed for recording is missing. The panel checks:

- Microphone access
- Screen & System Audio Recording access
- Storage folder access

Each row shows one user-facing state:

- `Granted`: ready
- `Missing`: enable it in System Settings
- `Denied`: permission was blocked and must be changed in System Settings
- `Not determined`: macOS has not granted it yet
- `Restart required`: the setting was changed, but the current app process must be restarted
- `Unknown`: the app cannot determine the state

Grant permissions in macOS System Settings:

- Privacy & Security -> Microphone -> `TOrbitRecorder`
- Privacy & Security -> Screen & System Audio Recording -> `TOrbitRecorder`

If Microphone is `Not determined`, use the onboarding button to trigger the macOS microphone prompt. If it becomes `Denied`, enable it manually in System Settings.

If the app shows `Restart required`, quit `TOrbitRecorder` completely and reopen the same app bundle:

```sh
pkill -x TOrbitRecorder 2>/dev/null || true
open -n dist/TOrbitRecorder.app
```

When testing Screen & System Audio Recording, use the same app bundle path after granting permission. Switching between `.build/app/TOrbitRecorder.app`, `dist/TOrbitRecorder.app`, and `/Applications/TOrbitRecorder.app` can make macOS treat the build as a different app until it is approved and restarted.

For normal manual testing, prefer `dist/TOrbitRecorder.app` or `/Applications/TOrbitRecorder.app` over `.build/app/TOrbitRecorder.app`.

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
11. Expand Library filters and filter the list by the saved tag.
12. Click Open in Finder on the recording row.
13. Confirm Finder opens the recording folder.

## Output Files

In the recording folder, confirm these files exist and are non-empty:

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

Useful local checks:

```sh
stat -f "%z %N" source/mic.m4a source/system.m4a export/mixed.m4a metadata.json
afinfo source/mic.m4a
afinfo source/system.m4a
afinfo export/mixed.m4a
plutil -p metadata.json
```

Expected metadata:

- `status` is `needs_tagging`, `saved`, `needs_review`, or `reviewed` after a normal recording.
- `audio_tracks` includes `microphone`, `system`, and `mixed`.
- Completed audio tracks have `file_size_bytes` greater than 0.
- Completed audio tracks include `signal.had_signal`, `signal.approximate_silence_ratio`, and `signal.clipping_detected`.
- `quality_warnings` is empty for normal speech recordings.
- `source.trigger` is `manual` for manual starts.
- `sync` remains `local_only`.
- `ai` remains `not_started`.

## Audio Quality Warnings

Silent microphone check:

1. Start a short manual recording with the microphone muted or without speaking.
2. Stop the recording.
3. Confirm the Latest strip shows `Microphone track seems silent.` when the mic track has almost no signal.
4. Open `metadata.json` and confirm the microphone track has `signal.had_signal: false` or a high `approximate_silence_ratio`.

Silent system audio check:

1. Start a short manual recording with no system audio playing.
2. Stop the recording.
3. Confirm the Latest strip shows `System audio track seems silent.` when the system track has almost no signal.
4. Open `metadata.json` and confirm the system track has `signal.had_signal: false` or a high `approximate_silence_ratio`.

Clipping check:

1. Record very loud microphone input.
2. Confirm `metadata.json` sets microphone `signal.clipping_detected: true`.
3. Confirm the Latest strip can show `Microphone is clipping.`

## Post-Call Tagging

1. Stop a recording longer than the short threshold.
2. Confirm the post-call tagging panel appears.
3. Close the panel without saving.
4. Confirm the metadata status remains `needs_tagging`.
5. Open Library.
6. Click More -> Tag on the recording row and edit title/tags in the tag dialog.
7. Save edits.
8. Confirm `metadata.json` and the SQLite list reflect the changed title/tags.

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

Check actions:

- Open recording folder
- Play mixed preview
- Edit title/participant/tags through the Tag dialog
- Add/remove tags in the tag dialog
- Delete local record with confirmation

Delete should remove the local session folder and the SQLite index row.

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
7. Confirm the compact Latest strip shows `Short recording`, Play/Open/Tag work, and metadata still exists for false-positive review.

## Auto-Start: Zoom

1. Open Settings -> Auto-start.
2. Set Mode to `Auto`.
3. Confirm Zoom or `us.zoom.xos` is in the whitelist.
4. Confirm Zoom is not in the blacklist.
5. Open Zoom and join or start a call.
6. Speak into the microphone.
7. Wait for the configured detection duration, default 20 seconds.
8. Confirm recording starts automatically.
9. Stop recording.
10. Confirm metadata:

```text
source.app_name = Zoom
source.bundle_id = us.zoom.xos
source.trigger = autostart
source.rule_id = autostart.v2.zoom
source.confidence = high
source.reason = Zoom active with microphone activity.
```

Known caveat: V2 treats Zoom as a known call app, so system audio activity is not required for the direct-call-app shortcut.

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

Screen & System Audio Recording:

1. Revoke Screen & System Audio Recording permission for `TOrbitRecorder`.
2. Quit and reopen the app.
3. Click Start Recording.
4. Confirm the UI shows Error or system audio permission denied.
5. Confirm logs explain the ScreenCaptureKit permission or setup failure.

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

### Screen & System Audio Recording Permission

Symptom:

- `source/system.m4a` is missing or empty.
- ScreenCaptureKit start fails.
- System audio status shows permission denied or error.

Fix:

1. Open System Settings -> Privacy & Security -> Screen & System Audio Recording.
2. Enable `TOrbitRecorder`.
3. Quit and reopen the exact same `TOrbitRecorder.app` bundle you are testing.
4. Play audible audio from another app.
5. Retry recording.

If System Settings already shows `TOrbitRecorder` enabled but the app still reports a ScreenCaptureKit permission error, quit the app completely and reopen it. If you installed or opened another build path, approve that build too.

Developer reset if TCC gets stuck:

```sh
tccutil reset Microphone com.torbit.recorder
tccutil reset ScreenCapture com.torbit.recorder
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

- MVP mixed preview is created from available source tracks.
- If one source track is missing, mixed should still be created from the available track.
- If both source tracks are missing or empty, status should be `failed`.

Fix:

1. Check `metadata.json` `audio_tracks` for the failed side.
2. Validate source files with `stat` and `afinfo`.
3. Fix the missing source track permission/device issue.
4. Retry recording.
