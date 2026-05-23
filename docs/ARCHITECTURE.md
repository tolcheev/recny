# Architecture

## Boundary

This repository contains the standalone desktop recorder client.

The T-Orbit backend is not part of this repository. MVP storage is local-first and does not sync to T-Orbit.

## Initial Layout

```text
apps/macos/        Native macOS menu bar app
packages/core/     Recording engine and domain logic
packages/protocol/ Shared recording metadata formats
docs/              Product and engineering docs
samples/scripts/   Local helper scripts and samples
tests/             Integration or fixture-oriented tests
```

## Runtime Components

- Menu bar app: owns user-facing state and app lifecycle.
- Recorder engine: owns capture sessions, file writing, mixing, and error handling.
- Storage layer: owns local directory layout and metadata persistence.
- Permission layer: checks microphone and system audio capture permissions.

## Principles

- Keep UI separate from recording mechanics.
- Prefer native macOS APIs over third-party dependencies.
- Treat permissions and API limitations as explicit product constraints.
- Keep behavior documented when it changes.
