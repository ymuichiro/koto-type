#!/usr/bin/env python3
# -*- coding: utf-8 -*-

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


if __name__ == "__main__":
    unittest.main()
