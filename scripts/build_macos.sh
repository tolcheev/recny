#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/macos"
CONFIGURATION="${CONFIGURATION:-debug}"

swift build --package-path "$PACKAGE_DIR" -c "$CONFIGURATION"

BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PACKAGE_DIR/.build/app/TOrbitRecorder.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR"

cp "$BIN_DIR/TOrbitRecorder" "$MACOS_DIR/TOrbitRecorder"
cp "$PACKAGE_DIR/Sources/TOrbitRecorder/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
chmod +x "$MACOS_DIR/TOrbitRecorder"

echo "Built $APP_DIR"
