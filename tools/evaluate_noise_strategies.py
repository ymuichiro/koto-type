#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import argparse
import json
import statistics
import subprocess
import sys
import time
import unicodedata
import wave
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

import numpy as np

from python import whisper_server


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_WORK_DIR = REPO_ROOT / "artifacts" / "evaluations" / "noise_preprocess_issue_72"
DEFAULT_MODEL = "mlx-community/whisper-large-v3-turbo"
DEFAULT_STRATEGIES = [
    "none",
    "ffmpeg_current",
    "ffmpeg_current_gate",
    "ffmpeg_current_no_gain",
    "ffmpeg_office",
    "ffmpeg_office_gate",
]
LEGACY_AUTO_GAIN_WEAK_THRESHOLD_DBFS = -18.0
LEGACY_AUTO_GAIN_TARGET_PEAK_DBFS = -10.0
LEGACY_AUTO_GAIN_MAX_DB = 18.0


@dataclass(frozen=True)
class EvalCase:
    case_id: str
    noise_condition: str
    reference_text: str
    audio_path: Path
    notes: str


@dataclass(frozen=True)
class SegmentMetrics:
    avg_logprob: float | None
    compression_ratio: float | None
    no_speech_prob: float | None


@dataclass(frozen=True)
class EvalResult:
    case_id: str
    noise_condition: str
    strategy: str
    reference_text: str
    hypothesis_text: str
    normalized_reference: str
    normalized_hypothesis: str
    cer: float | None
    false_insertion: bool
    dropped_utterance: bool
    preprocess_seconds: float
    transcribe_seconds: float
    total_seconds: float
    audio_duration_seconds: float
    realtime_factor: float
    processed_audio_path: str
    gate_reason: str | None
    segment_metrics: list[SegmentMetrics]
    activity: whisper_server.AudioActivityStats


def normalize_text(value: str) -> str:
    normalized = unicodedata.normalize("NFKC", value or "").lower()
    kept = []
    for character in normalized:
        if character.isspace():
            continue
        category = unicodedata.category(character)
        if category.startswith("P") or category.startswith("S"):
            continue
        kept.append(character)
    return "".join(kept)


def levenshtein_distance(left: str, right: str) -> int:
    if left == right:
        return 0
    if not left:
        return len(right)
    if not right:
        return len(left)

    previous = list(range(len(right) + 1))
    for left_index, left_char in enumerate(left, start=1):
        current = [left_index]
        for right_index, right_char in enumerate(right, start=1):
            substitution_cost = 0 if left_char == right_char else 1
            current.append(
                min(
                    previous[right_index] + 1,
                    current[right_index - 1] + 1,
                    previous[right_index - 1] + substitution_cost,
                )
            )
        previous = current
    return previous[-1]


def character_error_rate(reference: str, hypothesis: str) -> float | None:
    if not reference:
        return None
    return levenshtein_distance(reference, hypothesis) / len(reference)


def audio_duration_seconds(audio_path: Path) -> float:
    with wave.open(str(audio_path), "rb") as wav_file:
        return wav_file.getnframes() / float(wav_file.getframerate())


def run_command(args: list[str]) -> None:
    subprocess.run(args, cwd=str(REPO_ROOT), check=True, capture_output=True, text=True)


def convert_to_eval_wav(input_path: Path, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(input_path),
            "-acodec",
            "pcm_s16le",
            "-ac",
            "1",
            "-ar",
            "16000",
            str(output_path),
        ]
    )


def synthesize_speech(text: str, voice: str, output_path: Path) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    aiff_path = output_path.with_suffix(".aiff")
    run_command(["say", "-v", voice, "-r", "185", "-o", str(aiff_path), text])
    convert_to_eval_wav(aiff_path, output_path)
    aiff_path.unlink(missing_ok=True)


