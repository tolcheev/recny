# QA Checklist

Use this checklist for manual macOS MVP validation. Prefer testing the installed app from `/Applications` so macOS permissions apply to the same bundle every time.

## Test Context

- [ ] Mac model:
- [ ] macOS version:
- [ ] App version:
- [ ] Git commit:
- [ ] App path: `/Applications/ToRec.app`
- [ ] Recording root: `~/Recordings/TOrbitRecorder/`

## 1. Install

- [ ] Build passes:

```sh
./scripts/build_macos.sh
```

- [ ] Package passes:

```sh
./scripts/package_macos.sh
```

- [ ] Package exists:

```sh
test -d dist/ToRec.app
test -f dist/ToRec-v0.1.6-macOS.zip
test -f dist/ToRec-v0.1.6-macOS.dmg
test -f dist/latest.json
zipinfo -1 dist/ToRec-v0.1.6-macOS.zip | grep -Fx ToRec.app/
! zipinfo -1 dist/ToRec-v0.1.6-macOS.zip | grep -E 'INSTALL.md|RELEASE_NOTES.md'
hdiutil attach -readonly dist/ToRec-v0.1.6-macOS.dmg
# DMG should show ToRec.app, Applications, and install/Gatekeeper instructions.
```

- [ ] Install passes:

```sh
./scripts/install_macos.sh
```

- [ ] DMG does not expose blocked helper scripts or extra icons:

```sh
TMP_MOUNT="$(mktemp -d /tmp/torec-dmg-verify.XXXXXX)"
hdiutil attach -readonly -nobrowse -noverify -noautoopen -mountpoint "$TMP_MOUNT" dist/ToRec-v0.1.6-macOS.dmg
test -d "$TMP_MOUNT/ToRec.app"
test -L "$TMP_MOUNT/Applications"
ls -ldO "$TMP_MOUNT/.background" | grep hidden
test ! -e "$TMP_MOUNT/Install ToRec.command"
test ! -e "$TMP_MOUNT/Open Privacy Settings"
hdiutil detach "$TMP_MOUNT"
rmdir "$TMP_MOUNT"
```

- [ ] App opens from `/Applications`:

```sh
open /Applications/ToRec.app
```

- [ ] Menu bar item is visible.
- [ ] With microphone or system-audio permission missing, the menu bar item shows a large red question mark.
- [ ] With microphone or system-audio permission missing, app launch brings the main window forward and shows `Blocked` plus the red `Recording is blocked` panel.
- [ ] With microphone or system-audio permission missing, the menu bar recording action is `Fix Recording Permissions`, not `Start Recording`.
- [ ] App does not request macOS Notifications permission on first launch.
- [ ] Show Window brings the existing window to front without creating duplicates.
- [ ] `Ctrl+Option+R` brings the main window to front while another app is active.

## 2. Permissions

- [ ] Microphone permission is granted:
  - System Settings -> Privacy & Security -> Microphone -> ToRec enabled
- [ ] System audio permission is granted through the Core Audio tap path:
  - System Settings -> Privacy & Security -> Screen & System Audio Recording -> Only System Audio Recording -> ToRec enabled, if macOS shows the separate section
  - Otherwise, System Settings -> Privacy & Security -> Screen & System Audio Recording -> ToRec enabled
- [ ] `Fix Permissions` triggers the system-audio macOS prompt while the yellow permissions panel is still visible.
- [ ] The app does not show `Ready` or enable `Start Recording` until the Core Audio capture-start probe has completed.
- [ ] After the microphone prompt is accepted, the Recorder window returns to the front before the system-audio prompt appears.
- [ ] App was restarted after permission changes:

```sh
osascript -e 'tell application id "com.torbit.recorder" to quit' || true
open /Applications/ToRec.app
```

- [ ] Click `Fix Permissions` and confirm both required macOS prompts are handled before Start is enabled:
  - Microphone prompt, if microphone is not determined
  - System audio prompt, if system audio is not determined
- [ ] If macOS skips the system-audio prompt because access was already granted, the onboarding checklist stays visible and shows the system-audio verification message before Start is enabled.
- [ ] After system-audio access has already been granted and the app has been restarted, clicking the normal `Fix Permissions` / `Recheck` path does not clear the successful system-audio probe cache and does not repeatedly show the macOS `Screen & System Audio Recording` prompt.
- [ ] Diagnostics -> `Force Recheck Permissions` is the only UI path that intentionally clears the successful system-audio probe cache.
- [ ] Permission copy explains that macOS calls this `Screen & System Audio Recording`, but ToRec records system audio only and does not write screen video.
- [ ] Main UI no longer shows Fix Permissions.
- [ ] Clicking `Start Recording` does not show a macOS permission prompt. If a permission prompt appears on Start, the onboarding gate is broken.
- [ ] Diagnostics shows Microphone as granted/authorized.
- [ ] Diagnostics shows System audio as granted/available before recording starts.
- [ ] Storage/output folder is writable.

