import unittest
from pathlib import Path


PROJECT_ROOT = Path(__file__).resolve().parents[2]


class PublicCompatibilityDocsTests(unittest.TestCase):
    def test_public_pages_describe_current_release_support_policy(self):
        expected_snippets = {
            "docs/index.html": [
                '<span class="chip">macOS 26+ (current release)</span>',
                "macOS 14 and 15 may work through the CPU-only path",
                "macOS 13 remains a Swift source deployment target only",
            ],
            "docs/en/index.html": [
                '<span class="chip">macOS 26+ (current release)</span>',
                "macOS 14 and 15 may work through the CPU-only path",
                "macOS 13 remains a Swift source deployment target only",
            ],
            "docs/ja/index.html": [
                '<span class="chip">macOS 26+（現行Release）</span>',
                "macOS 14および15でもCPU-only経路",
                "macOS 13はSwiftのソースターゲットとしてのみ",
            ],
        }

        for relative_path, snippets in expected_snippets.items():
            with self.subTest(relative_path=relative_path):
                content = (PROJECT_ROOT / relative_path).read_text(encoding="utf-8")
                for snippet in snippets:
                    self.assertIn(snippet, content)

                self.assertNotIn(
                    '<span class="chip">macOS 13+</span>',
                    content,
                )


if __name__ == "__main__":
    unittest.main()
