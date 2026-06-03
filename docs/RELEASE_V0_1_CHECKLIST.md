# Release v0.1.7 Checklist

## Scope

Release target: ToRec v0.1.7 macOS update-reminder-bug-report build.

Artifact:

```text
dist/ToRec-v0.1.7-macOS.zip
dist/ToRec-v0.1.7-macOS.dmg
dist/latest.json
```

Do not create or publish the GitHub release from this checklist alone. GitHub tag and release draft require a separate explicit command.

## 1. Build

- [ ] `swift test --package-path apps/macos` passes.
- [ ] `./scripts/build_macos.sh` passes.
- [ ] `./scripts/package_macos.sh` passes.
- [ ] `dist/ToRec.app` exists.
- [ ] `dist/ToRec-v0.1.7-macOS.zip` exists.
- [ ] `dist/ToRec-v0.1.7-macOS.dmg` exists.
- [ ] `dist/latest.json` exists.
- [ ] Package output shows expected app version.
- [ ] Package output shows expected git commit hash.
- [ ] `git status --short --branch` is clean before final tagging/release draft.

Commands:

```sh
swift test --package-path apps/macos
./scripts/build_macos.sh
./scripts/package_macos.sh
test -d dist/ToRec.app
test -f dist/ToRec-v0.1.7-macOS.zip
test -f dist/ToRec-v0.1.7-macOS.dmg
test -f dist/latest.json
git status --short --branch
```

## 2. Install

- [ ] Install app to `/Applications`.
- [ ] Launch app from `/Applications/ToRec.app`.
- [ ] Do not test release permissions with `.build/app/ToRec.app`.
- [ ] Do not mix `.build/app`, `dist/`, and `/Applications` while validating permissions.
- [ ] Microphone permission is granted.
- [ ] System audio permission is granted through the Core Audio tap permission path.
- [ ] If macOS shows `Only System Audio Recording`, ToRec is enabled there.
- [ ] `Fix Permissions` requests microphone access and runs the Core Audio capture-start permission probe before Start Recording is enabled.
- [ ] During the system-audio macOS prompt, the app remains in the yellow permissions-needed/onboarding state, not `Ready`.
- [ ] After the microphone prompt, ToRec is frontmost again before the system-audio prompt appears.
- [ ] App does not request macOS Notifications permission.
- [ ] App is restarted after changing permissions in System Settings.
- [ ] macOS menu bar shows the compact text-free outline play status item while idle.
- [ ] macOS menu bar shows a large red question mark status item when microphone or system-audio permission is missing.
- [ ] Missing microphone or system-audio permission brings the main window forward on launch, changes the header to `Blocked`, shows the red `Recording is blocked` panel, and replaces the menu-bar recording action with `Fix Recording Permissions`.
- [ ] Main window opens from menu bar `Show Window`.
- [ ] App remains running after closing the main window.

Commands:

```sh
./scripts/install_macos.sh
open /Applications/ToRec.app
```

Permission locations:

```text
System Settings -> Privacy & Security -> Microphone
System Settings -> Privacy & Security -> Screen & System Audio Recording
If shown: Screen & System Audio Recording -> Only System Audio Recording
```

## 3. Recording

### Manual 10 Sec Short

- [ ] Start manual recording.
- [ ] Record approximately 10 seconds.
- [ ] Stop recording.
- [ ] Post-stop summary shows `Short recording`.
- [ ] Recording is saved under `Inbox/Short`.
- [ ] Play and Open work for the short recording.
- [ ] Short recording is not shown as failed/recoverable.

### Manual 70 Sec Normal

- [ ] Start manual recording.
- [ ] Record at least 70 seconds.
- [ ] Stop recording.
- [ ] Post-stop summary shows Play, Tag, and Show actions.
- [ ] Click Tag, then save title/tags/status.
- [ ] Recording appears in Library.

### YouTube + Voice

- [ ] Play audible YouTube or other system audio.
- [ ] Speak into microphone during recording.
- [ ] Stop recording.
- [ ] `mixed.m4a` contains voice and system audio.
- [ ] Metadata does not warn that mic is silent.
- [ ] Metadata does not warn that system audio is silent.

### AirPods Connected

