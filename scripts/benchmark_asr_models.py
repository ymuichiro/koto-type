#!/usr/bin/env python3

import argparse
import json
import math
import statistics
import subprocess
import sys
import time
import wave
from dataclasses import asdict, dataclass
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_SHORT_AUDIO = REPO_ROOT / "assets" / "audio" / "test_speech_ja.wav"
DEFAULT_LONG_AUDIO = REPO_ROOT / "assets" / "audio" / "test_speech_ja_300s.wav"
DEFAULT_OUTPUT = REPO_ROOT / "artifacts" / "benchmarks" / "asr_benchmark_results.json"


MODEL_CONFIGS = [
    {
        "label": "faster-whisper-large-v3-turbo-cpu-int8",
        "backend": "faster-whisper",
        "model_id": "large-v3-turbo",
        "device": "cpu",
        "compute_type": "int8",
    },
    {
        "label": "mlx-whisper-large-v3-turbo",
        "backend": "mlx-whisper",
        "model_id": "mlx-community/whisper-large-v3-turbo",
    },
    {
        "label": "mlx-whisper-large-v3-turbo-fp16",
        "backend": "mlx-whisper",
        "model_id": "mlx-community/whisper-large-v3-turbo-fp16",
    },
]


COMMON_TRANSCRIBE_KWARGS = {
    "task": "transcribe",
    "temperature": 0.0,
    "word_timestamps": False,
}


def transcribe_kwargs(language: str) -> dict:
    return {
        **COMMON_TRANSCRIBE_KWARGS,
        "language": None if language == "auto" else language,
    }


def faster_whisper_transcribe_kwargs(language: str) -> dict:
    return {**transcribe_kwargs(language), "beam_size": 1, "best_of": 1}


@dataclass
class WorkerResult:
    label: str
    backend: str
    model_id: str
    audio_seconds: float
    load_seconds: float
    cold_total_seconds: float
    warm_run_seconds: list[float]
    transcript_chars: int
    transcript_preview: str
    requested_language: str
    detected_language: str | None = None
    language_probability: float | None = None


@dataclass(frozen=True)
class BenchmarkCase:
    name: str
    audio_path: Path


def audio_duration_seconds(audio_path: Path) -> float:
    with wave.open(str(audio_path), "rb") as wav_file:
        return wav_file.getnframes() / float(wav_file.getframerate())


def ensure_long_audio(input_path: Path, output_path: Path, target_seconds: int) -> Path:
    if output_path.exists():
        current_seconds = audio_duration_seconds(output_path)
        if current_seconds >= target_seconds:
            return output_path

    output_path.parent.mkdir(parents=True, exist_ok=True)

    with wave.open(str(input_path), "rb") as input_wav:
        params = input_wav.getparams()
        input_frames = input_wav.readframes(input_wav.getnframes())
        input_seconds = params.nframes / float(params.framerate)

    repeats = max(1, math.ceil(target_seconds / input_seconds))

    with wave.open(str(output_path), "wb") as output_wav:
        output_wav.setparams(params)
        for _ in range(repeats):
            output_wav.writeframes(input_frames)

    return output_path


def faster_whisper_prepare(model_config: dict, audio_path: Path, language: str) -> None:
    from faster_whisper import WhisperModel

    model = WhisperModel(
        model_config["model_id"],
        device=model_config["device"],
        compute_type=model_config["compute_type"],
    )
    segments, _ = model.transcribe(
        str(audio_path), **faster_whisper_transcribe_kwargs(language)
    )
    list(segments)


def faster_whisper_benchmark(
    model_config: dict, audio_path: Path, warm_runs: int, language: str
) -> WorkerResult:
    from faster_whisper import WhisperModel

    audio_seconds = audio_duration_seconds(audio_path)

    cold_started_at = time.perf_counter()
    load_started_at = cold_started_at
    model = WhisperModel(
        model_config["model_id"],
        device=model_config["device"],
        compute_type=model_config["compute_type"],
    )
    load_seconds = time.perf_counter() - load_started_at

    transcribe_options = faster_whisper_transcribe_kwargs(language)
    segments, info = model.transcribe(str(audio_path), **transcribe_options)
    cold_segments = list(segments)
    cold_total_seconds = time.perf_counter() - cold_started_at

    warm_run_seconds = []
    last_text = ""
    for _ in range(warm_runs):
        run_started_at = time.perf_counter()
        segments, info = model.transcribe(str(audio_path), **transcribe_options)
        warm_segments = list(segments)
        warm_run_seconds.append(time.perf_counter() - run_started_at)
        last_text = " ".join(segment.text for segment in warm_segments).strip()

    cold_text = " ".join(segment.text for segment in cold_segments).strip()
    preview = (last_text or cold_text)[:120]

    return WorkerResult(
        label=model_config["label"],
        backend=model_config["backend"],
        model_id=model_config["model_id"],
        audio_seconds=audio_seconds,
        load_seconds=load_seconds,
        cold_total_seconds=cold_total_seconds,
        warm_run_seconds=warm_run_seconds,
        transcript_chars=len(last_text or cold_text),
        transcript_preview=preview,
        requested_language=language,
        detected_language=getattr(info, "language", None),
        language_probability=getattr(info, "language_probability", None),
    )


