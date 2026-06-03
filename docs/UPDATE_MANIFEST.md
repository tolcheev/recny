# ToRec Update Manifest

Both macOS and Windows clients check a small public JSON manifest:

`https://raw.githubusercontent.com/tolcheev/torec-releases/main/latest.json`

The manifest is intentionally separate from the app binaries so unsigned/free builds can still show a safe update prompt without self-modifying installed apps.

## Format

```json
{
  "schema_version": 1,
  "generated_at": "2026-06-03T08:00:00Z",
  "macos": {
    "version": "0.1.7",
    "display_version": "v0.1.7",
    "build": "8",
    "release_url": "https://github.com/tolcheev/torec-releases/releases/tag/torec-test-builds-2026-06-03-v7",
    "download_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v7/ToRec-v0.1.7-macOS.dmg",
    "sha256_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v7/ToRec-v0.1.7-macOS.dmg.sha256",
    "notes": "Adds background menu bar update notification with a subtle badge and later/skip actions."
  },
  "windows": {
    "version": "0.2.5-beta",
    "display_version": "v0.2.5-beta",
    "build": "5",
    "release_url": "https://github.com/tolcheev/torec-releases/releases/tag/torec-test-builds-2026-06-03-v7",
    "download_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v7/ToRec-Windows-v0.2.5-beta.zip",
    "sha256_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v7/ToRec-Windows-v0.2.5-beta.zip.sha256",
    "notes": "Adds tray update notification with a badge and later/skip actions."
  }
}
```

## Release Procedure

1. Build/package macOS with `PACKAGE_VERSION=v0.1.7 ./scripts/package_macos.sh`.
2. Build Windows on GitHub Actions and download `ToRec-Windows-v0.2.5-beta.zip`.
3. Upload both platform artifacts and `dist/latest.json` to the release.
4. Commit the same manifest to `tolcheev/torec-releases/main` as `latest.json`.
5. Verify the raw manifest URL returns HTTP 200 before announcing the release.
