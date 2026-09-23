#!/usr/bin/env python3
"""Measure aggregate CPU and RSS for a process and its descendants.

When the root exposes a process group, reparented members of that group are
included as well so orphaned backend workers are not missed by the audit.

The output intentionally omits PIDs, commands, paths, and host metadata so it
can be copied into an issue without exposing environment-specific details.
"""

import argparse
import json
import math
import subprocess
import time
from dataclasses import dataclass
from typing import Callable


@dataclass(frozen=True)
class ProcessRecord:
    parent_pid: int
    cpu_percent: float
    rss_kib: int
    elapsed_seconds: int | None = None
    process_group_id: int | None = None


@dataclass(frozen=True)
class ProcessSnapshot:
    root_present: bool
    process_count: int
    cpu_percent: float
    rss_kib: int


def parse_process_table(output: str) -> dict[int, ProcessRecord]:
    records: dict[int, ProcessRecord] = {}
    for line in output.splitlines():
        columns = line.split()
        if len(columns) < 4:
            continue
        try:
            pid, parent_pid = int(columns[0]), int(columns[1])
            cpu_percent = float(columns[2])
            rss_kib = int(columns[3])
        except ValueError:
            continue
        if pid <= 0 or parent_pid < 0 or cpu_percent < 0 or rss_kib < 0:
            continue
        elapsed_seconds = None
        if len(columns) >= 5:
            elapsed_seconds = parse_elapsed_time(columns[4])
            if elapsed_seconds is None:
                continue
        process_group_id = None
        if len(columns) >= 6:
            try:
                process_group_id = int(columns[5])
            except ValueError:
                continue
            if process_group_id <= 0:
                continue
        records[pid] = ProcessRecord(
            parent_pid,
            cpu_percent,
            rss_kib,
            elapsed_seconds,
            process_group_id,
        )
    return records


def parse_elapsed_time(value: str) -> int | None:
    """Parse the compact elapsed-time format emitted by macOS ``ps``."""
    try:
        parts = value.split("-", maxsplit=1)
        if len(parts) == 1:
            days, time_part = 0, parts[0]
        else:
            days, time_part = int(parts[0]), parts[1]
        time_fields = [int(field) for field in time_part.split(":")]
        if len(time_fields) == 2:
            hours, minutes, seconds = 0, *time_fields
        elif len(time_fields) == 3:
            hours, minutes, seconds = time_fields
        else:
            return None
    except ValueError:
        return None
    if days < 0 or hours < 0 or minutes < 0 or seconds < 0:
        return None
    if minutes >= 60 or seconds >= 60:
        return None
    return days * 24 * 60 * 60 + hours * 60 * 60 + minutes * 60 + seconds


def root_process_was_reused(
    previous: ProcessRecord | None, current: ProcessRecord | None
) -> bool:
    """Return true when the same PID now represents a younger process."""
    if previous is None or current is None:
        return False
    if previous.elapsed_seconds is None or current.elapsed_seconds is None:
        return False
    return current.elapsed_seconds < previous.elapsed_seconds


def process_tree_pids(root_pid: int, records: dict[int, ProcessRecord]) -> set[int]:
    if root_pid not in records:
        return set()

    children_by_parent: dict[int, set[int]] = {}
    for pid, record in records.items():
        children_by_parent.setdefault(record.parent_pid, set()).add(pid)

    tree = {root_pid}
    pending = [root_pid]
    while pending:
        parent_pid = pending.pop()
        for child_pid in children_by_parent.get(parent_pid, set()):
            if child_pid in tree:
                continue
            tree.add(child_pid)
            pending.append(child_pid)
    return tree


def process_group_ids_for_tree(
    root_pid: int,
    tree: set[int],
    records: dict[int, ProcessRecord],
) -> set[int]:
    """Return only dedicated groups owned by the measured process tree.

    A root launched from a shell can inherit the shell's process group. Treating
    that shared group as an ownership boundary would include unrelated shell
    processes in the CPU/RSS totals. A root group is safe to retain when the
    root is its group leader; descendant groups are retained when they differ
    from the inherited root group.
    """
    group_ids: set[int] = set()
    root_group_id = records.get(root_pid)
    root_group_id = root_group_id.process_group_id if root_group_id else None
    for pid in tree:
        process_group_id = records[pid].process_group_id
        if process_group_id is None:
            continue
        if process_group_id != root_group_id or (
            pid == root_pid and process_group_id == root_pid
        ):
            group_ids.add(process_group_id)
    return group_ids


