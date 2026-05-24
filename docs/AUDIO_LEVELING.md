# Audio Leveling / Post-Recording Loudness Balancing

## V1 Implementation Status

Audio Leveling v1 is implemented in the macOS app as post-recording processing.

Current behavior:

- `source/mic.m4a` and `source/system.m4a` remain immutable.
- `export/mixed.m4a` remains the original/simple mixed preview.
- `export/mixed_balanced.m4a` is created after Stop Recording when Audio leveling is enabled.
- `analysis/audio_analysis.json` stores track analysis, gain plan, and balanced output summary.
- `metadata.json` stores `audio.processing` summary fields and `audio.health` warnings.
- The Latest strip and Diagnostics prefer balanced playback when it is ready.
- Playback priority is `export/mixed_balanced.m4a`, then `export/mixed.m4a`, then an available source track.
- Latest and Library expose Original playback through More/Details actions.
- Latest and Library show compact audio health badges: `Audio OK`, `Audio warning`, or `Audio failed`.
- Diagnostics exposes the latest `analysis/audio_analysis.json`.

V1 uses conservative track-level gain plus safe peak protection. It does not perform real-time AGC, AI enhancement, noise cancellation, or advanced mastering.

## Purpose

Call recordings often have uneven loudness:

- The local microphone is too quiet while the remote side is loud.
- The remote side is too quiet while the local microphone is loud.
- `export/mixed.m4a` is hard to listen to.
- Future transcription quality may suffer when one side is much quieter than the other.

The goal is to create a post-recording balanced preview that is easier to listen to and safer for future speech-to-text processing, while preserving the raw source tracks.

## Mandatory Rule: Raw Files Are Immutable

The recorder must never modify raw source tracks after capture:

```text
source/mic.m4a
source/system.m4a
```

All processing output must be written under `export/` or `analysis/`:

```text
export/mixed.m4a
export/mixed_balanced.m4a
export/mic_leveled.m4a        # optional
export/system_leveled.m4a     # optional
analysis/audio_analysis.json
```

`source/` is evidence and recovery data. `export/` is derived playback data.

## Goals

- Make both call sides roughly similar in perceived loudness.
- Avoid the common "one person is shouting, the other is barely audible" problem.
- Preserve the original `source/mic.m4a` and `source/system.m4a` files.
- Produce an output that is comfortable for manual review.
- Produce audio that is more useful for future transcription.
- Keep the implementation local-first and lightweight.
- Store enough analysis data to explain what processing was applied.

## Non-Goals For v1

- No real-time automatic gain control.
- No changes to macOS input or output devices.
- No AI-based audio enhancement.
- No cloud processing.
- No noise cancellation.
- No advanced mastering workflow.
- No destructive edits to original files.
- No attempt to perfectly meet broadcast loudness standards.
- No speaker diarization.

## Proposed Output Files

Normal recording output remains:

```text
source/
  mic.m4a
  system.m4a
export/
  mixed.m4a
  mixed_balanced.m4a
analysis/
  audio_analysis.json
metadata.json
```

Optional intermediate files may be produced if they simplify implementation or diagnostics:

```text
export/mic_leveled.m4a
export/system_leveled.m4a
```

If intermediate files are not needed, the pipeline can apply gain directly while creating `mixed_balanced.m4a`.

## Processing Pipeline

Audio leveling runs after `Stop Recording`, after the raw tracks are finalized.

1. Validate input files.
   - Check whether `source/mic.m4a` exists and `size > 0`.
   - Check whether `source/system.m4a` exists and `size > 0`.
   - At least one source track must be usable.
   - Do not process empty files as valid speech sources.

2. Analyze each source track.
   - Decode audio for analysis.
   - Calculate peak level.
   - Calculate RMS level.
   - Estimate approximate loudness.
   - Estimate silence ratio.
   - Detect clipping.
   - Detect whether the track has meaningful signal.

3. Decide per-track gain.
   - Choose a target speech loudness range.
   - Compare mic and system loudness.
   - Calculate gain adjustments for each usable track.
   - Clamp gain to a safe range.
   - Avoid boosting mostly silent tracks.

4. Apply gain.
   - Apply track-level gain before mixing.
   - Optionally write `export/mic_leveled.m4a` and `export/system_leveled.m4a`.

5. Mix balanced output.
   - Combine available leveled tracks.
   - If both tracks exist, mix mic + system.
   - If only one track exists, create balanced output from the available track.
   - Preserve `export/mixed.m4a` as the original/simple mixed preview.