- [ ] Connect AirPods.
- [ ] Keep MacBook built-in microphone available.
- [ ] App selects MacBook/built-in microphone instead of AirPods microphone.
- [ ] UI shows selected microphone.
- [ ] If only Bluetooth headset mic is available, recording is blocked and the UI shows that AirPods/Bluetooth microphones are blocked.

### External Mic If Available

- [ ] Connect Shure MV7, Hollyland, USB mic, or audio interface.
- [ ] Refresh devices if needed.
- [ ] App selects external microphone in Auto mode.
- [ ] Recording uses selected external microphone.
- [ ] Connecting/disconnecting another mic during recording does not switch active input mid-recording.

## 4. Audio Files

Open the latest recording folder and verify:

- [ ] `source/mic.m4a` exists.
- [ ] `source/mic.m4a` size is greater than 0.
- [ ] `source/system.m4a` exists.
- [ ] `source/system.m4a` size is greater than 0.
- [ ] `export/mixed.m4a` exists.
- [ ] `export/mixed.m4a` size is greater than 0.
- [ ] `export/mixed_balanced.m4a` exists when Audio Leveling is enabled.
- [ ] `export/mixed_balanced.m4a` size is greater than 0 when Audio Leveling is enabled.
- [ ] `analysis/audio_analysis.json` exists when Audio Leveling is enabled.
- [ ] `metadata.json` exists.
- [ ] `metadata.json` includes audio processing status and audio health warnings.
- [ ] `metadata.json` includes recording id, timestamps, duration, source, audio tracks, status, tags, AI/sync statuses.
- [ ] SQLite index exists at `~/Recordings/TOrbitRecorder/db/app.sqlite`.
- [ ] Latest recording appears in Library after app restart.

Useful commands from inside the recording folder:

```sh
stat -f "%z %N" source/mic.m4a source/system.m4a export/mixed.m4a export/mixed_balanced.m4a analysis/audio_analysis.json metadata.json
afinfo source/mic.m4a
afinfo source/system.m4a
afinfo export/mixed.m4a
afinfo export/mixed_balanced.m4a
plutil -p metadata.json
```

## 5. UI

- [ ] Main Start button starts recording.
- [ ] Main Stop button stops recording.
- [ ] Timer updates while recording.
- [ ] Level meters show mic/system activity when signal is present.
- [ ] Marker buttons are visible while recording.
- [ ] Post-stop summary appears after a recording.
- [ ] Post-stop summary does not show long absolute paths.
- [ ] Post-stop Play opens the preferred local playback file.
- [ ] Post-stop Show opens the recording folder.
- [ ] Post-stop Tag opens Tag dialog.
- [ ] Records opens as a separate window.
- [ ] Records shows all local recordings from `Library/` and `Inbox/` metadata, not only the first 80 rows.
- [ ] Records search works.
- [ ] Records filters are collapsed by default.
- [ ] Records details show files, metadata, tags, and markers if present.
- [ ] Records details panel scrolls vertically and keeps all action buttons reachable in the default window size.
- [ ] Deleting a recording folder manually in Finder, then clicking Records Refresh, removes the stale row from Records.
- [ ] Records More -> Share Audio and details -> Share open the native macOS share sheet for the preferred local audio file.
- [ ] Records Copy Audio Path copies the preferred local audio file path.
- [ ] Records Trim Audio exports a non-empty `export/clip_*.m4a` without modifying original audio files.
- [ ] Records Trim & Share opens the native macOS share sheet for the created clip.
- [ ] Settings -> Local transcription exposes optional setup status and prepares the Parakeet model only when the user clicks the setup action.
- [ ] Records Transcribe Locally creates `transcript/transcript.txt` and `transcript/call_note.md` only after local transcription setup is ready.
- [ ] Records Transcribe Locally shows a clear Settings/setup hint and does not start model downloads when local transcription is not ready.
- [ ] Main Full Screenshot, Records Capture Full Screenshot, app-active `Cmd+Shift+S`, and global `Ctrl+Option+S` immediately save a full-screen `screenshots/screenshot_*.png` in the active/latest/selected recording folder without opening an area/window selector.
- [ ] Records Delete Local Recording confirmation warns that the whole recording folder and all files inside it will be permanently deleted.
- [ ] Confirmed delete removes the session folder from disk and removes the row from Records.
- [ ] Confirmed delete also stops playback immediately when that recording is open in the inline player or app player window.
- [ ] Settings opens.
- [ ] Settings shows Recording, Auto-start, Storage, Hotkeys, Behavior, and About sections.
- [ ] Diagnostics opens.
- [ ] Diagnostics shows permissions, device diagnostics, last error, recoverables, logs, and test recording action.
- [ ] Tag dialog saves title, participant, tags, and status.
- [ ] Menu bar item opens menu.
- [ ] Menu bar `Show Window` brings the main window to front.
- [ ] Global `Ctrl+Option+R` brings the main window to front while another app is active.
- [ ] Menu bar Start/Stop works.
- [ ] Menu bar Play Last Recording works when latest mixed preview exists.
- [ ] Menu bar Open Library opens the user-facing recordings folder.
- [ ] Menu bar Open Records, Settings, Diagnostics, and Quit work.

