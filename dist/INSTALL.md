# TOrbitRecorder macOS Install

This folder contains the packaged macOS MVP build.

## Install

From the repository root:

```sh
./scripts/install_macos.sh
```

The installer packages the app, replaces `/Applications/TOrbitRecorder.app`, and opens the installed app.

For a dry run without copying to `/Applications`:

```sh
DRY_RUN=1 ./scripts/install_macos.sh
```

## Open The App

```sh
open /Applications/TOrbitRecorder.app
```

TOrbitRecorder lives in the macOS menu bar. Use the menu bar item to show the window, start or stop recording, open the Library, Settings, or Diagnostics.

## Permissions

Grant permissions to the same app bundle you will keep using:

1. Open System Settings.
2. Go to Privacy & Security -> Microphone.
3. Enable TOrbitRecorder.
4. Go to Privacy & Security -> Screen & System Audio Recording.
5. Enable TOrbitRecorder.
6. Quit and reopen TOrbitRecorder after changing Screen & System Audio Recording.

If the toggle is enabled but the app still reports a missing permission, quit TOrbitRecorder and reopen `/Applications/TOrbitRecorder.app`. During development, avoid switching between `.build/app`, `dist/`, and `/Applications` because macOS permissions are tied to the launched app bundle.

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
