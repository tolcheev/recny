# Local Transcription and Notes Implementation Plan

> **For agentic workers:** Use subagent-driven-development for the independent model helper and reviews; integrate the Swift pipeline and interface in this session. Keep changes in the attached worktree.

**Goal:** Deliver user-triggered, offline transcription and structured, editable notes with timestamp playback and Markdown export.

**Architecture:** Preserve Parakeet recognition. A cancellable Swift process adapter runs local tools into per-job staging directories. A serial coordinator owns job state outside views. A bundled Python helper uses prepared MLX model files to generate validated, source-linked notes. SwiftUI reads committed artifacts and preserves edits across regeneration.

**Tech Stack:** Swift 6, SwiftUI, AVFoundation, Python 3.11+, parakeet-mlx, mlx-lm, Qwen3 4B Instruct (4-bit).

## Task 1: Baseline and helper contract
- [x] Run `swift test --package-path apps/macos` and retain the baseline result.
- [x] Add `Resources/recny_local_notes.py` and Python unittest coverage for bounded token chunks, strict JSON parsing, invalid references, offline setup detection, and bounded reduction.
- [x] CLI contract: `status --model-dir DIR`, `prepare --model-dir DIR`, `analyze --model-dir DIR --input FILE --output FILE`. Preparation writes a revision-pinned manifest. Analysis never downloads.
- [x] Input: `{ "segments": [{ "id": "s1", "text": "...", "start": 0, "end": 3 }], "preset": "meeting" }`. Output: `{ "schemaVersion": 1, "model": "...", "revision": "...", "promptVersion": 1, "sections": [{ "title": "...", "items": [{ "text": "...", "sourceIDs": ["s1"] }] }] }`.
- [x] Keep dependency installation separate from model preparation; no daemon, no transcripts in command arguments or diagnostic output.

## Task 2: Swift artifacts and process lifecycle
- [x] Add `LocalRecordingDocuments.swift`: normalized timestamp segments, source fingerprints, notes schema, legacy text/SRT import, safe storage and edit history.
- [x] Tests: malformed timestamps and source IDs rejected; plain text has no invented timing; source changes invalidate reuse; regenerated notes preserve edited history; failed staging does not replace valid output.
- [x] Add `LocalToolProcess.swift`: bounded diagnostics, asynchronous process execution, cancellation and timeout, no pipe deadlock. Test a helper producing more than a pipe buffer and cancellation of a running process.
- [x] Add a resource declaration in Package.swift so release packaging contains the helper.

## Task 3: Local processing service and serial coordinator
- [x] Add `LocalRecordingProcessor.swift`: reuse valid transcripts, run Parakeet offline into staging, normalize SRT, run notes helper, validate and atomically publish results.
- [x] Add `LocalProcessingCoordinator.swift`: queued/transcribing/analyzing/completed/failed/cancelled/interrupted state, duplicate protection, retry, cancellation, persisted stage.
- [x] Tests use injected processors to prove serialization, duplicate rejection, cancellation and restart handling. Real AI validation remains separate.
- [x] Setup UI detects helper runtime, missing dependencies and incomplete models. Explicit preparation downloads only models.

## Task 4: Recording interface
- [x] Add `RecordingDocumentsView.swift` with Transcript/Notes tabs, search, source timestamp links, editable notes, save/copy/export, preset picker, stage status and cancel/retry controls.
- [x] Replace LibraryView's view-local transcription task with the shared coordinator and open the document view without Finder activation.
- [x] Reuse the audio playback model for timestamp seek; never autoplay on opening a document.
- [x] Confirm dirty-note handling before navigation/regeneration, and prevent recording deletion while processing.

## Task 5: Validation and delivery
- [x] Run Python unittests, Swift tests and release build; fix regressions.
- [x] Prepare compatible local dependencies and models after checking disk space. Run a Russian factual fixture and a long fixture; inspect unsupported claims, token coverage, runtime and memory. Run prepared inference with network disabled.
- [x] Run actual Parakeet on available Russian audio locally and verify persisted segments/notes. Do not publish personal fixture content.
- [x] Review spec compliance and code quality, resolve actionable findings.
- [x] Update README, macOS setup and privacy documentation with actual supported behavior and limitations. Mark spec implemented only after checks pass.
Delivery: commit only scoped files and push `codex/local-transcription-notes` to the verified `origin`. Do not merge, release, or publish recordings.
