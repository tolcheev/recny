# ToRec Windows v0.2.3 Beta

## What Changed Since v0.2.2

- Added update checks from the public `latest.json` manifest.
- Added `Updates` button to the main window.
- Added `Check for Updates` to the tray menu.
- Diagnostics now shows the informational app version `0.2.3-beta`.
- Recording metadata now writes version `0.2.3-beta`.

## Install

1. Download `ToRec-Windows-v0.2.3-beta.zip`.
2. Extract the archive.
3. Run `ToRec.exe`.
4. If Windows SmartScreen blocks the app, click `More info` -> `Run anyway`.

## Update Checks

The app checks:

`https://raw.githubusercontent.com/tolcheev/torec-releases/main/latest.json`

ToRec opens the GitHub download URL. It does not overwrite or replace itself automatically.
