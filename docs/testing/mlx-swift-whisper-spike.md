# MLX Swift Whisper parity spike (Issue 90)

This is a developer-only feasibility spike. It is a separate Swift package and
executable; it is not part of the KotoType app target, release bundle, Python
server, PyInstaller build, or default runtime path.
It has no dependency on the Issue 89 voice prompt-authoring work.

## Current gate result

**No-Go for Swift ASR parity and Python replacement.** The official MLX Swift
package provides the MLX array/runtime API, but does not provide a drop-in
Whisper decoder. The official MLX Whisper implementation remains a Python
example/package. This spike therefore stops at the smallest useful boundary:
native MLX package/runtime loading plus the existing worker health and JSON-line
contract. It does not invent a second Whisper implementation.

The spike package currently resolves MLX Swift `0.31.6` from the declared
`>=0.31.3,<1.0` range. MLX Swift requires macOS 14 for this package, while the
app remains macOS 13-compatible; keeping the package separate avoids changing
the product deployment target.

## What is implemented

- `experiments/mlx-swift-whisper-spike/` is a separate macOS 14 Swift package.
- `mlx-swift-whisper-spike --probe` checks the developer flag and executes one
  native MLX array evaluation.
- The worker accepts the existing health-check prefix and
  `transcription_request` JSON lines.
- The feature is disabled unless
  `KOTOTYPE_ENABLE_EXPERIMENTAL_SWIFT_ASR=1` is set.
- Unsupported transcription requests return an empty stdout line, preserving
  the existing worker completion contract; the reason is written to stderr.
- `scripts/benchmark_swift_whisper_spike.py` runs the same short/long corpus
  inputs and records contract latency, exit status, diagnostics, and child RSS.
  It deliberately marks the result `not_comparable` because no transcript is
  produced.

## Commands

Run protocol tests:

```bash
make test-swift-mlx-spike
```

Build the executable with SwiftPM:

```bash
cd experiments/mlx-swift-whisper-spike
swift build --product mlx-swift-whisper-spike
```

Probe with the feature disabled and enabled:

```bash
experiments/mlx-swift-whisper-spike/.build/arm64-apple-macosx/debug/mlx-swift-whisper-spike --probe
KOTOTYPE_ENABLE_EXPERIMENTAL_SWIFT_ASR=1 \
  experiments/mlx-swift-whisper-spike/.build/arm64-apple-macosx/debug/mlx-swift-whisper-spike --probe
```

Generate evidence against the repository corpus:

```bash
make benchmark-swift-mlx-spike
```

The output is written to
`artifacts/benchmarks/swift_whisper_spike.json`. The existing Python CPU/MLX
baseline remains in `artifacts/benchmarks/asr_benchmark_results.json` and is
the reference for a future dual-run once Swift can produce text.

For Metal shader and release-style package validation, use the Xcode scheme
provided by the resolved official MLX Swift checkout:

```bash
cd experiments/mlx-swift-whisper-spike/.build/checkouts/mlx-swift
xcodebuild -scheme mlx-swift-Package \
  -destination 'platform=macOS' build
```

SwiftPM command-line builds are useful for the source/test gate, but official
MLX Swift documentation says Metal shaders require an Xcode/xcodebuild build.
On the validation host this command was attempted with `test` and stopped
because Xcode reported that the Metal Toolchain component is not installed;
the missing component must be installed in Xcode before the native runtime
probe can be considered passed.

## Parity matrix

| Area | Spike status | Gate decision |
| --- | --- | --- |
| Native MLX Swift package/runtime | Implemented and probeable | Build/runtime feasibility only |
| Health check and JSONL worker lifecycle | Implemented and unit-tested | Contract shape preserved |
| Transcribe-only Whisper inference | Not implemented | No comparison possible |
| Japanese/multilingual WER/CER | Not measured | No-Go |
| Translation | Unsupported | No-Go |
| `initial_prompt`, dictionary, screen context | Unsupported | No-Go |
| Segments, timestamps, confidence metrics | Unsupported | No-Go |
| Active clip, VAD, low-activity skip, retry, fallback | Unsupported | No-Go |
| Cancellation, long/noisy/silent audio behavior | Not measured as ASR | No-Go |
| Model download/cache/offline lifecycle | Not implemented | No-Go |
| Peak memory under a loaded Whisper model | Not measured | No-Go |
| App integration/recovery/circuit breaker | Not changed | Existing path protected |
| macOS 13/Intel support | Not supported by spike package | Python path retained |
| Release bundle/CI/signing impact | Not integrated | No release impact in this PR |

The Python CPU and Python MLX paths, FFmpeg preprocessing, PyInstaller server,
and all existing user behavior remain unchanged. Python removal is a separate
No-Go until the full parity, CPU/Intel policy, memory, lifecycle, recovery,
and release gates are proven.

## Refreshed Python baseline

The existing benchmark was rerun on 2026-08-04 using the repository corpus,
three warm runs, Python 3.13.7, macOS 26.5.2, Apple Silicon `Mac16,11`, and
24 GiB RAM:

| Input | Python CPU warm average | Python MLX warm average | CPU transcript | MLX transcript |
| --- | ---: | ---: | --- | --- |
| 3 s short | 4.077 s (RTF 1.359) | 0.488 s (RTF 0.163) | 14 chars | 14 chars |
| 300 s long | 45.688 s (RTF 0.152) | 4.786 s (RTF 0.016) | repeated sample | repeated sample |

The checked-in baseline artifact is
`artifacts/benchmarks/asr_benchmark_results.json`. The fp16 MLX candidate
still fails the existing loader because its cached weights are not in the
expected MLX-readable format. These results are Python CPU-vs-Python MLX
evidence only; they do not imply Swift parity.

The Swift harness generated
`artifacts/benchmarks/swift_whisper_spike.json`: both short and long requests
passed the health check and completed with `status=unsupported`, while the
enabled native probe exited 255 because `default.metallib` was unavailable.
The observed worker RSS was about 25.5 MiB, but this is process startup
overhead without a Whisper model and is not a model-memory measurement.

## Official constraints checked

- [MLX Swift](https://github.com/ml-explore/mlx-swift) documents SwiftPM and
  Xcode integration and notes that SwiftPM cannot build Metal shaders.
- [MLX Whisper](https://github.com/ml-explore/mlx-examples/tree/main/whisper)
  documents the Whisper implementation as Python (`mlx-whisper`), not a Swift
  decoder package.
- The package deployment target is macOS 14 because the resolved MLX Swift
  product requires it; the application target is intentionally not raised.
