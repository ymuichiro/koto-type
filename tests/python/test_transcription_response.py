import io
import json
import subprocess
import sys
import tempfile
import unittest
import wave
from contextlib import redirect_stdout
from pathlib import Path

from python import whisper_server as server


class TranscriptionResponseTests(unittest.TestCase):
    def test_low_activity_is_recoverable_and_processed_copy_is_cleaned(self):
        for sample in (0, 1):
            with (
                self.subTest(sample=sample),
                tempfile.TemporaryDirectory() as directory,
            ):
                source = Path(directory) / "source.wav"
                processed = Path(directory) / "processed.wav"
                for path in (source, processed):
                    with wave.open(str(path), "wb") as audio:
                        audio.setparams((1, 2, 16000, 0, "NONE", "not compressed"))
                        audio.writeframes(
                            sample.to_bytes(2, "little", signed=True) * 32000
                        )
                original = source.read_bytes()
                result = subprocess.run(
                    [
                        sys.executable,
                        "-c",
                        "import sys; from python import whisper_server as s; "
                        "s.default_application_support_directory=lambda:sys.argv[1]; "
                        "s.audio_preprocess=lambda path,log:sys.argv[2]; s.main()",
                        directory,
                        str(processed),
                    ],
                    cwd=Path(__file__).resolve().parents[2],
                    input=json.dumps(
                        dict(
                            type="transcription_request",
                            request_id="quiet",
                            audio_path=str(source),
                            gpu_acceleration_enabled=False,
                        )
                    )
                    + "\n",
                    text=True,
                    capture_output=True,
                    timeout=15,
                    check=True,
                )
                responses = [
                    json.loads(line[len(server.CONTROL_MESSAGE_PREFIX) :])
                    for line in result.stdout.splitlines()
                    if line.startswith(server.CONTROL_MESSAGE_PREFIX)
                ]
                self.assertEqual(
                    {
                        "results": [
                            r
                            for r in responses
                            if r.get("type") == "transcription_result"
                        ],
                        "processed_exists": processed.exists(),
                        "source_preserved": source.read_bytes() == original,
                    },
                    {
                        "results": [
                            dict(
                                type="transcription_result",
                                request_id="quiet",
                                error="insufficient_audio",
                            )
                        ],
                        "processed_exists": False,
                        "source_preserved": True,
                    },
                )

    def test_confidence_rejection_is_failure_not_empty_success(self):
        self.assert_rejected_result("...", "transcribe", "unreliable_transcription")

    def test_translation_rejection_is_failure_not_empty_success(self):
        self.assert_rejected_result(
            "これは日本語のままです。", "translate", "unsupported_translation_output"
        )

    def assert_rejected_result(self, text, mode, error):
        # Stub audio and inference; exercise the real gate, stdin loop and envelope.
        with tempfile.TemporaryDirectory() as directory:
            source = Path(directory) / "input.wav"
            source.write_bytes(b"test source preserved")
            code = """
import sys
from types import SimpleNamespace as S
from python import whisper_server as s
s.default_application_support_directory = lambda: sys.argv[1]
s.load_user_dictionary = lambda **kw: []
s.audio_preprocess = lambda path, log: path
s.analyze_wav_activity = lambda path: s.AudioActivityStats(3, -10, 3, 1, 150)
s.BackendManager.transcribe_with_details = lambda *a, **kw: S(
    text=sys.argv[2], detected_language='ja', segment_metrics=[],
    status=s.BackendStatus('cpu', False, False, 'gpu_disabled_in_settings'))
s.main()
"""
            result = subprocess.run(
                [sys.executable, "-c", code, directory, text],
                cwd=Path(__file__).resolve().parents[2],
                input=json.dumps(
                    {
                        "type": "transcription_request",
                        "request_id": "rejected",
                        "audio_path": str(source),
                        "mode": mode,
                        "translation_target_language": "en",
                    }
                )
                + "\n",
                text=True,
                capture_output=True,
                timeout=15,
                check=True,
            )
            payloads = [
                json.loads(line[len(server.CONTROL_MESSAGE_PREFIX) :])
                for line in result.stdout.splitlines()
                if line.startswith(server.CONTROL_MESSAGE_PREFIX)
            ]
            responses = [p for p in payloads if p.get("type") == "transcription_result"]
            self.assertEqual(
                responses,
                [
                    {
                        "type": "transcription_result",
                        "request_id": "rejected",
                        "error": error,
                    }
                ],
            )
            self.assertEqual(source.read_bytes(), b"test source preserved")

    def test_real_server_stdin_error_keeps_identity_without_blank_success(self):
        with tempfile.TemporaryDirectory() as directory:
            request = {
                "type": "transcription_request",
                "request_id": "attempt-123",
                "audio_path": str(Path(directory) / "missing.wav"),
            }
            unsupported = {**request, "request_id": "rejected-123", "mode": "unknown"}
            result = subprocess.run(
                [
                    sys.executable,
                    "-c",
                    "import sys; from python import whisper_server as s; "
                    "s.default_application_support_directory=lambda:sys.argv[1]; s.main()",
                    directory,
                ],
                cwd=Path(__file__).resolve().parents[2],
                input="not-json\n"
                + json.dumps(unsupported)
                + "\n"
                + json.dumps(request)
                + "\n",
                text=True,
                capture_output=True,
                timeout=15,
                check=True,
            )
            lines = result.stdout.splitlines()
            self.assertEqual(len(lines), 2)
            self.assertTrue(lines[0].startswith(server.CONTROL_MESSAGE_PREFIX))
            self.assertEqual(
                json.loads(lines[0][len(server.CONTROL_MESSAGE_PREFIX) :]),
                {
                    "type": "transcription_result",
                    "request_id": "rejected-123",
                    "error": "invalid_request",
                },
            )
            self.assertEqual(
                json.loads(lines[1][len(server.CONTROL_MESSAGE_PREFIX) :]),
                {
                    "type": "transcription_result",
                    "request_id": "attempt-123",
                    "error": "invalid_audio",
                },
            )

    def test_request_requires_bounded_string_identity(self):
        for identity in (None, 1, True, "", "a" * 65, "id\nother"):
            with self.subTest(identity=identity), self.assertRaises(ValueError):
                server.parse_request_line(
                    json.dumps(
                        {
                            "type": "transcription_request",
                            "request_id": identity,
                            "audio_path": "test.wav",
                        }
                    )
                )

    def test_request_preserves_identity(self):
        request = server.parse_request_line(
            json.dumps(
                {
                    "type": "transcription_request",
                    "request_id": "attempt-123",
                    "audio_path": "test.wav",
                }
            )
        )["request"]
        self.assertEqual(request.request_id, "attempt-123")

    def test_success_and_failure_are_distinct_single_line_envelopes(self):
        for content in (
            {"text": "日本語\n次の行"},
            {"text": ""},
            {"error": "invalid_audio"},
        ):
            with self.subTest(content=content):
                output = io.StringIO()
                with redirect_stdout(output):
                    server.emit_transcription_result("attempt-123", **content)
                lines = output.getvalue().splitlines()
                self.assertEqual(len(lines), 1)
                self.assertTrue(lines[0].startswith(server.CONTROL_MESSAGE_PREFIX))
                payload = json.loads(lines[0][len(server.CONTROL_MESSAGE_PREFIX) :])
                self.assertEqual(
                    payload,
                    {
                        "type": "transcription_result",
                        "request_id": "attempt-123",
                        **content,
                    },
                )

    def test_ambiguous_response_is_rejected(self):
        with self.assertRaises(ValueError):
            server.emit_transcription_result(
                "attempt-123", text="", error="backend_error"
            )
        with self.assertRaises(ValueError):
            server.emit_transcription_result("attempt-123")
