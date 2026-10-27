# Local transcripts and structured notes

Recny can transcribe a completed recording and create editable notes on the Mac. This optional feature extends the original recording-only MVP. It does not upload audio, transcript text, or notes, and does not require an API key. The application remains Swift/SwiftUI; inference uses separately installed command-line dependencies.

## Setup

Use Apple Silicon and macOS 15 or newer. Keep at least 10 GiB free for the optional runtimes, both models, downloads in progress, and processing output. Models are downloaded once; prepared inference works offline. Do not delete recordings to make room automatically.

1. Install the speech dependencies using the command shown in Settings → Local transcription (`uv`, `ffmpeg`, and `parakeet-mlx`).
2. Select **Prepare Parakeet Model**. Wait for the ready state before transcribing.
3. In the local notes Settings section, copy and run the displayed runtime installation command. It creates a dedicated Python 3.11 environment under `~/Library/Application Support/Recny/LocalAI/runtime` and installs `mlx-lm==0.32.2` and `lm-format-enforcer==0.11.3`. It does not modify the system Python environment or start a server.
4. Select **Prepare Notes Model**. This explicitly downloads `mlx-community/Qwen3-4B-Instruct-2507-4bit` into `~/Library/Application Support/Recny/LocalAI/notes-model` and records the resolved repository revision in `manifest.json`.

Downloads are restricted to explicit preparation. The runtime installer requires `uv`; the speech setup instructions include its installation. Preparing models requires internet access, sufficient disk space, and access to the public model repository. Normal processing does not download missing files or fall back to an API. Incomplete models produce a setup error.

## Processing a recording

Open **Transcript & Notes** from the recording library. Choose Meeting, Interview, or Mentoring and start local processing. You can also transcribe only, or regenerate notes from a previously verified transcript. Changing the preset does not require speech recognition again.

Jobs run sequentially across open library windows. Closing the document window leaves the job running. Cancel stops the helper before the next queued job starts. A failed note-generation step preserves the completed transcript. After an application restart, unfinished jobs are marked interrupted and require an explicit retry. Automatic processing after recording ends is not part of this version.

The Transcript tab provides search and timestamp playback. Legacy plain-text transcripts remain readable but have no inferred timing or verified audio identity. Re-transcribe a legacy recording before generating notes. The current version does not identify individual speakers in a mixed system-audio track.

The Notes tab provides source references, editing, copying, and Markdown export. Save edits before regeneration; previous Markdown is retained in `transcript/history/`. Notes refer to both the audio fingerprint and normalized transcript digest used when generated. If either changes, old source links are disabled until notes are regenerated. Editing exported Markdown does not change the recording's stored notes.

## What notes mean

Meeting notes extract topics, decisions, actions and open questions. Interview and mentoring presets organize discussion and may add explicitly labeled model assessments. The Interview preset is not a complete expert evaluation of a candidate. Unspecified owners and deadlines must remain unspecified. Generation uses a JSON grammar to constrain structure and source identifiers. Source references link a generated item to the supplied transcript segment; they are not a proof that the model interpreted the statement correctly. Speech recognition and generated notes can be wrong. In local evaluation, a draft changed an unresolved invitation owner into a question about whom to invite and strengthened a stated plan into an obligation. Review wording against the linked transcript before relying on or sharing notes.

Long transcripts are split using the model tokenizer, with space reserved for instructions, one bounded retry, and output. Each chunk contains at most 8 source segments. Distinct items from successive chunks are retained and identical items merged. This favors source coverage over a short executive summary, so long recordings may produce long notes. Paraphrased facts can repeat between sections. There are explicit limits of 8 MiB input, 20,000 segments, 256 chunks, and 2 MiB output; exceeding a limit or receiving malformed, incomplete, or ungrounded-reference output fails without replacing valid notes. No content is silently truncated to fit.

## Local artifacts

Existing source recordings and audio exports are unchanged. Processing writes inside each recording's `transcript/` directory:

- `transcript.txt`, `.srt`, `.vtt`, `.json`: Parakeet exports.
- `segments.json`: normalized segments, timestamps, schema version and SHA-256 audio identity.
- `notes.json`: generated sections, source segment IDs, preset, audio identity, model revision and prompt version.
- `notes.md`: editable Markdown notes.
- `history/*.md`: previous Markdown versions preserved when notes are saved or regenerated.
- `processing.json`: current or final job stage and sanitized error text.

The old `call_note.md` prompt template is retained when present; it is not presented as a generated analysis. Per-job input and helper-output files are temporary, local, and removed when the job exits. Interrupted job folders are cleaned when their recording is restored in the library. Logs contain stages and recording IDs, not transcript text or model responses.

## Verification

Run the deterministic checks without downloading models:

```sh
swift test --package-path apps/macos
PYTHONDONTWRITEBYTECODE=1 python3 -m unittest discover -s scripts/tests -p test_local_notes.py
```

An opt-in integration test runs real local recognition and note generation, then regenerates another preset without replacing the transcript:

```sh
RECNY_LOCAL_AI_SMOKE_AUDIO=/absolute/path/to/russian-audio.m4a swift test --package-path apps/macos --filter LocalAIIntegrationTests
```

This copies the selected audio into a temporary recording folder and removes it at test completion. It prints test results rather than recording content. Both model setups must be ready. The ordinary test suite skips this test when the environment variable is absent. Build success and fixture tests do not establish accuracy across arbitrary recordings or establish manual UI verification.

Measured checks and known quality limits are recorded in [the local validation report](LOCAL_AI_VALIDATION.md).
