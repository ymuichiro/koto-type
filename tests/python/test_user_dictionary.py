#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import ast
import json
import sys
import tempfile
import unittest
from pathlib import Path

PROJECT_ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(PROJECT_ROOT / "python"))

import whisper_server  # noqa: E402


class UserDictionaryTests(unittest.TestCase):
    def test_normalize_user_words(self):
        words = whisper_server.normalize_user_words(
            ["  OpenAI  ", "", "openai", "  Whisper   Turbo ", "日本語  用語", None]
        )
        self.assertEqual(words, ["OpenAI", "Whisper Turbo", "日本語 用語"])

    def test_load_user_dictionary_from_custom_path(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            dict_path = Path(temp_dir) / "user_dictionary.json"
            dict_path.write_text(
                json.dumps({"words": ["  ctranslate2  ", "CTranslate2", "MPS"]}),
                encoding="utf-8",
            )
            words = whisper_server.load_user_dictionary(path=str(dict_path))
            self.assertEqual(words, ["ctranslate2", "MPS"])

    def test_load_user_dictionary_supports_legacy_array(self):
        with tempfile.TemporaryDirectory() as temp_dir:
            dict_path = Path(temp_dir) / "user_dictionary.json"
            dict_path.write_text(
                json.dumps(["  Faster Whisper  ", "faster whisper", "GPU"]),
                encoding="utf-8",
            )
            words = whisper_server.load_user_dictionary(path=str(dict_path))
            self.assertEqual(words, ["Faster Whisper", "GPU"])

    def test_generate_initial_prompt_includes_terms(self):
        prompt = whisper_server.generate_initial_prompt(
            "ja",
            use_context=True,
            user_words=["OpenAI", "openai", "faster-whisper"],
        )
        self.assertIsNotNone(prompt)
        self.assertIn("OpenAI", prompt)
        self.assertIn("faster-whisper", prompt)
        self.assertEqual(prompt.count("OpenAI"), 1)

    def test_post_process_text_with_auto_punctuation_enabled(self):
        text = "今日は晴れです そして散歩に行きます"
        processed = whisper_server.post_process_text(
            text,
            language="ja",
            auto_punctuation=True,
        )
        self.assertEqual(processed, "今日は晴れです そして散歩に行きます。")

    def test_post_process_text_with_auto_punctuation_disabled(self):
        text = "今日は晴れです そして散歩に行きます"
        processed = whisper_server.post_process_text(
            text,
            language="ja",
            auto_punctuation=False,
        )
        self.assertEqual(processed, "今日は晴れです そして散歩に行きます")

    def test_post_process_text_does_not_duplicate_japanese_comma(self):
        text = "こういったものは除外するか、またはそもそも入らないようにしたい"
        processed = whisper_server.post_process_text(
            text,
            language="ja",
            auto_punctuation=True,
        )
        self.assertEqual(
            processed,
            "こういったものは除外するか、またはそもそも入らないようにしたい。",
        )

    def test_post_process_text_english_preserves_decimals_and_email(self):
        text = "The value is 3.14 and contact is a.b@example.com now"
        processed = whisper_server.post_process_text(
            text,
            language="en",
            auto_punctuation=True,
        )
        self.assertIn("3.14", processed)
        self.assertIn("a.b@example.com", processed)
        self.assertNotIn("3. 14", processed)
        self.assertNotIn("a. b@example. com", processed)
        self.assertTrue(processed.endswith("."))

    def test_main_guard_calls_freeze_support_before_main(self):
        source = (PROJECT_ROOT / "python" / "whisper_server.py").read_text(
            encoding="utf-8"
        )
        module = ast.parse(source)

        main_guards = []
        for node in module.body:
            if not isinstance(node, ast.If):
                continue
            if not isinstance(node.test, ast.Compare):
                continue
            if len(node.test.ops) != 1 or not isinstance(node.test.ops[0], ast.Eq):
                continue
            if len(node.test.comparators) != 1:
                continue
            if not isinstance(node.test.left, ast.Name) or node.test.left.id != "__name__":
                continue
            comparator = node.test.comparators[0]
            if isinstance(comparator, ast.Constant) and comparator.value == "__main__":
                main_guards.append(node)

        self.assertTrue(main_guards, "Expected __name__ == '__main__' guard")

        call_names = []
        for statement in main_guards[0].body:
            if not isinstance(statement, ast.Expr):
                continue
            if not isinstance(statement.value, ast.Call):
                continue
            function = statement.value.func
            if isinstance(function, ast.Attribute) and isinstance(function.value, ast.Name):
                call_names.append(f"{function.value.id}.{function.attr}")
            elif isinstance(function, ast.Name):
                call_names.append(function.id)

        self.assertIn("multiprocessing.freeze_support", call_names)
        self.assertIn("main", call_names)
        self.assertLess(
            call_names.index("multiprocessing.freeze_support"),
            call_names.index("main"),
        )


if __name__ == "__main__":
    unittest.main()
