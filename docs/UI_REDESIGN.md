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

- Main Window: daily recording surface with current status, one primary action, post-stop summary actions, and footer links
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
- Open Library
- Open Records
- Settings
- Diagnostics
- Quit

`Show Window` activates the app and brings the existing main window forward instead of creating duplicate windows. Closing the main window with the red close button does not quit the app; it keeps running in the menu bar and can be reopened from `Show Window`.

The menu bar item is a compact text-free play icon that can be hidden with Hidden Bar or similar menu bar utilities. On first launch, T-Orbit Recorder writes a default saved status-item position so Hidden Bar does not immediately place the new item in its hidden section. The idle and error states use an outline play icon. If microphone or system-audio recording permission is missing, idle/error uses a large red question mark and a red `Recording Blocked: Fix Permissions` menu item. When `Show recording indicator` is enabled, the recording state uses a filled play icon. Recorder state is also exposed through the menu tooltip and the main app windows.

T-Orbit Recorder does not request macOS Notifications permission. Auto-start, screenshot, and recorder lifecycle feedback stay in the app UI and local logs so first launch only asks for recording-related permissions.

If Quit is selected while recording is active, the app asks for confirmation before stopping the recording and quitting.

`Open Library` opens the user-facing `Library/` folder in Finder. `Open Records` opens the in-app searchable records list. The storage root still contains internal folders such as `Inbox`, `db`, and `logs`, but those are not the default Finder destination for normal use.

App-active keyboard shortcuts mirror the primary menu actions:

- `Cmd+Shift+R`: Start/Stop Recording
- `Cmd+Shift+O`: Open Library
- `Cmd+Shift+L`: Open Records
- `Cmd+Shift+D`: Open Diagnostics
- `Cmd+Shift+S`: Capture Full Screenshot

Global shortcuts:

- `Ctrl+Option+R`: Show Window
- `Ctrl+Option+S`: Capture Full Screenshot

The permission onboarding flow posts a Show Window request after each macOS permission prompt so the app does not disappear behind System Settings, Zoom, or the system permission dialog after microphone/system-audio approval.

Main, Records, Settings, Diagnostics, and Player windows are centered inside the current screen's visible frame every time they are shown. This avoids stale window positions reopening partially off-screen or under the Dock/menu bar. `Cmd+,`, the app menu Settings command, menu bar Settings, and the main window Settings button all route through the same controlled Settings window instead of creating a separate SwiftUI Settings scene.

Marker shortcuts are hidden from the default UI until the marker workflow is useful enough for daily use.

Auto-started recordings use an auto-stop guard. Zoom recordings prefer Core Audio process activity from `us.zoom.xos`: active Zoom input/output keeps recording alive even when Zoom is in the background. A meeting/conference window also keeps recording active when macOS exposes titles. If titles and per-process audio are unavailable, the app falls back to global system-audio activity and ignores microphone activity for auto-stop. The default auto-stop grace period is 10 seconds, with one-second monitoring polls to keep the visible behavior close to 10 seconds. Manual recordings never auto-stop.

## Main Window States

UI v3 keeps the main window as a compact recorder surface instead of a library dashboard:

- Header: compact auto-start badge and a small Ready/Recording/Error status dot; the app name stays in the window title/menu bar
- Center recording area: the only primary daily action, either `Start Recording` or `Stop Recording`
- Footer: Records, Library, Settings, and Diagnostics entry points

The main screen no longer shows file sizes, folder names, raw metadata, recoverable sessions, filters, or a recording list. Those details remain in Library and Diagnostics.

Microphone selection stays visible without exposing device internals: the main screen shows the selected input name, and AirPods/Bluetooth headset microphones are shown as blocked rather than as recording fallbacks.

### Idle

The center recording area shows:

- one primary `Start Recording` button
- selected microphone input
- system audio readiness
- auto-start state

If required permissions are missing, Start is replaced with `Fix Permissions`, the header status becomes `Blocked`, and a red `Recording is blocked` panel explains that calls will not be recorded until access is fixed. The menu-bar icon switches to a large red question mark, the menu-bar recording action becomes `Fix Recording Permissions`, and launch brings the main window forward so the blocked state is not missed before a call.

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

### Post-stop Summary

After Stop, the main screen shows a compact post-stop summary with status, duration/audio summary, and Play, Tag, and Show actions. Full history, search, playback details, notes, tags, and file actions live in the separate Library window.

## Library Behavior

Library is a separate window opened from the main footer or menu bar. It defaults to all local recordings known from disk and includes:

