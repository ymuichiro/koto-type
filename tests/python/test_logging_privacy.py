#!/usr/bin/env python3
# -*- coding: utf-8 -*-

import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

from python import whisper_server


class LoggingPrivacyTests(unittest.TestCase):
    def test_sanitize_log_message_redacts_absolute_paths(self):
        message = "failed to process /Users/example/recordings/sample.wav and /usr/local/bin/ffmpeg"

        sanitized = whisper_server.sanitize_log_message(message)

        self.assertNotIn("/Users/example", sanitized)
        self.assertNotIn("/usr/local", sanitized)
        self.assertEqual(sanitized, "failed to process <path> and <path>")

    def test_setup_logging_writes_redacted_message(self):
        with tempfile.TemporaryDirectory() as temporary_home:
            with patch.dict(os.environ, {"HOME": temporary_home}, clear=False):
                log_file, log = whisper_server.setup_logging()
                log("failed to process /private/tmp/kototype.wav")

                contents = Path(log_file).read_text(encoding="utf-8")

        self.assertNotIn("/private/tmp", contents)
        self.assertIn("failed to process <path>", contents)

    def test_sanitize_log_message_redacts_quoted_paths_with_spaces(self):
        message = 'script="/Users/example/Library/Application Support/koto-type/server.py"'

        sanitized = whisper_server.sanitize_log_message(message)

        self.assertEqual(sanitized, 'script="<path>"')

    def test_sanitize_log_message_redacts_file_urls_and_smart_quoted_paths(self):
        message = (
            "url=file:///Users/example/Library/Application%20Support/koto-type/server.py, "
            "error=The file “/Users/example/recording.wav” could not be saved"
        )

        sanitized = whisper_server.sanitize_log_message(message)

        self.assertEqual(
            sanitized,
            "url=<path>, error=The file “<path>” could not be saved",
        )


if __name__ == "__main__":
    unittest.main()