## 3. Manual Recording

### 10 Sec Short Recording

- [ ] Start Recording.
- [ ] Speak into the selected microphone.
- [ ] Play system audio from another app.
- [ ] Stop after about 10 seconds.
- [ ] Post-stop summary shows `Short recording`.
- [ ] Short recording is saved to `Inbox/Short`.
- [ ] Play works.
- [ ] Open works.
- [ ] Tag works.

### 70 Sec Normal Recording

- [ ] Start Recording.
- [ ] Speak into the selected microphone.
- [ ] Play system audio from another app.
- [ ] Stop after at least 70 seconds.
- [ ] Post-stop summary shows a non-failed status with Play, Tag, and Show actions.
- [ ] Post-call tag dialog opens when the user clicks Tag.
- [ ] Recording appears in Library.

### YouTube + Voice

- [ ] Open YouTube or another audible browser tab.
- [ ] Start Recording.
- [ ] Speak over the system audio for at least 10 seconds.
- [ ] Stop Recording.
- [ ] Play `export/mixed.m4a`.
- [ ] Mixed preview contains both voice and system audio.

### AirPods Connected

- [ ] Connect AirPods.
- [ ] Keep MacBook microphone available.
- [ ] Settings -> Recording -> Preferred microphone is `Auto, recommended`.
- [ ] Main UI shows MacBook microphone, not AirPods.
- [ ] Diagnostics reason says AirPods/Bluetooth microphone was avoided because another input is available.
- [ ] If only AirPods are available, recording is blocked and the UI says AirPods/Bluetooth microphone is blocked for recording.

### External Mic Connected

- [ ] Connect Shure MV7, Hollyland, USB mic, or audio interface.
- [ ] Refresh devices in Settings or Diagnostics.
- [ ] Main UI shows the external mic as selected.
- [ ] Start Recording.
- [ ] Connect/disconnect another mic during active recording.
- [ ] Active recording input does not switch mid-recording.

## 4. Audio Files

Open the latest recording folder and verify:

- [ ] `source/mic.m4a` exists and size is greater than 0.
- [ ] `source/system.m4a` exists and size is greater than 0.
- [ ] `export/mixed.m4a` exists and size is greater than 0.
- [ ] `metadata.json` exists.
- [ ] `export/mixed.m4a` contains voice and system audio.
- [ ] Metadata lists microphone track.
- [ ] Metadata lists system track.
- [ ] Metadata lists mixed track.
- [ ] Metadata has duration and file size fields.
- [ ] Metadata trigger is correct: `manual` or `auto`.
- [ ] Metadata has a `markers` array; it can be empty because marker controls are hidden from the default UI.

Useful commands from inside the recording folder:

```sh
stat -f "%z %N" source/mic.m4a source/system.m4a export/mixed.m4a metadata.json
afinfo source/mic.m4a
afinfo source/system.m4a
afinfo export/mixed.m4a
plutil -p metadata.json
```

## 5. UI