## 6. Auto-Start

### Zoom

- [ ] Open Zoom desktop.
- [ ] Enable Auto-start mode `Auto` or `Ask first`.
- [ ] Join or simulate a call so the Zoom process has active input/output audio.
- [ ] Recording can start immediately from `autostart.v2.zoom_process_audio`.
- [ ] Recording starts or asks first according to mode.
- [ ] Metadata source trigger is `autostart`.
- [ ] Metadata rule id matches Zoom auto-start rule.
- [ ] Switch to another app while Zoom remains in the background; recording stays active while Zoom process audio is active.
- [ ] Leave the Zoom conference while keeping Zoom open; recording stops about 10 seconds after Zoom process audio becomes idle.

### Browser Heuristic

- [ ] Open browser call page with title containing Meet/Zoom/Teams/Call/Interview or supported localized hint.
- [ ] Confirm mic activity and system audio activity.
- [ ] Wait detection duration.
- [ ] Recording starts or asks first according to mode.
- [ ] Browser + system audio only does not start recording.
- [ ] YouTube-like browser title with no mic activity does not start recording.

### Cooldown

- [ ] Stop a recording.
- [ ] Try to trigger auto-start immediately.
- [ ] Cooldown blocks duplicate immediate start.
- [ ] After cooldown, auto-start can trigger again.

### No Duplicate Recording

- [ ] While recording manually, trigger auto-start conditions.
- [ ] App does not start a second recording.
- [ ] Logs show auto-start ignored because recording is already active.

## 7. Error Handling

### Missing Mic Permission

- [ ] Revoke microphone permission.
- [ ] Launch app from `/Applications`.
- [ ] Main window opens automatically, header says `Blocked`, and Start is replaced with the red `Recording is blocked` / `Fix Permissions` state.
- [ ] No empty recording folder/recoverable is created from failed preflight.
- [ ] Menu bar status item shows a large red question mark and the menu includes `Recording Blocked: Fix Permissions`.
- [ ] Diagnostics shows microphone permission issue.

### Missing System Audio Permission

- [ ] Revoke system audio permission.
- [ ] Launch app from `/Applications`.
- [ ] Main window opens automatically, header says `Blocked`, and Start is replaced with the red `Recording is blocked` / `Fix Permissions` state.
- [ ] Menu bar status item shows a large red question mark and the menu includes `Recording Blocked: Fix Permissions`.
- [ ] Diagnostics shows system audio permission issue.
- [ ] If permission was just enabled, app explains restart requirement.

### No Mic Signal

- [ ] Record with muted mic or no speech.
- [ ] Stop recording.
- [ ] Metadata signal info marks mic silence where detectable.
- [ ] Post-stop summary or details show microphone silence warning.

### No System Audio Signal

- [ ] Record without playing system audio.
- [ ] Stop recording.
- [ ] Metadata signal info marks system silence where detectable.
- [ ] Post-stop summary or details show system audio silence warning.

### Quit While Recording

- [ ] Start recording.
- [ ] Choose Quit from menu bar.
- [ ] App shows `Recording is active. Stop and quit?`.
- [ ] Cancel keeps recording active.
- [ ] Stop and Quit stops recording before quitting.
- [ ] Resulting recording folder is preserved.

## 8. Known Limitations

