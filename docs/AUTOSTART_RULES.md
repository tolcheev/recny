# Autostart Rules

## MVP Intent

The app should start recording automatically when local rules indicate a call is active.

## Rule Design

Autostart rules must be local-only in MVP. They must not depend on cloud services, T-Orbit backend state, AI classification, or Telegram integration.

## Guardrails

- Never start recording without required macOS permissions.
- Log why a recording started.
- Log why a recording did not start when a rule matched but capture was blocked.
- Keep rules deterministic and testable.

## Initial Rule Candidates

- Active supported conferencing app.
- Audio route or system audio activity.
- Explicit local user setting for enabled apps.

Specific app detection behavior should be documented before implementation.
