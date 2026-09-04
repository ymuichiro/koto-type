# Issue #101: nonverbal and silence hallucination diagnostic

This diagnostic reuses `tools/evaluate_noise_strategies.py` to measure false
insertions separately from dropped speech. It does not change Whisper decode
or confidence thresholds without a measured improvement.

Run a reproducible screen with an already-downloaded MLX model:

```bash
uv run python tools/evaluate_noise_strategies.py \
  --strategies ffmpeg_office_gate \
  --repetitions 1
```

Run the release-equivalent CPU fallback with its managed local model (or set
`KOTOTYPE_CPU_MODEL_DIR` to an already-downloaded model directory):

```bash
uv run python tools/evaluate_noise_strategies.py \
  --backend cpu \
  --strategies ffmpeg_office_gate \
  --repetitions 1
```

The generated local-only cases include silence, steady-tone noise, keyboard
noise, cough-like and laughter-like synthetic burst proxies, and the short
Japanese acknowledgement `はい`. The nonverbal burst cases are intentionally
synthetic proxies, not human recordings; they provide a regression screen but
do not establish real-world cough or laughter accuracy.

Evaluate false insertion rate on empty-reference cases, dropped utterance rate
and CER on speech cases, and p95 latency/mean realtime factor for performance.
Compare the same corpus on CPU and MLX where both models are available. The CPU
path uses the application equivalent medium decode profile, VAD fallback, and
confidence gate inputs; the MLX path remains a separate runtime measurement. A
threshold or decode change is eligible only when it lowers false insertions
without increasing dropped utterances or worsening the existing ending-fidelity
cases. Keep temporary audio and result artifacts local.

## CPU and MLX baseline (2026-09-04)

The release-equivalent CPU fallback and MLX path were evaluated once on the 15
generated cases using the same Japanese language setting. CPU uses
`large-v3-turbo` int8, medium decode profile, and VAD fallback. These are local
synthetic regression results, not claims about microphone accuracy.

| backend | strategy | false insertion | dropped utterance | mean CER | p95 latency |
|---|---|---:|---:|---:|---:|
| CPU | `ffmpeg_office` | 37.5% | 14.3% | 47.6% | 4.54s |
| CPU | `ffmpeg_office_gate` | 12.5% | 14.3% | 47.6% | 4.55s |
| MLX | `ffmpeg_office` | 100.0% | 0.0% | 34.3% | 0.57s |
| MLX | `ffmpeg_office_gate` | 37.5% | 0.0% | 34.3% | 0.57s |

The current gate reduced synthetic non-speech false insertions without changing
the measured short-utterance drop rate or CER. No threshold or decode change
was made.

### Public non-speech spot check

As a non-bundled, temporary-only check, two clips each of coughing, laughing,
and keyboard typing were evaluated from the [ESC-50 dataset](https://github.com/karolpiczak/ESC-50).
ESC-50 provides five-second labeled environmental recordings and is licensed
CC BY-NC; no clip or transcript is stored in this repository or its artifacts.
This six-clip spot check is not a microphone, GUI, or real-world prevalence
measurement.

| backend | strategy | false insertion on six non-speech clips |
|---|---|---:|
| CPU | `ffmpeg_office` | 0.0% |
| CPU | `ffmpeg_office_gate` | 0.0% |
| MLX | `ffmpeg_office` | 100.0% |
| MLX | `ffmpeg_office_gate` | 33.3% |

Real microphone and GUI E2E remain separate manual gates.
