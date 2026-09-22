# AI Add-on

## Status

AI remains outside the automatic macOS audio-only MVP flow.

The app now supports an explicit local-only transcription action from Records only after the optional setup in Settings is ready. Do not add cloud calls, bundled model downloads, model downloads from Records, automatic transcription, or background AI processing in MVP.

## Goal

Help the mentor review calls faster after recording while keeping audio local by default.

## Use Cases

- Explicit local transcription through optional Parakeet setup.
- Optional diarization later.
- Markdown call notes.
- Sales call review.
- Mock interview review.
- Search by transcript.
- Timestamped highlights.
- Feedback draft for student or lead.

## Local-First Rules

- Audio stays local by default.
- AI runs only after explicit user action.
- Cloud AI is optional later and must be clearly labeled.
- Local-only mode blocks cloud AI.
- AI output is review aid, not source of truth.

## Pipeline

Future pipeline:

```text
recording saved
  -> prepare audio
  -> transcription
  -> diarization optional
  -> summary
  -> markdown note
  -> search index
```

Preferred input:

- `export/mixed_balanced.m4a` if available
- fallback to `export/mixed.m4a`
- source tracks later for better diarization

## Candidate Tools

- `whisper.cpp` for local transcription.
- MLX Whisper for Apple Silicon.
- Local LLM later for summaries/reviews.
- Cloud model later only with explicit opt-in.

## Output Files

Future AI folder:

```text
ai/
  transcript.txt
  call_note.md
  transcript.json
  summary.md
  review.md
```

## Metadata

Future metadata fields:

- `ai.transcript_status`
- `ai.summary_status`
- `ai.review_status`
- `ai.model`
- `ai.local_only`
- `ai.last_error`

## UX

Future Library actions:

- Run local transcription.
- Generate note.
- View transcript.
- Search transcript.
- Open AI outputs folder.

## Privacy

- No cloud by default.
- Clear indicator if cloud model is used.
- Redaction later.
- Do not log transcript content in app logs.

## T-Orbit Later

T-Orbit may sync transcript and note metadata. Raw audio/video remains local or in external storage.
