# TOrbitRecorder macOS Install

This folder contains the packaged macOS MVP build for internal testing on Apple Silicon Macs.

## Install From This Zip

1. Unzip the archive.
2. Move `TOrbitRecorder.app` to `/Applications`.
3. Open `/Applications/TOrbitRecorder.app`.

If macOS blocks the first launch because this internal build is not notarized yet, use Finder -> Applications -> right-click `TOrbitRecorder` -> Open. For trusted internal testing only, you can also clear the download quarantine:

```sh
xattr -dr com.apple.quarantine /Applications/TOrbitRecorder.app
open /Applications/TOrbitRecorder.app
```

## Install From Repository

From the repository root, developers can run:

```sh
./scripts/install_macos.sh
```

The repository installer packages the app, replaces `/Applications/TOrbitRecorder.app`, and opens the installed app.

If TOrbitRecorder is already running and an active recording is in progress, the installer refuses to replace the app. Stop recording and wait for finalization before installing. Emergency override:

```sh
ALLOW_INSTALL_WHILE_RECORDING=1 ./scripts/install_macos.sh
```

For a dry run without copying to `/Applications`:

```sh
DRY_RUN=1 ./scripts/install_macos.sh
```

## Open The App

```sh
open /Applications/TOrbitRecorder.app
```

TOrbitRecorder lives in the macOS menu bar by default and does not show a Dock icon unless you enable it in Settings -> Behavior. Use the menu bar item to show the window, start or stop recording, open the Library, Settings, or Diagnostics.

## Permissions

Grant permissions to the same app bundle you will keep using:

1. Open System Settings.
2. Go to Privacy & Security -> Microphone.
3. Enable TOrbitRecorder.
4. Go to Privacy & Security -> Screen & System Audio Recording.
5. Enable TOrbitRecorder. If macOS shows `Only System Audio Recording`, enable TOrbitRecorder there too.
6. Quit and reopen TOrbitRecorder after changing audio permissions.

If the toggle is enabled but the app still reports a missing permission, quit TOrbitRecorder and reopen `/Applications/TOrbitRecorder.app`. During development, avoid switching between `.build/app`, `dist/`, and `/Applications` because macOS permissions are tied to the launched app bundle and code-signing identity.

Dev packages use the stable bundle identifier `com.torbit.recorder`, but ad-hoc signing still changes the code hash after rebuilds. If you approved an older unsigned/hash-signed build, toggle `TOrbitRecorder` off and on again once, then restart `/Applications/TOrbitRecorder.app`.

On macOS Sequoia, system-audio-only capture may be requested when you click Start Recording for the first time. If the app says System audio is ready, start a short test recording to let macOS finalize the permission.

## Launch At Login

Launch at Login is enabled by default so the recorder is available after you log in. The app first uses macOS `SMAppService`; development/ad-hoc bundles can fall back to:

```text
~/Library/LaunchAgents/com.torbit.recorder.login.plist
```

Diagnostics shows which path is active.

## Restart After Permissions

macOS audio permissions can require a full app restart after the toggle is enabled:

```sh
osascript -e 'tell application id "com.torbit.recorder" to quit' || true
open /Applications/TOrbitRecorder.app
```

## Recordings Location

Default local storage:

```text
~/Recordings/TOrbitRecorder/
```

Recordings stay local in the MVP.

## Uninstall

Quit the app, then remove it:

```sh
osascript -e 'tell application "TOrbitRecorder" to quit' || true
rm -rf /Applications/TOrbitRecorder.app
```

This does not delete recordings. To remove local recordings too:

```sh
rm -rf ~/Recordings/TOrbitRecorder
```
