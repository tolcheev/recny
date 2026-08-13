# Recny

## Product goal

Build a lightweight macOS desktop app for automatic audio recording of calls.

MVP target:
- macOS Sequoia
- Apple Silicon
- primary device MacBook M4 Pro
- local-first storage
- audio-only recording
- automatic start
- microphone + system audio
- no screen recording in MVP
- no cloud upload in MVP
- no T-Orbit sync in MVP
- no AI in MVP
- no Windows in MVP

## Stack

- Swift
- SwiftUI
- AVFoundation
- ScreenCaptureKit
- SQLite
- macOS menu bar app
- no Electron

## MVP recording output

Each recording must create:

source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json

## MVP storage

Default path:

~/Recordings/TOrbitRecorder/

## Architecture rules

Recorder is a separate desktop client.
T-Orbit backend is not part of this repository.

Heavy audio/video files are stored locally in MVP.
In future versions, heavy files can be uploaded to external storage.
T-Orbit stores metadata, tags, transcripts, notes, permissions and links.

## Do not implement in MVP

- screen recording
- cloud upload
- Telegram integration
- AI transcription
- Windows support
- encryption
- retention/autodelete
- T-Orbit backend sync

## Development rules

- Keep the app lightweight
- Prefer native macOS APIs
- Keep recording engine testable separately from UI
- Every behavior change must update docs
- Add logs for recorder lifecycle and failures
- Do not fake working audio capture
- Stop and report if macOS permission limitations block implementation
- Use small PR-sized commits
- Validate with xcodebuild/swift test when possible