def read_wav_mono(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as wav_file:
        channels = wav_file.getnchannels()
        sample_width = wav_file.getsampwidth()
        sample_rate = wav_file.getframerate()
        frames = wav_file.readframes(wav_file.getnframes())
    if channels != 1 or sample_width != 2:
        raise ValueError(f"Expected mono 16-bit PCM WAV: {path}")
    audio = np.frombuffer(frames, dtype=np.int16).astype(np.float32) / 32768.0
    return audio, sample_rate


def write_wav_mono(path: Path, audio: np.ndarray, sample_rate: int = 16000) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    clipped = np.clip(audio, -0.98, 0.98)
    samples = (clipped * 32767.0).astype(np.int16)
    with wave.open(str(path), "wb") as wav_file:
        wav_file.setnchannels(1)
        wav_file.setsampwidth(2)
        wav_file.setframerate(sample_rate)
        wav_file.writeframes(samples.tobytes())


def rms(audio: np.ndarray) -> float:
    if audio.size == 0:
        return 0.0
    return float(np.sqrt(np.mean(np.square(audio))))


def pad_or_trim(audio: np.ndarray, length: int) -> np.ndarray:
    if len(audio) >= length:
        return audio[:length]
    return np.pad(audio, (0, length - len(audio)))


def mix_at_snr(target: np.ndarray, background: np.ndarray, snr_db: float) -> np.ndarray:
    length = max(len(target), len(background))
    target = pad_or_trim(target, length)
    background = pad_or_trim(background, length)
    target_rms = max(rms(target), 1e-6)
    background_rms = max(rms(background), 1e-6)
    desired_background_rms = target_rms / (10 ** (snr_db / 20.0))
    background = background * (desired_background_rms / background_rms)
    mixed = target + background
    peak = float(np.max(np.abs(mixed))) if mixed.size else 0.0
    if peak > 0.98:
        mixed = mixed * (0.98 / peak)
    return mixed


def scale_to_peak_dbfs(audio: np.ndarray, peak_dbfs: float) -> np.ndarray:
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if peak <= 0:
        return audio
    target_peak = 10 ** (peak_dbfs / 20.0)
    return audio * (target_peak / peak)


def synthetic_office_noise(duration_seconds: float, sample_rate: int = 16000) -> np.ndarray:
    rng = np.random.default_rng(seed=72)
    sample_count = int(duration_seconds * sample_rate)
    white = rng.normal(0.0, 0.018, sample_count).astype(np.float32)
    hum = 0.01 * np.sin(2 * np.pi * 120 * np.arange(sample_count) / sample_rate)
    keyboard = np.zeros(sample_count, dtype=np.float32)
    for start in range(int(0.35 * sample_rate), sample_count, int(0.42 * sample_rate)):
        click_len = min(int(0.018 * sample_rate), sample_count - start)
        if click_len <= 0:
            continue
        envelope = np.linspace(1.0, 0.0, click_len, dtype=np.float32)
        keyboard[start : start + click_len] += rng.normal(0.0, 0.18, click_len) * envelope
    noise = white + hum + keyboard
    peak = float(np.max(np.abs(noise))) if noise.size else 0.0
    return noise if peak <= 0.98 else noise * (0.98 / peak)


def ensure_dataset(work_dir: Path) -> list[EvalCase]:
    dataset_dir = work_dir / "dataset"
    source_dir = dataset_dir / "sources"
    target_path = source_dir / "target_ja.wav"
    long_target_path = source_dir / "target_long_ja.wav"
    background_jp_path = source_dir / "background_jp.wav"
    background_en_path = source_dir / "background_en.wav"

    target_text = "本日の議事録を以下にまとめます"
    long_target_text = "ただし今回は例外として扱います。設定を保存してから、もう一度確認します"
    background_jp_text = "来週の予定について、あとで田中さんに確認してください"
    background_en_text = "Please review the design document before the afternoon meeting"

    if not target_path.exists():
        synthesize_speech(target_text, "Kyoko", target_path)
    if not long_target_path.exists():
        synthesize_speech(long_target_text, "Kyoko", long_target_path)
    if not background_jp_path.exists():
        synthesize_speech(background_jp_text, "Eddy (日本語（日本）)", background_jp_path)
    if not background_en_path.exists():
        synthesize_speech(background_en_text, "Samantha", background_en_path)

    target_audio, sample_rate = read_wav_mono(target_path)
    long_target_audio, _ = read_wav_mono(long_target_path)
    background_jp, _ = read_wav_mono(background_jp_path)
    background_en, _ = read_wav_mono(background_en_path)

    cases: list[EvalCase] = []

    def add_case(
        case_id: str,
        condition: str,
        reference: str,
        audio: np.ndarray,
        notes: str,
    ) -> None:
        path = dataset_dir / f"{case_id}.wav"
        if not path.exists():
            write_wav_mono(path, audio, sample_rate)
        cases.append(EvalCase(case_id, condition, reference, path, notes))

    add_case("clean_short", "clean", target_text, target_audio, "target speech only")
    add_case("clean_long", "clean", long_target_text, long_target_audio, "longer target speech only")

    office_noise = synthetic_office_noise(audio_duration_seconds(target_path), sample_rate)
    add_case(
        "office_mid",
        "officeMid",
        target_text,
        mix_at_snr(target_audio, office_noise, 8.0),
        "target speech plus synthetic office noise at +8 dB SNR",
    )

    add_case(
        "competing_jp_mid",
        "competingSpeakerJP",
        target_text,
        mix_at_snr(target_audio, background_jp, 5.0),
        "target speech plus Japanese competing speaker at +5 dB SNR",
    )
    add_case(
        "competing_jp_high",
        "competingSpeakerJP",
        target_text,
        mix_at_snr(target_audio, background_jp, 0.0),
        "target speech plus Japanese competing speaker at 0 dB SNR",
    )
    add_case(
        "competing_en_mid",
        "competingSpeakerEN",
        target_text,
        mix_at_snr(target_audio, background_en, 5.0),
        "target speech plus English competing speaker at +5 dB SNR",
    )

    add_case(
        "background_jp_far",
        "competingSpeakerJP",
        "",
        scale_to_peak_dbfs(background_jp, -30.0),
        "Japanese background speaker only, attenuated to -30 dBFS peak",
    )
    add_case(
        "background_jp_near",
        "competingSpeakerJP",
        "",
        scale_to_peak_dbfs(background_jp, -20.0),
        "Japanese background speaker only, attenuated to -20 dBFS peak",
    )
    add_case(
        "background_en_far",
        "competingSpeakerEN",
        "",
        scale_to_peak_dbfs(background_en, -30.0),
        "English background speaker only, attenuated to -30 dBFS peak",
    )

    keyboard_only = synthetic_office_noise(3.0, sample_rate)
    add_case(
        "keyboard_only",
        "keyboard",
        "",
        scale_to_peak_dbfs(keyboard_only, -18.0),
        "keyboard and air-conditioner style non-speech noise only",
    )
    add_case("silence", "clean", "", np.zeros(sample_rate * 3, dtype=np.float32), "silence only")

    manifest_path = dataset_dir / "manifest.json"
    manifest_path.write_text(
        json.dumps(
            [
                {
                    "case_id": case.case_id,
                    "noise_condition": case.noise_condition,
                    "reference_text": case.reference_text,
                    "audio_path": str(case.audio_path),
                    "notes": case.notes,
                }
                for case in cases
            ],
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    return cases


def apply_ffmpeg_filter(input_path: Path, output_path: Path, filter_chain: str) -> None:
    output_path.parent.mkdir(parents=True, exist_ok=True)
    run_command(
        [
            "ffmpeg",
            "-hide_banner",
            "-loglevel",
            "error",
            "-y",
            "-i",
            str(input_path),
            "-acodec",
            "pcm_s16le",
            "-ac",
            "1",
            "-ar",
            "16000",
            "-af",
            filter_chain,
            str(output_path),
        ]
    )


def build_legacy_current_filter_chain() -> str:
    return "highpass=f=100,lowpass=f=7800,dynaudnorm=f=90:g=15:p=0.8"


def legacy_determine_gain(peak_dbfs: float) -> float:
    if peak_dbfs >= LEGACY_AUTO_GAIN_WEAK_THRESHOLD_DBFS:
        return 0.0
    required_gain = LEGACY_AUTO_GAIN_TARGET_PEAK_DBFS - peak_dbfs
    if required_gain <= 0:
        return 0.0
    return min(required_gain, LEGACY_AUTO_GAIN_MAX_DB)


def apply_legacy_gain(input_path: Path, output_path: Path, gain_db: float) -> None:
    apply_ffmpeg_filter(
        input_path,
        output_path,
        f"volume={gain_db:.2f}dB,alimiter=limit=0.98",
    )


def analyze_peak_dbfs(wav_path: Path) -> float:
    audio, _ = read_wav_mono(wav_path)
    peak = float(np.max(np.abs(audio))) if audio.size else 0.0
    if peak <= 0:
        return float("-inf")
    return float(20.0 * np.log10(peak))


def apply_strategy(case: EvalCase, strategy: str, output_dir: Path) -> tuple[Path, float]:
    if strategy == "none":
        return case.audio_path, 0.0

    started_at = time.perf_counter()
    processed_path = output_dir / f"{case.case_id}_{strategy}.wav"

    if strategy in {
        "ffmpeg_current",
        "ffmpeg_current_gate",
        "ffmpeg_current_no_gain",
        "ffmpeg_current_no_gain_gate",
    }:
        apply_ffmpeg_filter(
            case.audio_path,
            processed_path,
            build_legacy_current_filter_chain(),
        )
        if strategy in {"ffmpeg_current", "ffmpeg_current_gate"}:
            peak_dbfs = analyze_peak_dbfs(processed_path)
            gain_db = legacy_determine_gain(peak_dbfs)
            if gain_db > 0:
                boosted_path = output_dir / f"{case.case_id}_{strategy}_gain.wav"
                apply_legacy_gain(processed_path, boosted_path, gain_db)
                boosted_path.replace(processed_path)
        return processed_path, time.perf_counter() - started_at

    if strategy in {"ffmpeg_office", "ffmpeg_office_gate"}:
        apply_ffmpeg_filter(
            case.audio_path,
            processed_path,
            whisper_server.build_audio_filter_chain(),
        )
        return processed_path, time.perf_counter() - started_at

    raise ValueError(f"Unsupported strategy: {strategy}")


def collect_segment_metrics(result: dict) -> list[SegmentMetrics]:
    metrics = []
    for segment in result.get("segments", []) or []:
        metrics.append(
            SegmentMetrics(
                avg_logprob=segment.get("avg_logprob"),
                compression_ratio=segment.get("compression_ratio"),
                no_speech_prob=segment.get("no_speech_prob"),
            )
        )
    return metrics


def gate_hypothesis(
    text: str,
    metrics: list[SegmentMetrics],
    activity: whisper_server.AudioActivityStats,
) -> tuple[str, str | None]:
    if not normalize_text(text):
        return "", "empty_hypothesis"
    if whisper_server.should_skip_transcription_for_low_activity(activity):
        return "", "low_activity"
    decision = whisper_server.evaluate_transcription_confidence_gate(
        text,
        tuple(
            whisper_server.TranscriptionSegmentMetrics(
                avg_logprob=metric.avg_logprob,
                compression_ratio=metric.compression_ratio,
                no_speech_prob=metric.no_speech_prob,
            )
            for metric in metrics
        ),
    )
    if decision.should_suppress:
        return "", decision.reason
    return text, None


def warm_model(model: str) -> None:
    import mlx_whisper

    mlx_whisper.transcribe(
        str(REPO_ROOT / "assets" / "audio" / "test_speech_ja.wav"),
        path_or_hf_repo=model,
        language="ja",
        task="transcribe",
        temperature=0.0,
        word_timestamps=False,
    )


def transcribe_audio(audio_path: Path, model: str) -> tuple[dict, float]:
    import mlx_whisper

    started_at = time.perf_counter()
    result = mlx_whisper.transcribe(
        str(audio_path),
        path_or_hf_repo=model,
        language="ja",
        task="transcribe",
        temperature=0.0,
        word_timestamps=False,
        condition_on_previous_text=False,
        no_speech_threshold=whisper_server.DEFAULT_NO_SPEECH_THRESHOLD,
        compression_ratio_threshold=whisper_server.DEFAULT_COMPRESSION_RATIO_THRESHOLD,
    )
    return result, time.perf_counter() - started_at


def evaluate(
    cases: list[EvalCase],
    strategies: list[str],
    model: str,
    output_dir: Path,
) -> list[EvalResult]:
    processed_dir = output_dir / "processed"
    results = []
    warm_model(model)

    for case in cases:
        for strategy in strategies:
            processed_audio_path, preprocess_seconds = apply_strategy(
                case,
                strategy,
                processed_dir,
            )
            result, transcribe_seconds = transcribe_audio(processed_audio_path, model)
            hypothesis = str(result.get("text", "")).strip()
            metrics = collect_segment_metrics(result)
            activity = whisper_server.analyze_wav_activity(str(processed_audio_path))
            gate_reason = None
            if strategy.endswith("_gate"):
                hypothesis, gate_reason = gate_hypothesis(hypothesis, metrics, activity)

            normalized_reference = normalize_text(case.reference_text)
            normalized_hypothesis = normalize_text(hypothesis)
            cer = character_error_rate(normalized_reference, normalized_hypothesis)
            duration_seconds = audio_duration_seconds(processed_audio_path)
            total_seconds = preprocess_seconds + transcribe_seconds

            results.append(
                EvalResult(
                    case_id=case.case_id,
                    noise_condition=case.noise_condition,
                    strategy=strategy,
                    reference_text=case.reference_text,
                    hypothesis_text=hypothesis,
                    normalized_reference=normalized_reference,
                    normalized_hypothesis=normalized_hypothesis,
                    cer=cer,
                    false_insertion=not normalized_reference
                    and bool(normalized_hypothesis),
                    dropped_utterance=bool(normalized_reference)
                    and not normalized_hypothesis,
                    preprocess_seconds=preprocess_seconds,
                    transcribe_seconds=transcribe_seconds,
                    total_seconds=total_seconds,
                    audio_duration_seconds=duration_seconds,
                    realtime_factor=total_seconds / duration_seconds
                    if duration_seconds > 0
                    else 0.0,
                    processed_audio_path=str(processed_audio_path),
                    gate_reason=gate_reason,
                    segment_metrics=metrics,
                    activity=activity,
                )
            )
    return results


def percentile(values: list[float], percent: float) -> float:
    if not values:
        return 0.0
    sorted_values = sorted(values)
    index = (len(sorted_values) - 1) * percent
    lower = int(index)
    upper = min(lower + 1, len(sorted_values) - 1)
    if lower == upper:
        return sorted_values[lower]
    weight = index - lower
    return sorted_values[lower] * (1 - weight) + sorted_values[upper] * weight


def summarize(results: list[EvalResult]) -> list[dict]:
    rows = []
    strategies = sorted({result.strategy for result in results})
    for strategy in strategies:
        strategy_results = [result for result in results if result.strategy == strategy]
        cer_values = [result.cer for result in strategy_results if result.cer is not None]
        false_cases = [result for result in strategy_results if not result.normalized_reference]
        speech_cases = [result for result in strategy_results if result.normalized_reference]
        latencies = [result.total_seconds for result in strategy_results]
        rows.append(
            {
                "strategy": strategy,
                "case_count": len(strategy_results),
                "mean_cer": statistics.mean(cer_values) if cer_values else None,
                "false_insertion_rate": sum(
                    1 for result in false_cases if result.false_insertion
                )
                / len(false_cases)
                if false_cases
                else 0.0,
                "dropped_utterance_rate": sum(
                    1 for result in speech_cases if result.dropped_utterance
                )
                / len(speech_cases)
                if speech_cases
                else 0.0,
                "p50_latency_seconds": percentile(latencies, 0.50),
                "p95_latency_seconds": percentile(latencies, 0.95),
                "mean_realtime_factor": statistics.mean(
                    result.realtime_factor for result in strategy_results
                ),
            }
        )
    return sorted(
        rows,
        key=lambda row: (
            row["false_insertion_rate"],
            row["dropped_utterance_rate"],
            row["mean_cer"] if row["mean_cer"] is not None else 1.0,
            row["p95_latency_seconds"],
        ),
    )


def result_to_dict(result: EvalResult) -> dict:
    payload = asdict(result)
    payload["activity"] = asdict(result.activity)
    payload["segment_metrics"] = [asdict(metric) for metric in result.segment_metrics]
    return payload


def write_markdown_report(
    path: Path,
    *,
    summary_rows: list[dict],
    results: list[EvalResult],
    model: str,
) -> None:
    lines = [
        "# Issue 72 Noise Preprocess Evaluation",
        "",
        f"- Generated: {datetime.now(timezone.utc).isoformat()}",
        f"- Model: `{model}`",
        "- Dataset: local synthetic dataset generated with macOS `say`, synthetic office noise, and competing-speaker mixes.",
        "- Limitation: this does not replace real office dogfooding; it is a reproducible first-pass screen.",
        "",
        "## Summary",
        "",
        "| strategy | mean CER | false insertion | dropped utterance | p50 latency | p95 latency | mean RTF |",
        "|---|---:|---:|---:|---:|---:|---:|",
    ]
    for row in summary_rows:
        mean_cer = "-" if row["mean_cer"] is None else f"{row['mean_cer']:.3f}"
        lines.append(
            "| {strategy} | {mean_cer} | {false:.0%} | {dropped:.0%} | {p50:.2f}s | {p95:.2f}s | {rtf:.3f} |".format(
                strategy=row["strategy"],
                mean_cer=mean_cer,
                false=row["false_insertion_rate"],
                dropped=row["dropped_utterance_rate"],
                p50=row["p50_latency_seconds"],
                p95=row["p95_latency_seconds"],
                rtf=row["mean_realtime_factor"],
            )
        )

    lines.extend(
        [
            "",
            "## Per-Case Results",
            "",
            "| case | condition | strategy | ref | hyp | CER | false insertion | gate | latency |",
            "|---|---|---|---|---|---:|---|---|---:|",
        ]
    )
    for result in sorted(results, key=lambda item: (item.case_id, item.strategy)):
        cer = "-" if result.cer is None else f"{result.cer:.3f}"
        ref = result.reference_text.replace("|", "\\|")
        hyp = result.hypothesis_text.replace("|", "\\|")
        lines.append(
            f"| {result.case_id} | {result.noise_condition} | {result.strategy} | "
            f"{ref} | {hyp} | {cer} | {result.false_insertion} | "
            f"{result.gate_reason or ''} | {result.total_seconds:.2f}s |"
        )

    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text("\n".join(lines) + "\n", encoding="utf-8")


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument("--work-dir", type=Path, default=DEFAULT_WORK_DIR)
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument(
        "--strategies",
        default=",".join(DEFAULT_STRATEGIES),
        help="Comma-separated strategies to evaluate.",
    )
    return parser.parse_args()


def main() -> None:
    args = parse_args()
    strategies = [strategy.strip() for strategy in args.strategies.split(",") if strategy.strip()]
    cases = ensure_dataset(args.work_dir)
    output_dir = args.work_dir / "runs" / datetime.now().strftime("%Y%m%d_%H%M%S")
    results = evaluate(cases, strategies, args.model, output_dir)
    summary_rows = summarize(results)

    output_dir.mkdir(parents=True, exist_ok=True)
    (output_dir / "results.json").write_text(
        json.dumps(
            {
                "model": args.model,
                "strategies": strategies,
                "summary": summary_rows,
                "results": [result_to_dict(result) for result in results],
            },
            ensure_ascii=False,
            indent=2,
        ),
        encoding="utf-8",
    )
    write_markdown_report(
        output_dir / "report.md",
        summary_rows=summary_rows,
        results=results,
        model=args.model,
    )

    print(json.dumps({"output_dir": str(output_dir), "summary": summary_rows}, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    try:
        main()
    except subprocess.CalledProcessError as error:
        sys.stderr.write(error.stderr or error.stdout or str(error))
        raise
