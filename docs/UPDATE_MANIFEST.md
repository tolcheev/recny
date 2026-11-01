# Recny Update Manifest

Both macOS and Windows clients check a small public JSON manifest:

`https://tolcheev.github.io/recny/latest.json`

The manifest is intentionally separate from the app binaries so unsigned/free builds can still show a safe update prompt without self-modifying installed apps.

## Format

```json
{
  "schema_version": 1,
  "generated_at": "2026-06-03T08:00:00Z",
  "macos": {
    "version": "0.1.9",
    "display_version": "v0.1.9",
    "build": "12",
    "release_url": "https://github.com/tolcheev/recny/releases/tag/v0.1.9",
    "download_url": "https://github.com/tolcheev/recny/releases/download/v0.1.9/Recny-v0.1.9-macOS.dmg",
    "sha256_url": "https://github.com/tolcheev/recny/releases/download/v0.1.9/Recny-v0.1.9-macOS.dmg.sha256",
    "notes": "Public Recny release with local call recording, library tools, and update checks."
  },
  "windows": {
    "version": "0.2.5-beta",
    "display_version": "v0.2.5-beta",
    "build": "5",
    "release_url": "https://github.com/tolcheev/recny/releases/tag/v0.2.5-windows-beta",
    "download_url": "https://github.com/tolcheev/recny/releases/download/v0.2.5-windows-beta/Recny-Windows-v0.2.5-beta.zip",
    "sha256_url": "https://github.com/tolcheev/recny/releases/download/v0.2.5-windows-beta/Recny-Windows-v0.2.5-beta.zip.sha256",
    "notes": "Experimental Windows beta with local microphone and system-audio recording."
  }
}
```

## Release Procedure

1. Build/package macOS with `PACKAGE_VERSION=v0.1.9 ./scripts/package_macos.sh`.
2. Publish the macOS artifacts under tag `v0.1.9`.
3. Build Windows on GitHub Actions and download `Recny-Windows-v0.2.5-beta.zip`.
4. Publish the Windows artifacts under tag `v0.2.5-windows-beta`.
5. Commit the generated manifest to `site/latest.json` so GitHub Pages deploys it with the website.
6. Verify the Pages manifest and every release asset return HTTP 200 before announcing the release.
