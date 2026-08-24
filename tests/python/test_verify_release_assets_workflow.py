"""Regression tests for release asset verification workflow ordering."""

import unittest
from pathlib import Path


WORKFLOW_PATH = (
    Path(__file__).resolve().parents[2]
    / ".github"
    / "workflows"
    / "verify-release-assets.yml"
)

RELEASE_WORKFLOW_PATH = (
    Path(__file__).resolve().parents[2]
    / ".github"
    / "workflows"
    / "release.yml"
)

BENCHMARK_WORKFLOW_PATH = (
    Path(__file__).resolve().parents[2]
    / ".github"
    / "workflows"
    / "benchmark.yml"
)


class VerifyReleaseAssetsWorkflowTests(unittest.TestCase):
    def test_checks_out_the_resolved_release_tag(self) -> None:
        workflow = WORKFLOW_PATH.read_text(encoding="utf-8")
        resolve_start = workflow.index("- name: Resolve target release tag")
        checkout_start = workflow.index("- name: Checkout target release ref")
        checkout_end = workflow.find("\n      - name:", checkout_start + 1)
        checkout_step = workflow[checkout_start:checkout_end]

        self.assertLess(resolve_start, checkout_start)
        self.assertIn("ref: ${{ steps.target.outputs.tag }}", checkout_step)
        self.assertIn("fetch-depth: 1", checkout_step)

    def test_cpu_model_is_prepared_before_both_smoke_checks(self):
        workflow = RELEASE_WORKFLOW_PATH.read_text(encoding="utf-8")
        prepare_start = workflow.index("- name: Prepare CPU model for release smoke")
        binary_smoke_start = workflow.index("- name: Smoke Test Python Server Binary")
        bundle_smoke_start = workflow.index("- name: Verify bundled whisper_server binary")

        self.assertLess(prepare_start, binary_smoke_start)
        self.assertLess(binary_smoke_start, bundle_smoke_start)
        self.assertIn("DEFAULT_CPU_MODEL_ID", workflow[prepare_start:binary_smoke_start])
        self.assertIn("utils.download_model", workflow[prepare_start:binary_smoke_start])
        self.assertEqual(
            workflow.count(
                "KOTOTYPE_CPU_MODEL_DIR: ${{ runner.temp }}/koto-type-cpu-model"
            ),
            3,
        )

    def test_benchmark_workflow_installs_mlx_extra_before_running_benchmark(self):
        workflow = BENCHMARK_WORKFLOW_PATH.read_text(encoding="utf-8")
        install_start = workflow.index("- name: Install ffmpeg")
        benchmark_start = workflow.index("- name: Run benchmark")
        install_step = workflow[install_start:benchmark_start]

        self.assertIn("uv sync --extra mlx --extra dev", install_step)
        self.assertIn("brew install ffmpeg", install_step)


if __name__ == "__main__":
    unittest.main()
