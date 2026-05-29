# Autostart Rules

## Goal

The MVP should start recording automatically when local evidence indicates that Vlad is in a call worth recording.

Autostart is local-only. It must not depend on cloud services, AI classification, T-Orbit backend state, or external meeting bots.

## MVP Rule Inputs

Allowed local inputs:

- Foreground active app.
- Running app list for known call apps.
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
AND not_blacklisted
AND not_already_recording
AND cooldown_passed
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

Known direct call apps can start confidently from active app + call audio activity:

- Zoom
- Telegram
- Discord

For Zoom, the MVP accepts:

- microphone activity, with the configured minimum detection duration
- for Zoom only: Core Audio process activity from the Zoom process, immediately
- for Zoom only: global system audio activity, immediately, only when per-process audio activity is unavailable

For non-Zoom known call apps such as Telegram and Discord, the MVP requires both microphone activity and system audio activity for the configured minimum detection duration. Microphone-only activity is ignored because it can be a stale mic session, voice message, input-monitoring state, or background app behavior rather than a real call.

The Zoom process-audio path uses Core Audio process objects (`kAudioProcessPropertyIsRunningInput` / `kAudioProcessPropertyIsRunningOutput`) for `us.zoom.xos`. This is the preferred MVP signal because it means Zoom itself is using audio, not merely open. The older global system-audio path remains only as a fallback when macOS does not expose the process list. Browser, Telegram, and Discord rules remain stricter.

Zoom can also start or continue after the user switches to another window. The engine checks both the foreground app and running Zoom processes:

- If Zoom is running in the background and the Zoom process has active input or output audio, the app can start immediately with `autostart.v2.zoom_process_audio`.
- If per-process audio activity is unavailable and Zoom is running in the background with both microphone and system-audio activity, the app can start immediately with `autostart.v2.zoom`.
- This high-confidence Zoom signal can bypass the normal post-stop cooldown so a real call is not missed after a short manual test recording.
- If Zoom was recently foregrounded and Zoom process audio activity appears within the continuation window, the app can still start with `autostart.v2.zoom_process_audio` even while another app is frontmost.

This matches real call behavior where the user opens Zoom, joins a call, and then works in a browser, IDE, notes, or slides.

Browser heuristic v2:

- Browser + system audio alone is never enough.
- Browser detection requires microphone activity for the configured detection duration.
- Browser detection requires an active window title that looks call-like.
- Call-like title tokens include `Meet`, `Zoom`, `Teams`, `KTalk`, `МТС Линк`, `SberJazz`, `Встреча`, `Собеседование`, `Interview`, and `Call`.
- Single-word title tokens match on word boundaries, so unrelated words like `Callback` do not count as `Call`.
- If the active window title is unavailable or does not look call-like, the browser auto-start signal is ignored even when microphone and system audio are active.
- Browser URL detection and browser extensions are not part of MVP.

Rule ids:

- `autostart.v2.zoom_process_audio`
- `autostart.v2.zoom`
- `autostart.v2.known_call_app`
- `autostart.v2.browser_title`
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

Browsers are not blocked globally, but silent browser auto-start requires a call-like active window title. Without a title, the app ignores the browser signal instead of guessing from microphone and system audio alone.

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
- Zoom process audio activity can bypass cooldown because it is treated as a high-confidence active call.
- Zoom with simultaneous microphone and system-audio activity can bypass cooldown only when per-process audio activity is unavailable.
- Keep the call signal stable for the configured minimum detection duration before starting.
- Zoom process audio activity can bypass the minimum detection duration because it is a high-confidence call surface.
- Zoom with global system audio activity can bypass the minimum detection duration only when per-process audio activity is unavailable.
- If a recording is below the short-session threshold, classify it under `Inbox/Short/`.
- Short sessions must still keep metadata so false positives can be debugged.
- V1 short-session threshold defaults to 60 seconds and is configurable from Settings.
- Short sessions use `status: "short_recording"` and do not open the post-call tagging panel automatically.

## Auto-Stop

Auto-started recordings also need a clear stop rule. A Zoom call often remains in the background while the user switches between browser, IDE, notes, and slides, so foreground app loss alone must not stop recording.

MVP stop rule:

```text
IF recording was started by autostart
AND call signal is no longer present
AND signal has been lost for the configured grace period
THEN stop_recording()
```

Rules:

- Manual recordings never auto-stop.
- App focus changes do not stop an auto-started recording.
- Zoom recordings inspect running Zoom window titles when macOS exposes them. A meeting/conference-like Zoom window keeps the recording active even if another app is foreground.
- Zoom process audio activity keeps the recording active even when the Zoom window is in the background or titles are hidden.
- If Zoom is still running but only the main `zoom Workplace`/home window is visible and Zoom process audio is idle, the call signal is treated as ended.
- If Zoom window titles are unavailable and per-process audio activity is unavailable, the app falls back to global system-audio activity only. Microphone activity is ignored in that fallback path because the recorder can keep input devices marked as running.
- The default auto-stop grace period is 10 seconds, and auto-start monitoring polls once per second so stop timing stays close to that target.
- After auto-stop succeeds, the normal cooldown applies before another automatic start.
- The app logs when signal loss starts, when signal is restored, and when auto-stop runs.

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
- Zoom process audio state when evaluating Zoom auto-stop
- cooldown state
- session id, when a session was created

V2 logs both start and non-start decisions. Repeated identical non-start decisions may be de-duplicated in the UI layer to avoid log spam.

## Known False Positive Cases

- A whitelisted non-Zoom direct call app is foreground and has both microphone and system audio activity, but the user is not in a real call.
- Zoom remains open after a call and macOS exposes neither window titles nor process audio activity; the app falls back to coarse global system-audio activity.
- A browser is foreground while another tab or app creates microphone and system audio activity; this is ignored unless the active title looks call-like.
- A real browser call title is unavailable, so the app may miss that browser call instead of recording a false positive.
- A non-call browser page contains words such as `Call` or `Interview` in the title.
- Global system audio activity can be coarse because CoreAudio reports device activity, not a semantic "call audio" classification.
- Telegram or Discord voice/video areas can trigger only when both microphone and system audio are active; without a direct meeting API this can still be ambiguous.
- Quick app switches during a browser call can reset the minimum detection duration and delay start.

## Not In MVP

- Calendar integration.
- Cloud meeting bot detection.
- AI-based call classification.
- T-Orbit backend schedule lookup.
- Telegram integration beyond local app detection.
- Organization-wide policy rules.