- [ ] Start button starts recording.
- [ ] Stop button immediately changes to `Stopping...` while files are finalized.
- [ ] Duplicate Stop clicks during `Stopping...` do not start a second stop transaction.
- [ ] Stop completes and returns the app to Ready.
- [ ] Timer updates during recording.
- [ ] Marker buttons are visible while recording.
- [ ] Marker controls are not shown on the default recording screen.
- [ ] Post-stop summary appears after a recording.
- [ ] Post-stop summary does not show long absolute paths.
- [ ] Play plays the mixed preview.
- [ ] Library opens the user-facing recordings folder in Finder.
- [ ] Records opens as a separate window.
- [ ] Records shows all local recordings from `Library/` and `Inbox/` metadata, not only the first 80 rows.
- [ ] Default untitled rows are numbered as `Recording #N`.
- [ ] Long badges/details wrap cleanly and do not hide row actions.
- [ ] Records details panel scrolls vertically and all action buttons remain reachable in the default window size.
- [ ] Deleting a recording folder manually in Finder, then clicking Records Refresh, removes the stale row from Records.
- [ ] Records search works for title, participant, tags, and source app.
- [ ] Records filters are collapsed by default.
- [ ] Records filters include status, date range, source app, tags, and audio health.
- [ ] Settings opens.
- [ ] Settings -> About shows version, build date, commit hash, and local storage path.
- [ ] Settings -> About -> Check for Updates reports either the latest version or a newer version from the public release manifest.
- [ ] Settings -> About -> Download Update opens the public GitHub download URL when a newer version is available.
- [ ] Main window footer shows `ToRec v...`, `Check for Updates`, and `Report Bug`.
- [ ] If a newer version exists, the footer shows `Download`, `Later`, and `Skip`.
- [ ] `Later` hides the current update reminder for about 24 hours.
- [ ] `Skip` hides the current update version until a newer version appears.
- [ ] Automatic update checks do not run or surface reminders while recording is active.
- [ ] `Report Bug` opens the public GitHub issue form with version and platform prefilled.
- [ ] Diagnostics opens.
- [ ] Diagnostics shows permissions, selected input, recommended input, last error, logs, and recoverables.
- [ ] Diagnostics shows the last 100 local `app.log` lines.
- [ ] Copy Logs copies visible log lines to the clipboard.
- [ ] Open Logs opens `~/Recordings/TOrbitRecorder/logs/`.
- [ ] Clear Logs asks for confirmation and clears local file logs.
- [ ] Tag dialog opens from the post-stop summary.
- [ ] Tag dialog opens from Library.
- [ ] Tags save to `metadata.json`.
- [ ] Tags save to SQLite and appear in Library.
- [ ] Records details show marker timestamps and labels if older/imported metadata contains markers.
- [ ] Records details show audio health, gain values, and audio analysis availability.
- [ ] Records details can open `analysis/audio_analysis.json` when it exists.
- [ ] Records More -> Share Audio opens the native macOS share sheet for the preferred local audio file.
- [ ] Records details -> Share opens the native macOS share sheet for the preferred local audio file.
- [ ] Preferred share file order is `export/mixed_balanced.m4a`, then `export/mixed.m4a`, then `source/mic.m4a`, then `source/system.m4a`.
- [ ] Copy Audio Path copies the same preferred local audio file path to the clipboard.
- [ ] Share Audio and Copy Audio Path are disabled when no non-empty local audio file exists.
- [ ] Records More -> Trim Audio opens the trim sheet with start/end controls.
- [ ] Trim Only creates a non-empty `export/clip_*.m4a` and does not modify `source/mic.m4a`, `source/system.m4a`, `export/mixed.m4a`, or `export/mixed_balanced.m4a`.
- [ ] Trim & Share creates a non-empty `export/clip_*.m4a` and opens the native macOS share sheet for that clip.
- [ ] Settings -> Local transcription shows whether optional tools are missing, the Parakeet model needs preparation, or transcription is ready.
- [ ] Records More -> Transcribe Locally is unavailable until Settings reports local transcription is ready; Records must not trigger first-run model downloads.
- [ ] Local transcription creates `transcript/transcript.txt` and `transcript/call_note.md` after Settings -> Prepare Parakeet Model has completed.
- [ ] If local transcription is not ready, the app shows a clear Settings/setup hint and does not create partial output.
- [ ] Main Full Screenshot button immediately captures the full screen and saves `screenshots/screenshot_*.png` under the active or latest recording folder.
- [ ] Records Capture Full Screenshot immediately captures the full screen and saves `screenshots/screenshot_*.png` under the selected recording folder.
- [ ] App-active `Cmd+Shift+S` and global `Ctrl+Option+S` trigger the same full-screen screenshot flow without opening an area/window selector.
- [ ] Delete Local Recording confirmation explicitly says the entire folder and all files inside it are permanently deleted.
- [ ] After confirming Delete Local Recording, the session folder is gone from disk and the row is removed from Records.
- [ ] If the deleted recording is currently playing in the inline player or app player window, playback stops immediately when deletion is confirmed.

## 6. Auto-Start

### Zoom

- [ ] Auto-start mode is `Auto` or `Ask first`.
- [ ] Cooldown has passed, or Zoom has active per-process input/output audio.
- [ ] Open Zoom desktop app.
- [ ] Join or simulate a call with microphone active.
- [ ] Switch to another app while Zoom keeps running.
- [ ] Recording starts automatically, or Ask first prompt appears.
- [ ] Records source displays `Zoom`, not `TOrbitRecorder`.
- [ ] New metadata source app is `Zoom`, not `TOrbitRecorder`.
- [ ] Metadata source trigger is `autostart`.
- [ ] Metadata includes rule id, confidence, and human-readable reason.
- [ ] End the Zoom conference while leaving the Zoom app open.
- [ ] Recording auto-stops about 10 seconds after Zoom process audio becomes idle and Zoom returns to its home/workplace window.
- [ ] If Zoom window titles are unavailable and Zoom process audio is still active, recording does not auto-stop just because another app is foreground.
- [ ] If Zoom window titles are unavailable and Zoom process audio is idle, recording auto-stops about 10 seconds later even if another app is producing global system audio.
- [ ] If Core Audio process activity is unavailable, global system-audio fallback keeps recording alive; microphone-only fallback does not.

