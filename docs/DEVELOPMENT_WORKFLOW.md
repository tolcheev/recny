# Development Workflow

This repository is a standalone native macOS recorder client. After the MVP cleanup, `main` should be treated as the stable integration branch.

## Branch Naming

Use short, purpose-specific branches:

- `feature/<area>-<short-name>` for new behavior
- `fix/<area>-<short-name>` for bug fixes
- `ux/<short-name>` for UI/UX-only work
- `docs/<short-name>` for documentation-only changes
- `release/vX.Y.Z` for release preparation
- `mvp/<short-name>` only for MVP stabilization branches

Examples:

```text
feature/recording-level-meters
fix/permissions-restart-required
ux/library-empty-state
docs/qa-checklist
release/v0.1.0
```

## Commit Rules

- Keep commits small and reviewable.
- One commit should explain one product or engineering change.
- Update docs when behavior, storage, permissions, packaging, or QA flow changes.
- Do not commit generated build artifacts except explicitly tracked lightweight docs such as `dist/INSTALL.md`.
- Do not fake audio capture or mark unverified recording paths as working.
- Keep MVP scope boundaries intact unless a task explicitly changes them:
  - no automatic/cloud AI
  - no cloud upload
  - no T-Orbit sync
  - no screen recording
  - no Windows client

## Build And Test Before Push

Run the standard local checks before pushing:

```sh
swift test --package-path apps/macos
./scripts/build_macos.sh
./scripts/package_macos.sh
```

When packaging or install flow changes, also run:

```sh
DRY_RUN=1 ./scripts/install_macos.sh
```

`scripts/install_macos.sh` refuses to replace `/Applications/ToRec.app` while a running app has an active `recovery.json` with status `recording`. Stop the recording and wait for finalization before reinstalling. Use `ALLOW_INSTALL_WHILE_RECORDING=1` only for emergency debugging where losing the active recording is an explicit tradeoff.

For recorder changes, include manual validation notes from:

```text
docs/QA_CHECKLIST.md
MANUAL_TESTING.md
```

## Main Branch Policy

After the MVP stabilization work, do not push directly to `main`.

Expected flow:

1. Branch from latest `main`.
2. Implement scoped changes.
3. Run tests/build/package.
4. Push the branch.
5. Open a PR.
6. Review diff and manual QA notes.
7. Merge only after checks are green and the PR scope is understood.

Direct pushes to `main` are reserved only for emergency repository repair and should be documented afterward.

## Pull Request Checklist

Every PR should answer:

- What changed?
- What is intentionally out of scope?
- How was it tested?
- Were docs updated?
- Does it affect permissions, storage, recording, packaging, or metadata?
- Does it preserve MVP exclusions: no automatic/cloud AI, cloud upload, T-Orbit sync, screen recording, or Windows?
- Are generated artifacts excluded from the diff unless intentionally tracked?

Required local checks before requesting review:

```sh
swift test --package-path apps/macos
./scripts/build_macos.sh
./scripts/package_macos.sh
```

Recommended PR labels:

- `bug`
- `ux`
- `recording`
- `autostart`
- `packaging`
- `privacy`
- `tech-debt`

Future-scope labels:

- `ai`
- `torbit-sync`
- `windows`

## Release Branch Flow

Use a release branch when preparing a tagged build:

```sh
git switch main
git pull --ff-only
git switch -c release/v0.1.0
```

Release branch rules:

- Only release preparation, docs, versioning, packaging, and critical release fixes.
- No unrelated feature work.
- Run full checks:

```sh
swift test --package-path apps/macos
./scripts/build_macos.sh
./scripts/package_macos.sh
DRY_RUN=1 ./scripts/install_macos.sh
```

- Confirm `dist/ToRec-vX.Y.Z-macOS.zip` exists.
- Create a draft GitHub release first.
- Publish only after manual QA passes on a real Mac.

After release:

1. Merge the release branch through PR.
2. Tag the release commit.
3. Keep the release notes linked to the artifact and manual QA result.

## Current MVP Cleanup Guidance

If an existing PR duplicates `main`, close it as a duplicate only after confirming the file diff is empty.

If a branch contains real changes not in `main`, keep the PR open, run checks, and merge through review.

If history is hard to review because equivalent commits exist under different hashes, create a clean branch from `main`, cherry-pick only the needed commits, and open a replacement PR.
