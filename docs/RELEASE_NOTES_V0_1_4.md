# ToRec v0.1.4 macOS DMG/Icon Fix

Internal Apple Silicon macOS build for easier student testing.

## What Changed Since v0.1.3

- DMG layout now puts `ToRec.app` on the left and `Applications` on the right.
- DMG background includes a large right-pointing arrow from `ToRec.app` to `Applications`.
- DMG now includes visible install/Gatekeeper instructions, `Install ToRec.command`, and an `Open Privacy Settings` shortcut.
- Added a real app icon: play triangle on transparent background.
- App bundle version is now `0.1.4`, build `5`.

## Install

Use the DMG:

1. Download `ToRec-v0.1.4-macOS.dmg`.
2. Open the DMG.
3. Double-click `Install ToRec.command`.
4. If macOS asks whether Terminal may run it, allow it.
5. If macOS still blocks `ToRec`, click `Done`.
6. Double-click `Open Privacy Settings` in the DMG and press `Open Anyway` / `Все равно открыть`.

Manual fallback:

1. Drag `ToRec.app` along the arrow into `Applications`.
2. Open Finder -> Applications.
3. Right-click `ToRec` -> Open.
4. If macOS still blocks it, double-click `Open Privacy Settings` in the DMG and press `Open Anyway` / `Все равно открыть`.

## Gatekeeper Note

This build is still ad-hoc signed and not notarized with Apple Developer ID. A normal double-click can show a scary Gatekeeper dialog.

This cannot be silently bypassed for other people's Macs in the test build. The proper product fix is Developer ID signing plus Apple notarization. Until then, use the explicit trusted-testing path:

1. Prefer `Install ToRec.command` from the DMG.
2. If macOS still blocks it, double-click `Open Privacy Settings` in the DMG or open System Settings -> Privacy & Security -> Security manually.
3. Click `Open Anyway` / `Все равно открыть` for `ToRec`.

![macOS Gatekeeper Open Anyway](assets/gatekeeper-open-anyway.png)

The real long-term fix is Developer ID signing and Apple notarization. The DMG helper is the best free option for controlled trusted testing, not a substitute for notarization.
