# MVP Scope

## In Scope

- Native macOS menu bar app.
- Automatic recording start based on local app/activity rules.
- Microphone audio capture.
- System audio capture where macOS permissions and APIs allow it.
- Mixed audio export.
- Per-recording metadata.
- Local storage only.
- Basic lifecycle logs.

## Out of Scope

- Screen recording.
- Cloud upload.
- T-Orbit backend sync.
- AI transcription, summaries, or tagging.
- Telegram integration.
- Windows support.
- Encryption.
- Retention or autodelete.

## Constraints

- Use Swift and SwiftUI for the desktop client.
- Use AVFoundation and ScreenCaptureKit for native capture work.
- Use SQLite for local structured state when needed.
- Do not use Electron.
- Do not add heavy dependencies for MVP.
- Do not fake audio capture in tests or prototypes.

## Validation

When implementation begins, validate with:

- `swift test` for Swift packages where possible.
- `xcodebuild` for the macOS app once a full Xcode install is active.
