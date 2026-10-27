# Local transcription and structured notes

Status: implemented. See `docs/LOCAL_AI_VALIDATION.md` for measured checks and known quality limits.

## Scope and decision

The user selected local processing as the baseline on 2026-10-27. Extend the existing optional local transcription feature with readable transcripts and generated structured notes. This is an explicitly requested extension beyond the original recording-only MVP. Keep audio, transcript text, prompts, and generated notes on the Mac. Do not introduce cloud inference, uploads, accounts, or T-Orbit integration.

The current app calls user-installed `parakeet-mlx` and `ffmpeg`, requires a prepared Parakeet model, and creates transcript files plus `call_note.md`. That Markdown file currently contains a review prompt and the transcript; it is not a generated review. The current UI opens Finder after transcription.

## Runtime choice

- Keep Parakeet v3 for speech recognition. Do not replace it without a measured quality issue.
- Add `mlx-lm` as an optional local helper, consistent with the existing user-installed MLX tool approach. Launch a bounded child process for each analysis, with no HTTP server or resident daemon.
- Initial summarization candidate: `mlx-community/Qwen3-4B-Instruct-2507-4bit`. Its published model card documents MLX inference. Validate Russian meeting notes on the target Mac before calling this a supported default; do not claim measured speed or accuracy yet.
- Keep Swift/SwiftUI as the application stack. A Python helper is a deliberate first-release dependency, not part of the recording engine. Native Swift model inference can replace this adapter later without changing stored artifacts or the UI.
- Settings owns dependency checks and explicit model preparation. Show missing dependencies and download state separately. Never download a model as a side effect of analyzing a recording.
- Resolve a prepared local model directory and pin its revision in setup metadata. Inference must use local files, offline flags, and no remote-code loading. Report incomplete cache or unsupported runtime versions without a network fallback. Validate dependency compatibility with macOS 15 and the supported Python runtime before documenting installation commands.

## User experience

1. After setup, a recording offers local processing and separate actions to transcribe or regenerate notes.
2. Display Transcript and Notes in the recording detail view; finishing a job must not activate Finder.
3. Transcript supports search and playback from a segment timestamp when timestamp data exists. Plain-text transcripts remain usable without invented timestamps.
4. Notes presets: Meeting, Interview, and Mentoring. Meeting extracts topics, outcomes, decisions, actions, explicitly stated owners/deadlines, and unresolved questions. Interview groups questions, answers, and clearly labeled generated assessments. Mentoring groups discussed issues, explanations, agreements, and next actions.
5. Preserve missing information as unknown. Do not infer identities, commitments, deadlines, or motives. Distinguish suggested actions from agreed actions and generated assessments from statements in the recording.
6. Notes support editing, copying, Markdown export, and explicit regeneration without transcribing again. Keep a previous version before replacing edited notes.
7. Manual processing is the initial default. Automatic processing after recording completion is a later opt-in setting; it is not required for the first release.

## Processing and resource control

Move orchestration out of view-local tasks into a testable core coordinator. Serialize transcription and analysis so two models do not compete for memory. Reject duplicate jobs for the same recording. Show queued, transcribing, analyzing, completed, failed, and cancelled states with stage-level progress; do not invent percentages.

Use the existing playback resolver for audio selection and record the selected source identity. Reuse a transcript only when its source identity still matches. Preserve a completed transcript when analysis fails. Offer retry of the failed stage. Cancellation terminates the helper and prevents late output from being committed. On restart, mark interrupted work as interrupted and offer explicit retry.

Budget context using the selected tokenizer, including instructions and output allowance. For long recordings, extract facts from bounded transcript chunks and merge them through deterministic, bounded aggregation. Keep distinct items and merge exact duplicates; do not run a second lossy model summary. Preserve source segment IDs through each pass and deduplicate overlap. Never silently truncate a long call. Treat transcript content as data, not instructions to the helper. The model has no tools or filesystem actions.

Persist normalized transcript segments separately from provider output. Use stable segment IDs, optional speaker labels, and timestamps where available. Do not equate system audio with a single identified speaker. Speaker diarization and separate-track alignment are outside this first release.

## Storage and validation

Keep existing transcript exports and legacy `call_note.md` readable. New files within the recording's `transcript/` directory:

- `segments.json`: versioned normalized transcript and source identity.
- `notes.json`: versioned structured result, source references, preset, model revision, prompt version, and normalized transcript digest.
- `notes.md`: human-readable, editable notes.
- `processing.json`: persisted stage, recording ID, preset, mode, and sanitized error text. Source identity is stored with the transcript and notes.

Validate helper output before publishing: expected schema, field types, bounded sizes, valid source segment IDs, and timestamp bounds. Schema validation does not prove factual accuracy. Use source-linked UI and evaluation recordings to check omissions and unsupported claims. Write outputs atomically; preserve previous valid artifacts on errors. Temporary prompts and model output stay inside the recording's working directory and are removed on completion or cancellation. Do not put transcript text in command arguments or logs. Log lifecycle, durations, identifiers, and sanitized failures only.

## Verification and delivery

Tests cover queue serialization, duplicate jobs, cancellation, interrupted state recovery, source changes, malformed model output, context-budget splitting, source-reference preservation, partial failures, and atomic persistence. Use fake helpers for deterministic lifecycle tests; label them as test fixtures, not working AI inference.

Run `swift test` and a Swift build. Separately run real local inference on a synthetic Russian fixture with known decisions, negations, missing deadlines, and unresolved questions. Check that it retains facts and does not invent commitments. Measure runtime and peak memory on the target 24 GiB Mac, then check a long fixture and an offline inference run with models already prepared. Report the difference between build/test success and real-model quality validation. Do not open or automate the desktop app without separate user authorization under the current application-control rules.

Deliver in small changes: core job/artifact handling; local inference adapter and Settings preparation; transcript/notes UI; offline and quality validation. Update README, macOS setup documentation, privacy documentation, and release notes alongside behavior changes.

## Reference implementations

- Existing integration: `apps/macos/Sources/RecnyCore/LocalTranscription.swift`.
- Existing actions: `apps/macos/Sources/Recny/LibraryView.swift`.
- MLX LM: https://github.com/ml-explore/mlx-lm
- Candidate model: https://huggingface.co/mlx-community/Qwen3-4B-Instruct-2507-4bit
