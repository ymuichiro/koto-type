# ASR Local Benchmark Notes

This note is used to capture local benchmark results for standalone ASR experiments before any app integration work.

## Scope

- Compare the current `faster-whisper` baseline against MLX-based candidates on Apple Silicon.
- Measure both short-form and long-form transcription latency.
- Keep the benchmark script-based and isolated from the app runtime.

## Current command

```bash
.venv/bin/python scripts/benchmark_asr_models.py
```

## Notes

- Short audio defaults to `assets/audio/test_speech_ja.wav`
- Long audio defaults to a generated 300-second WAV derived from the short audio sample
- Results are written to `artifacts/benchmarks/asr_benchmark_results.json`
- `mlx-whisper` does not currently support beam search, so the shared benchmark uses greedy decoding

## Latest local run

- Date: 2026-04-21
- Host: Apple M4 Pro, 24 GB RAM, macOS 26.3.1
- Python: 3.13.7 (`.venv`)
- Baseline: `faster-whisper large-v3-turbo` on CPU with `int8`
- MLX candidate: `mlx-community/whisper-large-v3-turbo`
- MLX fp16 candidate: `mlx-community/whisper-large-v3-turbo-fp16`

### Short audio (3 seconds)

- `faster-whisper-large-v3-turbo-cpu-int8`: cold `5.40s`, warm avg `4.10s`, warm RTF `1.368`
- `mlx-whisper-large-v3-turbo`: cold `0.91s`, warm avg `0.52s`, warm RTF `0.173`
- Speedup vs baseline: about `7.9x` on warm runs

### Long audio (300 seconds)

- `faster-whisper-large-v3-turbo-cpu-int8`: cold `46.67s`, warm avg `45.70s`, warm RTF `0.152`
- `mlx-whisper-large-v3-turbo`: cold `5.52s`, warm avg `5.23s`, warm RTF `0.017`
- Speedup vs baseline: about `8.7x` on warm runs

### fp16 model status

- `mlx-community/whisper-large-v3-turbo-fp16` failed to load with `mlx-whisper 0.4.3`
- Observed error: `ValueError: [load_npz] Input must be a zip file...`
- The cached repo contains `model.safetensors`, while the tested `mlx-whisper` loader expects MLX weight files it can read with `mx.load`
