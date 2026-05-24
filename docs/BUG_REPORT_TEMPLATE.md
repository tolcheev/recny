# Bug Report Template

Copy this template into Codex when reporting a TOrbitRecorder bug.

````markdown
## Summary

Short one-line description:

## Build

- App version:
- Git commit hash:
- macOS version:
- Mac model:
- App path:
  - [ ] /Applications/TOrbitRecorder.app
  - [ ] dist/TOrbitRecorder.app
  - [ ] apps/macos/.build/app/TOrbitRecorder.app
  - [ ] Other:

## Permissions Status

- Microphone:
  - [ ] Granted
  - [ ] Missing
  - [ ] Denied
  - [ ] Not determined
  - [ ] Restart required
  - [ ] Unknown
- System audio:
  - [ ] Granted
  - [ ] Missing
  - [ ] Denied
  - [ ] Not determined
  - [ ] Restart required
  - [ ] Unknown
- Storage/output folder writable:
  - [ ] Yes
  - [ ] No
  - [ ] Unknown

## Audio Devices

- Selected microphone:
- Recommended microphone:
- AirPods/Bluetooth connected:
  - [ ] Yes
  - [ ] No
- External microphone connected:
  - [ ] Yes
  - [ ] No
- System output device:

## Steps To Reproduce

1.
2.
3.

## Expected

What should have happened:

## Actual

What happened instead:

## Screenshots

Attach screenshots or paste image paths:

- 

## Recording Folder

Path to the affected recording folder:

```text

```

Files present:

- [ ] source/mic.m4a
- [ ] source/system.m4a
- [ ] export/mixed.m4a
- [ ] metadata.json

File sizes:

```sh
cd "PASTE_RECORDING_FOLDER_HERE"
stat -f "%z %N" source/mic.m4a source/system.m4a export/mixed.m4a metadata.json
```

## Logs

Run and paste relevant output:

```sh
log show --predicate 'subsystem == "com.torbit.recorder"' --last 30m --style compact
```

Or copy visible file logs from Diagnostics -> Logs -> Copy Logs.

Local file log:

```sh
tail -n 100 ~/Recordings/TOrbitRecorder/logs/app.log
```

For live reproduction:

```sh
log stream --predicate 'subsystem == "com.torbit.recorder"' --style compact
```

Local logs folder, if relevant:

```sh
open ~/Recordings/TOrbitRecorder/logs/
```

## Metadata

Paste `metadata.json` or the relevant fields:

```json

```

## Notes

Anything else that might matter:
````
