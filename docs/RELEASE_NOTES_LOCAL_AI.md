# Local transcripts and notes — unreleased

This feature adds optional local processing to completed macOS recordings. Recording behavior remains unchanged.

- Open transcripts and generated notes inside Recny, search text, and play verified timestamps.
- Generate Meeting, Interview, or Mentoring notes using a prepared local Qwen3 4B model. Parakeet continues to handle speech recognition.
- Edit, copy, and export Markdown. Regenerate notes without repeating speech recognition; previous Markdown versions are retained.
- Queue jobs across library windows, cancel helpers, retry failures, and recover interrupted job state.
- Keep audio and text on the Mac. Dependency installation and model downloads are explicit setup steps; prepared inference runs offline.

This is a manually triggered first version. It does not identify speakers, automatically process every recording, synchronize with T-Orbit, or send recordings. Notes may contain recognition or interpretation errors and repeated facts; source links support review. Missing setup produces an error rather than a cloud fallback.

See [local setup and verification](LOCAL_AI.md). This branch has no published application release; the release version has not been incremented.
