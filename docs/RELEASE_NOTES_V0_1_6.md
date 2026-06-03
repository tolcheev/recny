# ToRec v0.1.6 macOS Update Reminder / Bug Report Build

## What Changed Since v0.1.5

- Added a Handy-style update footer to the main recorder window.
- Added quiet automatic update checks at most once per 24 hours.
- Added `Download`, `Later`, and `Skip` actions for available updates.
- Update reminders are not surfaced while recording is active.
- Added `Report Bug` links in the main window, Settings/About, and the menu bar.
- Bug reports open the public structured GitHub issue form with the app version and platform prefilled.

## Install

1. Download `ToRec-v0.1.6-macOS.dmg`.
2. Drag `ToRec.app` to `Applications`.
3. First launch: Finder -> Applications -> right-click ToRec -> Open.
4. If macOS blocks launch, click `Done`, then System Settings -> Privacy & Security -> Security -> `Open Anyway`.

## Notes

- ToRec still does not auto-replace itself. The update action opens the public GitHub download.
- The app still does not request macOS Notifications permission.
- Recordings remain local under `~/Recordings/TOrbitRecorder/`.
