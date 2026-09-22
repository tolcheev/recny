#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="Recny"
LEGACY_APP_NAMES=("ToRec" "TOrbitRecorder")
PACKAGE_VERSION="${PACKAGE_VERSION:-v0.1.8}"
DMG_VOLUME_NAME="${DMG_VOLUME_NAME:-$APP_NAME $PACKAGE_VERSION}"
BUILD_APP="$ROOT_DIR/apps/macos/.build/app/$APP_NAME.app"
DIST_DIR="$ROOT_DIR/dist"
DIST_APP="$DIST_DIR/$APP_NAME.app"
DIST_ZIP="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-macOS.zip"
DIST_DMG="$DIST_DIR/$APP_NAME-$PACKAGE_VERSION-macOS.dmg"
DIST_SHA256="$DIST_ZIP.sha256"
DIST_DMG_SHA256="$DIST_DMG.sha256"
DMG_ROOT="$DIST_DIR/dmg-root"

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
    "$DIST_DIR/$APP_NAME-macOS-MVP.zip" \
    "$DMG_ROOT"

for legacy_app_name in "${LEGACY_APP_NAMES[@]}"; do
    rm -rf \
        "$DIST_DIR"/"$legacy_app_name"-*-macOS.zip \
        "$DIST_DIR"/"$legacy_app_name"-*-macOS.zip.sha256 \
        "$DIST_DIR/$legacy_app_name.app"
done

cp -R "$BUILD_APP" "$DIST_APP"

(
    cd "$DIST_DIR"
    /usr/bin/zip -qry "$(basename "$DIST_ZIP")" "$(basename "$DIST_APP")"
)

mkdir -p "$DMG_ROOT"
cp -R "$DIST_APP" "$DMG_ROOT/$APP_NAME.app"
ln -s /Applications "$DMG_ROOT/Applications"
hdiutil create \
    -volname "$DMG_VOLUME_NAME" \
    -srcfolder "$DMG_ROOT" \
    -ov \
    -format UDZO \
    "$DIST_DMG" >/dev/null
rm -rf "$DMG_ROOT"

(
    cd "$DIST_DIR"
    env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$(basename "$DIST_ZIP")" > "$(basename "$DIST_SHA256")"
    env LC_ALL=C LANG=C /usr/bin/shasum -a 256 "$(basename "$DIST_DMG")" > "$(basename "$DIST_DMG_SHA256")"
)

RECNY_UPDATE_MANIFEST_PATH="$DIST_DIR/latest.json" \
    RECNY_MACOS_VERSION="${PACKAGE_VERSION#v}" \
    RECNY_MACOS_DISPLAY_VERSION="$PACKAGE_VERSION" \
    RECNY_MACOS_BUILD="${BUILD_NUMBER:-8}" \
    "$ROOT_DIR/scripts/write_update_manifest.py" >/dev/null

echo "Version: $PACKAGE_VERSION"
echo "App bundle: $DIST_APP"
echo "Archive: $DIST_ZIP"
echo "SHA256: $DIST_SHA256"
echo "DMG: $DIST_DMG"
echo "DMG SHA256: $DIST_DMG_SHA256"
echo "Update manifest: $DIST_DIR/latest.json"
