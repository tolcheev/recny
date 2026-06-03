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
    "version": "0.1.6",
    "display_version": "v0.1.6",
    "build": "7",
    "release_url": "https://github.com/tolcheev/torec-releases/releases/tag/torec-test-builds-2026-06-03-v6",
    "download_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v6/ToRec-v0.1.6-macOS.dmg",
    "sha256_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v6/ToRec-v0.1.6-macOS.dmg.sha256",
    "notes": "Adds a Handy-style update reminder footer and a structured bug-report form link."
  },
  "windows": {
    "version": "0.2.4-beta",
    "display_version": "v0.2.4-beta",
    "build": "4",
    "release_url": "https://github.com/tolcheev/torec-releases/releases/tag/torec-test-builds-2026-06-03-v6",
    "download_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v6/ToRec-Windows-v0.2.4-beta.zip",
    "sha256_url": "https://github.com/tolcheev/torec-releases/releases/download/torec-test-builds-2026-06-03-v6/ToRec-Windows-v0.2.4-beta.zip.sha256",
    "notes": "Adds update reminder state and a structured bug-report form link."
  }
}
```

## Release Procedure

1. Build/package macOS with `PACKAGE_VERSION=v0.1.6 ./scripts/package_macos.sh`.
2. Build Windows on GitHub Actions and download `ToRec-Windows-v0.2.4-beta.zip`.
3. Upload both platform artifacts and `dist/latest.json` to the release.
4. Commit the same manifest to `tolcheev/torec-releases/main` as `latest.json`.
5. Verify the raw manifest URL returns HTTP 200 before announcing the release.
