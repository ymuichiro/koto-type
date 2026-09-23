import json
import unittest
from typing import cast
from unittest.mock import Mock

from tools import measure_process_activity


class ProcessActivityTests(unittest.TestCase):
    def test_parse_elapsed_time_supports_mac_os_ps_formats(self):
        self.assertEqual(measure_process_activity.parse_elapsed_time("00:01"), 1)
        self.assertEqual(measure_process_activity.parse_elapsed_time("01:02:03"), 3723)
        self.assertEqual(
            measure_process_activity.parse_elapsed_time("2-03:04:05"), 183845
        )
        self.assertIsNone(measure_process_activity.parse_elapsed_time("not-time"))
        self.assertIsNone(measure_process_activity.parse_elapsed_time("01:60"))

    def test_build_snapshot_includes_descendants_without_exposing_identifiers(self):
        records = measure_process_activity.parse_process_table(
            """
            100 1 2.5 120
            101 100 10.0 300
            102 101 1.5 80
            999 1 99.0 9999 /private/path/should-not-be-used
            """
        )

        snapshot = measure_process_activity.build_snapshot(100, records)

        self.assertTrue(snapshot.root_present)
        self.assertEqual(snapshot.process_count, 3)
        self.assertEqual(snapshot.cpu_percent, 14.0)
        self.assertEqual(snapshot.rss_kib, 500)
        self.assertNotIn("/private/path", json.dumps(snapshot.__dict__))

    def test_build_snapshot_includes_reparented_members_of_root_process_group(self):
        records = measure_process_activity.parse_process_table(
            """
            100 1 2.5 120 00:10 100
            101 1 10.0 300 00:10 100
            102 101 1.5 80 00:10 100
            200 1 99.0 9999 00:10 200
            """
        )

        snapshot = measure_process_activity.build_snapshot(100, records)

        self.assertTrue(snapshot.root_present)
        self.assertEqual(snapshot.process_count, 3)
        self.assertEqual(snapshot.cpu_percent, 14.0)
        self.assertEqual(snapshot.rss_kib, 500)

    def test_build_snapshot_excludes_unrelated_members_of_inherited_root_group(self):
        records = measure_process_activity.parse_process_table(
            """
            100 1 2.5 120 00:10 1
            101 100 10.0 300 00:10 1
            999 1 99.0 9999 00:10 1
            """
        )

        snapshot = measure_process_activity.build_snapshot(100, records)

        self.assertEqual(snapshot.process_count, 2)
        self.assertEqual(snapshot.cpu_percent, 12.5)
        self.assertEqual(snapshot.rss_kib, 420)

    def test_parse_process_table_accepts_optional_elapsed_and_process_group(self):
        records = measure_process_activity.parse_process_table(
            "100 1 2.0 100 01:02:03 100\n"
        )

        self.assertEqual(records[100].elapsed_seconds, 3723)
        self.assertEqual(records[100].process_group_id, 100)

    def test_measure_reports_aggregate_metrics_without_process_identifiers(self):
        table = "100 1 2.0 100\n101 100 4.0 200\n"
        clock = iter([0.0, 0.0, 1.0])
        result = measure_process_activity.measure(
            root_pid=100,
            duration_seconds=0,
            interval_seconds=1,
            read_table=Mock(return_value=table),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result["status"], "READY")
        self.assertEqual(result["sample_count"], 1)
        self.assertEqual(result["root_present_samples"], 1)
        self.assertEqual(result["process_count_max"], 2)
        self.assertEqual(result["cpu_percent"], {"p50": 6.0, "p95": 6.0, "max": 6.0})
        self.assertEqual(result["rss_kib"], {"p50": 300.0, "p95": 300.0, "max": 300.0})
        self.assertNotIn("100", json.dumps(result))
        self.assertNotIn("101", json.dumps(result))

    def test_measure_aggregates_reparented_process_group_members(self):
        table = "100 1 2.0 100 00:10 100\n101 1 4.0 200 00:10 100\n"
        result = measure_process_activity.measure(
            root_pid=100,
            duration_seconds=0,
            interval_seconds=1,
            read_table=Mock(return_value=table),
        )

        self.assertEqual(result["status"], "READY")
        self.assertEqual(result["process_count_max"], 2)
        self.assertEqual(result["cpu_percent"], {"p50": 6.0, "p95": 6.0, "max": 6.0})
        self.assertEqual(result["rss_kib"], {"p50": 300.0, "p95": 300.0, "max": 300.0})

    def test_snapshot_marks_root_missing_while_retaining_group_members(self):
        records = measure_process_activity.parse_process_table(
            "101 1 4.0 200 00:10 100\n"
        )

        snapshot = measure_process_activity.build_snapshot(100, records, {100})

        self.assertFalse(snapshot.root_present)
        self.assertEqual(snapshot.process_count, 1)
        self.assertEqual(snapshot.cpu_percent, 4.0)
        self.assertEqual(snapshot.rss_kib, 200)

    def test_snapshot_keeps_verified_orphan_outside_shared_root_group(self):
        records = measure_process_activity.parse_process_table(
            "101 1 4.0 200 00:11 1\n999 1 99.0 9999 00:11 1\n"
        )

        snapshot = measure_process_activity.build_snapshot(
            100,
            records,
            descendant_elapsed_seconds={101: 10},
        )

        self.assertFalse(snapshot.root_present)
        self.assertEqual(snapshot.process_count, 1)
        self.assertEqual(snapshot.cpu_percent, 4.0)
        self.assertEqual(snapshot.rss_kib, 200)

    def test_snapshot_excludes_reused_orphan_pid(self):
        records = measure_process_activity.parse_process_table(
            "101 1 4.0 200 00:02 1\n"
        )

        snapshot = measure_process_activity.build_snapshot(
            100,
            records,
            descendant_elapsed_seconds={101: 10},
        )

        self.assertEqual(snapshot.process_count, 0)

    def test_measure_keeps_descendant_groups_after_reparenting(self):
        tables = iter(
            [
                "100 1 2.0 100 00:10 100\n101 100 4.0 200 00:10 200\n",
                "100 1 2.0 100 00:10 100\n"
                "101 1 4.0 200 00:10 200\n"
                "102 1 1.0 50 00:10 200\n",
            ]
        )
        clock = iter([0.0, 0.0, 0.1])
        result = measure_process_activity.measure(
            root_pid=100,
            duration_seconds=0.1,
            interval_seconds=0.1,
            read_table=lambda: next(tables),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result["status"], "READY")
        self.assertEqual(result["process_count_max"], 3)
        cpu_percent = cast(dict[str, float], result["cpu_percent"])
        rss_kib = cast(dict[str, float], result["rss_kib"])
        self.assertEqual(cpu_percent["max"], 7.0)
        self.assertEqual(rss_kib["max"], 350.0)

    def test_measure_keeps_verified_orphan_from_shared_root_group(self):
        tables = iter(
            [
                "100 1 2.0 100 00:10 1\n"
                "101 100 4.0 200 00:10 1\n"
                "999 1 99.0 9999 00:10 1\n",
                "101 1 4.0 200 00:11 1\n999 1 99.0 9999 00:11 1\n",
            ]
        )
        clock = iter([0.0, 0.0, 0.1])
        result = measure_process_activity.measure(
            root_pid=100,
            duration_seconds=0.1,
            interval_seconds=0.1,
            read_table=lambda: next(tables),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result["status"], "READY")
        self.assertEqual(result["root_present_samples"], 1)
        self.assertEqual(result["process_count_max"], 2)
        self.assertEqual(result["cpu_percent"], {"p50": 4.0, "p95": 6.0, "max": 6.0})
        self.assertEqual(result["rss_kib"], {"p50": 200.0, "p95": 300.0, "max": 300.0})

    def test_measure_returns_not_run_when_root_is_missing(self):
        result = measure_process_activity.measure(
            root_pid=100,
            duration_seconds=0,
            interval_seconds=1,
            read_table=Mock(return_value="200 1 0.0 10\n"),
        )

        self.assertEqual(
            result, {"status": "NOT_RUN", "reason": "root_process_not_found"}
        )

    def test_measure_rejects_root_pid_reuse(self):
        tables = iter(
            [
                "100 1 2.0 100 00:10\n",
                "100 1 2.0 100 00:02\n",
            ]
        )
        clock = iter([0.0, 0.0, 0.1])
        result = measure_process_activity.measure(
            root_pid=100,
            duration_seconds=1,
            interval_seconds=0.1,
            read_table=lambda: next(tables),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result, {"status": "ERROR", "reason": "root_process_reused"})

    def test_wait_for_exit_reports_exit_without_identifiers(self):
        tables = iter(
            [
                "100 1 2.0 100\n101 100 4.0 200\n",
                "200 1 0.0 10\n",
            ]
        )
        clock = iter([0.0, 0.0, 0.1])
        result = measure_process_activity.wait_for_exit(
            root_pid=100,
            timeout_seconds=1,
            interval_seconds=0.1,
            read_table=lambda: next(tables),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result, {"status": "EXITED", "sample_count": 2})
        self.assertNotIn("100", json.dumps(result))

    def test_wait_for_exit_waits_for_reparented_process_group_members(self):
        tables = iter(
            [
                "100 1 2.0 100 00:10 100\n101 100 4.0 200 00:10 200\n",
                "101 1 4.0 200 00:10 200\n",
                "200 1 0.0 10 00:10 300\n",
            ]
        )
        clock = iter([0.0, 0.0, 0.1, 0.2])
        result = measure_process_activity.wait_for_exit(
            root_pid=100,
            timeout_seconds=1,
            interval_seconds=0.1,
            read_table=lambda: next(tables),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result, {"status": "EXITED", "sample_count": 3})

    def test_wait_for_exit_waits_for_verified_orphan_from_shared_root_group(self):
        tables = iter(
            [
                "100 1 2.0 100 00:10 1\n"
                "101 100 4.0 200 00:10 1\n"
                "999 1 99.0 9999 00:10 1\n",
                "101 1 4.0 200 00:11 1\n999 1 99.0 9999 00:11 1\n",
                "101 1 4.0 200 00:12 1\n999 1 99.0 9999 00:12 1\n",
            ]
        )
        clock = iter([0.0, 0.0, 0.1, 0.2])
        result = measure_process_activity.wait_for_exit(
            root_pid=100,
            timeout_seconds=0.2,
            interval_seconds=0.1,
            read_table=lambda: next(tables),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result, {"status": "STILL_RUNNING", "sample_count": 3})

    def test_wait_for_exit_reports_still_running_when_group_member_remains(self):
        tables = iter(
            [
                "100 1 2.0 100 00:10 100\n101 100 4.0 200 00:10 200\n",
                "101 1 4.0 200 00:10 200\n",
                "101 1 4.0 200 00:10 200\n",
            ]
        )
        clock = iter([0.0, 0.0, 0.1, 0.2, 0.3])
        result = measure_process_activity.wait_for_exit(
            root_pid=100,
            timeout_seconds=0.2,
            interval_seconds=0.1,
            read_table=lambda: next(tables),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result, {"status": "STILL_RUNNING", "sample_count": 3})

    def test_wait_for_exit_does_not_treat_missing_root_as_exited(self):
        result = measure_process_activity.wait_for_exit(
            root_pid=100,
            timeout_seconds=1,
            interval_seconds=0.1,
            read_table=Mock(return_value="200 1 0.0 10\n"),
        )

        self.assertEqual(
            result, {"status": "NOT_RUN", "reason": "root_process_not_found"}
        )

    def test_wait_for_exit_reports_still_running_at_timeout(self):
        clock = iter([0.0, 0.0, 0.1, 0.2, 0.25])
        result = measure_process_activity.wait_for_exit(
            root_pid=100,
            timeout_seconds=0.25,
            interval_seconds=0.1,
            read_table=Mock(return_value="100 1 0.0 10\n"),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result, {"status": "STILL_RUNNING", "sample_count": 4})

    def test_wait_for_exit_rejects_root_pid_reuse(self):
        tables = iter(
            [
                "100 1 0.0 10 00:10\n",
                "100 1 0.0 10 00:02\n",
            ]
        )
        clock = iter([0.0, 0.0, 0.1])
        result = measure_process_activity.wait_for_exit(
            root_pid=100,
            timeout_seconds=1,
            interval_seconds=0.1,
            read_table=lambda: next(tables),
            sleep=Mock(),
            monotonic=lambda: next(clock),
        )

        self.assertEqual(result, {"status": "ERROR", "reason": "root_process_reused"})

    def test_wait_for_exit_rejects_invalid_arguments_and_ps_failure(self):
        self.assertEqual(
            measure_process_activity.wait_for_exit(0, 0, 1),
            {"status": "ERROR", "reason": "invalid_root_pid"},
        )
        self.assertEqual(
            measure_process_activity.wait_for_exit(100, -1, 1),
            {"status": "ERROR", "reason": "invalid_timeout"},
        )
        self.assertEqual(
            measure_process_activity.wait_for_exit(100, 0, 0),
            {"status": "ERROR", "reason": "invalid_interval"},
        )
        failing_reader = Mock(side_effect=OSError("ps unavailable"))
        self.assertEqual(
            measure_process_activity.wait_for_exit(
                100, 0, 1, read_table=failing_reader
            ),
            {"status": "ERROR", "reason": "process_table_failed"},
        )

    def test_measure_returns_error_for_invalid_arguments_or_ps_failure(self):
        self.assertEqual(
            measure_process_activity.measure(0, 0, 1),
            {"status": "ERROR", "reason": "invalid_root_pid"},
        )
        self.assertEqual(
            measure_process_activity.measure(100, -1, 1),
            {"status": "ERROR", "reason": "invalid_duration"},
        )
        self.assertEqual(
            measure_process_activity.measure(100, 0, 0),
            {"status": "ERROR", "reason": "invalid_interval"},
        )
        failing_reader = Mock(side_effect=OSError("ps unavailable"))
        self.assertEqual(
            measure_process_activity.measure(100, 0, 1, read_table=failing_reader),
            {"status": "ERROR", "reason": "process_table_failed"},
        )


if __name__ == "__main__":
    unittest.main()
