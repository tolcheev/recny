# Storage Format

## Default Root

```text
~/Recordings/TOrbitRecorder/
```

## Recording Directory

Each recording should live in its own directory under the default root.

Suggested directory name:

```text
YYYY-MM-DDTHH-mm-ssZ-<session-id>/
```

## Required Files

```text
source/mic.m4a
source/system.m4a
export/mixed.m4a
metadata.json
```

## Metadata

`metadata.json` should include at least:

- session id
- start time
- end time
- duration
- app version
- capture sources
- file paths relative to the recording directory
- recorder lifecycle status
- error details when capture fails

## Local State

SQLite may be used for local indexes and app state. Heavy audio files remain as local files in the MVP.
