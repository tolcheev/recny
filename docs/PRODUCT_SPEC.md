# Product Spec

## Goal

T-Orbit Recorder is a lightweight native macOS desktop app that automatically records call audio locally.

The MVP must produce reliable audio-only recordings without adding backend, AI, or cloud dependencies.

## Target Platform

- macOS Sequoia
- Apple Silicon
- primary device: MacBook M4 Pro

## Core User Outcome

When a user joins a supported call, the app starts recording microphone and system audio automatically, stores the recording locally, and keeps metadata that can be used by future versions.

## Non-Goals

- screen recording
- cloud upload
- T-Orbit backend sync
- AI transcription or summaries
- Telegram integration
- Windows support
- encryption
- retention or autodelete policies

## MVP Output

Each recording session must create:

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

## Success Criteria

- The app records microphone audio with real AVFoundation capture.
- The app records system audio with real native macOS APIs where permitted.
- Recorder lifecycle and failures are logged.
- The recording engine is testable separately from the UI.
- Local files remain under `~/Recordings/TOrbitRecorder/` by default.
