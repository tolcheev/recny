#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TOrbitRecorder"
DIST_APP="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"
DRY_RUN="${DRY_RUN:-0}"
AUTO_QUIT="${AUTO_QUIT:-1}"

"$ROOT_DIR/scripts/package_macos.sh"

is_running() {
    pgrep -x "$APP_NAME" >/dev/null 2>&1
}

if is_running; then
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "$APP_NAME is running. Dry run would ask it to quit before replacing $INSTALL_APP."
    elif [[ "$AUTO_QUIT" == "1" ]]; then
        echo "$APP_NAME is running. Asking it to quit before install..."
        osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true

        for _ in {1..10}; do
            if ! is_running; then
                break
            fi
            sleep 1
        done

        if is_running; then
            echo "$APP_NAME is still running. Quit it from the menu bar, then rerun this script." >&2
            exit 1
        fi
    else
        echo "$APP_NAME is running. Quit it from the menu bar, then rerun this script." >&2
        exit 1
    fi
fi

if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run only. Would replace: $INSTALL_APP"
    echo "Dry run only. Would open: $INSTALL_APP"
    echo
    echo "Next steps after a real install:"
    echo "1. Grant Microphone permission to TOrbitRecorder."
    echo "2. Grant Screen & System Audio Recording permission to TOrbitRecorder."
    echo "3. Quit and reopen TOrbitRecorder after changing Screen & System Audio Recording."
    echo "4. Recordings are stored in ~/Recordings/TOrbitRecorder/."
    exit 0
fi

rm -rf "$INSTALL_APP"
cp -R "$DIST_APP" "$INSTALL_APP"
open "$INSTALL_APP"

echo "Installed: $INSTALL_APP"
echo "Launched: open $INSTALL_APP"
echo
echo "Next steps:"
echo "1. Grant Microphone permission in System Settings -> Privacy & Security -> Microphone."
echo "2. Grant Screen & System Audio Recording in System Settings -> Privacy & Security -> Screen & System Audio Recording."
echo "3. Quit and reopen TOrbitRecorder after changing Screen & System Audio Recording."
echo "4. Recordings are stored in ~/Recordings/TOrbitRecorder/."
echo "5. Install guide: $ROOT_DIR/dist/INSTALL.md"
