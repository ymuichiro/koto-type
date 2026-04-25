#!/usr/bin/env python3

import json
import traceback
from dataclasses import dataclass
from pathlib import Path
from typing import Any


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_AUDIO = REPO_ROOT / "assets" / "audio" / "test_speech_ja.wav"
OUTPUT_PATH = (
    REPO_ROOT / "artifacts" / "benchmarks" / "whisper_backend_compatibility.json"
)

CURRENT_DEFAULT_PROMPT = "これは会話の文字起こしです。正確な日本語で出力してください。"
CURRENT_VAD_PARAMETERS = {
    "threshold": 0.57,
    "min_speech_duration_ms": 320,
    "min_silence_duration_ms": 700,
    "speech_pad_ms": 80,
}


FAST_MODEL_CONFIG = {
    "backend": "faster-whisper",
    "label": "faster-whisper-large-v3-turbo-cpu-int8",
    "model_id": "large-v3-turbo",
    "device": "cpu",
    "compute_type": "int8",
}

MLX_MODEL_CONFIG = {
    "backend": "mlx-whisper",
    "label": "mlx-whisper-large-v3-turbo",
    "model_id": "mlx-community/whisper-large-v3-turbo",
}


@dataclass
class BackendResult:
    status: str
    transcript_preview: str | None = None
    detected_language: str | None = None
    error_type: str | None = None
    error_message: str | None = None


TEST_CASES = [
    {
        "id": "current_server_defaults",
        "description": "Current server-style defaults, including beam search and VAD.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.0,
            "beam_size": 5,
            "best_of": 5,
            "word_timestamps": False,
            "initial_prompt": CURRENT_DEFAULT_PROMPT,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
            "vad_filter": True,
            "vad_parameters": CURRENT_VAD_PARAMETERS,
        },
    },
    {
        "id": "common_core_defaults",
        "description": "Cross-backend core settings without beam search or VAD.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.0,
            "word_timestamps": False,
            "initial_prompt": CURRENT_DEFAULT_PROMPT,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "language_auto",
        "description": "Auto language detection by passing language=None.",
        "kwargs": {
            "language": None,
            "task": "transcribe",
            "temperature": 0.0,
            "word_timestamps": False,
            "initial_prompt": None,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "task_translate",
        "description": "Translate task with explicit Japanese input.",
        "kwargs": {
            "language": "ja",
            "task": "translate",
            "temperature": 0.0,
            "word_timestamps": False,
            "initial_prompt": None,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "word_timestamps_enabled",
        "description": "Word timestamp extraction enabled.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.0,
            "word_timestamps": True,
            "initial_prompt": None,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "beam_size_1",
        "description": "Explicit beam_size=1.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.0,
            "beam_size": 1,
            "word_timestamps": False,
            "initial_prompt": None,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "beam_size_5",
        "description": "Explicit beam_size=5.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.0,
            "beam_size": 5,
            "word_timestamps": False,
            "initial_prompt": None,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "best_of_5_temperature_zero",
        "description": "best_of=5 under deterministic decoding.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.0,
            "best_of": 5,
            "word_timestamps": False,
            "initial_prompt": None,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "best_of_5_temperature_sampling",
        "description": "best_of=5 under sampling temperature.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.2,
            "best_of": 5,
            "word_timestamps": False,
            "initial_prompt": None,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "initial_prompt_enabled",
        "description": "Initial prompt enabled with the current Japanese base prompt.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.0,
            "word_timestamps": False,
            "initial_prompt": CURRENT_DEFAULT_PROMPT,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
        },
    },
    {
        "id": "vad_filter_enabled",
        "description": "Built-in VAD enabled with the current server-style parameters.",
        "kwargs": {
            "language": "ja",
            "task": "transcribe",
            "temperature": 0.0,
            "word_timestamps": False,
            "initial_prompt": None,
            "no_speech_threshold": 0.6,
            "compression_ratio_threshold": 2.4,
            "vad_filter": True,
            "vad_parameters": CURRENT_VAD_PARAMETERS,
        },
    },
]


def run_faster_whisper(audio_path: Path, kwargs: dict[str, Any]) -> BackendResult:
    from faster_whisper import WhisperModel

    model = WhisperModel(
        FAST_MODEL_CONFIG["model_id"],
        device=FAST_MODEL_CONFIG["device"],
        compute_type=FAST_MODEL_CONFIG["compute_type"],
    )
    segments, info = model.transcribe(str(audio_path), **kwargs)
    segment_list = list(segments)
    transcript = " ".join(segment.text for segment in segment_list).strip()
    return BackendResult(
        status="ok",
        transcript_preview=transcript[:120],
        detected_language=getattr(info, "language", None),
    )


def run_mlx_whisper(audio_path: Path, kwargs: dict[str, Any]) -> BackendResult:
    import mlx_whisper

    mlx_kwargs = dict(kwargs)
    result = mlx_whisper.transcribe(
        str(audio_path),
        path_or_hf_repo=MLX_MODEL_CONFIG["model_id"],
        **mlx_kwargs,
    )
    return BackendResult(
        status="ok",
        transcript_preview=result.get("text", "").strip()[:120],
        detected_language=result.get("language"),
    )


def execute_case(audio_path: Path, case: dict[str, Any]) -> dict[str, Any]:
    row = {
        "id": case["id"],
        "description": case["description"],
        "kwargs": case["kwargs"],
    }

    for label, runner in (
        ("faster_whisper_cpu", run_faster_whisper),
        ("mlx_whisper", run_mlx_whisper),
    ):
        try:
            result = runner(audio_path, case["kwargs"])
            row[label] = result.__dict__
        except Exception as error:  # noqa: BLE001
            row[label] = BackendResult(
                status="error",
                error_type=type(error).__name__,
                error_message=str(error),
            ).__dict__
            row[f"{label}_traceback"] = traceback.format_exc(limit=2)

    return row


def summarize(rows: list[dict[str, Any]]) -> None:
    print("id".ljust(34), "cpu".ljust(10), "mlx".ljust(10), "note")
    for row in rows:
        cpu = row["faster_whisper_cpu"]["status"]
        mlx = row["mlx_whisper"]["status"]
        note = ""
        if cpu == "ok" and mlx == "ok":
            note = "shared"
        elif cpu == "ok" and mlx == "error":
            note = row["mlx_whisper"]["error_type"] or "mlx_error"
        else:
            note = "inspect"
        print(row["id"].ljust(34), cpu.ljust(10), mlx.ljust(10), note)


def main() -> None:
    rows = [execute_case(DEFAULT_AUDIO, case) for case in TEST_CASES]
    payload = {
        "audio_path": str(DEFAULT_AUDIO),
        "faster_whisper_model": FAST_MODEL_CONFIG,
        "mlx_whisper_model": MLX_MODEL_CONFIG,
        "cases": rows,
    }
    OUTPUT_PATH.parent.mkdir(parents=True, exist_ok=True)
    OUTPUT_PATH.write_text(
        json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8"
    )
    summarize(rows)


if __name__ == "__main__":
    main()
