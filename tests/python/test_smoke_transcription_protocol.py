import json
import unittest
from unittest.mock import patch

from tests.python import smoke_whisper_server_binary as smoke


class SmokeTranscriptionProtocolTests(unittest.TestCase):
    def response(self, **values):
        return "__KOTOTYPE_CONTROL__:" + json.dumps(values)

    def test_old_and_wrong_identity_lines_cannot_pass_smoke(self):
        lines = [
            "uncorrelated text",
            self.response(type="backend_status"),
            self.response(type="transcription_result", request_id="old", text="stale"),
            self.response(
                type="transcription_result", request_id="current", text="日本語"
            ),
        ]
        with patch.object(smoke, "wait_for_line", side_effect=lines):
            self.assertEqual(
                smoke.wait_for_transcript_line(None, 1, "current"), "日本語"
            )

    def test_error_is_not_a_passing_transcript(self):
        line = self.response(
            type="transcription_result", request_id="current", error="invalid_audio"
        )
        with (
            patch.object(smoke, "wait_for_line", return_value=line),
            self.assertRaises(RuntimeError),
        ):
            smoke.wait_for_transcript_line(None, 1, "current")

    def test_no_implicit_sine_wave_speech_fixture(self):
        with patch.dict(smoke.os.environ, {"KOTOTYPE_SMOKE_AUDIO_PATH": ""}):
            self.assertIsNone(smoke.resolve_smoke_audio_path())
