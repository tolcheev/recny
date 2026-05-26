# QA Checklist

Use this checklist for manual macOS MVP validation. Prefer testing the installed app from `/Applications` so macOS permissions apply to the same bundle every time.

## Test Context

- [ ] Mac model:
- [ ] macOS version:
- [ ] App version:
- [ ] Git commit:
- [ ] App path: `/Applications/TOrbitRecorder.app`
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
test -d dist/TOrbitRecorder.app
test -f dist/TOrbitRecorder-v0.1.0-macOS.zip
test -f dist/INSTALL.md
```

- [ ] Install passes:

```sh
./scripts/install_macos.sh
```

- [ ] App opens from `/Applications`:

```sh
open /Applications/TOrbitRecorder.app
```

- [ ] Menu bar item is visible.
- [ ] Show Window brings the existing window to front without creating duplicates.

## 2. Permissions

- [ ] Microphone permission is granted:
  - System Settings -> Privacy & Security -> Microphone -> TOrbitRecorder enabled
- [ ] System audio permission is granted:
  - System Settings -> Privacy & Security -> Screen & System Audio Recording -> TOrbitRecorder enabled
  - If macOS shows `Only System Audio Recording`, TOrbitRecorder is enabled there too
- [ ] App was restarted after permission changes:

```sh
osascript -e 'tell application "TOrbitRecorder" to quit' || true
open /Applications/TOrbitRecorder.app
```

- [ ] Click `Fix Permissions` and confirm both required macOS prompts are handled before Start is enabled:
  - Microphone prompt, if microphone is not determined
  - System audio prompt, if system audio is not determined
- [ ] Main UI no longer shows Fix Permissions.
- [ ] Diagnostics shows Microphone as granted/authorized.
- [ ] Diagnostics shows System audio as granted/available before recording starts.
- [ ] Storage/output folder is writable.

## 3. Manual Recording

### 10 Sec Short Recording

- [ ] Start Recording.
- [ ] Speak into the selected microphone.
- [ ] Play system audio from another app.
- [ ] Stop after about 10 seconds.
- [ ] Latest strip shows `Short recording`.
- [ ] Short recording is saved to `Inbox/Short`.
- [ ] Play works.
- [ ] Open works.
- [ ] Tag works.

### 70 Sec Normal Recording

- [ ] Start Recording.
- [ ] Speak into the selected microphone.
- [ ] Play system audio from another app.
- [ ] Stop after at least 70 seconds.
- [ ] Latest strip shows a non-failed status.
- [ ] Post-call tag dialog appears when expected.
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
- [ ] If only AirPods are available, warning is shown: Bluetooth microphone quality may be degraded.

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
- [ ] Latest strip appears after a recording.
- [ ] Latest strip does not show long absolute paths.
- [ ] Play plays the mixed preview.
- [ ] Library opens the user-facing recordings folder in Finder.
- [ ] Records opens as a separate window.
- [ ] Records shows recent recordings.
- [ ] Records search works for title, participant, tags, and source app.
- [ ] Records filters are collapsed by default.
- [ ] Records filters include status, date range, source app, tags, and audio health.
- [ ] Settings opens.
- [ ] Settings -> About shows version, build date, commit hash, and local storage path.
- [ ] Diagnostics opens.
- [ ] Diagnostics shows permissions, selected input, recommended input, last error, logs, and recoverables.
- [ ] Diagnostics shows the last 100 local `app.log` lines.
- [ ] Copy Logs copies visible log lines to the clipboard.
- [ ] Open Logs opens `~/Recordings/TOrbitRecorder/logs/`.
- [ ] Clear Logs asks for confirmation and clears local file logs.
- [ ] Tag dialog opens from Latest.
- [ ] Tag dialog opens from Library.
- [ ] Tags save to `metadata.json`.
- [ ] Tags save to SQLite and appear in Library.
- [ ] Records details show marker timestamps and labels if older/imported metadata contains markers.
- [ ] Records details show audio health, gain values, and audio analysis availability.
- [ ] Records details can open `analysis/audio_analysis.json` when it exists.

## 6. Auto-Start

### Zoom

- [ ] Auto-start mode is `Auto` or `Ask first`.
- [ ] Cooldown has passed, or Zoom has a strong mic + system-audio signal.
- [ ] Open Zoom desktop app.
- [ ] Join or simulate a call with microphone active.
- [ ] Switch to another app while Zoom keeps running.
- [ ] Recording starts automatically, or Ask first prompt appears.
- [ ] Metadata source app is `Zoom` or `zoom.us`, not `TOrbitRecorder`.
- [ ] Metadata source trigger is `autostart`.
- [ ] Metadata includes rule id, confidence, and human-readable reason.
- [ ] End the Zoom conference while leaving the Zoom app open.
- [ ] Recording auto-stops after the grace period when Zoom returns to its home/workplace window.

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
- [ ] Choose Quit from menu bar or press Cmd+Q.
- [ ] Confirmation appears: `Recording is active. Stop and quit?`
- [ ] Cancel keeps recording active.
- [ ] Stop and Quit stops recording before app exits.

### No Permissions

- [ ] Revoke Microphone permission.
- [ ] Restart app.
- [ ] Start is disabled or Fix Permissions is shown.
- [ ] No empty recording folder is created by failed preflight.
- [ ] Diagnostics explains missing microphone permission.
- [ ] Repeat with system audio permission revoked.

### AirPods Mic Avoidance

- [ ] AirPods + MacBook microphone available -> MacBook microphone selected.
- [ ] AirPods + external mic available -> external mic selected.
- [ ] Only AirPods available -> AirPods selected as fallback with warning.

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
