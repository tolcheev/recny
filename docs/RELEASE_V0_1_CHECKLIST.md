# Release v0.1.0 Checklist

## Scope

Release target: TOrbitRecorder v0.1.0 macOS audio-only MVP.

Artifact:

```text
dist/TOrbitRecorder-v0.1.0-macOS.zip
```

Do not create or publish the GitHub release from this checklist alone. GitHub tag and release draft require a separate explicit command.

## 1. Build

- [ ] `swift test --package-path apps/macos` passes.
- [ ] `./scripts/build_macos.sh` passes.
- [ ] `./scripts/package_macos.sh` passes.
- [ ] `dist/TOrbitRecorder.app` exists.
- [ ] `dist/TOrbitRecorder-v0.1.0-macOS.zip` exists.
- [ ] Package output shows expected app version.
- [ ] Package output shows expected git commit hash.
- [ ] `git status --short --branch` is clean before final tagging/release draft.

Commands:

```sh
swift test --package-path apps/macos
./scripts/build_macos.sh
./scripts/package_macos.sh
test -d dist/TOrbitRecorder.app
test -f dist/TOrbitRecorder-v0.1.0-macOS.zip
git status --short --branch
```

## 2. Install

- [ ] Install app to `/Applications`.
- [ ] Launch app from `/Applications/TOrbitRecorder.app`.
- [ ] Do not test release permissions with `.build/app/TOrbitRecorder.app`.
- [ ] Do not mix `.build/app`, `dist/`, and `/Applications` while validating permissions.
- [ ] Microphone permission is granted.
- [ ] Screen & System Audio Recording permission is granted.
- [ ] App is restarted after changing permissions in System Settings.
- [ ] Main window opens from menu bar `Show Window`.
- [ ] App remains running after closing the main window.

Commands:

```sh
./scripts/install_macos.sh
open /Applications/TOrbitRecorder.app
```

Permission locations:

```text
System Settings -> Privacy & Security -> Microphone
System Settings -> Privacy & Security -> Screen & System Audio Recording
```

## 3. Recording

### Manual 10 Sec Short

- [ ] Start manual recording.
- [ ] Record approximately 10 seconds.
- [ ] Stop recording.
- [ ] Latest strip shows `Short recording`.
- [ ] Recording is saved under `Inbox/Short`.
- [ ] Play and Open work for the short recording.
- [ ] Short recording is not shown as failed/recoverable.

### Manual 70 Sec Normal

- [ ] Start manual recording.
- [ ] Record at least 70 seconds.
- [ ] Stop recording.
- [ ] Post-call Tag dialog appears.
- [ ] Save title/tags/status.
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
- [ ] If only Bluetooth headset mic is available, UI shows degraded quality warning.

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
- [ ] Latest strip appears after a recording.
- [ ] Latest strip does not show long absolute paths.
- [ ] Latest Play opens `mixed.m4a`.
- [ ] Latest Open opens the recording folder.
- [ ] Latest Tag opens Tag dialog.
- [ ] Library opens as a separate window.
- [ ] Library shows recent recordings.
- [ ] Library search works.
- [ ] Library filters are collapsed by default.
- [ ] Library details show files, metadata, tags, and markers if present.
- [ ] Settings opens.
- [ ] Settings shows Recording, Auto-start, Storage, Hotkeys, Behavior, and About sections.
- [ ] Diagnostics opens.
- [ ] Diagnostics shows permissions, device diagnostics, last error, recoverables, logs, and test recording action.
- [ ] Tag dialog saves title, participant, tags, and status.
- [ ] Menu bar item opens menu.
- [ ] Menu bar `Show Window` brings the main window to front.
- [ ] Menu bar Start/Stop works.
- [ ] Menu bar Play Last Recording works when latest mixed preview exists.
- [ ] Menu bar Open Last Recording Folder works.
- [ ] Menu bar Open Library, Settings, Diagnostics, and Quit work.

## 6. Auto-Start

### Zoom

