# macOS 0.1.9 release validation

Validation date: 2026-11-01. App version: 0.1.9, build 12.
Packaged source commit: `9b79f7a` (subsequent changes contain website and documentation only).

- Swift package: 336 tests passed.
- Local notes helper: 33 Python tests passed.
- Release build and installer dry run completed without launching or installing the app.
- DMG integrity, ZIP extraction, SHA-256 checksums, and strict code-signature verification passed. The app is ad-hoc signed, not Apple notarized.
- The helper extracted from the packaged app generated valid notes from two synthetic Russian transcript segments while network access was denied with the macOS sandbox. Both source segment IDs were retained.
- The landing page and Russian guide were inspected in the Codex in-app browser at desktop and 390-pixel mobile widths. Neither page overflowed horizontally. Keyboard focus was visible.
- Website links, anchors, heading structure, JSON-LD, sitemap XML, and whitespace checks passed. Windows update metadata is unchanged.
- Independent specification and quality reviews found no release blockers.

This release check did not launch the desktop UI or capture another call. Earlier audio, integration, and longer-input model measurements are recorded separately in [the 2026-10-28 validation report](LOCAL_AI_VALIDATION.md). Model output remains an editable draft and can misinterpret the recording.
