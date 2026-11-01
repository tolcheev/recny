#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PACKAGE_DIR="$ROOT_DIR/apps/macos"
CONFIGURATION="${CONFIGURATION:-release}"
APP_DISPLAY_NAME="${APP_DISPLAY_NAME:-Recny}"
EXECUTABLE_NAME="Recny"
APP_DISPLAY_VERSION="${APP_DISPLAY_VERSION:-v0.1.9}"
MARKETING_VERSION="${MARKETING_VERSION:-0.1.9}"
BUILD_NUMBER="${BUILD_NUMBER:-12}"
GIT_COMMIT="${GIT_COMMIT:-$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)}"
BUILD_DATE="${BUILD_DATE:-$(date -u +"%Y-%m-%dT%H:%M:%SZ")}"

swift build --package-path "$PACKAGE_DIR" -c "$CONFIGURATION"

BIN_DIR="$(swift build --package-path "$PACKAGE_DIR" -c "$CONFIGURATION" --show-bin-path)"
APP_DIR="$PACKAGE_DIR/.build/app/$APP_DISPLAY_NAME.app"
CONTENTS_DIR="$APP_DIR/Contents"
MACOS_DIR="$CONTENTS_DIR/MacOS"
RESOURCES_DIR="$CONTENTS_DIR/Resources"

rm -rf "$APP_DIR"
mkdir -p "$MACOS_DIR" "$RESOURCES_DIR"

cp "$BIN_DIR/$EXECUTABLE_NAME" "$MACOS_DIR/$EXECUTABLE_NAME"
# Keep the optional Python helper inside the signed application resources.
cp -R "$BIN_DIR/Recny_RecnyCore.bundle" "$RESOURCES_DIR/Recny_RecnyCore.bundle"
cp "$PACKAGE_DIR/Sources/Recny/Resources/Info.plist" "$CONTENTS_DIR/Info.plist"
python3 "$ROOT_DIR/scripts/make_macos_assets.py" app-icon "$RESOURCES_DIR/AppIcon.icns"
chmod +x "$MACOS_DIR/$EXECUTABLE_NAME"

set_plist_value() {
    local key="$1"
    local type="$2"
    local value="$3"

    /usr/libexec/PlistBuddy -c "Set :$key $value" "$CONTENTS_DIR/Info.plist" 2>/dev/null \
        || /usr/libexec/PlistBuddy -c "Add :$key $type $value" "$CONTENTS_DIR/Info.plist"
}

set_plist_value "CFBundleDisplayName" "string" "$APP_DISPLAY_NAME"
set_plist_value "CFBundleName" "string" "$APP_DISPLAY_NAME"
set_plist_value "CFBundleShortVersionString" "string" "$MARKETING_VERSION"
set_plist_value "CFBundleVersion" "string" "$BUILD_NUMBER"
set_plist_value "CFBundleIconFile" "string" "AppIcon"
set_plist_value "RecnyAppVersion" "string" "$APP_DISPLAY_VERSION"
set_plist_value "RecnyBuildDate" "string" "$BUILD_DATE"
set_plist_value "RecnyGitCommit" "string" "$GIT_COMMIT"

codesign --force --sign - --timestamp=none --identifier "com.torbit.recorder" "$APP_DIR"

echo "Built $APP_DIR"
echo "Version: $APP_DISPLAY_VERSION"
echo "Build date: $BUILD_DATE"
echo "Git commit: $GIT_COMMIT"
echo "Code sign identifier: com.torbit.recorder"
