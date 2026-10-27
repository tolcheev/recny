# Local AI validation — 2026-10-28

Environment: Apple M4 Pro, 24 GiB unified memory, macOS 26.5.2. The deployment target remains macOS 15; this run did not exercise macOS 15 itself. Optional Python 3.11 runtime: mlx-lm 0.32.2 and lm-format-enforcer 0.11.3. Model: mlx-community/Qwen3-4B-Instruct-2507-4bit, revision `50d427756c6b1b2fe0c0a10f67fbda1fc8e82c1b`.

## Deterministic checks

- 335 Swift tests passed; the real-model integration test is separately enabled.
- 33 Python tests passed in the prepared runtime, including grammar handling, chunk budgets, invalid references, incomplete coverage, bounded retries, rollback, SIGTERM cleanup, SIGKILL recovery and live download locks.
- A release application was built. The bundled helper resolves through Foundation Bundle; the final package is verified with codesign and its helper is compared byte-for-byte with the committed source at delivery.
- Focused reviews covered process lifetime, storage, model preparation, helper bounds, UI edit preservation and stale source links. Reported defects were fixed and rechecked.

## Actual local inference

Recognition used a temporary 45-second excerpt from an existing Russian recording. Original audio was unchanged. Offline Parakeet completed in 5.76 seconds with a 4,162,178,144-byte peak memory footprint. This was a sparse speech sample, not a recognition-accuracy benchmark. The temporary excerpt and its recognition exports are removed after validation. The final Swift integration test completed in 32.773 seconds: it generated transcript and notes, regenerated the Mentoring preset without speech recognition, verified persisted artifacts and confirmed that the transcript stayed unchanged.

Synthetic Russian notes checks include a rejected cloud feature, an unapproved budget, an unknown invitation owner, an unstated installation deadline, the GraphQL/GraphiQL distinction and an unanswered interview question. Prepared model inference was run under a macOS sandbox denying network access. Timing and footprint describe individual local runs, not general performance guarantees.

| Synthetic fixture | Wall time | Peak memory footprint | Source IDs | Sections / items |
| --- | ---: | ---: | ---: | ---: |
| Meeting | 10.51 s | 3,540,667,344 bytes | 6 / 6 | 4 / 7 |
| Interview | 17.59 s | 3,627,862,992 bytes | 8 / 8 | 6 / 11 |
| Mentoring | 13.94 s | 3,556,461,544 bytes | 6 / 6 | 3 / 10 |
| Long, 33,927 characters | 302.26 s | 5,365,009,840 bytes | 48 / 48 | 4 / 73 |

The final long run used six chunks of eight segments. A previous 16-segment chunk configuration exhausted its output budget and failed without replacing the previous output. The final eight-segment cap retained all source IDs and produced a fresh valid result. Long processing is substantially slower and can produce lengthy, repetitive notes.

## Quality limits

All-source-ID coverage and JSON validation establish structural completeness, not factual fidelity. Spot checks found repetition and wording drift: the mentoring draft changed who would invite users into whom to invite and strengthened a stated plan into an obligation. The Interview preset retained the correct answer and missing-answer context, but did not consistently provide expert scoring or corrected answers. These outputs are editable, source-linked drafts requiring review.

No desktop application was launched or controlled for validation. UI behavior was compiled and reviewed, but not manually exercised. No app release was published and no existing app installation was replaced.