- search by title, participant, tags, and source app
- collapsed filters for status, date range, source app, tags, and audio health
- recording rows with title, started time, duration, source app, audio summary, audio health badge, human status badge, and compact tags
- compact row actions: Play, Open, and an icon-only More menu
- Play expands an inline mini-player inside the selected recording row instead of opening a separate playback window
- a details panel for the selected recording with primary actions directly under the title, followed by files, audio analysis summary, metadata summary, tags, and markers
- an `Open Library Folder` action for jumping to local storage
- More actions: Share Audio, Copy Audio Path, Trim Audio, Capture Full Screenshot, Transcribe Locally, Edit Note / Tags, Reprocess Audio, Reveal Audio Analysis, and Delete Local Recording

Records refresh synchronizes the local SQLite index with `metadata.json` files under `Library/` and `Inbox/`. Folders restored or created on disk appear after refresh, and rows whose folders were deleted in Finder are removed instead of staying as broken `missing file` entries.

The details panel is vertically scrollable and groups actions into wrapping rows directly near the top so Play, Open, Edit, Share, Trim, Screenshot, Copy Path, Analysis, and Delete stay reachable without scrolling in the default Records window when possible. The details-panel Share button anchors the native macOS share sheet to the button itself, so AirDrop/Telegram/Mail choices appear beside the control the user clicked.

Sharing is implemented through the native macOS share sheet and never uploads by itself. It uses the best available local audio file in this order: `export/mixed_balanced.m4a`, `export/mixed.m4a`, `source/mic.m4a`, then `source/system.m4a`. `Copy Audio Path` copies the same preferred file path for manual Telegram, bot, messenger, or file-upload workflows.

`Trim Audio` opens a compact sheet with start/end sliders and exports a non-destructive local `export/clip_*.m4a`. The primary action is `Trim & Share`, which opens the same macOS share sheet for the created clip. `Trim Only` leaves the clip in the recording folder.

`Full Screenshot` immediately captures the full screen and saves a PNG under `screenshots/` without asking the user to select an area or window. Screenshots can be created from the main window, a Records row/details action, app-active `Cmd+Shift+S`, or global `Ctrl+Option+S` while another app is frontmost. This is a still-image workflow, not screen recording.

`Transcribe Locally` is explicit, user-triggered, and optional. Records does not launch a first-run model download. Users prepare the add-on from Settings -> Local transcription: install the local tools, run Prepare Parakeet Model once, then use Records to write `transcript/transcript.*` plus `transcript/call_note.md` inside the selected recording folder. The Markdown note includes the full transcript and a Codex review prompt for later manual analysis.

`Delete Local Recording` first closes any inline player or app player window that is playing audio from the deleted session folder, then permanently deletes the whole session folder and every file inside it after confirmation.

Title, participant, context note, and tags are edited through the Tag dialog instead of inline fields.

## Tag Dialog Behavior

The Tag dialog opens from a Records row/details action. It includes:

- optional title
- optional participant
- optional context note for company/screening/interview context
- quick tag chips for the interview-first tags: `#лид`, `#скрининг`, `#интервью`, `#важное`
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
- post-stop summary content inside `RecordingStatusCard` for immediate Play, Tag, and Show actions
- `RecordingDisplayFormatter` for shared UI copy and formatting

The design keeps native macOS styling, supports light/dark mode through system colors, and avoids heavy visual dependencies.

## Known Limitations

- Settings still contain disabled placeholders for custom hotkey capture because editable shortcut capture is not implemented in MVP.
- Library has local search and collapsed filters; advanced saved views are out of scope.
- Direct Telegram bot/API upload remains out of MVP scope. Users can share the existing audio or a trimmed clip through the OS share sheet or copy its path for manual workflows.
- Local transcription requires optional local setup. The app surfaces install hints and a Settings-only Parakeet model preparation action instead of bundling large models or downloading them from Records.
- Diagnostics test recording requires local macOS microphone and system audio permissions.
- macOS may require quitting and reopening the exact app bundle after enabling system audio permission, especially when switching between `.build`, `dist`, and `/Applications` builds.
- `Show Dock icon` defaults off for MVP. The app is menu-bar-first by default; use the menu bar icon or `Ctrl+Option+R` to bring windows back.
- `Launch at Login` defaults on so the menu bar recorder is available after macOS login. Diagnostics shows whether this is backed by `SMAppService` or the local LaunchAgent fallback used by some development/ad-hoc bundles.
