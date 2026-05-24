# Screen Recording Technical Design

## Status

Future design only. Screen recording is not part of the macOS audio-only local MVP.

The current MVP records microphone audio, system audio, mixed audio preview, metadata, tags, markers, and local library data. It does not record the screen.

## Goals

Future screen recording should support mentor workflows where audio alone is not enough:

- live coding
- resume review
- project review
- student showing a solution
- conflict-sensitive or important calls where visual context matters

The feature must remain explicit, privacy-aware, and separate from the default audio-only flow.

## Non-Goals

- Do not enable screen recording in MVP.
- Do not start screen recording automatically by default.
- Do not upload screen video to T-Orbit.
- Do not treat screen video as required for normal audio recording.
- Do not implement selected window capture in the first screen recording step if it complicates reliability.

## Recording Modes

### Audio Only, Default

Default mode remains audio-only:

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

This is the safest daily mode for calls. It has lower storage cost, lower privacy risk, and lower CPU/GPU load.

### Screen + Audio, Manual

Future manual mode records screen video plus microphone/system audio.

Expected output:

```text
source/mic.m4a
source/system.m4a
source/screen.mp4
export/mixed.m4a
export/compact.mp4
preview/thumb.jpg
metadata.json
```

This mode should require an explicit toggle before recording starts. The user must understand that the screen will be captured and larger files will be created.

### Selected Window + Audio, Future

Selected window capture can reduce privacy risk and file size by recording only a chosen app/window.

This should be a later phase because it needs:

- window picker UX
- handling window close/minimize/move cases
- clear preview of what will be captured
- edge case behavior for browser tabs, popups, and app switching

## macOS API

### ScreenCaptureKit

Future implementation should use ScreenCaptureKit for native macOS screen capture.

ScreenCaptureKit can provide:

- display capture
- window capture
- system audio capture
- frame filtering
- capture configuration

The current MVP already uses ScreenCaptureKit for system audio capture, but deliberately does not persist screen video.

### Permissions

macOS requires Screen & System Audio Recording permission for screen/system capture.

Expected permission UX:

- explain why permission is needed
- show current permission status
- open System Settings
- detect restart-required cases
- do not start capture if permission is missing

Screen recording mode should require an explicit permission check before enabling the toggle.

### Limitations

Known macOS/ScreenCaptureKit limitations to account for:

- permission changes often require app restart
- some protected video content may be blank or blocked
- capture can fail when no display/window is available
- high resolution capture can increase CPU/GPU usage
- frame delivery may pause or degrade under system load
- selected window capture can break if the window closes
- capture behavior may differ by macOS version

If the API cannot safely capture screen video, the app must show a clear error and keep audio recording behavior intact.

## Output Files

Screen recording mode adds video outputs under the session folder.

```text
source/
  screen.mp4
export/
  compact.mp4
preview/
  thumb.jpg
metadata.json
```

### `source/screen.mp4`

Primary captured screen video.

Expected container/codec:

- MP4
- H.264 or HEVC depending on compatibility decision
- includes no audio track by default, unless the export strategy requires muxing

Audio remains separately captured as:

- `source/mic.m4a`
- `source/system.m4a`

### `export/compact.mp4`

Smaller preview/export file for quick review or future external upload.

Possible contents:

- video track from screen capture
- mixed audio track
- lower resolution and bitrate than source

### `preview/thumb.jpg`

Thumbnail for Library UI.

Rules:

- generated after stop
- should avoid exposing thumbnails on main screen unless screen recording is enabled
- should be treated as sensitive because it may contain private screen content

## Quality Presets

### Compact

Target:

- 720p
- 10-15 fps
- low bitrate

Use cases:

- long mentoring sessions
- resume/project review where smooth motion is not critical
- lower disk usage
- easier future upload

### Standard

Target:

- 1080p
- 15 fps
- moderate bitrate

Use cases:

- live coding
- UI/project review
- normal screen recording quality

### High, Later

High quality should be a later option because it can create very large files and increase system load.

Possible target:

- native display or 1440p+
- 30 fps
- higher bitrate

This should show a stronger storage and performance warning.

