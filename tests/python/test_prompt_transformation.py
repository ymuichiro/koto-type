#!/usr/bin/env python3

import tempfile
import unittest

from python import whisper_server


class PromptTransformationTests(unittest.TestCase):
    def test_prompt_mode_is_accepted_without_changing_whisper_task(self):
        self.assertEqual(whisper_server.normalize_request_mode(" prompt "), "prompt")
        self.assertEqual(
            whisper_server.select_whisper_task("prompt", "ja"), "transcribe"
        )
        self.assertEqual(
            whisper_server.select_whisper_task("faithful", "en"), "transcribe"
        )

    def test_prompt_messages_preserve_no_fabrication_contract(self):
        messages = whisper_server.build_prompt_messages(
            "GitHub に issue を作る。期限は未定。", "ja"
        )

        system = messages[0]["content"]
        user = messages[1]["content"]
        self.assertIn("do not invent", system.lower())
        self.assertIn("do not answer", system.lower())
        self.assertIn("Markdown", system)
        self.assertIn("期限は未定", user)
        self.assertTrue(user.endswith("/no_think"))

    def test_prompt_markdown_normalization_removes_wrappers_only(self):
        generated = (
            "<think>internal reasoning</think>\n```markdown\n# Goal\nunknown\n```"
        )

        self.assertEqual(
            whisper_server.normalize_prompt_markdown(generated),
            "# Goal\nunknown",
        )

    def test_prompt_markdown_normalization_preserves_embedded_code_fence(self):
        generated = "# Code\n```python\nprint('keep this')\n```"

        self.assertEqual(
            whisper_server.normalize_prompt_markdown(generated),
            generated,
        )

    def test_prompt_model_fallback_is_raw_text_when_empty(self):
        class FailingBackendManager(whisper_server.BackendManager):
            def _ensure_prompt_model(self):
                raise RuntimeError("test failure")

        with tempfile.TemporaryDirectory() as temp_dir:
            manager = FailingBackendManager(
                state_path=f"{temp_dir}/state.json",
                lock_path=f"{temp_dir}/state.lock",
                pid=1234,
                max_parallel_model_loads=1,
                model_load_wait_timeout=1,
                cpu_model_dir=f"{temp_dir}/cpu",
                mlx_model_dir=f"{temp_dir}/mlx",
                model_cache_dir=f"{temp_dir}/cache",
                log=lambda _: None,
            )
            transformed, used_fallback = manager.transform_prompt(
                "Keep this exact wording."
            )

        self.assertEqual(transformed, "Keep this exact wording.")
        self.assertTrue(used_fallback)


if __name__ == "__main__":
    unittest.main()
