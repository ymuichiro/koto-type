#!/usr/bin/env python3

import argparse
import json
import sys
from pathlib import Path


LOWER_IS_BETTER = (
    "mean_cer",
    "false_insertion_rate",
    "dropped_utterance_rate",
    "p95_latency_seconds",
    "mean_realtime_factor",
)


def load_summary(path: Path) -> dict[str, dict]:
    payload = json.loads(path.read_text(encoding="utf-8"))
    return {row["strategy"]: row for row in payload["summary"]}


def regressions(baseline: dict[str, dict], candidate: dict[str, dict]) -> list[str]:
    failures = []
    for strategy, baseline_row in baseline.items():
        candidate_row = candidate.get(strategy)
        if candidate_row is None:
            failures.append(f"missing strategy: {strategy}")
            continue
        for metric in LOWER_IS_BETTER:
            before = baseline_row.get(metric)
            after = candidate_row.get(metric)
            if before is None or after is None:
                if before != after:
                    failures.append(f"{strategy}.{metric}: {before} -> {after}")
                continue
            if after > before:
                failures.append(f"{strategy}.{metric}: {before:.6f} -> {after:.6f}")
    return failures


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    args = parser.parse_args()
    failures = regressions(load_summary(args.baseline), load_summary(args.candidate))
    if failures:
        print("Benchmark regression detected:", file=sys.stderr)
        for failure in failures:
            print(f"- {failure}", file=sys.stderr)
        return 1
    print("Benchmark gate passed: accuracy and speed maintained or improved")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
