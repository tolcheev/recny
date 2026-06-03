#!/usr/bin/env python3
import json
import os
from datetime import datetime, timezone
from pathlib import Path


def env(name: str, default: str) -> str:
    return os.environ.get(name, default)


release_tag = env("TOREC_RELEASE_TAG", "torec-test-builds-2026-06-03-v5")
release_base = f"https://github.com/tolcheev/torec-releases/releases/download/{release_tag}"
release_page = f"https://github.com/tolcheev/torec-releases/releases/tag/{release_tag}"
mac_version = env("TOREC_MACOS_VERSION", "0.1.5")
mac_display_version = env("TOREC_MACOS_DISPLAY_VERSION", f"v{mac_version}")
mac_build = env("TOREC_MACOS_BUILD", "6")
windows_version = env("TOREC_WINDOWS_VERSION", "0.2.3-beta")
windows_display_version = env("TOREC_WINDOWS_DISPLAY_VERSION", f"v{windows_version}")
windows_build = env("TOREC_WINDOWS_BUILD", "3")
output_path = Path(env("TOREC_UPDATE_MANIFEST_PATH", "dist/latest.json"))

manifest = {
    "schema_version": 1,
    "generated_at": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    "macos": {
        "version": mac_version,
        "display_version": mac_display_version,
        "build": mac_build,
        "release_url": release_page,
        "download_url": f"{release_base}/ToRec-v{mac_version}-macOS.dmg",
        "sha256_url": f"{release_base}/ToRec-v{mac_version}-macOS.dmg.sha256",
        "notes": "Fixes repeated macOS permission prompts and adds update checks."
    },
    "windows": {
        "version": windows_version,
        "display_version": windows_display_version,
        "build": windows_build,
        "release_url": release_page,
        "download_url": f"{release_base}/ToRec-Windows-v{windows_version}.zip",
        "sha256_url": f"{release_base}/ToRec-Windows-v{windows_version}.zip.sha256",
        "notes": "Adds update checks and keeps Windows auto-recording beta behavior."
    }
}

output_path.parent.mkdir(parents=True, exist_ok=True)
output_path.write_text(
    json.dumps(manifest, ensure_ascii=False, indent=2) + "\n",
    encoding="utf-8",
)
print(output_path)
