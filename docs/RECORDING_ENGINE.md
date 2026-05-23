# Recording Engine

## Responsibilities

- Start and stop microphone capture.
- Start and stop system audio capture.
- Write source files separately.
- Produce a mixed export file.
- Persist metadata for every session.
- Log lifecycle events and failures.

## Capture APIs

- Microphone capture: AVFoundation.
- System audio capture: ScreenCaptureKit where macOS permits.

The MVP must not simulate successful capture. If a native permission or API limitation blocks capture, implementation must stop and report the limitation clearly.

## Session Output

Each session directory contains:

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

## Testability

The recording engine should be testable without the SwiftUI menu bar app. File layout, metadata generation, state transitions, and error mapping should have package-level tests where possible.
