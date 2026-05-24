# AI Add-on Technical Design

## Status

Future design only. AI is not part of the macOS audio-only local MVP.

The AI add-on is intended primarily for the mentor workflow. Students do not need AI features in the initial product direction.

This document describes future AI capabilities without adding runtime code, dependencies, cloud calls, model downloads, or UI changes to the MVP.

## Goals

The AI add-on should help a mentor review calls faster after recording:

- produce local transcripts
- identify speakers where possible
- generate Markdown notes
- analyze sales calls
- analyze mock interviews
- enable transcript search
- evaluate checklist quality
- preserve timestamps for review
- draft feedback for students/leads

The recorder remains a lightweight capture app. AI should be explicit, optional, and isolated from the recording pipeline.

## Non-Goals

- Do not run AI automatically after every recording by default.
- Do not send audio to cloud AI by default.
- Do not require AI to record, play, tag, or store calls.
- Do not add AI to MVP.
- Do not make AI output the source of truth for human review.
- Do not use AI as a permissions, compliance, or moderation authority.

## User Model

Primary user:

- mentor
- reviews student calls, sales calls, mock interviews, and conflict-sensitive calls
- needs faster recall, notes, timestamps, and feedback drafts

Non-primary user:

- student
- does not need direct AI features in early versions
- may later receive mentor-approved notes or feedback through T-Orbit

## Local-First Approach

### Default Behavior

Audio stays local by default.

AI does not run unless the user explicitly starts an AI action, such as:

- Run transcription
- Generate note
- Generate review
- Search transcript

The app must make it clear whether processing is local or cloud-based.

### Explicit User Action

AI jobs should be started by a deliberate user action. This avoids unexpected CPU/GPU load, battery usage, privacy surprises, and accidental processing of sensitive calls.

Recommended MVP-later defaults:

- local transcription disabled until user clicks `Run transcription`
- note generation disabled until transcript exists and user clicks `Generate note`
- cloud AI disabled unless explicitly configured

### Cloud AI Later

Cloud AI can be optional later for higher quality summaries, analysis, or feedback drafts.

Rules:

- disabled by default
- requires explicit settings
- shows a clear cloud indicator before sending data
- logs provider/model metadata
- respects local-only mode
- should support redaction later

## Pipeline

Future AI pipeline:

```text
recording saved
  > prepare audio
  > transcription
  > diarization optional
  > summary
  > markdown note
  > search index
```

### 1. Recording Saved

AI starts only after the recording has finished and the local metadata is stable:

- `source/mic.m4a`
- `source/system.m4a`
- `export/mixed.m4a`
- `metadata.json`

The preferred input for AI is `export/mixed.m4a` for quick review. Source tracks can be used later for better diarization or channel-aware processing.

### 2. Prepare Audio

Preparation can include:

- choose best input track
- convert to model-friendly WAV/PCM if required
- downmix to mono if required
- segment long audio
- detect silence
- preserve offset timestamps

Prepared files should be stored under `ai/tmp/` or a cache directory and should be safe to regenerate.

### 3. Transcription

Transcription converts speech to text with timestamps.

Output should preserve:

- segment start/end timestamps
- text
- confidence if available
- model name/version
- input track
- language if detected or configured

### 4. Diarization Optional

Diarization is optional because reliable speaker separation may require heavier models or source-track/channel logic.

Possible phases:

- v1: no diarization, transcript segments only
- v2: simple channel hints, for example mic vs system
- v3: local diarization model
- v4: cloud diarization if explicitly enabled

### 5. Summary

Summary is a short digest for fast recall.

Possible sections:

- topic
- key decisions
- action items
- risks
- follow-up questions
- important timestamps

### 6. Markdown Note

Markdown note is the mentor-facing artifact. It should be editable and safe to sync later.

Possible sections:

- Call context
- What happened
- Strong moments
- Problems
- Student/lead feedback
- Next steps
- Timestamps

### 7. Search Index

Transcript search should work locally before any T-Orbit sync.

Search index can include:

- transcript text
- timestamps
- recording id
- title
- participants
- tags

SQLite FTS or a small local index is enough for early versions.

## Tool Candidates

### whisper.cpp

Pros:

- mature local Whisper implementation
- works offline
- broadly documented
- can run on Apple Silicon

Cons:

- model management is a product concern
- performance depends on model size and hardware
- integration and packaging must stay lightweight

### MLX Whisper for Apple Silicon

Pros:

- optimized for Apple Silicon
- good fit for MacBook M-series devices
- local-first

Cons:

- packaging and Swift integration need careful design
- model download/storage UX needed
- API stability and binary distribution need review

### Local LLM Later

Local LLM can generate notes, reviews, and feedback drafts after transcript exists.

Candidate usage:

- summarize transcript
- produce Markdown note
- analyze sales objections
- analyze mock interview quality
- draft feedback

Risks:

- large model storage
- CPU/GPU/RAM load
- hallucinations
- slower UX
- complex model updates

## Output Files

AI outputs live beside the recording in an `ai/` folder.

```text
recording-folder/
  ai/
    transcript.md
    transcript.json
    summary.md
    review.md
```

### `ai/transcript.md`

Human-readable transcript with timestamps.

Example:

