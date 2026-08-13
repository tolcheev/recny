# Flat Recordings Folder Design

## Goal

Give the user one obvious Finder folder containing every completed recording as a final `.m4a` file. The folder must not expose session directories, source tracks, exports, metadata, UUID suffixes, or recovery artifacts.

## User-facing result

The storage root gains a `Recordings/` directory. It contains a flat list:

```text
~/Recordings/TOrbitRecorder/
  Recordings/
    zoom_10-30__13.08.26.m4a
    safari_15-06__12.08.26.m4a
    torec_09-24__11.08.26.m4a
```

There are no subdirectories inside `Recordings/`.

The basename format is:

```text
<source>_<HH-mm>__<dd.MM.yy>.m4a
```

The source is lowercase and filesystem-safe. Known Zoom variants become `zoom`; manual ToRec recordings become `torec`; browser recordings use the detected browser name such as `safari`. Unsupported punctuation and path separators become a single hyphen.

Examples:

- `zoom_10-30__13.08.26.m4a`
- `safari_15-06__12.08.26.m4a`
- `unknown_09-24__11.08.26.m4a`

If two recordings have the same source and start minute, the later filename gets `_2`, then `_3`, without overwriting an existing file.

## Internal storage

The existing session folder remains the canonical record. It keeps `source/mic.m4a`, `source/system.m4a`, `export/mixed.m4a`, optional balanced audio, `metadata.json`, and recovery data. This is required for crash recovery, audio diagnostics, reprocessing, trimming, and deletion from the in-app library.

The app does not move or delete canonical files when publishing the flat recording. It copies the best completed audio into `Recordings/` in this order:

1. `export/mixed_balanced.m4a`
2. `export/mixed.m4a`
3. `source/mic.m4a`
4. `source/system.m4a`

An empty or missing file is never published.

## Publishing and migration

Publishing runs after successful session finalization and during library refresh. The refresh path backfills all existing sessions, including completed recordings currently stored under `Inbox/Short`.

Migration is non-destructive and idempotent:

- existing canonical session folders are left untouched;
- rerunning migration does not create another copy for the same recording;
- an existing flat file is reused when it represents the same recording and has the expected non-zero size;
- filename collisions between different recordings use numeric suffixes;
- failed or interrupted sessions without completed audio are skipped and logged;
- one failed copy does not prevent other recordings from being published.

The recording ID is stored in an extended attribute on the published file when the filesystem supports it. If attributes are unavailable, the app uses its local index to keep the operation idempotent.

## App behavior

`Open Library Folder`, the menu-bar folder action, and the corresponding keyboard shortcut open `Recordings/`, not the technical `Library/` directory. `Open` for a recording reveals its published final `.m4a` file.

The in-app Records list remains backed by canonical metadata so playback, deletion, tags, diagnostics, and recovery keep working. Its primary visible name uses the same source/time/date basename as Finder unless the recording has an explicit user title.

Deleting a recording from the app removes both the canonical session folder and its published final file. Deleting only the published file in Finder does not delete the canonical recording; the next refresh republishes it.

## Failure handling and logs

Lifecycle logs record:

- publication success with recording ID and destination filename;
- skipped sessions and the concrete reason;
- collision suffix selection;
- migration summary with published, reused, skipped, and failed counts.

Logs must not contain audio contents, metadata contents, or user-entered notes.

## Tests

Core tests cover:

- exact source/time/date formatting;
- source sanitization and known source normalization;
- deterministic `_2` collision handling without overwrite;
- preferred final-audio selection;
- idempotent republishing;
- migration of Library and `Inbox/Short` recordings;
- skipping failed or empty sessions;
- deletion of the matching published file only;
- `Recordings/` path creation and routing for folder actions.

Validation consists of `swift test --package-path apps/macos`, the release build, packaging, and a dry-run install. Manual QA verifies that a new recording and historical recordings appear in one flat Finder list and remain playable.

## Out of scope

- changing the required canonical session format;
- deleting source tracks or metadata;
- cloud upload or T-Orbit synchronization;
- publishing failed recordings without usable audio;
- Windows client changes.