def mlx_whisper_prepare(model_config: dict, audio_path: Path, language: str) -> None:
    import mlx_whisper

    mlx_whisper.transcribe(
        str(audio_path),
        path_or_hf_repo=model_config["model_id"],
        **transcribe_kwargs(language),
    )


def mlx_whisper_benchmark(
    model_config: dict, audio_path: Path, warm_runs: int, language: str
) -> WorkerResult:
    import mlx_whisper

    audio_seconds = audio_duration_seconds(audio_path)

    cold_started_at = time.perf_counter()
    load_started_at = cold_started_at
    transcribe_options = transcribe_kwargs(language)
    cold_result = mlx_whisper.transcribe(
        str(audio_path),
        path_or_hf_repo=model_config["model_id"],
        **transcribe_options,
    )
    cold_total_seconds = time.perf_counter() - cold_started_at

    # mlx-whisper loads lazily on the first transcribe call, so separate load time cannot be isolated
    # without reaching into internal package state. Keep the field for a consistent report shape.
    load_seconds = time.perf_counter() - load_started_at

    warm_run_seconds = []
    last_text = ""
    last_result = cold_result
    for _ in range(warm_runs):
        run_started_at = time.perf_counter()
        warm_result = mlx_whisper.transcribe(
            str(audio_path),
            path_or_hf_repo=model_config["model_id"],
            **transcribe_options,
        )
        warm_run_seconds.append(time.perf_counter() - run_started_at)
        last_text = warm_result.get("text", "").strip()
        last_result = warm_result

    cold_text = cold_result.get("text", "").strip()
    preview = (last_text or cold_text)[:120]

    return WorkerResult(
        label=model_config["label"],
        backend=model_config["backend"],
        model_id=model_config["model_id"],
        audio_seconds=audio_seconds,
        load_seconds=load_seconds,
        cold_total_seconds=cold_total_seconds,
        warm_run_seconds=warm_run_seconds,
        transcript_chars=len(last_text or cold_text),
        transcript_preview=preview,
        requested_language=language,
        detected_language=(last_result or cold_result).get("language"),
        language_probability=(last_result or cold_result).get("language_probability"),
    )


def run_prepare(model_config: dict, audio_path: Path, language: str) -> None:
    if model_config["backend"] == "faster-whisper":
        faster_whisper_prepare(model_config, audio_path, language)
        return
    if model_config["backend"] == "mlx-whisper":
        mlx_whisper_prepare(model_config, audio_path, language)
        return
    raise ValueError(f"Unsupported backend: {model_config['backend']}")


def run_worker(
    model_config: dict, audio_path: Path, warm_runs: int, language: str
) -> WorkerResult:
    if model_config["backend"] == "faster-whisper":
        return faster_whisper_benchmark(model_config, audio_path, warm_runs, language)
    if model_config["backend"] == "mlx-whisper":
        return mlx_whisper_benchmark(model_config, audio_path, warm_runs, language)
    raise ValueError(f"Unsupported backend: {model_config['backend']}")


def resolve_model(label: str) -> dict:
    for model in MODEL_CONFIGS:
        if model["label"] == label:
            return model
    raise ValueError(f"Unknown model label: {label}")


def run_subprocess(args: list[str]) -> dict:
    completed = subprocess.run(
        [
            str(REPO_ROOT / ".venv" / "bin" / "python"),
            str(Path(__file__).resolve()),
            *args,
        ],
        cwd=str(REPO_ROOT),
        capture_output=True,
        text=True,
    )
    if completed.returncode != 0:
        raise RuntimeError(
            completed.stderr.strip() or completed.stdout.strip() or "subprocess failed"
        )
    return json.loads(completed.stdout)


