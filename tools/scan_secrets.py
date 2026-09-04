#!/usr/bin/env python3
"""Scan tracked text files for high-confidence credential patterns.

This dependency-free guard reports only a safe path and rule name, never a
matched value.
"""

from __future__ import annotations

import argparse
import os
import re
import subprocess
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


@dataclass(frozen=True)
class SecretMatch:
    path: Path
    rule: str


PATTERNS: tuple[tuple[str, re.Pattern[bytes]], ...] = (
    ("huggingface-token", re.compile(rb"\bhf_[A-Za-z0-9]{20,}\b")),
    ("github-token", re.compile(rb"\b(?:ghp|gho|ghu|ghs|ghr)_[A-Za-z0-9]{20,}\b")),
    ("github-pat", re.compile(rb"\bgithub_pat_[A-Za-z0-9_]{20,}\b")),
    ("slack-token", re.compile(rb"\bxox[baprs]-[A-Za-z0-9-]{20,}\b")),
    ("openai-token", re.compile(rb"\bsk-[A-Za-z0-9_-]{20,}\b")),
    ("aws-access-key", re.compile(rb"\bAKIA[0-9A-Z]{16}\b")),
    (
        "private-key",
        re.compile(rb"-----BEGIN (?:RSA |OPENSSH |EC |DSA )?PRIVATE KEY-----"),
    ),
)


class ScanError(RuntimeError):
    """Raised when the scanner cannot inspect a requested file set."""


def scan_bytes(path: Path, content: bytes) -> list[SecretMatch]:
    """Return one finding per matching rule without exposing secret content."""

    return [
        SecretMatch(path, rule)
        for rule, pattern in PATTERNS
        if pattern.search(content)
    ]


def scan_paths(paths: Iterable[Path]) -> list[SecretMatch]:
    findings: list[SecretMatch] = []
    for path in paths:
        try:
            content = path.read_bytes()
        except OSError as error:
            raise ScanError(f"could not read {path}: {type(error).__name__}") from error
        findings.extend(scan_bytes(path, content))
    return findings


def tracked_paths(project_root: Path) -> list[Path]:
    result = subprocess.run(
        ["git", "-C", str(project_root), "ls-files", "-z"],
        check=False,
        capture_output=True,
    )
    if result.returncode != 0:
        raise ScanError("git ls-files failed")

    return [
        project_root / os.fsdecode(relative_path)
        for relative_path in result.stdout.split(b"\0")
        if relative_path
    ]


def display_path(path: Path, project_root: Path) -> str:
    """Render repository-relative paths without exposing local directories."""

    try:
        return path.relative_to(project_root).as_posix()
    except ValueError:
        return path.name


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(
        description="Scan tracked files, or explicitly supplied files, for credentials."
    )
    parser.add_argument(
        "paths",
        nargs="*",
        type=Path,
        help="optional files to scan instead of the repository's tracked files",
    )
    args = parser.parse_args(argv)
    project_root = Path(__file__).resolve().parents[1]
    paths = [
        path if path.is_absolute() else project_root / path
        for path in args.paths
    ] or tracked_paths(project_root)

    try:
        findings = scan_paths(paths)
    except ScanError as error:
        print(f"Secret scan error: {error}", file=sys.stderr)
        return 2

    if findings:
        print("Potential credential detected:", file=sys.stderr)
        for finding in findings:
            print(
                f"- {display_path(finding.path, project_root)}: {finding.rule}",
                file=sys.stderr,
            )
        return 1

    print(f"Secret scan passed: {len(paths)} files checked")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
