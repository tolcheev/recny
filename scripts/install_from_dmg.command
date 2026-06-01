#!/bin/bash
set -euo pipefail

APP_NAME="ToRec"
PROCESS_NAME="TOrbitRecorder"
BUNDLE_ID="com.torbit.recorder"
SOURCE_DIR="$(cd "$(dirname "$0")" && pwd)"
SOURCE_APP="$SOURCE_DIR/$APP_NAME.app"
TARGET_APP="/Applications/$APP_NAME.app"
LEGACY_TARGET_APP="/Applications/TOrbitRecorder.app"
STORAGE_ROOT="${TORBIT_RECORDINGS_ROOT:-$HOME/Recordings/TOrbitRecorder}"
ALLOW_INSTALL_WHILE_RECORDING="${ALLOW_INSTALL_WHILE_RECORDING:-0}"

echo "ToRec installer"
echo "==============="
echo

if [[ ! -d "$SOURCE_APP" ]]; then
    echo "Could not find $APP_NAME.app next to this installer."
    echo "Open the ToRec DMG again and run Install ToRec.command from there."
    echo
    read -r -n 1 -p "Press any key to close..."
    echo
    exit 1
fi

active_recording_recoveries() {
    [[ -d "$STORAGE_ROOT" ]] || return 0

    while IFS= read -r -d '' recovery; do
        if /usr/bin/grep -Eq '"status"[[:space:]]*:[[:space:]]*"recording"' "$recovery"; then
            printf '%s\n' "$recovery"
        fi
    done < <(/usr/bin/find "$STORAGE_ROOT/Inbox/Unsorted" -name recovery.json -type f -print0 2>/dev/null)
}

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1 && [[ "$ALLOW_INSTALL_WHILE_RECORDING" != "1" ]]; then
    active_recoveries="$(active_recording_recoveries)"
    if [[ -n "$active_recoveries" ]]; then
        echo "$APP_NAME appears to be recording now."
        echo "Stop recording and wait for finalization before installing a new build."
        echo
        echo "$active_recoveries"
        echo
        read -r -n 1 -p "Press any key to close..."
        echo
        exit 1
    fi
fi

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
    echo "$APP_NAME is running. Asking it to quit before replacing the app..."
    osascript -e "tell application id \"$BUNDLE_ID\" to quit" >/dev/null 2>&1 || true
    osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true

    for _ in {1..10}; do
        if ! pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
            break
        fi
        sleep 1
    done
fi

if pgrep -x "$PROCESS_NAME" >/dev/null 2>&1; then
    echo
    echo "$APP_NAME is still running."
    echo "Quit it from the menu bar, then run this installer again."
    echo
    read -r -n 1 -p "Press any key to close..."
    echo
    exit 1
fi

echo "Installing $APP_NAME into /Applications..."
rm -rf "$TARGET_APP" "$LEGACY_TARGET_APP"
/usr/bin/ditto "$SOURCE_APP" "$TARGET_APP"

echo "Removing downloaded-app quarantine flag for this local install..."
/usr/bin/xattr -cr "$TARGET_APP" 2>/dev/null || true

echo "Opening $APP_NAME..."
/usr/bin/open "$TARGET_APP"

echo
echo "Done."
echo
echo "If macOS still blocks the first launch:"
echo "1. Click Done."
echo "2. Double-click Open Privacy Settings in this DMG."
echo "3. Click Open Anyway / Все равно открыть."
echo
read -r -n 1 -p "Press any key to close this window..."
echo
