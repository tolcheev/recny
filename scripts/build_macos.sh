#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/macos"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DISPLAY_VERSION="${APP_DISPLAY_VERSION:-v0.1.1-mvp}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.1}"
BUILD_NUMBER="${BUILD_NUMBER:-2}"
GIT_COMMIT="${GIT_COMMIT:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
BUILD_DATE="${BUILD_DATE:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

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

set_plist_value() {
    local key="$1"
    local type="$2"
    local value="$3"

    /usr/libexec/PlistBuddy -c "Set :$key $value" "$CONTENTS_DIR/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$CONTENTS_DIR/Info.plist"
}

set_plist_value "CFBundleShortVersionString" "string" "$MARKETING_VERSION"
set_plist_value "CFBundleVersion" "string" "$BUILD_NUMBER"
set_plist_value "TORbitAppVersion" "string" "$APP_DISPLAY_VERSION"
set_plist_value "TORbitBuildDate" "string" "$BUILD_DATE"
set_plist_value "TORbitGitCommit" "string" "$GIT_COMMIT"

codesign --force --sign - --timestamp=none --identifier "com.torbit.recorder" "$APP_DIR"

echo "Built $APP_DIR"
echo "Version: $APP_DISPLAY_VERSION"
echo "Build date: $BUILD_DATE"
echo "Git commit: $GIT_COMMIT"
echo "Code sign identifier: com.torbit.recorder"
