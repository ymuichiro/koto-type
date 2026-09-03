# Issue #101: nonverbal and silence hallucination diagnostic

This diagnostic reuses `tools/evaluate_noise_strategies.py` to measure false
insertions separately from dropped speech. It does not change Whisper decode
or confidence thresholds without a measured improvement.

Run a reproducible MLX screen with an already-downloaded model:

```bash
uv run python tools/evaluate_noise_strategies.py \
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
Compare the same corpus on CPU and MLX where both models are available. A
threshold or decode change is eligible only when it lowers false insertions
without increasing dropped utterances or worsening the existing ending-fidelity
cases. Keep temporary audio and result artifacts local.
