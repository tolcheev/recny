# Recny v0.1.5 macOS Permissions/Updates Build

## What Changed Since v0.1.4

- Normal `Fix Permissions` no longer clears a previously successful system-audio permission probe.
- Added `Diagnostics -> Force Recheck Permissions` for the rare case where macOS Privacy settings were changed and the cached state is stale.
- Permission copy now explains that macOS calls the permission `Screen & System Audio Recording`, but Recny records only audio, not screen video.
- Added Settings -> About update checks using the public `latest.json` manifest.
- App bundle version is now `0.1.5`, build `6`.

## Install

1. Download `Recny-v0.1.5-macOS.dmg`.
2. Open the DMG.
3. Drag `Recny.app` to Applications.
4. First launch: Finder -> Applications -> right-click `Recny` -> Open.
5. If macOS blocks launch, open System Settings -> Privacy & Security -> Security -> Open Anyway.

## Update Checks

Settings -> About -> Check for Updates reads:

`https://tolcheev.github.io/recny/latest.json`

Recny opens the GitHub download URL. It does not overwrite or replace itself automatically.
