#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ToRec"
LEGACY_APP_NAME="TOrbitRecorder"
PROCESS_NAME="TOrbitRecorder"
DIST_APP="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"
LEGACY_INSTALL_APP="/Applications/$LEGACY_APP_NAME.app"
DRY_RUN="${DRY_RUN:-0}"
AUTO_QUIT="${AUTO_QUIT:-1}"
STORAGE_ROOT="${TORBIT_RECORDINGS_ROOT:-$HOME/Recordings/TOrbitRecorder}"
ALLOW_INSTALL_WHILE_RECORDING="${ALLOW_INSTALL_WHILE_RECORDING:-0}"

running_pids() {
    pgrep -x "$PROCESS_NAME" || true
}

is_running() {
    [[ -n "$(running_pids)" ]]
}

print_running_instances() {
    local pids
    pids="$(running_pids)"
    if [[ -n "$pids" ]]; then
        echo "Running $APP_NAME instances:"
        ps -p "$(echo "$pids" | paste -sd, -)" -o pid=,command=
    fi
}

active_recording_recoveries() {
    [[ -d "$STORAGE_ROOT" ]] || return 0

    while IFS= read -r -d '' recovery; do
        if /usr/bin/grep -Eq '"status"[[:space:]]*:[[:space:]]*"recording"' "$recovery"; then
            printf '%s\n' "$recovery"
        fi
    done < <(/usr/bin/find "$STORAGE_ROOT/Inbox/Unsorted" -name recovery.json -type f -print0 2>/dev/null)
}

if is_running && [[ "$ALLOW_INSTALL_WHILE_RECORDING" != "1" ]]; then
    active_recoveries="$(active_recording_recoveries)"
    if [[ -n "$active_recoveries" ]]; then
        print_running_instances
        echo "$APP_NAME appears to be actively recording. Refusing to install over a live recording." >&2
        echo "$active_recoveries" >&2
        echo "Stop recording and wait for finalization to finish, then rerun this script." >&2
        echo "Override only for emergency debugging: ALLOW_INSTALL_WHILE_RECORDING=1 ./scripts/install_macos.sh" >&2
        exit 1
    fi
fi

"$ROOT_DIR/scripts/package_macos.sh"

if is_running; then
    print_running_instances
    if [[ "$DRY_RUN" == "1" ]]; then
        echo "$APP_NAME is running. Dry run would ask every running copy to quit before replacing $INSTALL_APP."
    elif [[ "$AUTO_QUIT" == "1" ]]; then
        echo "$APP_NAME is running. Asking the app to quit before install..."
        osascript -e "tell application id \"com.torbit.recorder\" to quit" >/dev/null 2>&1 || true
        osascript -e "tell application \"$APP_NAME\" to quit" >/dev/null 2>&1 || true
        osascript -e "tell application \"$LEGACY_APP_NAME\" to quit" >/dev/null 2>&1 || true

        for _ in {1..10}; do
            if ! is_running; then
                break
            fi
            sleep 1
        done

        if is_running; then
            print_running_instances
            echo "$APP_NAME is still running. Quit every listed copy from the menu bar, then rerun this script." >&2
            echo "For debugging only, inspect running copies with: pgrep -fl TOrbitRecorder" >&2
            exit 1
        fi
    else
        echo "$APP_NAME is running. Quit every running copy from the menu bar, then rerun this script." >&2
        exit 1
    fi
fi

if [[ "$DRY_RUN" == "1" ]]; then
    echo "Dry run only. Would replace: $INSTALL_APP"
    echo "Dry run only. Would remove legacy app if present: $LEGACY_INSTALL_APP"
    echo "Dry run only. Would open: $INSTALL_APP"
    echo
    echo "Next steps after a real install:"
    echo "1. Grant Microphone permission to ToRec."
    echo "2. Grant system audio permission to ToRec."
    echo "3. Quit and reopen ToRec after changing audio permissions."
    echo "4. Recordings are stored in ~/Recordings/TOrbitRecorder/."
    exit 0
fi

rm -rf "$INSTALL_APP"
rm -rf "$LEGACY_INSTALL_APP"
cp -R "$DIST_APP" "$INSTALL_APP"
open "$INSTALL_APP"

echo "Installed: $INSTALL_APP"
echo "Launched: open $INSTALL_APP"
echo
echo "Next steps:"
echo "1. Grant Microphone permission in System Settings -> Privacy & Security -> Microphone."
echo "2. Grant system audio permission in System Settings -> Privacy & Security -> Screen & System Audio Recording."
echo "   If macOS shows Only System Audio Recording, enable ToRec there too."
echo "3. Quit and reopen ToRec after changing audio permissions."
echo "4. Recordings are stored in ~/Recordings/TOrbitRecorder/."
echo "5. Shareable packages are in $ROOT_DIR/dist/."
