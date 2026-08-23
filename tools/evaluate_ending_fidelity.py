#!/usr/bin/env python3

"""Measure Japanese sentence-ending fidelity across backend stages.

The audio runner is intentionally opt-in. Do not commit recordings or result files;
they may contain speech content. A pre-recorded result JSON/JSONL can be evaluated
without loading an ASR model.
"""

import argparse
import itertools
import json
import sys
import time
from collections import defaultdict
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_CORPUS = REPO_ROOT / "tests" / "data" / "ending_fidelity_corpus.json"
DEFAULT_OUTPUT = REPO_ROOT / "artifacts" / "benchmarks" / "ending_fidelity_results.json"
QUESTION_MARKS = ("？", "?")
PUNCTUATION = ("。", "！", "？", ".", "!", "?")
BASELINE_PROMPT = (
    "Verbatim transcription. Preserve the original spoken wording and language as much as possible. "
    "Keep code-switching, proper nouns, acronyms, product names, and technical terms in the form they "
    "were spoken. Do not translate, summarize, or rewrite into another language."
)


def load_corpus(path: Path) -> dict[str, dict]:
    path = Path(path)
    rows = json.loads(path.read_text(encoding="utf-8"))
    return {row["id"]: row for row in rows}


def load_result_rows(path: Path) -> list[dict]:
    text = path.read_text(encoding="utf-8").strip()
    if not text:
        return []
    if text.startswith("[") or text.startswith("{"):
        value = json.loads(text)
        if isinstance(value, dict):
            return value.get("rows", [value])
        return value
    return [json.loads(line) for line in text.splitlines() if line.strip()]


def metric_text(value: str) -> str:
    return str(value or "").strip().rstrip("".join(PUNCTUATION)).strip()


def is_question_output(value: str) -> bool:
    stripped = str(value or "").strip()
    return stripped.endswith(QUESTION_MARKS) or metric_text(stripped).endswith("か")


def evaluate_rows(corpus: dict[str, dict], rows: list[dict]) -> dict[str, dict]:
    grouped: dict[str, list[dict]] = defaultdict(list)
    for row in rows:
        case_id = row.get("case_id")
        if not isinstance(case_id, str):
            continue
        case = corpus.get(case_id)
        if case is None:
            continue
        text = metric_text(row.get("text", ""))
        retains_ending = text.endswith(case["spoken_ending"])
        question_to_declarative = bool(
            case["question"] and not is_question_output(row.get("text", ""))
        )
        key = "/".join(
            str(row.get(name, "unknown"))
            for name in ("backend", "prompt", "vad", "post_process")
        )
        grouped[key].append(
            {
                "question": case["question"],
                "retains_ending": retains_ending,
                "question_to_declarative": question_to_declarative,
            }
        )

    metrics = {}
    for key, group in sorted(grouped.items()):
        question_count = sum(item["question"] for item in group)
        metrics[key] = {
            "sample_count": len(group),
            "ending_retention_rate": sum(item["retains_ending"] for item in group) / len(group),
            "question_to_declarative_rate": (
                sum(item["question_to_declarative"] for item in group) / question_count
                if question_count
                else 0.0
            ),
            "question_samples_observed": question_count,
        }
    return metrics


def prompt_for_mode(mode: str) -> str | None:
    if mode == "none":
        return None
    if mode == "baseline":
        return BASELINE_PROMPT
    if mode == "ending":
        from whisper_server import generate_initial_prompt

        return generate_initial_prompt("ja", use_context=False)
    raise ValueError(f"Unsupported prompt mode: {mode}")


def find_audio(audio_dir: Path, case_id: str) -> Path | None:
    for suffix in (".wav", ".mp3", ".m4a", ".aiff"):
        candidate = audio_dir / f"{case_id}{suffix}"
        if candidate.exists():
            return candidate
    return None


def run_cpu(model, audio_path: Path, prompt: str | None, use_vad: bool) -> str:
    from whisper_server import build_cpu_decode_profile, build_vad_parameters

    profile = build_cpu_decode_profile("medium")
    kwargs = {
        "language": "ja",
        "task": "transcribe",
        "temperature": profile.temperature,
        "beam_size": profile.beam_size,
        "best_of": profile.best_of,
        "word_timestamps": False,
        "condition_on_previous_text": False,
        "initial_prompt": prompt,
        "no_speech_threshold": 0.6,
        "compression_ratio_threshold": 2.4,
        "vad_filter": use_vad,
    }
    if use_vad:
        kwargs["vad_parameters"] = build_vad_parameters(profile.vad_threshold)
    segments, _ = model.transcribe(str(audio_path), **kwargs)
    return " ".join(segment.text for segment in segments).strip()


