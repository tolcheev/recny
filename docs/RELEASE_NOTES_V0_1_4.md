# Recny v0.1.4 macOS DMG/Icon Fix

Internal Apple Silicon macOS build for easier student testing.

## What Changed Since v0.1.3

- DMG layout now puts `Recny.app` on the left and `Applications` on the right.
- DMG background includes a large right-pointing arrow from `Recny.app` to `Applications`.
- DMG includes visible install/Gatekeeper instructions without extra installer-script icons.
- Added a real app icon: play triangle on transparent background.
- App bundle version is now `0.1.4`, build `5`.

## Install

Use the DMG:

1. Download `Recny-v0.1.4-macOS.dmg`.
2. Open the DMG.
3. Drag `Recny.app` along the arrow into `Applications`.
4. Open Finder -> Applications.
5. Right-click `Recny` -> Open.
6. If macOS still blocks it, click `Done`, then open System Settings -> Privacy & Security -> Security and press `Open Anyway` / `Все равно открыть`.

## Gatekeeper Note

This build is still ad-hoc signed and not notarized with Apple Developer ID. A normal double-click can show a scary Gatekeeper dialog.

This cannot be silently bypassed for other people's Macs in the test build. The proper product fix is Developer ID signing plus Apple notarization. Until then, use the explicit trusted-testing path:

1. Finder -> Applications -> right-click `Recny` -> Open.
2. If macOS still blocks it, open System Settings -> Privacy & Security -> Security manually.
3. Click `Open Anyway` / `Все равно открыть` for `Recny`.

![macOS Gatekeeper Open Anyway](assets/gatekeeper-open-anyway.png)

The real long-term fix is Developer ID signing and Apple notarization. The DMG drag-and-open flow is the best free option for controlled trusted testing, not a substitute for notarization.
