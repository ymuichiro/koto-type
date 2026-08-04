#!/usr/bin/env python3

import argparse
import json
import os
import platform
import resource
import subprocess
import time
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_OUTPUT = REPO_ROOT / "artifacts" / "benchmarks" / "swift_whisper_spike.json"
DEFAULT_AUDIO = [
    REPO_ROOT / "assets/audio/test_speech_ja.wav",
    REPO_ROOT / "assets/audio/test_speech_ja_300s.wav",
]
HEALTHCHECK = "__KOTOTYPE_HEALTHCHECK__:benchmark"
FEATURE_FLAG = "KOTOTYPE_ENABLE_EXPERIMENTAL_SWIFT_ASR"


def peak_rss_bytes() -> int:
    value = resource.getrusage(resource.RUSAGE_CHILDREN).ru_maxrss
    return int(value if platform.system() == "Darwin" else value * 1024)


def run_case(binary: Path, audio_path: Path) -> dict:
    request = {
        "type": "transcription_request",
        "audio_path": str(audio_path),
        "language": "ja",
        "mode": "transcribe",
        "quality_preset": "medium",
        "gpu_acceleration_enabled": True,
    }
    started_at = time.perf_counter()
    environment = os.environ.copy()
    environment[FEATURE_FLAG] = "1"
    completed = subprocess.run(
        [str(binary)],
        input=HEALTHCHECK + "\n" + json.dumps(request) + "\n",
        capture_output=True,
        text=True,
        check=False,
        env=environment,
    )
    elapsed = time.perf_counter() - started_at
    stdout_lines = completed.stdout.splitlines()
    return {
        "audio_path": str(audio_path),
        "status": "unsupported" if stdout_lines[-1:] == [""] else "contract_failure",
        "exit_code": completed.returncode,
        "elapsed_seconds": elapsed,
        "peak_rss_bytes_cumulative_child_processes": peak_rss_bytes(),
        "healthcheck_response": stdout_lines[0] if stdout_lines else None,
        "transcript": stdout_lines[-1] if stdout_lines else None,
        "diagnostics": completed.stderr.strip().splitlines(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--binary", type=Path, required=True)
    parser.add_argument("--output", type=Path, default=DEFAULT_OUTPUT)
    parser.add_argument("--audio", type=Path, action="append", dest="audio_paths")
    args = parser.parse_args()

    environment = os.environ.copy()
    environment[FEATURE_FLAG] = "1"
    probe = subprocess.run(
        [str(args.binary), "--probe"],
        capture_output=True,
        text=True,
        check=False,
        env=environment,
    )
    try:
        probe_payload = json.loads(probe.stdout)
        probe_parse_error = None
    except json.JSONDecodeError as error:
        probe_payload = None
        probe_parse_error = str(error)

    payload = {
        "status": "not_comparable",
        "reason": "native_whisper_decoder_not_implemented",
        "binary": str(args.binary),
        "probe": probe_payload,
        "probe_exit_code": probe.returncode,
        "probe_stdout": probe.stdout.strip(),
        "probe_stderr": probe.stderr.strip(),
        "probe_parse_error": probe_parse_error,
        "cases": [
            run_case(args.binary, audio_path)
            for audio_path in (args.audio_paths or DEFAULT_AUDIO)
        ],
        "python_baseline": "artifacts/benchmarks/asr_benchmark_results.json",
        "comparison_note": "No WER/CER or ASR latency comparison is valid until Swift produces text.",
    }
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(json.dumps(payload, ensure_ascii=False, indent=2) + "\n")
    print(json.dumps(payload, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
