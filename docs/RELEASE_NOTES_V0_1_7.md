# ToRec v0.1.7 macOS Menu Bar Update Notification Build

## What Changed Since v0.1.6

- Added background update checks from the menu bar app lifecycle.
- Added a subtle blue update badge on the menu bar icon when a new version is available.
- Added a menu bar `Update available: ...` action plus `Remind Later` and `Skip This Version`.
- Recording and permission-problem states still take priority over update badges.
- Existing `Download`, `Later`, and `Skip` actions in the main window still work.

## Install

1. Download `ToRec-v0.1.7-macOS.dmg`.
2. Drag `ToRec.app` to `Applications`.
3. First launch: Finder -> Applications -> right-click ToRec -> Open.
4. If macOS blocks launch, click `Done`, then System Settings -> Privacy & Security -> Security -> `Open Anyway`.

## Notes

- ToRec still does not auto-replace itself. The update action opens the public GitHub download.
- The app still does not request macOS Notifications permission; update notifications stay inside ToRec.
- Recordings remain local under `~/Recordings/TOrbitRecorder/`.