## UX

### Manual Toggle Before Recording

Screen recording should be enabled before Start Recording:

```text
Recording mode:
(*) Audio only
( ) Screen + audio
```

The toggle should not appear as a hidden side effect of auto-start.

### Warning Copy

When enabling screen mode:

```text
Screen recording can capture sensitive information and creates large files.
```

For high quality:

```text
High quality screen recording can use significant disk space and system resources.
```

### No Auto Screen Recording by Default

Auto-start should remain audio-only by default.

Future auto screen recording, if ever added, must require a separate explicit setting and a clear recording indicator. It should not be enabled by default.

### Recording Indicator

When screen recording is active, the app should show:

- menu bar recording state
- main window recording state
- screen recording label
- selected display/window if applicable

### Library UX

Library details can show:

- screen recording available
- thumbnail
- `screen.mp4` size
- `compact.mp4` size
- Play compact video
- Open folder

Main recorder UI should stay compact and not become a video editor.

## Storage Risks

### Bigger Files

Screen video can be much larger than audio.

Example risks:

- long calls can produce multi-GB files
- high quality presets can exhaust disk space
- thumbnails/previews add extra files
- external upload becomes more expensive

### Disk Usage

Before starting screen recording, preflight should check more free disk than audio-only mode.

Possible thresholds:

- audio-only: at least 2 GB free
- compact screen: at least 10 GB free
- standard screen: at least 20 GB free
- high screen: later, stronger warning and higher threshold

Exact thresholds should be tuned after real test recordings.

### External Storage Later

Screen files should eventually be uploaded to external storage, not T-Orbit.

T-Orbit should store:

- file links
- size
- duration
- thumbnail link if allowed
- permissions
- audit log

Raw screen files stay local or external. They are not stored in the T-Orbit app database.

## Privacy

Screen recording is more sensitive than audio recording.

Potential sensitive content:

- private messages
- credentials
- student data
- lead/customer data
- browser tabs
- notifications
- payment details
- internal docs

Rules:

- explicit user action required
- no auto screen recording by default
- show clear indicator
- allow audio-only mode at all times
- do not show thumbnails in contexts where they can leak information
- do not upload video without explicit user action or configured sync policy

## Metadata Extension

Future metadata can include video tracks:

```json
{
  "recording_mode": "screen_audio",
  "video_tracks": [
    {
      "kind": "screen",
      "relative_path": "source/screen.mp4",
      "codec": "h264",
      "container": "mp4",
      "width": 1920,
      "height": 1080,
      "fps": 15,
      "duration_sec": 2538,
      "file_size_bytes": 1800000000,
      "status": "completed"
    },
    {
      "kind": "compact",
      "relative_path": "export/compact.mp4",
      "codec": "h264",
      "container": "mp4",
      "width": 1280,
      "height": 720,
      "fps": 15,
      "duration_sec": 2538,
      "file_size_bytes": 420000000,
      "status": "completed"
    }
  ],
  "preview": {
    "thumbnail_path": "preview/thumb.jpg"
  }
}
```

This should be additive and backward-compatible with audio-only metadata.

## Implementation Phases

### Phase 1: Manual Screen + Audio

- manual mode toggle
- permission preflight
- capture full display
- write `source/screen.mp4`
- generate `preview/thumb.jpg`
- keep audio pipeline unchanged

### Phase 2: Compact Export

- create `export/compact.mp4`
- mux mixed audio with compact video
- add Library playback action
- add file size/duration metadata

### Phase 3: Selected Window

- selected window picker
- window preview
- selected window + audio capture
- handle window disappearance

### Phase 4: External Storage

- upload screen files to external storage
- attach storage links to T-Orbit
- permissioned/revocable links
- upload progress and retry

## Open Questions

- Should `source/screen.mp4` include audio, or should audio remain separate until export?
- Should compact export use H.264 for compatibility or HEVC for smaller files?
- What disk-space threshold is acceptable for standard mode?
- Should thumbnails be generated automatically or only after user opens Library?
- Should screen recording be blocked when Focus Mode reminder is enabled?
- Which display should be captured by default on multi-monitor setups?
