#!/usr/bin/env python3
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


repository = "https://github.com/tolcheev/recny"
mac_tag = env("RECNY_MACOS_RELEASE_TAG", "v0.1.9")
windows_tag = env("RECNY_WINDOWS_RELEASE_TAG", "v0.2.5-windows-beta")
mac_release_base = f"{repository}/releases/download/{mac_tag}"
windows_release_base = f"{repository}/releases/download/{windows_tag}"
mac_release_page = f"{repository}/releases/tag/{mac_tag}"
windows_release_page = f"{repository}/releases/tag/{windows_tag}"
mac_version = env("RECNY_MACOS_VERSION", "0.1.9")
mac_display_version = env("RECNY_MACOS_DISPLAY_VERSION", f"v{mac_version}")
mac_build = env("RECNY_MACOS_BUILD", "12")
windows_version = env("RECNY_WINDOWS_VERSION", "0.2.5-beta")
windows_display_version = env("RECNY_WINDOWS_DISPLAY_VERSION", f"v{windows_version}")
windows_build = env("RECNY_WINDOWS_BUILD", "5")
output_path = Path(env("RECNY_UPDATE_MANIFEST_PATH", "dist/latest.json"))

manifest = {
    "schema_version": 1,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "macos": {
        "version": mac_version,
        "display_version": mac_display_version,
        "build": mac_build,
        "release_url": mac_release_page,
        "download_url": f"{mac_release_base}/Recny-v{mac_version}-macOS.dmg",
        "sha256_url": f"{mac_release_base}/Recny-v{mac_version}-macOS.dmg.sha256",
        "notes": "Adds optional local transcripts and editable structured notes with timestamp links, queueing, cancellation and Markdown export."
    },
    "windows": {
        "version": windows_version,
        "display_version": windows_display_version,
        "build": windows_build,
        "release_url": windows_release_page,
        "download_url": f"{windows_release_base}/Recny-Windows-v{windows_version}.zip",
        "sha256_url": f"{windows_release_base}/Recny-Windows-v{windows_version}.zip.sha256",
        "notes": "Experimental Windows beta with local microphone and system-audio recording."
    }
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
print(output_path)
