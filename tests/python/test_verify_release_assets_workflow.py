"""Regression tests for release asset verification workflow ordering."""

import unittest
from pathlib import Path


WORKFLOW_PATH = (
    Path(__file__).resolve().parents[2]
    / ".github"
    / "workflows"
    / "verify-release-assets.yml"
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


if __name__ == "__main__":
    unittest.main()
