import tempfile
import unittest
from pathlib import Path

from tools.scan_secrets import display_path, scan_bytes, scan_paths


class SecretScanTests(unittest.TestCase):
    def test_workflow_scans_on_push_and_pull_request_with_read_only_permissions(self):
        project_root = Path(__file__).resolve().parents[2]
        workflow = (project_root / ".github" / "workflows" / "secret-scan.yml").read_text(
            encoding="utf-8"
        )

        self.assertIn("  push:\n", workflow)
        self.assertIn("  pull_request:\n", workflow)
        self.assertIn("contents: read", workflow)
        self.assertIn("run: python3 tools/scan_secrets.py", workflow)

    def test_detects_high_confidence_credentials_without_returning_values(self):
        fake_token = b"hf_" + b"A" * 34

        findings = scan_bytes(Path("notes.txt"), b"token=" + fake_token)

        self.assertEqual([finding.rule for finding in findings], ["huggingface-token"])
        self.assertNotIn(fake_token.decode(), repr(findings))

    def test_detects_private_key_headers(self):
        header = b"-----BEGIN " + b"OPENSSH " + b"PRIVATE KEY-----"

        findings = scan_bytes(Path("key.txt"), header + b"\nexample")

        self.assertEqual([finding.rule for finding in findings], ["private-key"])

    def test_scans_binary_like_content(self):
        findings = scan_bytes(Path("image.bin"), b"\0hf_" + b"A" * 34)

        self.assertEqual([finding.rule for finding in findings], ["huggingface-token"])

    def test_scans_explicit_paths_and_reports_only_path_and_rule(self):
        with tempfile.TemporaryDirectory() as temporary_directory:
            path = Path(temporary_directory) / "secret.txt"
            path.write_bytes(b"github_pat_" + b"B" * 30)

            findings = scan_paths([path])

        self.assertEqual(len(findings), 1)
        self.assertEqual(findings[0].path, path)
        self.assertEqual(findings[0].rule, "github-pat")

    def test_display_path_does_not_expose_directories_outside_repository(self):
        project_root = Path("/repo")

        self.assertEqual(
            display_path(project_root / "nested" / "secret.txt", project_root),
            "nested/secret.txt",
        )
        self.assertEqual(
            display_path(Path("/private/tmp/secret.txt"), project_root),
            "secret.txt",
        )


if __name__ == "__main__":
    unittest.main()