```markdown
# Transcript

Model: whisper.cpp large-v3

## Segments

[00:00:04] Mentor: Let's start with the test strategy.
[00:00:17] Student: I would split API and UI checks.
```

### `ai/transcript.json`

Structured transcript for search, sync, and future UI.

Example:

```json
{
  "schema_version": 1,
  "recording_id": "rec_2026-05-24_10-30-00_ab12cd34",
  "model": "whisper.cpp-large-v3",
  "language": "ru",
  "segments": [
    {
      "start_sec": 4.2,
      "end_sec": 12.8,
      "speaker": "mentor",
      "text": "Let's start with the test strategy."
    }
  ]
}
```

### `ai/summary.md`

Short summary for quick recall.

### `ai/review.md`

Mentor review artifact. This can include sales analysis, mock interview analysis, checklist quality, and feedback draft sections depending on call type.

## Metadata

Current MVP has top-level `ai: "not_started"`. Future metadata should become structured.

Recommended future shape:

```json
{
  "ai": {
    "transcript_status": "completed",
    "summary_status": "completed",
    "review_status": "not_started",
    "model": "whisper.cpp-large-v3",
    "local_only": true,
    "cloud_provider": null,
    "last_run_at": "2026-05-24T10:45:00Z",
    "error": null
  }
}
```

### Status Values

For transcript, summary, and review:

- `not_started`
- `queued`
- `processing`
- `completed`
- `failed`
- `skipped`

### Required Metadata Fields

- `ai.transcript_status`
- `ai.summary_status`
- `ai.model`
- `ai.local_only`

Optional later:

- `ai.review_status`
- `ai.cloud_provider`
- `ai.language`
- `ai.error`
- `ai.last_run_at`

## UX

AI UX should be secondary to recording UX.

### Entry Points

In Library details for a recording:

- Run transcription
- Generate note
- View transcript
- Search transcript

Diagnostics can show AI engine availability later, but the main recorder screen should not become an AI dashboard.

### Run Transcription

User action:

```text
Library > Recording details > Run transcription
```

Expected UI:

- processing state
- model used
- local/cloud indicator
- cancel if possible
- error with retry

### Generate Note

Requires transcript.

Expected output:

- `ai/summary.md`
- `ai/review.md` or note draft
- editable Markdown preview

### View Transcript

Transcript viewer should support:

- timestamped segments
- click timestamp to play from position later
- copy selected text
- show model/source metadata

### Search Transcript

Search should work locally:

- search within selected transcript
- search across Library
- return recording, timestamp, and snippet

## Analysis Modes

### Sales Analysis

Useful for lead calls.

Possible sections:

- lead pain
- objections
- offer fit
- missed questions
- pricing discussion
- next action
- sales risk

### Mock Interview Analysis

Useful for interview prep.

Possible sections:

- question coverage
- answer structure
- technical gaps
- communication issues
- strong answers
- follow-up drills

### Checklist Quality

Checklist quality can compare call content against mentor-defined checklists.

Examples:

- did mentor ask for context
- did student explain reasoning
- did candidate mention test data
- did sales call cover next steps

This should be advisory and editable, not authoritative.

### Feedback Draft

Feedback draft should be a mentor-editable output, not something sent automatically.

Possible output:

```markdown
## Feedback Draft

Strong points:
- ...

To improve:
- ...

Next practice task:
- ...
```

## Privacy

### No Cloud by Default

Default AI processing is local-only. The app must not upload audio, transcripts, notes, or summaries unless the user explicitly enables cloud AI or T-Orbit sync.

### Clear Cloud Indicator

If cloud model is used, the UI must show:

- provider
- model
- what data will be sent
- whether transcript/note will be stored remotely

The user should confirm before first cloud use.

### Redaction Later

Future redaction can remove or mask:

- phone numbers
- emails
- names
- company names
- payment details
- credentials

Redaction is not a substitute for consent or correct privacy settings.

### Audit

AI jobs should record:

- recording id
- job type
- local/cloud mode
- model/provider
- start/end time
- status
- error

Do not log transcript text or audio content by default.

## Future T-Orbit Integration

T-Orbit may sync transcript and note artifacts later.

Possible sync items:

- transcript status
- transcript text or external transcript link
- summary Markdown
- review Markdown
- search metadata
- model metadata

Raw audio still remains local or external storage. T-Orbit stores metadata, notes, transcript records, and storage links.

Suggested API mapping:

- `POST /recordings/{id}/transcripts`
- `POST /recordings/{id}/notes`
- `POST /recordings/{id}/storage-links` for external transcript/note files if needed

Local-only mode blocks all T-Orbit sync and all cloud AI.

## Failure Handling

AI failure must not mark the recording as failed.

Failure examples:

- model missing
- insufficient disk space
- insufficient memory
- unsupported audio format
- transcript job cancelled
- cloud provider error

Expected behavior:

- keep recording playable
- set AI status to `failed`
- preserve error message
- offer retry
- keep partial artifacts only if useful

## Open Questions

- Which local transcription engine should be the first supported path: whisper.cpp or MLX Whisper?
- Should model download happen inside the app or through a separate installer script?
- Should summaries use local LLM only, cloud LLM only, or both?
- How much transcript text should sync to T-Orbit by default?
- Should transcript search use SQLite FTS or a separate local index?
- What redaction rules are required before cloud AI can be enabled?
