# Windows Auto-Start Design

## Context

Windows must support the main Recny promise: launch the app once, leave it in the tray, and let it record likely calls automatically. Manual recording is only a fallback.

## Behavior

- Poll Windows call signals once per second.
- Start recording after 10 seconds of stable call-like activity.
- Stop only auto-started recordings after 10 seconds without the active call/source audio session.
- Never auto-stop manual recordings.
- Store metadata trigger as `autostart`, source app, and reason. Log source process id where available.

## Signals

Use Windows audio sessions through WASAPI/NAudio:

- known desktop call apps can trigger from active audio sessions;
- browser apps require a call-like window title so YouTube/music does not start recording by itself;
- after auto-start, active recordings are held by the same source process/app audio session, not by the active window;
- Recny's own process is ignored.

Known desktop call apps:

- Zoom
- Microsoft Teams
- Telegram
- Discord
- Slack
- Skype
- Webex
- KTalk

Browser/title heuristic:

- Chrome
- Edge
- Firefox
- Brave
- Opera
- Yandex Browser
- Arc

The browser title must contain a call hint such as Meet, Google Meet, Zoom, Teams, KTalk, call, huddle, interview, Jitsi, Whereby, `собесед`, `созвон`, or `звонок`.

## Implementation

- `AutoStartDecisionEngine` is pure and tested separately.
- `WindowsCallActivityDetector` converts WASAPI audio sessions into `CallActivitySnapshot`.
- `AutoStartMonitor` runs in the Windows tray app and calls `RecordingController.StartAsync(trigger: "autostart", ...)` or `StopAsync()`.
- The tray menu shows `Auto-start: On`.

## Limits

- This is heuristic, not a Zoom/Meet API integration.
- Browser start detection depends on the active window title. Stop detection for an already active recording does not depend on the active window.
- A real Windows laptop test is still required because devices and app audio-session behavior vary.
