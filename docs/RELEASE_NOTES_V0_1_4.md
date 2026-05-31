# ToRec v0.1.4 macOS DMG/Icon Fix

Internal Apple Silicon macOS build for easier student testing.

## What Changed Since v0.1.3

- DMG layout now puts `ToRec.app` on the left and `Applications` on the right.
- DMG background includes a large right-pointing arrow from `ToRec.app` to `Applications`.
- Added a real app icon: play triangle on transparent background.
- App bundle version is now `0.1.4`, build `5`.

## Install

Use the DMG:

1. Download `ToRec-v0.1.4-macOS.dmg`.
2. Open the DMG.
3. Drag `ToRec.app` along the arrow into `Applications`.
4. Open Finder -> Applications.
5. Right-click `ToRec` -> Open.

## Gatekeeper Note

This build is still ad-hoc signed and not notarized with Apple Developer ID. A normal double-click can show a scary Gatekeeper dialog.

This cannot be silently bypassed for other people's Macs in the test build. The proper product fix is Developer ID signing plus Apple notarization. Until then, use the explicit trusted-testing path:

1. Finder -> Applications -> right-click `ToRec` -> Open.
2. If macOS still blocks it, open System Settings -> Privacy & Security -> Security.
3. Click `Open Anyway` / `Все равно открыть` for `ToRec`.

![macOS Gatekeeper Open Anyway](assets/gatekeeper-open-anyway.png)

The real long-term fix is Developer ID signing and Apple notarization.
