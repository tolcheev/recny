#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_NAME="TOrbitRecorder"
DIST_APP="$ROOT_DIR/dist/$APP_NAME.app"
INSTALL_APP="/Applications/$APP_NAME.app"

"$ROOT_DIR/scripts/package_macos.sh"

rm -rf "$INSTALL_APP"
cp -R "$DIST_APP" "$INSTALL_APP"

echo "Installed: $INSTALL_APP"
echo "Launch with:"
echo "open /Applications/$APP_NAME.app"