- [ ] Open Zoom desktop.
- [ ] Enable Auto-start mode `Auto` or `Ask first`.
- [ ] Confirm mic activity is present.
- [ ] Wait detection duration.
- [ ] Recording starts or asks first according to mode.
- [ ] Metadata source trigger is `autostart`.
- [ ] Metadata rule id matches Zoom auto-start rule.

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
- [ ] Start is blocked or fails with human-readable message.
- [ ] No empty recording folder/recoverable is created from failed preflight.
- [ ] Diagnostics shows microphone permission issue.

### Missing System Audio Permission

- [ ] Revoke Screen & System Audio Recording permission.
- [ ] Launch app from `/Applications`.
- [ ] Start is blocked or fails with human-readable message.
- [ ] Diagnostics shows system audio permission issue.
- [ ] If permission was just enabled, app explains restart requirement.

### No Mic Signal

- [ ] Record with muted mic or no speech.
- [ ] Stop recording.
- [ ] Metadata signal info marks mic silence where detectable.
- [ ] Latest strip or details show microphone silence warning.

### No System Audio Signal

- [ ] Record without playing system audio.
- [ ] Stop recording.
- [ ] Metadata signal info marks system silence where detectable.
- [ ] Latest strip or details show system audio silence warning.

### Quit While Recording

- [ ] Start recording.
- [ ] Choose Quit from menu bar.
- [ ] App shows `Recording is active. Stop and quit?`.
- [ ] Cancel keeps recording active.
- [ ] Stop and Quit stops recording before quitting.
- [ ] Resulting recording folder is preserved.

## 8. Known Limitations

- [ ] No screen recording in v0.1.0.
- [ ] No AI transcription, summary, review, or search in v0.1.0.
- [ ] No cloud upload in v0.1.0.
- [ ] No T-Orbit sync in v0.1.0.
- [ ] No Telegram integration in v0.1.0.
- [ ] No Windows client in v0.1.0.
- [ ] No DMG, signing, or notarization unless added separately.
- [ ] Global hotkeys are not implemented; shortcuts are app-active only.
- [ ] Auto-start browser heuristic can still have false positives/negatives.
- [ ] Permission changes may require restarting the same app bundle.

## 9. Release Artifact

- [ ] Final artifact path is `dist/TOrbitRecorder-v0.1.0-macOS.zip`.
- [ ] Zip contains `TOrbitRecorder.app`.
- [ ] Zip opens on a clean local unpack.
- [ ] App launches from unpacked artifact or `/Applications`.
- [ ] Artifact is attached to draft GitHub release only after checks pass.

Artifact check:

```sh
ls -lh dist/TOrbitRecorder-v0.1.0-macOS.zip
zipinfo -1 dist/TOrbitRecorder-v0.1.0-macOS.zip | head
```

## 10. GitHub

- [ ] Confirm target release commit.
- [ ] Confirm branch status is clean.
- [ ] Confirm no uncommitted artifacts are required.
- [ ] Create tag `v0.1.0` only after release decision.
- [ ] Create GitHub release notes draft only after release decision.
- [ ] Do not publish release without explicit command.
- [ ] Release notes include what works, local-only behavior, install steps, permissions, known limitations, and next steps.
- [ ] Attach `dist/TOrbitRecorder-v0.1.0-macOS.zip` to draft release.

Suggested tag command after explicit approval:

```sh
git tag v0.1.0
git push origin v0.1.0
```

Suggested draft release command after explicit approval:

```sh
gh release create v0.1.0 \
  dist/TOrbitRecorder-v0.1.0-macOS.zip \
  --draft \
  --title "TOrbitRecorder v0.1.0 macOS audio-only MVP" \
  --notes-file RELEASE_NOTES.md
```

## Go/No-Go

- [ ] All build/install/recording/file/UI/auto-start/error checks passed.
- [ ] Known limitations are acceptable for v0.1.0.
- [ ] Artifact path is confirmed.
- [ ] Release notes draft is ready.
- [ ] Separate approval received to create tag and draft GitHub release.