### Browser Call

- [ ] Open browser call page with a call-like title, such as Meet, Zoom, Teams, Interview, or Call.
- [ ] Keep microphone active longer than detection duration.
- [ ] Play/receive system audio.
- [ ] Recording starts automatically, or Ask first prompt appears.
- [ ] Logs explain browser call detection.

### Browser False Positive Check

- [ ] Open a normal YouTube/music/video page in a browser.
- [ ] Do not use the microphone.
- [ ] Confirm auto-start does not start.
- [ ] If microphone is active on a non-call browser title, confirm auto-start does not start when title is available and looks YouTube/video-only.
- [ ] Logs explain why auto-start ignored the case.

## 7. Edge Cases

### Stop Immediately

- [ ] Start Recording.
- [ ] Stop within 1-2 seconds.
- [ ] App does not crash.
- [ ] Status is Short recording or Recording failed with a human-readable reason.
- [ ] Empty files are not shown as Saved.

### Quit During Recording

- [ ] Start Recording.
- [ ] With `Show recording indicator` enabled, confirm the macOS menu bar status item changes from outline play to filled play while recording.
- [ ] Choose Quit from menu bar or press Cmd+Q.
- [ ] Confirmation appears: `Recording is active. Stop and quit?`
- [ ] Cancel keeps recording active.
- [ ] Stop and Quit stops recording before app exits.
- [ ] After stopping, the macOS menu bar status item returns to outline play.

### No Permissions

- [ ] Revoke Microphone permission.
- [ ] Restart app.
- [ ] Main window opens automatically, the header says `Blocked`, and the red `Recording is blocked` panel explains the missing permission.
- [ ] Start is disabled and `Fix Permissions` is shown.
- [ ] No empty recording folder is created by failed preflight.
- [ ] Menu bar item changes to a large red question mark.
- [ ] Menu bar menu shows `Recording Blocked: Fix Permissions` at the top.
- [ ] Diagnostics explains missing microphone permission.
- [ ] Repeat with system audio permission revoked.

### AirPods Mic Avoidance

- [ ] AirPods + MacBook microphone available -> MacBook microphone selected.
- [ ] AirPods + external mic available -> external mic selected.
- [ ] Only AirPods available -> no recording input is selected; Start Recording is blocked.

### Output Folder Unavailable

- [ ] Change Storage root to an unavailable or unwritable folder, if possible.
- [ ] Try to start recording.
- [ ] Preflight fails before creating a recording folder.
- [ ] UI shows human-readable error.
- [ ] Diagnostics/logs explain output folder problem.

### Low Disk Space

- [ ] If safe to simulate, test with a volume that has less than 2 GB free.
- [ ] Try to start recording.
- [ ] Preflight blocks recording.
- [ ] UI shows human-readable low disk space error.
- [ ] No empty recording folder is created.

## Logs

Recent unified logs:

```sh
log show --predicate 'subsystem == "com.torbit.recorder"' --last 30m --style compact
```

Live logs:

```sh
log stream --predicate 'subsystem == "com.torbit.recorder"' --style compact
```

Local logs folder:

```sh
open ~/Recordings/TOrbitRecorder/logs/
```

Local file logs:

```sh
tail -n 100 ~/Recordings/TOrbitRecorder/logs/app.log
ls -lh ~/Recordings/TOrbitRecorder/logs/app.log ~/Recordings/TOrbitRecorder/logs/app.1.log 2>/dev/null
```

Stop debugging:

```sh
tail -n 200 ~/Recordings/TOrbitRecorder/logs/app.log | grep -E "stop requested|stop pipeline|writer stopped|system audio stop|mixed preview|audio leveling|metadata finalization|stop request finished"
```

Expected healthy stop sequence:

- `recording stop requested`
- `stop pipeline begin`
- `microphone writer stopped`
- `system audio stop finished`
- `segment finalization finished`
- `mixed preview finished`
- `audio leveling finished`
- `metadata finalization finished`
- `recording stop request finished`
