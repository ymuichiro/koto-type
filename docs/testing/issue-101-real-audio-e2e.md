# Issue #101: real-audio and GUI validation gate

The synthetic corpus and backend diagnostics are not sufficient to close
Issue #101. This document defines the remaining manual gate for real user
speech, microphone capture, and text insertion through the packaged app.

## Input-device preflight

Before starting the manual gate, run:

```sh
make test-real-audio-preflight
```

The command uses macOS `system_profiler` device metadata only; it does not
record audio or inspect transcripts. The JSON result reports only readiness,
device count, and channel counts; it does not print device names. It uses
these exit codes:

- `0`: `READY` — at least one input device exposes one or more input channels.
- `2`: `NOT_RUN` — no usable input device or the host is not macOS. This is not
  a pass and must be recorded as the platform blocker.
- `1`: `ERROR` — the device inventory could not be inspected.

The preflight is a prerequisite, not the real-audio/GUI test itself. A
`READY` result does not grant microphone or Accessibility permission and does
not replace the six-utterance app test below.

When the preflight returns `READY`, the recorder-only smoke can be run with:

```sh
make test-real-audio-capture
```

This runs the existing `RealtimeRecorderTests`, including the actual
`AVAudioEngine` start/stop path on the host. It does not prove microphone
permission handling in the packaged app, text insertion, spoken-word
accuracy, cancellation recovery, or the full GUI gate below.

The deterministic preflight parser regression test is also included in
`make test-all`; it does not require an input device and does not grant a
hardware E2E result.

## Scope

Run the same fixed utterances from
`tests/data/ending_fidelity_corpus.json`, at least three times each:

| Case | Spoken sentence | Required ending |
| --- | --- | --- |
| `question_kadoka` | `これは実現できますか？` | `か` and question punctuation |
| `question_deshouka` | `この方法で問題ないでしょうか？` | `でしょうか` and question punctuation |
| `question_masenka` | `明日までに確認してもらえませんか？` | `ませんか` and question punctuation |
| `particle_ne` | `今日はここまでですね。` | `ですね` |
| `particle_yo` | `この設定で動きますよ。` | `ますよ` |
| `declarative` | `これは実現できます。` | declarative ending; no question mark |

Do not use only the first three question cases: the `ね`, `よ`, and declarative
controls detect over-correction in the opposite direction.

## Test matrix

Record the following for every run:

- OS version and architecture
- app version/commit and whether the app was packaged or source-launched
- backend (`CPU` or `MLX Swift`), model, cold/warm state, VAD state, prompt mode,
  and post-processing state
- input device, permission state, elapsed time, inserted text, and the final
  ending classification
- whether the app stayed responsive, whether cancel worked, and whether an
  immediate second recording succeeded

The minimum platform matrix is:

| Platform | Backend | Required status |
| --- | --- | --- |
| macOS 14 | CPU-only | `PASS`, `FAIL`, or `NOT_RUN` |
| macOS 15 | CPU-only | `PASS`, `FAIL`, or `NOT_RUN` |
| macOS 26 or later | MLX Swift | `PASS`, `FAIL`, or `NOT_RUN` |

On each platform, run one cold start and one warm start. Use the app's normal
hotkey and insert into an editable target such as TextEdit. Repeat one complete
cycle after cancelling a recording to cover stop/cancel recovery. If a second
editable target is available, repeat the question cases there to rule out a
single-target insertion issue.

## Pass criteria

A platform row passes only when all of these hold for every required repeat:

1. The three question cases retain their spoken question ending and are not
   converted to declarative sentences.
2. `ね` and `よ` remain present in their respective particle cases.
3. The declarative control does not gain a question ending.
4. Text is inserted into the editable target once, without duplication or
   truncation.
5. The app does not hang or crash; cancel followed by a new recording works.
6. No transcript, audio content, token, or credential appears in diagnostic
   logs or is copied into the repository.

The content criteria are evaluated per utterance, not by an average that could
hide a lost suffix. A single lost question ending is a failure for that run.

## Not-run and failure handling

`NOT_RUN` is an honest result, not a pass. Use it when the host lacks a usable
input device, the required OS/backend is unavailable, or microphone/Accessibility
permission cannot be granted. Record the exact blocker and do not manufacture
audio or GUI evidence to replace it.

For a `FAIL`, retain only safe metadata and a short redacted description of the
symptom. Keep audio and transcripts in a user-controlled temporary directory;
do not commit them or add them to logs.

## Result template

```text
Date / operator / commit:
OS / architecture:
App launch: packaged | source
Backend / model / cold-warm / VAD / prompt / post-process:
Input device and permissions:

Case results (three repeats each): PASS | FAIL
question_kadoka:       ___ / 3, ending preserved: ___
question_deshouka:     ___ / 3, ending preserved: ___
question_masenka:      ___ / 3, ending preserved: ___
particle_ne:           ___ / 3, ending preserved: ___
particle_yo:           ___ / 3, ending preserved: ___
declarative:           ___ / 3, no question ending: ___

Text insertion / cancel-restart / crash-hang: PASS | FAIL
Logs contain speech or secrets: YES | NO
Overall platform result: PASS | FAIL | NOT_RUN
Blocker or redacted notes:
```

This gate is intentionally separate from the deterministic backend benchmark:
the latter can demonstrate prompt and post-processing behavior, but cannot
prove microphone permissions, real-user acoustics, GUI insertion, or packaged
application recovery.
