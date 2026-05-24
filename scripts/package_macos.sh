#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TOrbitRecorder"
PACKAGE_VERSION="${PACKAGE_VERSION:-v0.1.0}"
BUILD_APP="$ROOT_DIR/apps/macos/.build/app/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"
DIST_INSTALL="$DIST_DIR/INSTALL.md"
DIST_ZIP="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-macOS.zip"

"$ROOT_DIR/scripts/build_macos.sh"

mkdir -p "$DIST_DIR"
rm -rf "$DIST_APP" "$DIST_ZIP" "$DIST_DIR/$APP_NAME-macOS-MVP.zip"

cat > "$DIST_INSTALL" <<'INSTALL_GUIDE'
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

If the toggle is enabled but the app still reports a missing permission, quit TOrbitRecorder and reopen `/Applications/TOrbitRecorder.app`. During development, avoid switching between `.build/app`, `dist/`, and `/Applications` because macOS permissions are tied to the launched app bundle and code-signing identity.

Dev packages use the stable bundle identifier `com.torbit.recorder`, but ad-hoc signing still changes the code hash after rebuilds. If you approved an older unsigned/hash-signed build, toggle `TOrbitRecorder` off and on again once, then restart `/Applications/TOrbitRecorder.app`.

On macOS Sequoia, system-audio-only capture may be requested when you click Start Recording for the first time. If the app says System audio is ready, start a short test recording to let macOS finalize the permission.

## Restart After Permissions

Screen & System Audio Recording often requires a full app restart after the toggle is enabled:

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
INSTALL_GUIDE

cp -R "$BUILD_APP" "$DIST_APP"

(
    cd "$DIST_DIR"
    zip -qry "$(basename "$DIST_ZIP")" "$(basename "$DIST_APP")" "$(basename "$DIST_INSTALL")"
)

echo "Version: $PACKAGE_VERSION"
echo "App bundle: $DIST_APP"
echo "Install guide: $DIST_INSTALL"
echo "Archive: $DIST_ZIP"
