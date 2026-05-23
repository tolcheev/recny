# Autostart Rules

## Goal

The MVP should start recording automatically when local evidence indicates that Vlad is in a call worth recording.

Autostart is local-only. It must not depend on cloud services, AI classification, T-Orbit backend state, or external meeting bots.

## MVP Rule Inputs

Allowed local inputs:

- Foreground or running source app.
- Source app bundle id.
- User-enabled app allowlist.
- Audio activity signal where available.
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
- Keep a cooldown after stop before a new automatic start can occur.
- If a recording is below the short-session threshold, classify it under `Inbox/Short/`.
- Short sessions must still keep metadata so false positives can be debugged.

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

## Not In MVP

- Calendar integration.
- Cloud meeting bot detection.
- AI-based call classification.
- T-Orbit backend schedule lookup.
- Telegram integration.
- Organization-wide policy rules.