def run_mlx(mlx_whisper, model_path: str, audio_path: Path, prompt: str | None, use_vad: bool) -> str:
    from whisper_server import build_active_clip_timestamps, build_mlx_decode_profile, build_mlx_transcribe_kwargs

    profile = build_mlx_decode_profile("medium")
    kwargs = build_mlx_transcribe_kwargs(
        model_path=model_path,
        language="ja",
        profile=profile,
        initial_prompt=prompt,
    )
    if use_vad:
        clip_timestamps = build_active_clip_timestamps(str(audio_path))
        if clip_timestamps is not None:
            kwargs["clip_timestamps"] = clip_timestamps
    result = mlx_whisper.transcribe(str(audio_path), **kwargs)
    return str(result.get("text", "") or "").strip()


def run_audio_matrix(args, corpus: dict[str, dict]) -> list[dict]:
    rows = []
    cpu_model = None
    mlx_whisper = None
    if "cpu" in args.backends:
        from faster_whisper import WhisperModel

        cpu_model = WhisperModel(
            args.cpu_model,
            device="cpu",
            compute_type="int8",
            local_files_only=True,
        )
    if "mlx" in args.backends:
        import mlx_whisper as mlx_module

        mlx_whisper = mlx_module

    for backend, prompt_mode, vad_mode, post_mode in itertools.product(
        args.backends, args.prompt_modes, args.vad_modes, args.post_process_modes
    ):
        for case_id, case in corpus.items():
            audio_path = find_audio(args.audio_dir, case_id)
            if audio_path is None:
                continue
            prompt = prompt_for_mode(prompt_mode)
            started_at = time.perf_counter()
            try:
                if backend == "cpu":
                    raw_text = run_cpu(cpu_model, audio_path, prompt, vad_mode == "on")
                else:
                    raw_text = run_mlx(
                        mlx_whisper,
                        args.mlx_model,
                        audio_path,
                        prompt,
                        vad_mode == "on",
                    )
                text = raw_text
                if post_mode == "on":
                    from whisper_server import post_process_text

                    text = post_process_text(raw_text, language="ja", auto_punctuation=True)
                rows.append(
                    {
                        "case_id": case_id,
                        "backend": backend,
                        "prompt": prompt_mode,
                        "vad": vad_mode,
                        "post_process": post_mode,
                        "text": text,
                        "elapsed_seconds": time.perf_counter() - started_at,
                    }
                )
            except Exception as error:
                rows.append(
                    {
                        "case_id": case_id,
                        "backend": backend,
                        "prompt": prompt_mode,
                        "vad": vad_mode,
                        "post_process": post_mode,
                        "error_type": type(error).__name__,
                    }
                )
    return rows


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--corpus", type=Path, default=DEFAULT_CORPUS)
    parser.add_argument("--results", type=Path)
    parser.add_argument("--audio-dir", type=Path)
    parser.add_argument("--backends", nargs="+", choices=("cpu", "mlx"), default=["cpu", "mlx"])
    parser.add_argument("--cpu-model", default=None)
    parser.add_argument("--mlx-model", default=None)
    parser.add_argument("--prompt-modes", nargs="+", choices=("none", "baseline", "ending"), default=["baseline", "ending"])
    parser.add_argument("--vad-modes", nargs="+", choices=("off", "on"), default=["off", "on"])
    parser.add_argument("--post-process-modes", nargs="+", choices=("off", "on"), default=["off", "on"])
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    args = parser.parse_args()

    sys.path.insert(0, str(REPO_ROOT / "python"))
    import whisper_server

    args.cpu_model = args.cpu_model or whisper_server.default_managed_cpu_model_path()
    args.mlx_model = args.mlx_model or whisper_server.default_managed_mlx_model_path()
    corpus = load_corpus(args.corpus)
    if args.results:
        rows = load_result_rows(args.results)
    elif args.audio_dir:
        rows = run_audio_matrix(args, corpus)
    else:
        raise SystemExit("one of --results or --audio-dir is required")

    payload = {"corpus": str(args.corpus), "rows": rows, "metrics": evaluate_rows(corpus, rows)}
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2), encoding="utf-8")
    print(json.dumps(payload["metrics"], ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
