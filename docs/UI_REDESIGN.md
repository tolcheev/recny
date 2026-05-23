# UI Redesign

## Before Problems

The early MVP UI exposed too much implementation detail:

- recorder state, library filtering, tag controls, and recovery information competed on the main screen
- raw statuses such as `needs_tagging` and `short_recording` leaked into user-facing areas
- long paths and file internals made the app feel like a debug panel
- the primary Start/Stop workflow was not visually dominant
- Library and Diagnostics were not clearly separated from daily recording

## New Screen Structure

The app now uses a recorder-first information architecture:

- Main Window: daily recording surface with current status, one primary action, compact latest recording strip, and footer links
- Library Window: recent recordings, search, collapsed filters, and per-recording actions
- Settings Window: grouped recording, auto-start, storage, hotkeys, and privacy controls in a dedicated app window
- Diagnostics Window: permissions, device diagnostics, writable storage check, recoverable recordings, logs, and test recording
- Tag Dialog: optional title, optional participant, quick tags, Save/Cancel

The main window deliberately avoids database controls, raw technical status, recovery details, long paths, and permanent tag fields.

## Menu Bar Behavior

TOrbitRecorder is controlled primarily from the macOS menu bar. The menu exposes:

- Show Window
- Start Recording / Stop Recording
- Play Last Recording
- Open Last Recording Folder
- Open Library
- Settings
- Diagnostics
- Quit

`Show Window` activates the app and brings the existing main window forward instead of creating duplicate windows. Closing the main window with the red close button does not quit the app; it keeps running in the menu bar and can be reopened from `Show Window`.

The menu bar icon reflects recorder state:

- idle: neutral record icon
- recording: filled red record icon when the recording indicator is enabled
- error: orange error icon

If Quit is selected while recording is active, the app asks for confirmation before stopping the recording and quitting.

## Main Window States

### Idle

The current recording card shows:

- `Ready`
- one primary `Start Recording` button
- selected microphone input
- system audio readiness
- auto-start state

The header shows the app name and `Auto-start On` or `Auto-start Off`.

### Recording

The recording card switches to:

- `Recording`
- large timer
- one primary `Stop Recording` button
- active microphone/system audio details
- subtle copy that all system audio is being recorded

### Error

The error state avoids stack traces on the main screen. It shows:

- `Recording failed`
- short human-readable reason when known
- `Open Diagnostics`
- `Try Again`

Detailed error text remains in Diagnostics.

## Library Behavior

Library is a separate window opened from the main footer or menu bar. It defaults to recent recordings and includes:

- search by title
- collapsed filters for date, status, source app, and tags
- recording rows with title, started time, duration, source app, human status badge, and compact tags
- compact row actions: Play, Open, and an icon-only More menu
- an `Open Library Folder` action for jumping to local storage
- More actions: Tag and Delete Local Record

Title, participant, and tags are edited through the Tag dialog instead of inline fields.

## Diagnostics Behavior

Diagnostics is separate from daily use. It includes:

- microphone permission
- Screen & System Audio Recording permission
- output folder writable status
- selected input device
- available input devices
- Bluetooth headset microphone warning when relevant
- last recorder error
- recoverable recordings with recovery/open actions
- clear empty recoverables
- log folder
- 10 second test recording
- Screen & System Audio Recording guidance for the macOS case where permission is enabled but the current app bundle still needs restart or re-approval
- collapsed raw recorder errors so the default view stays readable

Recoverable recordings are never shown on the main screen.

## Design System

The SwiftUI UI now uses small reusable components:

- `RecorderCard` for subtle macOS cards
- `StatusBadge` for human-readable state
- `InfoRow` for compact metadata
- `PrimaryRecordingButton` for the single Start/Stop action
- `RecordingDisplayFormatter` for shared UI copy and formatting

The design keeps native macOS styling, supports light/dark mode through system colors, and avoids heavy visual dependencies.

## Known Limitations

- No screenshot automation is currently wired for the native macOS window.
- Settings still contain disabled placeholders for audio quality presets and hotkeys because the runtime behavior is not implemented in MVP.
- Library uses simple title search and collapsed filters; advanced saved views are out of scope.
- Diagnostics test recording requires local macOS microphone and Screen & System Audio Recording permissions.
- macOS may require quitting and reopening the exact app bundle after enabling Screen & System Audio Recording permission, especially when switching between `.build`, `dist`, and `/Applications` builds.
- `Show Dock icon` defaults on for MVP. Turning it off switches the app to menu-bar-only accessory behavior; use the menu bar icon to bring windows back.
