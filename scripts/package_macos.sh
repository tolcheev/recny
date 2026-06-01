#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="ToRec"
LEGACY_APP_NAME="TOrbitRecorder"
PACKAGE_VERSION="${PACKAGE_VERSION:-v0.1.4}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-$APP_NAME $PACKAGE_VERSION}"
BUILD_APP="$ROOT_DIR/apps/macos/.build/app/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"
DIST_ZIP="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-macOS.zip"
DIST_DMG="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-macOS.dmg"
DIST_SHA256="$DIST_ZIP.sha256"
DIST_DMG_SHA256="$DIST_DMG.sha256"
DMG_ROOT="$DIST_DIR/dmg-root"
DMG_BACKGROUND="$DIST_DIR/dmg-background.tiff"
DMG_BACKGROUND_PREFIX="$DIST_DIR/dmg-background"
DMG_BACKGROUND_GENERATOR="$DIST_DIR/dmg-background-generator"
DMG_RW="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-macOS-rw.dmg"
INSTALL_COMMAND_NAME="Install ToRec.command"
INSTALL_COMMAND_SOURCE="$ROOT_DIR/scripts/install_from_dmg.command"
PRIVACY_SETTINGS_NAME="Open Privacy Settings"
PRIVACY_SETTINGS_TARGET="/System/Library/PreferencePanes/Security.prefPane"
MOUNT_DIR=""

cleanup_mount() {
    if [[ -n "$MOUNT_DIR" && -d "$MOUNT_DIR" ]]; then
        hdiutil detach "$MOUNT_DIR" >/dev/null 2>&1 || true
    fi
}

trap cleanup_mount EXIT

"$ROOT_DIR/scripts/build_macos.sh"

mkdir -p "$DIST_DIR"
rm -rf \
    "$DIST_APP" \
    "$DIST_DIR/INSTALL.md" \
    "$DIST_DIR/RELEASE_NOTES.md" \
    "$DIST_DIR"/"$APP_NAME"-*-macOS.zip \
    "$DIST_DIR"/"$APP_NAME"-*-macOS.zip.sha256 \
    "$DIST_DIR"/"$APP_NAME"-*-macOS.dmg \
    "$DIST_DIR"/"$APP_NAME"-*-macOS.dmg.sha256 \
    "$DIST_DIR"/"$APP_NAME"-*-macOS-rw.dmg \
    "$DIST_DIR"/"$LEGACY_APP_NAME"-*-macOS.zip \
    "$DIST_DIR"/"$LEGACY_APP_NAME"-*-macOS.zip.sha256 \
    "$DIST_DIR/$APP_NAME-macOS-MVP.zip" \
    "$DIST_DIR/$LEGACY_APP_NAME.app" \
    "$DMG_ROOT" \
    "$DMG_BACKGROUND" \
    "$DMG_BACKGROUND_PREFIX"_1x.png \
    "$DMG_BACKGROUND_PREFIX"_2x.png \
    "$DMG_BACKGROUND_GENERATOR"

cp -R "$BUILD_APP" "$DIST_APP"

(
    cd "$DIST_DIR"
    /usr/bin/zip -qry "$(basename "$DIST_ZIP")" "$(basename "$DIST_APP")"
)

mkdir -p "$DMG_ROOT"
cp -R "$DIST_APP" "$DMG_ROOT/$APP_NAME.app"
cp "$INSTALL_COMMAND_SOURCE" "$DMG_ROOT/$INSTALL_COMMAND_NAME"
chmod +x "$DMG_ROOT/$INSTALL_COMMAND_NAME"
ln -s /Applications "$DMG_ROOT/Applications"
ln -s "$PRIVACY_SETTINGS_TARGET" "$DMG_ROOT/$PRIVACY_SETTINGS_NAME"
swiftc "$ROOT_DIR/scripts/dmg_background.swift" -o "$DMG_BACKGROUND_GENERATOR"
"$DMG_BACKGROUND_GENERATOR" "$DMG_BACKGROUND_PREFIX" >/dev/null
tiffutil \
    -cathidpicheck \
    "$DMG_BACKGROUND_PREFIX"_1x.png \
    "$DMG_BACKGROUND_PREFIX"_2x.png \
    -out "$DMG_BACKGROUND" >/dev/null
hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDRW \
    "$DMG_RW" >/dev/null

ATTACH_OUTPUT="$(hdiutil attach -readwrite -noverify -noautoopen "$DMG_RW")"
MOUNT_DIR="$(printf '%s\n' "$ATTACH_OUTPUT" | awk '/\/Volumes\// {print substr($0, index($0, "/Volumes/")); exit}')"
if [[ -z "$MOUNT_DIR" || ! -d "$MOUNT_DIR" ]]; then
    echo "Failed to mount DMG for Finder layout" >&2
    printf '%s\n' "$ATTACH_OUTPUT" >&2
    exit 1
fi
mkdir -p "$MOUNT_DIR/.background"
cp "$DMG_BACKGROUND" "$MOUNT_DIR/.background/background.tiff"

/usr/bin/osascript <<APPLESCRIPT
set volumeAlias to POSIX file "$MOUNT_DIR" as alias
set backgroundAlias to POSIX file "$MOUNT_DIR/.background/background.tiff" as alias

tell application "Finder"
    open volumeAlias
    set containerWindow to container window of volumeAlias
    set current view of containerWindow to icon view
    set toolbar visible of containerWindow to false
    set statusbar visible of containerWindow to false
    set bounds of containerWindow to {100, 100, 760, 664}
    set viewOptions to icon view options of containerWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to backgroundAlias
    set position of item "$APP_NAME.app" of volumeAlias to {175, 108}
    set position of item "Applications" of volumeAlias to {485, 108}
    set position of item "$INSTALL_COMMAND_NAME" of volumeAlias to {330, 258}
    set position of item "$PRIVACY_SETTINGS_NAME" of volumeAlias to {330, 410}
    update volumeAlias without registering applications
    delay 3
    close containerWindow
end tell
APPLESCRIPT

rm -rf "$MOUNT_DIR/.fseventsd" "$MOUNT_DIR/.Trashes"
sync
hdiutil detach "$MOUNT_DIR" >/dev/null
MOUNT_DIR=""

hdiutil convert "$DMG_RW" -format UDZO -o "$DIST_DMG" >/dev/null
rm -f "$DMG_RW"

(
    cd "$DIST_DIR"
    env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$(basename "$DIST_ZIP")" > "$(basename "$DIST_SHA256")"
    env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$(basename "$DIST_DMG")" > "$(basename "$DIST_DMG_SHA256")"
)

echo "Version: $PACKAGE_VERSION"
echo "App bundle: $DIST_APP"
echo "Archive: $DIST_ZIP"
echo "SHA256: $DIST_SHA256"
echo "DMG: $DIST_DMG"
echo "DMG SHA256: $DIST_DMG_SHA256"
