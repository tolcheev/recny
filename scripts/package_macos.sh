#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TOrbitRecorder"
BUILD_APP="$ROOT_DIR/apps/macos/.build/app/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"
DIST_ZIP="$DIST_DIR/$APP_NAME-macOS-MVP.zip"

"$ROOT_DIR/scripts/build_macos.sh"

rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR"

cp -R "$BUILD_APP" "$DIST_APP"

(
    cd "$DIST_DIR"
    zip -qry "$(basename "$DIST_ZIP")" "$(basename "$DIST_APP")"
)

echo "App bundle: $DIST_APP"
echo "Archive: $DIST_ZIP"
