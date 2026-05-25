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

T-Orbit Recorder is controlled primarily from the macOS menu bar. The menu exposes:

- Show Window
- Start Recording / Stop Recording
- Play Last Recording
- Open Recordings
- Open Library
- Settings
- Diagnostics
- Quit

`Show Window` activates the app and brings the existing main window forward instead of creating duplicate windows. Closing the main window with the red close button does not quit the app; it keeps running in the menu bar and can be reopened from `Show Window`.

The menu bar icon reflects recorder state:

- idle: neutral waveform icon
- recording: filled red record icon when the recording indicator is enabled
- error: orange warning icon

If Quit is selected while recording is active, the app asks for confirmation before stopping the recording and quitting.

`Open Recordings` opens the user-facing `Library/` folder. The storage root still contains internal folders such as `Inbox`, `db`, and `logs`, but those are not the default Finder destination for normal use.

App-active keyboard shortcuts mirror the primary menu actions:

- `Option+R`: Show Window globally, including when the Dock icon is hidden
- `Cmd+Shift+R`: Start/Stop Recording
- `Cmd+Shift+O`: Open Recordings
- `Cmd+Shift+L`: Open Library
- `Cmd+Shift+D`: Open Diagnostics

Marker shortcuts are hidden from the default UI until the marker workflow is useful enough for daily use.

Auto-started recordings use an auto-stop guard: after both microphone and system-audio activity disappear for 30 seconds, the app stops the recording and saves it. Manual recordings never auto-stop.

## Main Window States

UI v3 keeps the main window as a compact recorder surface instead of a library dashboard:

- Header: compact auto-start badge and a small Ready/Recording/Error status dot; the app name stays in the window title/menu bar
- Center recording area: the only primary daily action, either `Start Recording` or `Stop Recording`
- Footer: Library, Open Recordings, Settings, and Diagnostics entry points

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

### Recent Recordings

The main screen does not show a latest recording strip. Recent recordings, playback, details, notes, tags, and file actions live in the separate Library window.

## Library Behavior

Library is a separate window opened from the main footer or menu bar. It defaults to recent recordings and includes:

- search by title, participant, tags, and source app
- collapsed filters for status, date range, source app, tags, and audio health
- recording rows with title, started time, duration, source app, audio summary, audio health badge, human status badge, and compact tags
- compact row actions: Play, Open, and an icon-only More menu
- a details panel for the selected recording with files, audio analysis summary, metadata summary, tags, markers, and actions
- an `Open Library Folder` action for jumping to local storage
- More actions: Edit Note / Tags, Reprocess Audio, Reveal Audio Analysis, and Delete Local Recording

Title, participant, context note, and tags are edited through the Tag dialog instead of inline fields.

## Tag Dialog Behavior

The Tag dialog opens from a Library row/details action. It includes:

- optional title
- optional participant
- optional context note for company/screening/interview context
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
- System audio permission
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
- System audio guidance for the macOS case where permission is enabled but the current app bundle still needs restart or re-approval
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
- Settings still contain disabled placeholders for custom hotkey capture because editable shortcut capture is not implemented in MVP.
- Library has local search and collapsed filters; advanced saved views are out of scope.
- Diagnostics test recording requires local macOS microphone and system audio permissions.
- macOS may require quitting and reopening the exact app bundle after enabling system audio permission, especially when switching between `.build`, `dist`, and `/Applications` builds.
- `Show Dock icon` defaults off for MVP. The app is menu-bar-first by default; use the menu bar icon or `Option+R` to bring windows back.
- `Launch at Login` defaults on so the menu bar recorder is available after macOS login. Diagnostics shows whether this is backed by `SMAppService` or the local LaunchAgent fallback used by some development/ad-hoc bundles.
