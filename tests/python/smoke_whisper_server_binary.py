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
        events = selector.select(timeout=1)
        if events:
            line = process.stdout.readline()
            if line:
                return line.rstrip("\n")
        if process.poll() is not None:
            break
    return None


def wait_for_non_control_line(process, timeout_seconds):
    deadline = time.time() + timeout_seconds

    while time.time() < deadline:
        line = wait_for_line(
            process, timeout_seconds=max(1, int(deadline - time.time()))
        )
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


def read_server_log_tail(log_path, max_lines=80):
    if not log_path.exists():
        return ""
    return "\n".join(log_path.read_text(encoding="utf-8").splitlines()[-max_lines:])


def resolve_smoke_audio_path(project_root):
    configured_path = os.environ.get("KOTOTYPE_SMOKE_AUDIO_PATH", "").strip()
    if configured_path:
        return Path(configured_path).expanduser().resolve()
    return project_root / "assets" / "audio" / "test_speech_ja.wav"


def resolve_smoke_language():
    return os.environ.get("KOTOTYPE_SMOKE_LANGUAGE", "ja").strip() or "ja"


def parse_smoke_arguments(arguments):
    healthcheck_only = "--healthcheck" in arguments
    positional_arguments = [
        argument for argument in arguments if argument != "--healthcheck"
    ]
    if len(positional_arguments) > 1:
        raise ValueError("Only one server binary path may be provided")
    server_binary = (
        Path(positional_arguments[0]).resolve() if positional_arguments else None
    )
    return server_binary, healthcheck_only


def main():
    project_root = Path(__file__).resolve().parents[2]
    try:
        configured_server_binary, healthcheck_only = parse_smoke_arguments(sys.argv[1:])
    except ValueError as error:
        print(str(error), file=sys.stderr)
        return 2
    server_binary = configured_server_binary or (
        project_root / "dist" / "whisper_server"
    )
    test_audio = resolve_smoke_audio_path(project_root)
    smoke_language = resolve_smoke_language()
    real_home = Path.home()

    if not server_binary.exists():
        print(f"Server binary not found: {server_binary}", file=sys.stderr)
        return 2
    if not healthcheck_only and not test_audio.exists():
        print(f"Test audio not found: {test_audio}", file=sys.stderr)
        return 2

    with tempfile.TemporaryDirectory() as tmp_home:
        log_dir = Path(tmp_home) / "Library" / "Application Support" / "koto-type"
        log_dir.mkdir(parents=True, exist_ok=True)
        env = dict(os.environ)
        env["HOME"] = tmp_home
        env["HF_HOME"] = str(real_home / ".cache" / "huggingface")
        env["HUGGINGFACE_HUB_CACHE"] = str(real_home / ".cache" / "huggingface" / "hub")
        env["HF_HUB_DISABLE_IMPLICIT_TOKEN"] = "1"
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
        if process.stdin is None:
            raise RuntimeError("whisper_server smoke process has no stdin pipe")
        stdin = process.stdin
        try:
            if healthcheck_only:
                token = "cpu-only"
                stdin.write(f"__KOTOTYPE_HEALTHCHECK__:{token}\n")
                stdin.flush()
                stdin.close()
                line = wait_for_non_control_line(process, timeout_seconds=15)
                expected = f"__KOTOTYPE_HEALTHCHECK_OK__:{token}"
                if line != expected:
                    stderr = read_available_stderr(process)
                    print("whisper_server healthcheck failed", file=sys.stderr)
                    if line:
                        print(f"Unexpected response: {line}", file=sys.stderr)
                    if stderr:
                        print(stderr[:2000], file=sys.stderr)
                    return 1
                print("Whisper server healthcheck passed")
                return 0

            request = (
                json.dumps(
                    {
                        "type": "transcription_request",
                        "audio_path": str(test_audio),
                        "language": smoke_language,
                        "auto_punctuation": True,
                        "quality_preset": "medium",
                        "gpu_acceleration_enabled": False,
                    },
                    ensure_ascii=False,
                )
                + "\n"
            )
            stdin.write(request)
            stdin.flush()
            stdin.close()

            line = wait_for_non_control_line(process, timeout_seconds=180)
            if line is None:
                stderr = read_available_stderr(process)
                print("No response from whisper_server", file=sys.stderr)
                if stderr:
                    print(stderr[:2000], file=sys.stderr)
                server_log_tail = read_server_log_tail(log_dir / "server.log")
                if server_log_tail:
                    print("--- server.log (tail) ---", file=sys.stderr)
                    print(server_log_tail, file=sys.stderr)
                return 1

            if not line.strip():
                log_path = log_dir / "server.log"
                print(
                    "whisper_server returned empty transcription for speech sample",
                    file=sys.stderr,
                )
                server_log_tail = read_server_log_tail(log_path)
                if server_log_tail:
                    print("--- server.log (tail) ---", file=sys.stderr)
                    print(server_log_tail, file=sys.stderr)
                return 1

            print(f"Transcription smoke passed: {line[:120]}")
            return 0
        finally:
            try:
                stdin.close()
            except Exception:
                pass
            try:
                process.terminate()
                process.wait(timeout=5)
            except Exception:
                process.kill()


if __name__ == "__main__":
    raise SystemExit(main())
