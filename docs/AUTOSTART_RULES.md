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

- `source.app`
- `source.bundle_id`
- `source.trigger`
- `source.rule_id`

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

## Auto-Start Engine V1

V1 starts only when all required guards pass:

```text
IF active_app in call_whitelist
AND microphone_active
AND (system_audio_active OR active_app_is_known_call_app)
AND not_blacklisted
AND not_already_recording
AND cooldown_passed
AND min_detection_duration_passed
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

Known direct call apps for the `active_app_is_known_call_app` shortcut:

- Zoom
- Telegram
- Discord

Browsers do not use the shortcut. Browser autostart requires active browser, microphone activity, and system audio activity. V1 does not inspect browser URLs and does not require a browser extension.

## Settings

MVP settings:

- auto-start enabled or disabled
- whitelist entries, matched against app name or bundle id
- blacklist entries, matched against app name or bundle id
- cooldown after stop, default 180 seconds
- minimum detection duration, clamped to 15-30 seconds
- short-recording threshold, default 60 seconds and clamped to 15-300 seconds

Changing whitelist, blacklist, cooldown, detection duration, or short-recording threshold resets the current detection candidate.

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
- session id, when a session was created

V1 logs both start and non-start decisions. Repeated identical non-start decisions may be de-duplicated in the UI layer to avoid log spam.

## Known False Positive Cases

- A whitelisted direct call app is foreground and has microphone activity, but the user is not in a real call.
- A browser is foreground while another tab or app creates microphone and system audio activity.
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