- [ ] No screen recording in v0.1.0.
- [ ] No automatic/cloud AI transcription, summary, review, or search in v0.1.0. Explicit local transcription stays local and requires optional Settings setup before Records can transcribe.
- [ ] No cloud upload in v0.1.0.
- [ ] No T-Orbit sync in v0.1.0.
- [ ] No Telegram integration in v0.1.0.
- [ ] No direct Telegram bot/API upload in v0.1.0; native macOS sharing is only a local OS handoff.
- [ ] No waveform editor, destructive audio editing, or multi-clip timeline in v0.1.0.
- [ ] Windows client remains packaged separately.
- [ ] DMG exists; Developer ID signing and notarization are still separate.
- [ ] Global hotkey scope is limited to Show Window and screenshot capture; recording/library/diagnostics shortcuts are app-active only.
- [ ] Auto-start browser heuristic can still have false positives/negatives.
- [ ] Permission changes may require restarting the same app bundle.

## 9. Release Artifact

- [ ] Final zip artifact path is `dist/ToRec-v0.1.7-macOS.zip`.
- [ ] Final DMG artifact path is `dist/ToRec-v0.1.7-macOS.dmg`.
- [ ] Final update manifest path is `dist/latest.json`.
- [ ] Zip contains `ToRec.app`.
- [ ] Zip does not contain `INSTALL.md` or `RELEASE_NOTES.md`.
- [ ] DMG contains `ToRec.app`, an `Applications` shortcut, and visible install/Gatekeeper instructions.
- [ ] DMG does not contain `Install ToRec.command` or `Open Privacy Settings`; downloaded helper scripts/shortcuts can create a second Gatekeeper failure path.
- [ ] `ToRec.app` has the play-triangle app icon.
- [ ] Zip opens on a clean local unpack.
- [ ] App launches from unpacked artifact or `/Applications`.
- [ ] Artifact is attached to draft GitHub release only after checks pass.

Artifact check:

```sh
ls -lh dist/ToRec-v0.1.7-macOS.zip dist/ToRec-v0.1.7-macOS.dmg
python3 -m json.tool dist/latest.json >/dev/null
zipinfo -1 dist/ToRec-v0.1.7-macOS.zip | head
! zipinfo -1 dist/ToRec-v0.1.7-macOS.zip | grep -E 'INSTALL.md|RELEASE_NOTES.md'
TMP_MOUNT="$(mktemp -d /tmp/torec-dmg-verify.XXXXXX)"
hdiutil attach -readonly -nobrowse -noverify -noautoopen -mountpoint "$TMP_MOUNT" dist/ToRec-v0.1.7-macOS.dmg
test -d "$TMP_MOUNT/ToRec.app"
test -L "$TMP_MOUNT/Applications"
ls -ldO "$TMP_MOUNT/.background" | grep hidden
test ! -e "$TMP_MOUNT/Install ToRec.command"
test ! -e "$TMP_MOUNT/Open Privacy Settings"
hdiutil detach "$TMP_MOUNT"
rmdir "$TMP_MOUNT"
```

## 10. GitHub

- [ ] Confirm target release commit.
- [ ] Confirm branch status is clean.
- [ ] Confirm no uncommitted artifacts are required.
- [ ] Create tag `v0.1.7` only after release decision.
- [ ] Create GitHub release notes draft only after release decision.
- [ ] Do not publish release without explicit command.
- [ ] Release notes include what works, local-only behavior, install steps, permissions, known limitations, and next steps.
- [ ] Attach `dist/ToRec-v0.1.7-macOS.zip` and `dist/ToRec-v0.1.7-macOS.dmg` to draft release.
- [ ] Publish `dist/latest.json` to `tolcheev/torec-releases/main/latest.json` after the release artifacts are uploaded.

Suggested tag command after explicit approval:

```sh
git tag v0.1.7
git push origin v0.1.7
```

Suggested draft release command after explicit approval:

```sh
gh release create v0.1.7 \
  dist/ToRec-v0.1.7-macOS.zip \
  dist/ToRec-v0.1.7-macOS.dmg \
  --draft \
  --title "ToRec v0.1.7 macOS update-reminder-bug-report build" \
  --notes-file docs/RELEASE_NOTES_V0_1_7.md
```

## Go/No-Go

- [ ] All build/install/recording/file/UI/auto-start/error checks passed.
- [ ] Known limitations are acceptable for v0.1.0.
- [ ] Artifact path is confirmed.
- [ ] Release notes draft is ready.
- [ ] Separate approval received to create tag and draft GitHub release.
