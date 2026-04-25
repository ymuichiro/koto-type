#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import json
import selectors
import subprocess
import sys
import tempfile
import time
from pathlib import Path


def wait_for_line(process, timeout_seconds):
    selector = selectors.DefaultSelector()
    selector.register(process.stdout, selectors.EVENT_READ)
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        if process.poll() is not None:
            break
        events = selector.select(timeout=1)
        if events:
            line = process.stdout.readline()
            if line:
                return line.rstrip("\n")
    return None


def wait_for_transcript_line(process, timeout_seconds):
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        line = wait_for_line(process, timeout_seconds=max(1, int(deadline - time.time())))
        if line is None:
            return None
        if line.startswith("__KOTOTYPE_CONTROL__:"):
            continue
        return line

    return None


def read_available_stderr(process):
    selector = selectors.DefaultSelector()
    selector.register(process.stderr, selectors.EVENT_READ)
    chunks = []

    while True:
        events = selector.select(timeout=0)
        if not events:
            break
        chunk = process.stderr.readline()
        if not chunk:
            break
        chunks.append(chunk.rstrip("\n"))

    return "\n".join(chunks)


def main():
    project_root = Path(__file__).resolve().parents[2]
    server_binary = (
        Path(sys.argv[1]).resolve()
        if len(sys.argv) > 1
        else (project_root / "dist" / "whisper_server")
    )
    test_audio = project_root / "assets" / "audio" / "test_speech_ja.wav"
    real_home = Path.home()

    if not server_binary.exists():
        print(f"Server binary not found: {server_binary}", file=sys.stderr)
        return 2
    if not test_audio.exists():
        print(f"Test audio not found: {test_audio}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp_home:
        log_dir = Path(tmp_home) / "Library" / "Application Support" / "koto-type"
        log_dir.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ)
        env["HOME"] = tmp_home
        env["HF_HOME"] = str(real_home / ".cache" / "huggingface")
        env["HUGGINGFACE_HUB_CACHE"] = str(real_home / ".cache" / "huggingface" / "hub")
        env["KOTOTYPE_SKIP_AUDIO_PREPROCESSING"] = "1"
        env["KOTOTYPE_VAD_STRICT"] = "0"
        env["KOTOTYPE_FALLBACK_ON_EMPTY_VAD"] = "1"

        process = subprocess.Popen(
            [str(server_binary)],
            stdin=subprocess.PIPE,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            bufsize=1,
            env=env,
        )
        try:
            request = json.dumps(
                {
                    "type": "transcription_request",
                    "audio_path": str(test_audio),
                    "language": "ja",
                    "auto_punctuation": True,
                    "quality_preset": "medium",
                    "gpu_acceleration_enabled": False,
                },
                ensure_ascii=False,
            ) + "\n"
            process.stdin.write(request)
            process.stdin.flush()
            process.stdin.close()

            line = wait_for_transcript_line(process, timeout_seconds=180)
            if line is None:
                stderr = read_available_stderr(process)
                print("No response from whisper_server", file=sys.stderr)
                if stderr:
                    print(stderr[:2000], file=sys.stderr)
                return 1

            if not line.strip():
                log_path = log_dir / "server.log"
                print(
                    "whisper_server returned empty transcription for speech sample",
                    file=sys.stderr,
                )
                if log_path.exists():
                    print("--- server.log (tail) ---", file=sys.stderr)
                    tail_lines = log_path.read_text(encoding="utf-8").splitlines()[-80:]
                    for log_line in tail_lines:
                        print(log_line, file=sys.stderr)
                return 1

            print(f"Transcription smoke passed: {line[:120]}")
            return 0
        finally:
            try:
                process.stdin.close()
            except Exception:
                pass
            try:
                process.terminate()
                process.wait(timeout=5)
            except Exception:
                process.kill()


if __name__ == "__main__":
    raise SystemExit(main())