def remember_descendants(
    root_pid: int,
    tree: set[int],
    records: dict[int, ProcessRecord],
    descendant_elapsed_seconds: dict[int, int],
) -> None:
    """Remember descendants that can be recognized after their parent exits.

    A process tree can inherit the caller's shared group, which intentionally is
    not retained as an ownership boundary. Keep only same-group descendants with
    an elapsed-time value, so a reparented child can be counted until it exits
    without adding unrelated members of that shared group.
    """
    root_group_id = records[root_pid].process_group_id
    if root_group_id is None or root_group_id == root_pid:
        return
    for pid in tree:
        if pid == root_pid:
            continue
        record = records[pid]
        elapsed_seconds = record.elapsed_seconds
        if record.process_group_id == root_group_id and elapsed_seconds is not None:
            descendant_elapsed_seconds[pid] = elapsed_seconds


def build_snapshot(
    root_pid: int,
    records: dict[int, ProcessRecord],
    process_group_ids: set[int] | None = None,
    descendant_elapsed_seconds: dict[int, int] | None = None,
) -> ProcessSnapshot:
    root_present = root_pid in records
    tree = process_tree_pids(root_pid, records)
    group_ids = set(process_group_ids or ())
    group_ids.update(process_group_ids_for_tree(root_pid, tree, records))
    if group_ids:
        tree.update(
            pid
            for pid, record in records.items()
            if record.process_group_id in group_ids
        )
    for pid, observed_elapsed_seconds in (descendant_elapsed_seconds or {}).items():
        record = records.get(pid)
        if record is not None and record.elapsed_seconds is not None:
            if record.elapsed_seconds >= observed_elapsed_seconds:
                tree.add(pid)
    return ProcessSnapshot(
        root_present=root_present,
        process_count=len(tree),
        cpu_percent=sum(records[pid].cpu_percent for pid in tree),
        rss_kib=sum(records[pid].rss_kib for pid in tree),
    )


def percentile(values: list[float], quantile: float) -> float:
    if not values:
        return 0.0
    ordered = sorted(values)
    index = max(0, math.ceil(quantile * len(ordered)) - 1)
    return ordered[index]


def metric_summary(values: list[float]) -> dict[str, float]:
    return {
        "p50": round(percentile(values, 0.50), 2),
        "p95": round(percentile(values, 0.95), 2),
        "max": round(max(values, default=0.0), 2),
    }


def read_process_table() -> str:
    result = subprocess.run(
        ["/bin/ps", "-axo", "pid=,ppid=,%cpu=,rss=,etime=,pgid="],
        check=True,
        capture_output=True,
        text=True,
    )
    return result.stdout


def measure(
    root_pid: int,
    duration_seconds: float,
    interval_seconds: float,
    read_table: Callable[[], str] = read_process_table,
    sleep: Callable[[float], None] = time.sleep,
    monotonic: Callable[[], float] = time.monotonic,
) -> dict[str, object]:
    if root_pid <= 0:
        return {"status": "ERROR", "reason": "invalid_root_pid"}
    if duration_seconds < 0:
        return {"status": "ERROR", "reason": "invalid_duration"}
    if interval_seconds <= 0:
        return {"status": "ERROR", "reason": "invalid_interval"}

    started_at = monotonic()
    deadline = started_at + duration_seconds
    snapshots: list[ProcessSnapshot] = []
    previous_root: ProcessRecord | None = None
    process_group_ids: set[int] = set()
    descendant_elapsed_seconds: dict[int, int] = {}

    while True:
        try:
            records = parse_process_table(read_table())
        except (OSError, subprocess.SubprocessError):
            return {"status": "ERROR", "reason": "process_table_failed"}

        current_root = records.get(root_pid)
        if root_process_was_reused(previous_root, current_root):
            return {"status": "ERROR", "reason": "root_process_reused"}
        if current_root is not None:
            previous_root = current_root
        tree = process_tree_pids(root_pid, records)
        process_group_ids.update(process_group_ids_for_tree(root_pid, tree, records))
        if current_root is not None:
            remember_descendants(root_pid, tree, records, descendant_elapsed_seconds)
        snapshots.append(
            build_snapshot(
                root_pid,
                records,
                process_group_ids,
                descendant_elapsed_seconds,
            )
        )
        now = monotonic()
        if now >= deadline or duration_seconds == 0:
            break
        sleep(min(interval_seconds, deadline - now))

    if not snapshots[0].root_present:
        return {"status": "NOT_RUN", "reason": "root_process_not_found"}

    return {
        "status": "READY",
        "sample_count": len(snapshots),
        "root_present_samples": sum(snapshot.root_present for snapshot in snapshots),
        "process_count_max": max(snapshot.process_count for snapshot in snapshots),
        "cpu_percent": metric_summary([snapshot.cpu_percent for snapshot in snapshots]),
        "rss_kib": metric_summary([float(snapshot.rss_kib) for snapshot in snapshots]),
    }


