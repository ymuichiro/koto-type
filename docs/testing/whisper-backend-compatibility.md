# Historical Whisper Backend Compatibility

This is an archival summary of a direct-library probe run on 2026-04-23, before app integration. Its 296-line runner and raw JSON output were removed under Issue #132: the runner had no Make, CI, test, or product callsites; it called the libraries directly rather than KotoType's request path; and it included `task="translate"`, which the product no longer offers.

## Evidence limits

The input was `assets/audio/test_speech_ja.wav`, a three-second 440 Hz tone, not Japanese speech. Language detection as English, empty translation output, or prompt-generated text on that input says nothing about Japanese recognition or translation quality. The raw output also contained transcript previews and machine-local paths, so only the summarized compatibility facts are retained here.

## Historical observations

| Option | faster-whisper CPU | MLX | Limit |
| --- | --- | --- | --- |
| `language`, `task="transcribe"`, temperature, timestamps, prompt, no-speech and compression thresholds | Accepted | Accepted | API acceptance only |
| `task="translate"` | Accepted | Accepted | Product feature retired; output was empty on this non-speech input |
| `beam_size` | Accepted | Unsupported | MLX raised `NotImplementedError` |
| `vad_filter` / `vad_parameters` | Accepted | Unsupported | MLX raised `TypeError` |
| `best_of` with deterministic decoding | Accepted | Accepted but ignored | Not equivalent behavior |

These results describe old library versions and direct calls only. They are not a current compatibility guarantee, product-path test, or quality result. Reintroduce an executable matrix only when a dependency change or a reproducible product-path failure requires it.
