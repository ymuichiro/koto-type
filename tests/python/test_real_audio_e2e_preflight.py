import unittest
from unittest.mock import patch

from tools.real_audio_e2e_preflight import collect_profile, inspect_profile


class RealAudioE2EPreflightTests(unittest.TestCase):
    def test_input_device_is_ready_without_exposing_device_name(self):
        result = inspect_profile(
            {
                "SPAudioDataType": [
                    {
                        "_items": [
                            {"_name": "Speaker", "coreaudio_device_output": 2},
                            {"_name": "Microphone", "coreaudio_device_input": 2},
                        ]
                    }
                ]
            }
        )

        self.assertEqual(result["status"], "READY")
        self.assertEqual(result["input_device_count"], 1)
        self.assertEqual(result["max_input_channels"], 2)
        self.assertNotIn("name", result)

    def test_output_only_host_is_not_run(self):
        result = inspect_profile(
            {
                "SPAudioDataType": [
                    {"_items": [{"_name": "Speaker", "coreaudio_device_output": 2}]}
                ]
            }
        )

        self.assertEqual(
            result,
            {"status": "NOT_RUN", "reason": "no_audio_input_device"},
        )

    def test_invalid_profile_is_error(self):
        self.assertEqual(
            inspect_profile({"unexpected": []}),
            {"status": "ERROR", "reason": "invalid_audio_profile"},
        )

    @patch("tools.real_audio_e2e_preflight.platform.system", return_value="Linux")
    def test_non_macos_host_is_not_run(self, _system):
        self.assertEqual(
            collect_profile(),
            {"status": "NOT_RUN", "reason": "unsupported_platform"},
        )


if __name__ == "__main__":
    unittest.main()
