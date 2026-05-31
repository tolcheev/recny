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
DMG_BACKGROUND="$DIST_DIR/dmg-background.png"
DMG_RW="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-macOS-rw.dmg"
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
    "$DMG_BACKGROUND"

cp -R "$BUILD_APP" "$DIST_APP"

(
    cd "$DIST_DIR"
    /usr/bin/zip -qry "$(basename "$DIST_ZIP")" "$(basename "$DIST_APP")"
)

mkdir -p "$DMG_ROOT"
cp -R "$DIST_APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
python3 "$ROOT_DIR/scripts/make_macos_assets.py" dmg-background "$DMG_BACKGROUND"
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
cp "$DMG_BACKGROUND" "$MOUNT_DIR/.background/background.png"

/usr/bin/osascript <<APPLESCRIPT
set volumeAlias to POSIX file "$MOUNT_DIR" as alias
set backgroundAlias to POSIX file "$MOUNT_DIR/.background/background.png" as alias

tell application "Finder"
    open volumeAlias
    set containerWindow to container window of volumeAlias
    set current view of containerWindow to icon view
    set toolbar visible of containerWindow to false
    set statusbar visible of containerWindow to false
    set bounds of containerWindow to {120, 120, 760, 480}
    set viewOptions to icon view options of containerWindow
    set arrangement of viewOptions to not arranged
    set icon size of viewOptions to 96
    set background picture of viewOptions to backgroundAlias
    set position of item "$APP_NAME.app" of volumeAlias to {185, 170}
    set position of item "Applications" of volumeAlias to {455, 170}
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
