# Whisper Backend Compatibility

This note records runtime compatibility testing between the current CPU path and the MLX path before any app integration work.

## Scope

- Existing backend: `faster-whisper large-v3-turbo` on CPU with `int8`
- Candidate backend: `mlx-community/whisper-large-v3-turbo`
- Test method: script-based runtime checks using the current server-style parameters as the baseline

## Commands

```bash
.venv/bin/python scripts/check_whisper_backend_compatibility.py
```

## Latest local run

- Date: 2026-04-23
- Host: Apple M4 Pro, 24 GB RAM, macOS 26.3.1
- Input audio: `assets/audio/test_speech_ja.wav`
- Raw output: `artifacts/benchmarks/whisper_backend_compatibility.json`

## Compatibility matrix

| Setting or case | faster-whisper CPU | MLX | Notes |
| --- | --- | --- | --- |
| `language="ja"` | OK | OK | Shared |
| `language=None` | OK | OK | Shared, but both backends detected `en` on this 3-second sample |
| `task="transcribe"` | OK | OK | Shared |
| `task="translate"` | OK | OK | Runtime-compatible, but this short sample returned empty text on both backends |
| `temperature=0.0` | OK | OK | Shared |
| `word_timestamps=True` | OK | OK | Shared |
| `initial_prompt` | OK | OK | Shared |
| `no_speech_threshold=0.6` | OK | OK | Shared |
| `compression_ratio_threshold=2.4` | OK | OK | Shared |
| `beam_size=1` | OK | Error | MLX raises `NotImplementedError: Beam search decoder is not yet implemented` |
| `beam_size=5` | OK | Error | Same limitation |
| `best_of=5`, `temperature=0.0` | OK | OK | Runtime-compatible, but MLX drops `best_of` in the deterministic path |
| `best_of=5`, `temperature=0.2` | OK | OK | Runtime-compatible |
| `vad_filter=True` | OK | Error | MLX raises `TypeError` for unsupported `vad_filter` |
| `vad_parameters={...}` | OK | Error | Same limitation through the unsupported VAD path |
| Current server defaults as a whole | OK | Error | Fails on MLX because the current request shape includes built-in VAD and beam search |

## Result buckets

### Shared as-is

- `language`
- `task`
- `temperature`
- `word_timestamps`
- `initial_prompt`
- `no_speech_threshold`
- `compression_ratio_threshold`

### Shared with caveats

- `language=None`
  Both backends accepted it, but the sample auto-detected as English. This is a quality caveat, not a backend mismatch.
- `best_of`
  The runtime accepted it on MLX, but MLX removes `best_of` when `temperature == 0.0`. That means it is not a stable cross-backend control for deterministic decoding.
- `task="translate"`
  Accepted by both, but this test did not validate output quality.

### Not shared

- `beam_size`
  MLX does not currently implement beam search.
- `vad_filter`
  MLX does not expose faster-whisper-style built-in VAD.
- `vad_parameters`
  Same as above. This cannot remain a raw pass-through option if MLX is supported.

## Design direction

- Keep a backend-agnostic request shape at the app boundary
- Add a backend capability layer in Python that maps or strips unsupported parameters
- Treat VAD and decode strategy as backend-specific capabilities rather than assuming full 1:1 parity
- Introduce backend presets if preserving the current raw parameter list creates fragile branching logic

## Proposed preset direction

### Shared request fields

These can stay in a common request model because both backends can execute them:

- `language`
- `task`
- `temperature`
- `word_timestamps`
- `initial_prompt`
- `no_speech_threshold`
- `compression_ratio_threshold`

### Backend-only fields

These should move out of the shared request contract and into backend presets or capability-specific mapping:

- `beam_size`
- `best_of`
- `vad_filter`
- `vad_parameters`

### Preset sketch

- `cpu_default`
  Keep the current behavior: `beam_size=5`, `best_of=5`, built-in VAD enabled with the current thresholds.
- `mlx_default`
  Use MLX-compatible greedy decoding, omit `beam_size`, and do not pass built-in VAD arguments.
- `shared_safe`
  Use only the shared request fields. This is the interoperability baseline and the simplest fallback preset for tests.

## Risk assessment

- High: decode-strategy mismatch
  The current CPU path relies on beam search by default, while MLX currently does not support it. This is the main incompatibility and the strongest reason to introduce backend presets.
- High: VAD mismatch
  The current CPU path uses built-in VAD parameters. MLX does not accept these options, so silence handling cannot be treated as a shared backend toggle.
- Medium: semantic drift in `best_of`
  The parameter is accepted by both runtimes, but not with identical behavior in deterministic decoding.
- Medium: auto language detection quality
  Runtime compatibility exists, but the short sample misdetected language on both backends. Presets should not rely on auto-detect quality without broader evaluation.
