# t-orbit-recorder

Lightweight native macOS recorder for automatic audio-only call capture.

MVP focus:
- macOS Sequoia on Apple Silicon
- menu bar desktop app
- microphone and system audio recording
- local-first storage under `~/Recordings/TOrbitRecorder/`
- no Electron, cloud upload, AI, screen recording, Windows support, or T-Orbit sync

Project docs live in `docs/`. Implementation will be split between the macOS app in `apps/macos` and testable Swift packages under `packages/`.
