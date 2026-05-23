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
open -n apps/macos/.build/app/TOrbitRecorder.app
```

The app runs as a menu bar app. Use the menu bar icon or the main panel for Show Window, Start Recording or Stop Recording, Play Last Recording, Open Last Recording Folder, Open Library, Settings, Diagnostics, and Quit.

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

## Permissions

Grant permissions in macOS System Settings:

- Privacy & Security -> Microphone -> `TOrbitRecorder`
- Privacy & Security -> Screen & System Audio Recording -> `TOrbitRecorder`

If macOS prompts during Start Recording, grant access, quit the app, reopen it, and run the test again.

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
- `source.trigger` is `manual` for manual starts.
- `sync` remains `local_only`.
- `ai` remains `not_started`.

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

Check the MVP filters:

- date
- status
- source app
- title search
- tags

Check actions:

- Open recording folder
- Play mixed preview
- Tag/Edit title
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
7. Confirm Last Recording shows `Short recording`, Play/Open/Tag work, and metadata still exists for false-positive review.

## Auto-Start: Zoom

1. Open Settings -> Auto-start.
2. Confirm Auto-start is enabled.
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
source.rule_id = autostart.v1
```

Known caveat: V1 treats Zoom as a known call app, so system audio activity is not required for the direct-call-app shortcut.

## Auto-Start: Browser Heuristic

1. Open Settings -> Auto-start.
2. Confirm the browser is in the whitelist: Google Chrome, Safari, Firefox, Yandex Browser, or Microsoft Edge.
3. Confirm the browser is not in the blacklist.
4. Open a browser-based call or any page that uses microphone input.
5. Ensure system audio is active in the browser or another app.
6. Keep the browser active in the foreground.
7. Wait for the configured detection duration.
8. Confirm recording starts automatically.
9. Stop recording.
10. Confirm metadata has `source.trigger = autostart`.

Known caveat: V1 does not inspect URLs or meeting rooms. Browser auto-start requires active browser, microphone activity, and system audio activity.

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
3. Quit and reopen the app.
4. Play audible audio from another app.
5. Retry recording.

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
3. Click Refresh.
4. Confirm the main window shows `Mic: MacBook Pro Microphone` or the external mic name while AirPods remain connected for output.

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