6. Apply compressor/limiter.
   - Use a conservative compressor only if needed.
   - Apply a final limiter to prevent clipping.
   - The limiter is mandatory for balanced output.

7. Write outputs.
   - Create `export/mixed_balanced.m4a`.
   - Create `analysis/audio_analysis.json`.
   - Update `metadata.json`.
   - Update SQLite index fields when the index supports audio analysis metadata.

8. Update UI-facing state.
   - Prefer `mixed_balanced.m4a` for playback when available.
   - Show warnings if one side was silent or clipping.
   - Keep original playback available through details.

## Audio Metrics

`analysis/audio_analysis.json` should record analysis per track and per export.

### Per-Track Metrics

- `exists`: whether the file exists.
- `file_size_bytes`: file size.
- `duration_sec`: detected duration.
- `peak_dbfs`: maximum peak level in dBFS.
- `rms_dbfs`: approximate RMS level in dBFS.
- `approx_loudness_db`: approximate integrated loudness or speech loudness estimate.
- `silence_ratio`: approximate ratio of silent frames, `0.0...1.0`.
- `has_signal`: whether meaningful audio signal was detected.
- `clipping_detected`: whether clipping was detected.
- `gain_applied_db`: gain applied during leveling.
- `limiter_applied`: whether limiting was applied to the derived output.

### Example

```json
{
  "schema_version": 1,
  "recording_id": "rec_123",
  "created_at": "2026-05-24T02:40:00Z",
  "preset": "balanced",
  "tracks": {
    "mic": {
      "exists": true,
      "file_size_bytes": 184320,
      "duration_sec": 72.4,
      "peak_dbfs": -8.2,
      "rms_dbfs": -31.5,
      "approx_loudness_db": -28.0,
      "silence_ratio": 0.18,
      "has_signal": true,
      "clipping_detected": false,
      "gain_applied_db": 5.0,
      "limiter_applied": true
    },
    "system": {
      "exists": true,
      "file_size_bytes": 291840,
      "duration_sec": 72.4,
      "peak_dbfs": -2.0,
      "rms_dbfs": -19.0,
      "approx_loudness_db": -20.5,
      "silence_ratio": 0.12,
      "has_signal": true,
      "clipping_detected": false,
      "gain_applied_db": -3.0,
      "limiter_applied": true
    }
  },
  "exports": {
    "mixed_balanced": {
      "path": "export/mixed_balanced.m4a",
      "file_size_bytes": 312000,
      "peak_dbfs": -1.0,
      "rms_dbfs": -22.0,
      "limiter_applied": true,
      "integrity_ok": true
    }
  },
  "warnings": []
}
```

## Metadata Updates

`metadata.json` should keep the canonical recording metadata and reference analysis/export state.

Suggested additions:

```json
{
  "audio": {
    "health": {
      "status": "warning",
      "warnings": [
        "mic_too_quiet"
      ]
    },
    "processing": {
      "balanced_mix_status": "done",
      "balanced_mix_path": "export/mixed_balanced.m4a",
      "analysis_path": "analysis/audio_analysis.json",
      "mic_gain_db": 6,
      "system_gain_db": -2,
      "warnings": []
    }
  }
}
```

Possible `balanced_mix_status` values:

- `disabled`
- `pending`
- `ready`
- `partial`
- `failed`

Warnings should be user-facing but concise:

- `mic_silent`
- `system_silent`
- `mic_too_quiet`
- `system_too_quiet`
- `clipping_detected`
- `balanced_mix_failed`
- `only_one_track_available`

## Presets

Add a future `Settings > Audio Processing` section.

### Off

- Do not create `mixed_balanced.m4a`.
- Keep using `export/mixed.m4a`.
- Still allow lightweight analysis if diagnostics need it, but do not alter exports.

### Balanced, Default

- Target normal speech listening level.
- Moderate gain adjustment.
- Conservative compression.
- Final limiter enabled.
- Best default for calls and mentorship sessions.

### Voice Boost

- Stronger speech leveling.
- More aggressive gain on quiet but non-silent tracks.
- Useful for difficult calls.
- Higher risk of raising room noise.

### Conservative

- Small gain changes only.
- Minimal compression.
- Final limiter enabled.
- Useful when preserving the original sound is more important than loudness matching.

## Gain Safety Rules

Leveling must be conservative because call recordings can contain silence, music, notification sounds, and noisy rooms.

Rules:

