# Screen Recording

## Status

Future design only. Screen recording is not part of the macOS audio-only MVP.

The MVP records microphone, system audio, mixed previews, metadata, tags, markers, and local library data only.

## Goal

Add optional visual context for calls where audio is not enough:

- live coding
- resume review
- project review
- student solution review
- important/conflict-sensitive calls

## Modes

### Audio Only

Default mode. Current MVP behavior.

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

### Screen + Audio

Future manual mode only.

```text
source/screen.mp4
source/mic.m4a
source/system.m4a
export/mixed.m4a
export/compact.mp4
preview/thumb.jpg
metadata.json
```

### Selected Window + Audio

Future phase after full-screen capture is reliable.

## macOS API

Use ScreenCaptureKit.

The app already uses ScreenCaptureKit for system audio capture. Future screen recording should extend that pipeline without making screen capture required for audio-only recording.

## UX Rules

- Screen recording is manual only.
- No auto screen recording by default.
- User must choose screen mode before Start.
- Show clear warning before recording:
  - screen may contain sensitive information
  - files will be much larger
  - storage usage may grow quickly
- Keep audio-only as the default daily mode.

## Quality Presets

- Compact: 720p, 10-15 fps.
- Standard: 1080p, 15 fps.
- High: later, with stronger storage/performance warning.

## Storage Risks

Screen video creates larger files than audio.

Future work needs:

- disk space preflight
- file size estimates
- storage cleanup UX
- external storage upload later

## Privacy

- Explicit user action required.
- Show recording indicator.
- Thumbnail is sensitive.
- Do not upload screen video to T-Orbit.
- Heavy files stay local or in external storage.

## Failure Handling

If screen capture fails:

- show clear error
- preserve audio recording if it already started and partial mode is allowed
- never silently fake video capture
