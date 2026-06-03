# ToRec Windows v0.2.5 Beta

## What Changed Since v0.2.4

- Added background update checks from the tray app lifecycle.
- Added a tray update badge and `Update available: ...` menu item when a new version is available.
- Recording state stays primary while a recording is active.
- Tray update checks now support download, remind later, and skip-this-version behavior.
- Recording metadata now writes version `0.2.5-beta`.

## Install

1. Download `ToRec-Windows-v0.2.5-beta.zip`.
2. Extract the archive.
3. Run `ToRec.exe`.
4. If SmartScreen blocks the app, choose `More info` -> `Run anyway`.

## Notes

- Auto-start remains beta behavior.
- ToRec still opens the public GitHub release download instead of replacing itself.
- Recordings stay local under `%USERPROFILE%\Recordings\TOrbitRecorder\`.