- Never boost a track above the maximum configured gain.
- Do not heavily boost a track with high `silence_ratio`.
- Do not boost a track where `has_signal == false`.
- Do not boost noise as if it were speech.
- Reduce gain if clipping is detected.
- Always apply a final limiter to `mixed_balanced.m4a`.
- If only one source track exists, create balanced output from that track and mark the export as `partial`.
- If both source tracks are missing or empty, do not create a successful balanced export.

Suggested initial limits:

- Maximum boost: `+12 dB`.
- Maximum attenuation: `-12 dB`.
- Limiter ceiling: `-1 dBFS`.
- Silence threshold: implementation-defined, but stable across test fixtures.

## UX

### Main Window

The main UI should stay simple.

When balanced output is ready, the latest strip can show:

```text
Audio: Balanced
```

The primary `Play` action should play `export/mixed_balanced.m4a` when it exists and passes integrity checks.

Fallback order:

1. `export/mixed_balanced.m4a`
2. `export/mixed.m4a`
3. Available source track, only from details/diagnostics

### Details / Library

Recording details should expose:

- Balanced mix status.
- Original mix path.
- Balanced mix path.
- Audio warnings.
- Analysis summary.
- Action: `Play Balanced`.
- Action: `Play Original`.

### Diagnostics

Diagnostics should show:

- Analysis file path.
- Mic/system loudness summary.
- Gain applied per track.
- Whether limiter was applied.
- Warnings for silent or clipped tracks.
- Failure reason if balanced export failed.

### Error And Warning Copy

Examples:

- `Microphone track seems silent.`
- `System audio track seems silent.`
- `Microphone is clipping.`
- `Balanced preview could not be created. Original mix is still available.`

## Storage And Indexing

`analysis/audio_analysis.json` is the source of detailed analysis data.

`metadata.json` stores only the summary needed for UI and sync compatibility.

SQLite can index a small subset later:

- `balanced_mix_status`
- `preferred_playback_path`
- `mic_has_signal`
- `system_has_signal`
- `mic_clipping_detected`
- `system_clipping_detected`

Do not store large analysis payloads in SQLite unless there is a clear query need.

## Implementation Notes

Preferred implementation direction:

- Use native macOS audio APIs.
- Avoid adding FFmpeg as a heavy dependency for the MVP app.
- Keep analysis and export logic separate from recorder capture logic.
- Make the processor testable with fixture audio files.
- Treat audio leveling as post-processing that can fail without losing the recording.

Suggested service boundary:

```text
AudioAnalysisService
AudioLevelingPlanner
BalancedMixExporter
AudioProcessingController
```

The recorder pipeline should call the audio processing controller after raw recording finalization.

## Failure Handling

Balanced processing must never turn a valid recording into a failed recording.

If raw capture succeeded but balanced processing fails:

- Keep `source/mic.m4a`.
- Keep `source/system.m4a`.
- Keep `export/mixed.m4a`.
- Mark `audio_processing.balanced_mix_status = failed`.
- Log the failure.
- Show that original playback is available.

If raw capture failed or both source tracks are empty:

- Recording status remains failed according to the existing recording reliability rules.
- Do not create a misleading balanced output.

## Tests Plan

### Unit Tests

- Gain planner clamps boost and attenuation.
- Silent track does not receive large boost.
- Clipping track receives attenuation or limiter flag.
- Missing mic creates partial balanced export from system.
- Missing system creates partial balanced export from mic.
- Missing both returns failed processing status.
- Metadata summary maps analysis warnings correctly.
- Playback fallback prefers `mixed_balanced.m4a` when integrity is OK.

### Fixture-Based Tests

Use small generated fixture audio files:

- Loud mic + quiet system.
- Quiet mic + loud system.
- One track silent.
- Both tracks normal.
- Clipped mic.
- Missing system track.
- Missing mic track.

### Manual QA

- Record YouTube + voice with low microphone volume.
- Record YouTube + voice with loud microphone volume.
- Record with system audio muted.
- Record with microphone muted.
- Compare `mixed.m4a` vs `mixed_balanced.m4a`.
- Confirm source files are byte-for-byte untouched after processing.

## Open Questions

- Should `mixed_balanced.m4a` replace `mixed.m4a` as the default user-facing preview, or should the app expose both equally?
- Should intermediate `mic_leveled.m4a` and `system_leveled.m4a` be retained by default or only in diagnostics mode?
- What target loudness is acceptable for speech review without creating a mastering dependency?
- How much processing is acceptable before future transcription results become less faithful to the original call?
