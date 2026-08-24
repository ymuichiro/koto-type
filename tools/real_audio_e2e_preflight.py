"""Check whether a macOS host exposes an audio input device for Issue #101."""

from __future__ import annotations

import argparse
import json
import platform
import subprocess
import sys
from pathlib import Path
from typing import Any

EXIT_READY = 0
EXIT_ERROR = 1
EXIT_NOT_RUN = 2


def _input_channels(item: dict[str, Any]) -> int:
    value = item.get("coreaudio_device_input")
    if isinstance(value, bool):
        return 0
    if isinstance(value, int | float):
        return max(0, int(value))
    if isinstance(value, str):
        try:
            return max(0, int(value))
        except ValueError:
            return 0
    return 0


def inspect_profile(profile: dict[str, Any]) -> dict[str, Any]:
    """Convert system_profiler JSON into a safe, deterministic result."""
    categories = profile.get("SPAudioDataType")
    if not isinstance(categories, list):
        return {"status": "ERROR", "reason": "invalid_audio_profile"}

    input_channel_counts: list[int] = []
    for category in categories:
        if not isinstance(category, dict):
            continue
        items = category.get("_items", [])
        if not isinstance(items, list):
            continue
        for item in items:
            if not isinstance(item, dict):
                continue
            channels = _input_channels(item)
            if channels > 0:
                input_channel_counts.append(channels)

    if not input_channel_counts:
        return {"status": "NOT_RUN", "reason": "no_audio_input_device"}
    return {
        "status": "READY",
        "input_device_count": len(input_channel_counts),
        "max_input_channels": max(input_channel_counts),
    }


def _read_profile(path: Path) -> dict[str, Any]:
    return json.loads(path.read_text(encoding="utf-8"))


def collect_profile() -> dict[str, Any]:
    """Run native macOS inventory without touching audio content."""
    if platform.system() != "Darwin":
        return {"status": "NOT_RUN", "reason": "unsupported_platform"}

    try:
        completed = subprocess.run(
            ["system_profiler", "SPAudioDataType", "-json"],
            capture_output=True,
            check=False,
            text=True,
            timeout=10,
        )
    except FileNotFoundError:
        return {"status": "NOT_RUN", "reason": "system_profiler_unavailable"}
    except subprocess.TimeoutExpired:
        return {"status": "ERROR", "reason": "system_profiler_timeout"}

    if completed.returncode != 0:
        return {"status": "ERROR", "reason": "system_profiler_failed"}
    try:
        profile = json.loads(completed.stdout)
    except json.JSONDecodeError:
        return {"status": "ERROR", "reason": "invalid_audio_profile"}
    if not isinstance(profile, dict):
        return {"status": "ERROR", "reason": "invalid_audio_profile"}
    return inspect_profile(profile)


def _exit_code(status: str) -> int:
    return {
        "READY": EXIT_READY,
        "ERROR": EXIT_ERROR,
        "NOT_RUN": EXIT_NOT_RUN,
    }.get(status, EXIT_ERROR)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--profile-json",
        type=Path,
        help="Read a saved system_profiler JSON fixture instead of invoking macOS.",
    )
    args = parser.parse_args()

    if args.profile_json is None:
        result = collect_profile()
    else:
        try:
            profile = _read_profile(args.profile_json)
        except (OSError, json.JSONDecodeError):
            result = {"status": "ERROR", "reason": "invalid_audio_profile"}
        else:
            result = (
                inspect_profile(profile)
                if isinstance(profile, dict)
                else {"status": "ERROR", "reason": "invalid_audio_profile"}
            )

    print(json.dumps(result, ensure_ascii=False, indent=2, sort_keys=True))
    return _exit_code(str(result.get("status")))


if __name__ == "__main__":
    sys.exit(main())
