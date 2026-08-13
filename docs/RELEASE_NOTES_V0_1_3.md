# Recny v0.1.3 macOS Install-Fix Build

Internal Apple Silicon macOS build for easier student testing.

## What Changed Since v0.1.2

- Added a DMG package: `Recny-v0.1.3-macOS.dmg`.
- The release zip is now app-only: `Recny-v0.1.3-macOS.zip` contains only `Recny.app`.
- Removed `INSTALL.md` and release notes from the user-facing zip to avoid opening the wrong file after unzip.
- App bundle version is now `0.1.3`, build `4`.

## Recommended Install Path

Use the DMG:

1. Download `Recny-v0.1.3-macOS.dmg`.
2. Open the DMG.
3. Drag `Recny.app` to `Applications`.
4. Open Finder -> Applications.
5. Right-click `Recny` -> Open.
6. If macOS warns that Apple cannot verify the app, click `Open` when the right-click flow allows it.

If the user downloaded the zip instead:

1. Unzip it.
2. Move `Recny.app` to Applications.
3. Open Finder -> Applications.
4. Right-click `Recny` -> Open.

## Gatekeeper Note

This build is still ad-hoc signed and not notarized with Apple Developer ID. A normal double-click can show a scary Gatekeeper dialog. The expected workaround for trusted internal testing is Finder -> Applications -> right-click `Recny` -> Open.

The real long-term fix is Developer ID signing and Apple notarization.
