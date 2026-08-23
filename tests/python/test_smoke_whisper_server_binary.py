import importlib.util
import os
import sys
import unittest
from pathlib import Path
from unittest import mock


PROJECT_ROOT = Path(__file__).resolve().parents[2]
SCRIPT_PATH = PROJECT_ROOT / "tests" / "python" / "smoke_whisper_server_binary.py"
SPEC = importlib.util.spec_from_file_location("smoke_whisper_server_binary", SCRIPT_PATH)
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


if __name__ == "__main__":
    unittest.main()
