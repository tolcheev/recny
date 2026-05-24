# Autostart Rules

## Goal

The MVP should start recording automatically when local evidence indicates that Vlad is in a call worth recording.

Autostart is local-only. It must not depend on cloud services, AI classification, T-Orbit backend state, or external meeting bots.

## MVP Rule Inputs

Allowed local inputs:

- Foreground active app.
- Source app bundle id.
- User-enabled app allowlist and blocklist.
- Microphone activity signal.
- System audio activity signal.
- Manual local override.

The exact implementation can evolve, but every start must be explainable through metadata fields:

- `source.app_name`
- `source.bundle_id`
- `source.trigger`
- `source.rule_id`
- `source.confidence`
- `source.reason`

## Initial Trigger Types

Suggested `trigger` values:

- `app_active`
- `audio_activity`
- `manual`
- `debug`

Suggested MVP rule examples:

- Start when an enabled conferencing app becomes active and audio activity is detected.
- Start when a user manually enables recording from the menu bar app.
- Ignore apps that are not in the local allowlist.

## Auto-Start Engine V2

V2 starts only when all required guards pass:

```text
IF active_app in call_whitelist
AND microphone_active
AND not_blacklisted
AND not_already_recording
AND cooldown_passed
AND min_detection_duration_passed
AND app_specific_call_signal_passed
THEN start_recording()
```

Default call whitelist:

- Zoom
- Google Chrome
- Safari
- Firefox
- Yandex Browser
- Microsoft Edge
- Telegram
- Discord

Auto-start modes:

- `Off`: never start automatically.
- `Ask first`: detect the call signal and notify, but do not start until the user starts recording.
- `Auto`: start recording after the signal is stable.

Default dev/MVP mode is `Auto`.

Known direct call apps can start confidently from active app + microphone activity:

- Zoom
- Telegram
- Discord

Browser heuristic v2:

- Browser + system audio alone is never enough.
- Browser detection requires microphone activity for the configured detection duration.
- If an active browser window title is available, the title must look call-like.
- Call-like title tokens include `Meet`, `Zoom`, `Teams`, `KTalk`, `МТС Линк`, `SberJazz`, `Встреча`, `Собеседование`, `Interview`, and `Call`.
- If the active window title is unavailable, the MVP falls back to browser + microphone activity + system audio activity with `medium` confidence.
- Browser URL detection and browser extensions are not part of MVP.

Rule ids:

- `autostart.v2.zoom`
- `autostart.v2.known_call_app`
- `autostart.v2.browser_title`
- `autostart.v2.browser_fallback`
- `autostart.v2.generic_whitelist`

## Settings

MVP settings:

- auto-start mode: Off, Ask first, or Auto
- whitelist entries, matched against app name or bundle id
- blacklist entries, matched against app name or bundle id
- cooldown after stop, default 180 seconds
- minimum detection duration, clamped to 15-30 seconds
- short-recording threshold, default 60 seconds and clamped to 15-300 seconds
- optional blacklist hints for music/video players such as Music, Spotify, VLC, QuickTime Player, and TV

Changing whitelist, blacklist, cooldown, detection duration, or short-recording threshold resets the current detection candidate.

Browsers are not blocked globally. A YouTube-only browser false positive cannot be perfectly detected without a browser extension, so V2 relies on microphone activity plus active window title when available.

## Recording Categories

The autostart rule may assign an initial category:

- `student_call`
- `lead_sales`
- `interview_review`
- `important`
- `unsorted`

Category can be refined later when tags and a local library UI exist.

## Debounce And Short Sessions

Autostart must avoid creating noisy library entries.

Rules:

- Do not start multiple sessions for the same continuous call signal.
- Keep a 3 minute default cooldown after stop before a new automatic start can occur.
- Keep the call signal stable for the configured minimum detection duration before starting.
- If a recording is below the short-session threshold, classify it under `Inbox/Short/`.
- Short sessions must still keep metadata so false positives can be debugged.
- V1 short-session threshold defaults to 60 seconds and is configurable from Settings.
- Short sessions use `status: "short_recording"` and do not open the post-call tagging panel automatically.

## Permission Guardrails

- Never mark a recording as successful if microphone capture did not start.
- Never mark system audio as successful if system capture did not start.
- If permissions are missing, write a blocked or failed status and log the reason.
- Surface blocked permissions in the app UI.

## Logging Requirements

Every autostart decision should log:

- timestamp
- rule id
- source app
- bundle id
- trigger
- decision: start, ignore, blocked, or already recording
- reason
- confidence
- microphone active state
- system audio active state
- cooldown state
- session id, when a session was created

V2 logs both start and non-start decisions. Repeated identical non-start decisions may be de-duplicated in the UI layer to avoid log spam.

## Known False Positive Cases

- A whitelisted direct call app is foreground and has microphone activity, but the user is not in a real call.
- A browser is foreground while another tab or app creates microphone and system audio activity.
- A browser call title is unavailable, forcing fallback to microphone + system audio activity.
- A non-call browser page contains words such as `Call` or `Interview` in the title.
- System audio activity can be coarse because CoreAudio reports device activity, not a semantic "call audio" classification.
- Telegram or Discord voice/video areas can trigger without enough context to know whether the conversation should be recorded.
- Quick app switches during a call can reset the minimum detection duration and delay start.

## Not In MVP

- Calendar integration.
- Cloud meeting bot detection.
- AI-based call classification.
- T-Orbit backend schedule lookup.
- Telegram integration beyond local app detection.
- Organization-wide policy rules.
