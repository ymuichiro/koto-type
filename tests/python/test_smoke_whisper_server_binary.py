import importlib.util
import os
import sys
import unittest
from pathlib import Path
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / "tests" / "python" / "smoke_whisper_server_binary.py"
SPEC = importlib.util.spec_from_file_location(
    "smoke_whisper_server_binary", SCRIPT_PATH
)
SMOKE = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = SMOKE
assert SPEC.loader is not None
SPEC.loader.exec_module(SMOKE)


class SmokeWhisperServerBinaryTests(unittest.TestCase):
    def test_default_audio_and_language_remain_local_ja_fixture(self):
        with mock.patch.dict(
            os.environ,
            {
                "KOTOTYPE_SMOKE_AUDIO_PATH": "",
                "KOTOTYPE_SMOKE_LANGUAGE": "",
            },
            clear=False,
        ):
            self.assertEqual(
                SMOKE.resolve_smoke_audio_path(PROJECT_ROOT),
                PROJECT_ROOT / "assets" / "audio" / "test_speech_ja.wav",
            )
            self.assertEqual(SMOKE.resolve_smoke_language(), "ja")

    def test_release_smoke_can_select_generated_audio_and_language(self):
        configured_audio = "/tmp/koto-type-release-smoke.aiff"
        with mock.patch.dict(
            os.environ,
            {
                "KOTOTYPE_SMOKE_AUDIO_PATH": configured_audio,
                "KOTOTYPE_SMOKE_LANGUAGE": "en",
            },
            clear=False,
        ):
            self.assertEqual(
                SMOKE.resolve_smoke_audio_path(PROJECT_ROOT),
                Path(configured_audio).resolve(),
            )
            self.assertEqual(SMOKE.resolve_smoke_language(), "en")

    def test_healthcheck_flag_does_not_require_audio(self):
        server_binary, healthcheck_only = SMOKE.parse_smoke_arguments(
            ["--healthcheck", "/tmp/whisper_server"]
        )

        self.assertEqual(server_binary, Path("/tmp/whisper_server").resolve())
        self.assertTrue(healthcheck_only)

    def test_wait_for_non_control_line_skips_backend_control_messages(self):
        with mock.patch.object(
            SMOKE,
            "wait_for_line",
            side_effect=[
                '__KOTOTYPE_CONTROL__:{"type":"backend_process_group_ready"}',
                "__KOTOTYPE_HEALTHCHECK_OK__:cpu-only",
            ],
        ):
            self.assertEqual(
                SMOKE.wait_for_non_control_line(object(), timeout_seconds=1),
                "__KOTOTYPE_HEALTHCHECK_OK__:cpu-only",
            )

    def test_missing_server_log_tail_is_empty(self):
        self.assertEqual(
            SMOKE.read_server_log_tail(Path("/tmp/no-koto-type-server.log")), ""
        )


if __name__ == "__main__":
    unittest.main()