def wait_for_exit(
    root_pid: int,
    timeout_seconds: float,
    interval_seconds: float,
    read_table: Callable[[], str] = read_process_table,
    sleep: Callable[[float], None] = time.sleep,
    monotonic: Callable[[], float] = time.monotonic,
) -> dict[str, object]:
    """Wait for a root process to disappear without reporting its identity."""
    if root_pid <= 0:
        return {"status": "ERROR", "reason": "invalid_root_pid"}
    if timeout_seconds < 0:
        return {"status": "ERROR", "reason": "invalid_timeout"}
    if interval_seconds <= 0:
        return {"status": "ERROR", "reason": "invalid_interval"}

    deadline = monotonic() + timeout_seconds
    sample_count = 0
    root_seen = False
    previous_root: ProcessRecord | None = None
    process_group_ids: set[int] = set()
    descendant_elapsed_seconds: dict[int, int] = {}
    while True:
        try:
            records = parse_process_table(read_table())
        except (OSError, subprocess.SubprocessError):
            return {"status": "ERROR", "reason": "process_table_failed"}

        sample_count += 1
        current_root = records.get(root_pid)
        if root_process_was_reused(previous_root, current_root):
            return {"status": "ERROR", "reason": "root_process_reused"}
        if current_root is not None:
            previous_root = current_root
            root_seen = True
            tree = process_tree_pids(root_pid, records)
            process_group_ids.update(
                process_group_ids_for_tree(root_pid, tree, records)
            )
            remember_descendants(root_pid, tree, records, descendant_elapsed_seconds)
        elif root_seen:
            remaining = build_snapshot(
                root_pid,
                records,
                process_group_ids,
                descendant_elapsed_seconds,
            )
            if remaining.process_count == 0:
                return {"status": "EXITED", "sample_count": sample_count}
        elif sample_count == 1:
            return {"status": "NOT_RUN", "reason": "root_process_not_found"}

        now = monotonic()
        if now >= deadline:
            return {"status": "STILL_RUNNING", "sample_count": sample_count}
        sleep(min(interval_seconds, deadline - now))


def build_argument_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Measure aggregate CPU/RSS for a process tree without emitting identifiers."
    )
    parser.add_argument("--pid", type=int, required=True, help="root process ID")
    mode = parser.add_mutually_exclusive_group()
    mode.add_argument(
        "--duration", type=float, default=30.0, help="measurement duration in seconds"
    )
    mode.add_argument(
        "--wait-for-exit",
        action="store_true",
        help="wait for the root process to disappear instead of measuring activity",
    )
    parser.add_argument(
        "--timeout", type=float, default=30.0, help="exit wait timeout in seconds"
    )
    parser.add_argument(
        "--interval", type=float, default=1.0, help="sampling interval in seconds"
    )
    return parser


def main() -> int:
    args = build_argument_parser().parse_args()
    if args.wait_for_exit:
        result = wait_for_exit(args.pid, args.timeout, args.interval)
    else:
        result = measure(args.pid, args.duration, args.interval)
    print(json.dumps(result, ensure_ascii=False, sort_keys=True))
    return 1 if result["status"] == "ERROR" else 0


if __name__ == "__main__":
    raise SystemExit(main())
