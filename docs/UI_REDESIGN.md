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
- Tag Dialog: optional title, optional participant, quick tags, custom tags, status, Save/Cancel

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

UI v3 keeps the main window as a compact recorder surface instead of a library dashboard:

- Header: `TOrbit Recorder`, compact auto-start badge, and a small Ready/Recording/Error status dot
- Center recording area: the only primary daily action, either `Start Recording` or `Stop Recording`
- Latest strip: one compact row for the last recording only, with Play/Open/Tag
- Footer: Library, Settings, and Diagnostics entry points

The main screen no longer shows file sizes, folder names, raw metadata, recoverable sessions, filters, or a recording list. Those details remain in Library and Diagnostics.

Microphone selection stays visible without exposing device internals: the main screen shows the selected input name and only shows a warning when Bluetooth fallback is actually used.

### Idle

The center recording area shows:

- one primary `Start Recording` button
- selected microphone input
- system audio readiness
- auto-start state

If required permissions are missing, Start is replaced with `Fix Permissions`.

### Recording

The center recording area switches to:

- large timer
- one primary `Stop Recording` button
- `Recording mic + system audio`
- subtle copy that all system audio is being recorded

### Error

The error state avoids stack traces on the main screen. It shows:

- `Recording failed`
- short human-readable reason when known
- `Open Diagnostics`
- `Try Again`

Detailed error text remains in Diagnostics.

### Latest Strip

The latest recording is intentionally compressed into one row:

- `Last: Saved · 01:12 · Mic + system`
- Play
- Open
- Tag

Short recordings use human copy such as `Short recording`; they are not presented as failures.

## Library Behavior

Library is a separate window opened from the main footer or menu bar. It defaults to recent recordings and includes:

- search by title, participant, tags, and source app
- collapsed filters for status, date range, source app, and tags
- recording rows with title, started time, duration, source app, audio summary, human status badge, and compact tags
- compact row actions: Play, Open, and an icon-only More menu
- a details panel for the selected recording with files, metadata summary, tags, and actions
- an `Open Library Folder` action for jumping to local storage
- More actions: Tag and Delete Local Recording

Title, participant, and tags are edited through the Tag dialog instead of inline fields.

## Tag Dialog Behavior

The Tag dialog opens from the main Latest strip or from a Library row/details action. It includes:

- optional title
- optional participant
- quick tag chips for the MVP review tags
- custom tags input with normalization to `#tag`
- status choices: `Saved`, `Needs review`, and `Reviewed`

Keyboard behavior:

- Enter saves from text fields.
- Cmd+Enter saves.
- Escape closes without saving.

Tags are persisted to both `metadata.json` and the local SQLite index.

## Diagnostics Behavior

Diagnostics is separate from daily use. It includes:

- microphone permission
- Screen & System Audio Recording permission
- output folder writable status
- selected input device
- recommended input device
- microphone selection reason
- available input devices
- Bluetooth headset microphone warning when relevant
- last recorder error
- recoverable recordings with recovery/open actions
- clear empty recoverables
- local file log viewer showing the last 100 `app.log` lines
- copy logs, open logs folder, and clear logs actions
- 10 second test recording
- Screen & System Audio Recording guidance for the macOS case where permission is enabled but the current app bundle still needs restart or re-approval
- collapsed raw recorder errors so the default view stays readable

Recoverable recordings are never shown on the main screen.

Diagnostics reads local logs from `~/Recordings/TOrbitRecorder/logs/app.log`. The app rotates that file to `app.1.log` when it reaches the local size limit, so the viewer combines the archive and active log before showing the latest lines.

## Design System

The SwiftUI UI now uses small reusable components:

- `RecorderCard` for subtle macOS cards
- `StatusBadge` for human-readable state
- `PrimaryRecordingButton` for the single Start/Stop action
- `LatestRecordingStrip` for the compact last-recording row
- `RecordingDisplayFormatter` for shared UI copy and formatting

The design keeps native macOS styling, supports light/dark mode through system colors, and avoids heavy visual dependencies.

## Known Limitations

- No screenshot automation is currently wired for the native macOS window.
- Settings still contain disabled placeholders for hotkeys because runtime hotkey capture is not implemented in MVP.
- Library has local search and collapsed filters; advanced saved views are out of scope.
- Diagnostics test recording requires local macOS microphone and Screen & System Audio Recording permissions.
- macOS may require quitting and reopening the exact app bundle after enabling Screen & System Audio Recording permission, especially when switching between `.build`, `dist`, and `/Applications` builds.
- `Show Dock icon` defaults on for MVP. Turning it off switches the app to menu-bar-only accessory behavior; use the menu bar icon to bring windows back.