def summarize_case(case_name: str, rows: list[dict]) -> None:
    print(f"\n[{case_name}]")
    print(
        "label".ljust(40),
        "cold(s)".rjust(10),
        "warm_avg(s)".rjust(12),
        "audio(s)".rjust(10),
        "warm_rtf".rjust(10),
    )
    for row in rows:
        if "error" in row:
            print(
                row["label"].ljust(40),
                "ERROR".rjust(10),
                "-".rjust(12),
                f"{row.get('audio_seconds', 0.0):.2f}".rjust(10),
                "-".rjust(10),
            )
            continue
        print(
            row["label"].ljust(40),
            f"{row['cold_total_seconds']:.2f}".rjust(10),
            f"{row['warm_average_seconds']:.2f}".rjust(12),
            f"{row['audio_seconds']:.2f}".rjust(10),
            f"{row['warm_rtf']:.3f}".rjust(10),
        )


def safe_error_summary(error: Exception) -> str:
    final_line = next(
        (line.strip() for line in reversed(str(error).splitlines()) if line.strip()),
        "benchmark subprocess failed",
    )
    return type(error).__name__ if "/" in final_line else final_line[:200]


def benchmark(
    short_audio: Path,
    long_audio: Path,
    warm_runs: int,
    output_path: Path,
    language: str,
) -> dict:
    cases = [
        BenchmarkCase(name="short", audio_path=short_audio),
        BenchmarkCase(name="long", audio_path=long_audio),
    ]

    results = {
        "host": {
            "python": sys.version,
            "platform": sys.platform,
        },
        "common_transcribe_kwargs": transcribe_kwargs(language),
        "faster_whisper_transcribe_kwargs": faster_whisper_transcribe_kwargs(language),
        "requested_language": language,
        "warm_runs": warm_runs,
        "cases": [],
    }

    for case in cases:
        case_rows = []
        for model in MODEL_CONFIGS:
            try:
                print(
                    f"Preparing {model['label']} for {case.name} audio...",
                    file=sys.stderr,
                )
                run_subprocess(
                    [
                        "--mode",
                        "prepare",
                        "--model-label",
                        model["label"],
                        "--audio-path",
                        str(case.audio_path),
                        "--language",
                        language,
                    ]
                )

                print(
                    f"Benchmarking {model['label']} for {case.name} audio...",
                    file=sys.stderr,
                )
                row = run_subprocess(
                    [
                        "--mode",
                        "worker",
                        "--model-label",
                        model["label"],
                        "--audio-path",
                        str(case.audio_path),
                        "--language",
                        language,
                        "--warm-runs",
                        str(warm_runs),
                    ]
                )
                warm_average_seconds = statistics.mean(row["warm_run_seconds"])
                row["warm_average_seconds"] = warm_average_seconds
                row["warm_rtf"] = warm_average_seconds / row["audio_seconds"]
                row["cold_rtf"] = row["cold_total_seconds"] / row["audio_seconds"]
            except RuntimeError as error:
                row = {
                    "label": model["label"],
                    "backend": model["backend"],
                    "model_id": model["model_id"],
                    "audio_seconds": audio_duration_seconds(case.audio_path),
                    "requested_language": language,
                    "error": safe_error_summary(error),
                }
            case_rows.append(row)

        results["cases"].append({"name": case.name, "rows": case_rows})
        summarize_case(case.name, case_rows)

    output_path.parent.mkdir(parents=True, exist_ok=True)
    output_path.write_text(
        json.dumps(results, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    return results


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--mode", choices=["benchmark", "prepare", "worker"], default="benchmark"
    )
    parser.add_argument("--model-label")
    parser.add_argument("--audio-path", type=Path)
    parser.add_argument("--short-audio", type=Path, default=DEFAULT_SHORT_AUDIO)
    parser.add_argument("--long-audio", type=Path, default=DEFAULT_LONG_AUDIO)
    parser.add_argument("--long-seconds", type=int, default=300)
    parser.add_argument("--warm-runs", type=int, default=3)
    parser.add_argument("--language", choices=["auto", "ja"], default="ja")
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    if args.mode == "benchmark":
        long_audio = ensure_long_audio(
            args.short_audio, args.long_audio, args.long_seconds
        )
        benchmark(
            args.short_audio,
            long_audio,
            args.warm_runs,
            args.output,
            args.language,
        )
        return

    if not args.model_label or not args.audio_path:
        raise SystemExit(
            "--model-label and --audio-path are required for prepare/worker mode"
        )

    model_config = resolve_model(args.model_label)

    if args.mode == "prepare":
        run_prepare(model_config, args.audio_path, args.language)
        print(json.dumps({"status": "ok"}))
        return

    result = run_worker(model_config, args.audio_path, args.warm_runs, args.language)
    print(json.dumps(asdict(result), ensure_ascii=False))


if __name__ == "__main__":
    main()
